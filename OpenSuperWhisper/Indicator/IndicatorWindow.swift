import Cocoa
import Combine
import SwiftUI

enum RecordingState {
    case idle
    case connecting
    case recording
    case decoding
    case busy
}

@MainActor
protocol IndicatorViewDelegate: AnyObject {
    
    func didFinishDecoding()
}

@MainActor
class IndicatorViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var isBlinking = false
    @Published var recorder: AudioRecorder = .shared
    @Published var isVisible = false
    
    var delegate: IndicatorViewDelegate?
    private var blinkTimer: Timer?
    private var hideTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private let recordingStore: RecordingStore
    private let transcriptionService: TranscriptionService
    private let transcriptionQueue: TranscriptionQueue
    
    init() {
        self.recordingStore = RecordingStore.shared
        self.transcriptionService = TranscriptionService.shared
        self.transcriptionQueue = TranscriptionQueue.shared
        
        recorder.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnecting in
                guard let self = self else { return }
                if isConnecting {
                    self.state = .connecting
                    self.stopBlinking()
                }
            }
            .store(in: &cancellables)
        
        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording {
                    self.state = .recording
                    self.startBlinking()
                }
            }
            .store(in: &cancellables)
    }
    
    var isTranscriptionBusy: Bool {
        transcriptionService.isTranscribing || transcriptionQueue.isProcessing
    }
    
    func showBusyMessage() {
        state = .busy
        
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.delegate?.didFinishDecoding()
            }
        }
    }
    
    func startRecording() {
        if isTranscriptionBusy {
            showBusyMessage()
            return
        }
        
        if MicrophoneService.shared.isActiveMicrophoneRequiresConnection() {
            state = .connecting
            stopBlinking()
        } else {
            state = .recording
            startBlinking()
        }
        
        Task.detached { [recorder] in
            recorder.startRecording()
        }
    }
    
    func startDecoding() {
        stopBlinking()
        
        if isTranscriptionBusy {
            recorder.cancelRecording()
            showBusyMessage()
            return
        }
        
        state = .decoding
        
        if let tempURL = recorder.stopRecording() {
            Task { [weak self] in
                guard let self = self else { return }
                
                do {
                    print("start decoding...")
                    let text = try await transcriptionService.transcribeAudio(url: tempURL)

                    if TranscriptionFilter.isEmptyOrHallucinated(text) {
                        print("Transcription is empty/hallucinated, discarding: \(text)")
                        try? FileManager.default.removeItem(at: tempURL)
                    } else {
                        // Create a new Recording instance
                        let timestamp = Date()
                        let fileName = "\(Int(timestamp.timeIntervalSince1970)).wav"
                        let recordingId = UUID()
                        let finalURL = Recording(
                            id: recordingId,
                            timestamp: timestamp,
                            fileName: fileName,
                            transcription: text,
                            duration: 0,
                            status: .completed,
                            progress: 1.0,
                            sourceFileURL: nil
                        ).url

                        // Move the temporary recording to final location
                        try recorder.moveTemporaryRecording(from: tempURL, to: finalURL)

                        // Save the recording to store
                        await MainActor.run {
                            self.recordingStore.addRecording(Recording(
                                id: recordingId,
                                timestamp: timestamp,
                                fileName: fileName,
                                transcription: text,
                                duration: 0,
                                status: .completed,
                                progress: 1.0,
                                sourceFileURL: nil
                            ))
                        }

                        insertText(text)
                        print("Transcription result: \(text)")
                    }
                } catch {
                    print("Error transcribing audio: \(error)")
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                await MainActor.run {
                    self.delegate?.didFinishDecoding()
                }
            }
        } else {
            
            print("!!! Not found record url !!!")
            
            Task {
                await MainActor.run {
                    self.delegate?.didFinishDecoding()
                }
            }
        }
    }
    
    func insertText(_ text: String) {
        ClipboardUtil.insertText(text)
    }
    
    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            // Update UI on the main thread
            Task { @MainActor in
                guard let self = self else { return }
                self.isBlinking.toggle()
            }
        }
    }
    
    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isBlinking = false
    }

    func cleanup() {
        stopBlinking()
        hideTimer?.invalidate()
        hideTimer = nil
        cancellables.removeAll()
    }

    func cancelRecording() {
        hideTimer?.invalidate()
        hideTimer = nil
        recorder.cancelRecording()
    }

    @MainActor
    func hideWithAnimation() async {
        await withCheckedContinuation { continuation in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isVisible = false
            } completion: {
                continuation.resume()
            }
        }
    }
}

struct RecordingIndicator: View {
    let isBlinking: Bool

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.red.opacity(0.8),
                        Color.red
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 12, height: 12)
            .shadow(color: .red.opacity(0.6), radius: 6)
            .opacity(isBlinking ? 0.2 : 1.0)
            .animation(.easeInOut(duration: 0.4), value: isBlinking)
    }
}

struct IndicatorWindow: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let textColor = Color.green
    private let borderColor = Color.purple

    var body: some View {
        let rect = RoundedRectangle(cornerRadius: 16)

        VStack(spacing: 0) {
            switch viewModel.state {
            case .connecting:
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(textColor)
                }

            case .recording:
                HStack(spacing: 10) {
                    RecordingIndicator(isBlinking: viewModel.isBlinking)
                    Text("Recording...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(textColor)
                }

            case .decoding:
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(textColor)
                }

            case .busy:
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text("Processing...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.orange)
                }

            case .idle:
                EmptyView()
            }
        }
        .frame(width: 220, height: 48)
        .background(
            rect
                .fill(Color.black.opacity(0.88))
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .overlay(
            rect
                .stroke(borderColor.opacity(0.7), lineWidth: 1.5)
        )
        .clipShape(rect)
        .scaleEffect(viewModel.isVisible ? 1 : 0.5)
        .offset(y: viewModel.isVisible ? 0 : 20)
        .opacity(viewModel.isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isVisible)
        .onAppear {
            viewModel.isVisible = true
        }
    }
}

struct IndicatorWindowPreview: View {
    @StateObject private var recordingVM = {
        let vm = IndicatorViewModel()
//        vm.startRecording()
        return vm
    }()
    
    @StateObject private var decodingVM = {
        let vm = IndicatorViewModel()
        vm.startDecoding()
        return vm
    }()
    
    var body: some View {
        VStack(spacing: 20) {
            IndicatorWindow(viewModel: recordingVM)
            IndicatorWindow(viewModel: decodingVM)
        }
        .padding()
        .frame(height: 200)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    IndicatorWindowPreview()
}
