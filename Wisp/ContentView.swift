import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSettingsPresented = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var showDeleteConfirmation = false
    @State private var searchTask: Task<Void, Never>? = nil

    private var currentShortcutDescription: String {
        let bindings = AppPreferences.shared.shortcutBindings
        guard let first = bindings.first,
              let shortcut = KeyboardShortcuts.getShortcut(for: first.keyboardShortcutsName) else {
            return ""
        }
        return shortcut.description
    }

    private func performSearch(_ query: String) {
        searchTask?.cancel()

        if query.isEmpty {
            debouncedSearchText = ""
            viewModel.search(query: "")
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.debouncedSearchText = query
                viewModel.search(query: query)
            }
        }
    }

    var body: some View {
        VStack {
            if !permissionsManager.isMicrophonePermissionGranted
                || !permissionsManager.isAccessibilityPermissionGranted
            {
                PermissionsView(permissionsManager: permissionsManager)
            } else {
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search in transcriptions", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .onChange(of: searchText) { _, newValue in
                                performSearch(newValue)
                            }

                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                debouncedSearchText = ""
                                searchTask?.cancel()
                                viewModel.search(query: "")
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .imageScale(.medium)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(ThemePalette.panelSurface(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1)
                    )
                    .cornerRadius(20)
                    .padding([.horizontal, .top])

                    ScrollView(showsIndicators: false) {
                        if viewModel.recordings.isEmpty {
                            emptyStateView
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(viewModel.recordings) { recording in
                                    RecordingRow(
                                        recording: recording,
                                        searchQuery: debouncedSearchText,
                                        onDelete: {
                                            viewModel.deleteRecording(recording)
                                        },
                                        onRegenerate: {
                                            Task {
                                                await TranscriptionQueue.shared.requeueRecording(recording)
                                            }
                                        }
                                    )
                                    .id(recording.id)
                                    .onAppear {
                                        if recording.id == viewModel.recordings.last?.id {
                                            viewModel.loadMore()
                                        }
                                    }
                                }

                                if viewModel.isLoadingMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 16)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.recordings.count)
                    .animation(.easeInOut(duration: 0.2), value: debouncedSearchText.isEmpty)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        ThemePalette.windowBackground(colorScheme).opacity(1),
                                        ThemePalette.windowBackground(colorScheme).opacity(0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 20)
                    }

                    bottomBar
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 400)
        .background(ThemePalette.windowBackground(colorScheme))
        .onAppear {
            viewModel.loadInitialData()
        }
        .onReceive(NotificationCenter.default.publisher(for: RecordingStore.recordingProgressDidUpdateNotification)) { notification in
            guard let userInfo = notification.userInfo,
                  let id = userInfo["id"] as? UUID,
                  let progress = userInfo["progress"] as? Float,
                  let status = userInfo["status"] as? RecordingStatus else { return }

            let transcription = userInfo["transcription"] as? String
            let isRegeneration = userInfo["isRegeneration"] as? Bool

            viewModel.handleProgressUpdate(
                id: id,
                transcription: transcription,
                progress: progress,
                status: status,
                isRegeneration: isRegeneration
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: RecordingStore.recordingsDidUpdateNotification)) { _ in
            viewModel.loadInitialData()
        }
        .overlay {
            let isPermissionsGranted = permissionsManager.isMicrophonePermissionGranted
                && permissionsManager.isAccessibilityPermissionGranted

            if viewModel.transcriptionService.isLoading && isPermissionsGranted {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading Whisper Model...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .fileDropHandler()
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .onChange(of: viewModel.shouldClearSearch) { _, shouldClear in
            if shouldClear {
                searchText = ""
                debouncedSearchText = ""
                searchTask?.cancel()
                viewModel.shouldClearSearch = false
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if !debouncedSearchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                    .padding(.top, 40)

                Text("No results found")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Try different search terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                    .padding(.top, 40)

                Text("No recordings yet")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Tap the record button below to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !currentShortcutDescription.isEmpty {
                    VStack(spacing: 8) {
                        Text("Pro Tip:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Text("Press")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(currentShortcutDescription)
                                .font(.system(size: 16, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(6)
                            Text("anywhere")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text("to quickly record and paste text")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            Button(action: {
                if viewModel.isRecording {
                    viewModel.startDecoding()
                } else {
                    viewModel.startRecording()
                }
            }) {
                if viewModel.state == .decoding || viewModel.state == .connecting {
                    ProgressView()
                        .scaleEffect(1.0)
                        .frame(width: 48, height: 48)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    MainRecordButton(isRecording: viewModel.isRecording)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.transcriptionService.isLoading || viewModel.transcriptionService.isTranscribing || viewModel.transcriptionQueue.isProcessing || viewModel.state == .decoding)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isRecording)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.state)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(currentShortcutDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("to show mini recorder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                            .foregroundColor(.secondary)
                            .imageScale(.medium)
                        Text("Drop audio file here to transcribe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)
                }

                Spacer()

                HStack(spacing: 12) {
                    MicrophonePickerIconView(microphoneService: viewModel.microphoneService)

                    if !viewModel.recordings.isEmpty {
                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                                .background(ThemePalette.panelSurface(colorScheme))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1)
                                )
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help("Delete all recordings")
                        .confirmationDialog(
                            "Delete All Recordings",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete All", role: .destructive) {
                                viewModel.deleteAllRecordings()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Are you sure you want to delete all recordings? This action cannot be undone.")
                        }
                        .interactiveDismissDisabled()
                    }

                    Button(action: {
                        isSettingsPresented.toggle()
                    }) {
                        Image(systemName: "gear")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .background(ThemePalette.panelSurface(colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
        }
        .padding()
    }
}

// MARK: - Permissions

struct PermissionsView: View {
    @ObservedObject var permissionsManager: PermissionsManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Required Permissions")
                .font(.title)
                .padding()

            PermissionRow(
                isGranted: permissionsManager.isMicrophonePermissionGranted,
                title: "Microphone Access",
                description: "Required for audio recording",
                action: {
                    permissionsManager.requestMicrophonePermissionOrOpenSystemPreferences()
                }
            )

            PermissionRow(
                isGranted: permissionsManager.isAccessibilityPermissionGranted,
                title: "Accessibility Access",
                description: "Required for global keyboard shortcuts",
                action: { permissionsManager.openSystemPreferences(for: .accessibility) }
            )

            Spacer()
        }
        .padding()
    }
}

private struct PermissionRow: View {
    let isGranted: Bool
    let title: String
    let description: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isGranted ? .green : .red)

                Text(title)
                    .font(.headline)

                Spacer()

                if !isGranted {
                    Button("Grant Access") {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(ThemePalette.panelSurface(colorScheme))
        .cornerRadius(10)
    }
}

// MARK: - Small Components

struct MicrophonePickerIconView: View {
    @ObservedObject var microphoneService: MicrophoneService
    @State private var showMenu = false
    @Environment(\.colorScheme) private var colorScheme

    private var builtInMicrophones: [MicrophoneService.AudioDevice] {
        microphoneService.availableMicrophones.filter { $0.isBuiltIn }
    }

    private var externalMicrophones: [MicrophoneService.AudioDevice] {
        microphoneService.availableMicrophones.filter { !$0.isBuiltIn }
    }

    var body: some View {
        Button(action: {
            showMenu.toggle()
        }) {
            Image(systemName: microphoneService.availableMicrophones.isEmpty ? "mic.slash" : "mic.fill")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(ThemePalette.panelSurface(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(microphoneService.currentMicrophone?.displayName ?? "Select microphone")
        .popover(isPresented: $showMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                if microphoneService.availableMicrophones.isEmpty {
                    Text("No microphones available")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(builtInMicrophones) { microphone in
                        Button(action: {
                            microphoneService.selectMicrophone(microphone)
                            showMenu = false
                        }) {
                            HStack {
                                Text(microphone.displayName)
                                Spacer()
                                if let current = microphoneService.currentMicrophone,
                                   current.id == microphone.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if !builtInMicrophones.isEmpty && !externalMicrophones.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    ForEach(externalMicrophones) { microphone in
                        Button(action: {
                            microphoneService.selectMicrophone(microphone)
                            showMenu = false
                        }) {
                            HStack {
                                Text(microphone.displayName)
                                Spacer()
                                if let current = microphoneService.currentMicrophone,
                                   current.id == microphone.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minWidth: 200)
            .padding(.vertical, 8)
        }
    }
}

struct MainRecordButton: View {
    let isRecording: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var buttonColor: Color {
        ThemePalette.recordButtonBase(colorScheme)
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        isRecording ? Color.red.opacity(0.8) : buttonColor.opacity(0.8),
                        isRecording ? Color.red : buttonColor.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .shadow(
                color: isRecording ? .red.opacity(0.5) : buttonColor.opacity(0.3),
                radius: 12,
                x: 0,
                y: 0
            )
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                isRecording ? .red.opacity(0.6) : buttonColor.opacity(0.6),
                                isRecording ? .red.opacity(0.3) : buttonColor.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isRecording ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
