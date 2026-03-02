import AVFoundation
import Combine
import SwiftUI

@MainActor
class ContentViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var isBlinking = false
    @Published var recorder: AudioRecorder = .shared
    @Published var transcriptionService = TranscriptionService.shared
    @Published var transcriptionQueue = TranscriptionQueue.shared
    @Published var recordingStore = RecordingStore.shared
    @Published var recordings: [Recording] = []
    @Published var isLoadingMore = false
    @Published var canLoadMore = true
    @Published var recordingDuration: TimeInterval = 0
    @Published var microphoneService = MicrophoneService.shared
    @Published var shouldClearSearch = false

    private var currentPage = 0
    private let pageSize = 100
    private var currentSearchQuery = ""
    private var blinkTimer: Timer?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        recorder.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnecting in
                guard let self = self else { return }
                if isConnecting && self.state != .decoding {
                    self.state = .connecting
                    self.stopBlinking()
                    self.stopDurationTimer()
                    self.recordingDuration = 0
                }
            }
            .store(in: &cancellables)

        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording && self.state != .decoding {
                    self.state = .recording
                    self.startBlinking()
                    self.startDurationTimerIfNeeded()
                } else if !isRecording && self.state == .recording {
                    self.state = .idle
                    self.stopBlinking()
                    self.stopDurationTimer()
                    self.recordingDuration = 0
                }
            }
            .store(in: &cancellables)
    }

    func loadInitialData() {
        currentSearchQuery = ""
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }

    func loadMore() {
        guard !isLoadingMore && canLoadMore else { return }
        isLoadingMore = true

        let page = currentPage
        let limit = pageSize
        let query = currentSearchQuery
        let offset = page * limit

        Task {
            let newRecordings: [Recording]
            if query.isEmpty {
                newRecordings = try await recordingStore.fetchRecordings(limit: limit, offset: offset)
            } else {
                newRecordings = await recordingStore.searchRecordingsAsync(query: query, limit: limit, offset: offset)
            }

            await MainActor.run {
                defer {
                    self.isLoadingMore = false
                }

                guard self.currentSearchQuery == query else {
                    return
                }

                if page == 0 {
                    self.recordings = newRecordings
                } else {
                    self.recordings.append(contentsOf: newRecordings)
                }

                if newRecordings.count < limit {
                    self.canLoadMore = false
                } else {
                    self.currentPage += 1
                }
            }
        }
    }

    func search(query: String) {
        currentSearchQuery = query
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }

    func handleProgressUpdate(id: UUID, transcription: String?, progress: Float, status: RecordingStatus, isRegeneration: Bool?) {
        if let index = recordings.firstIndex(where: { $0.id == id }) {
            if let transcription = transcription {
                recordings[index].transcription = transcription
            }
            recordings[index].progress = progress
            recordings[index].status = status
            if let isRegeneration = isRegeneration {
                recordings[index].isRegeneration = isRegeneration
            }
        }
    }

    func deleteRecording(_ recording: Recording) {
        recordingStore.deleteRecording(recording)
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings.remove(at: index)
        }
    }

    func deleteAllRecordings() {
        recordingStore.deleteAllRecordings()
        recordings.removeAll()
    }

    var isRecording: Bool {
        recorder.isRecording
    }

    func startRecording() {
        if microphoneService.isActiveMicrophoneRequiresConnection() {
            state = .connecting
            stopBlinking()
            stopDurationTimer()
            recordingDuration = 0
        } else {
            state = .recording
            startBlinking()
            recordingStartTime = Date()
            recordingDuration = 0
            startDurationTimerIfNeeded()
        }

        Task.detached { [recorder] in
            recorder.startRecording()
        }
    }

    func startDecoding() {
        state = .decoding
        stopBlinking()
        stopDurationTimer()

        IndicatorWindowManager.shared.hide()

        if let tempURL = recorder.stopRecording() {
            Task { [weak self] in
                guard let self = self else { return }

                do {
                    let text = try await transcriptionService.transcribeAudio(url: tempURL)

                    let duration = await MainActor.run { self.recordingDuration }

                    let timestamp = Date()
                    let fileName = "\(Int(timestamp.timeIntervalSince1970)).wav"
                    let recordingId = UUID()
                    let finalURL = Recording(
                        id: recordingId,
                        timestamp: timestamp,
                        fileName: fileName,
                        transcription: text,
                        duration: duration,
                        status: .completed,
                        progress: 1.0,
                        sourceFileURL: nil
                    ).url

                    try recorder.moveTemporaryRecording(from: tempURL, to: finalURL)

                    await MainActor.run {
                        let newRecording = Recording(
                            id: recordingId,
                            timestamp: timestamp,
                            fileName: fileName,
                            transcription: text,
                            duration: self.recordingDuration,
                            status: .completed,
                            progress: 1.0,
                            sourceFileURL: nil
                        )
                        self.recordingStore.addRecording(newRecording)

                        if !self.currentSearchQuery.isEmpty {
                            self.shouldClearSearch = true
                            self.currentSearchQuery = ""
                        }
                        self.recordings.insert(newRecording, at: 0)
                    }

                    print("Transcription result: \(text)")
                } catch {
                    print("Error transcribing audio: \(error)")
                    try? FileManager.default.removeItem(at: tempURL)
                }

                await MainActor.run {
                    self.state = .idle
                    self.recordingDuration = 0
                }
            }
        } else {
            state = .idle
            recordingDuration = 0
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil
    }

    private func startDurationTimerIfNeeded() {
        guard durationTimer == nil else { return }
        if recordingStartTime == nil {
            recordingStartTime = Date()
            recordingDuration = 0
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let startTime = Date()
            Task { @MainActor in
                if let recordingStartTime = self.recordingStartTime {
                    self.recordingDuration = startTime.timeIntervalSince(recordingStartTime)
                }
            }
        }
        RunLoop.main.add(durationTimer!, forMode: .common)
    }

    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isBlinking.toggle()
            }
        }
        RunLoop.main.add(blinkTimer!, forMode: .common)
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isBlinking = false
    }
}
