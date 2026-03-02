import AppKit
import Carbon
import Combine
import Foundation
import KeyboardShortcuts
import SwiftUI
import FluidAudio

class SettingsViewModel: ObservableObject {
    @Published var selectedEngine: String {
        didSet {
            AppPreferences.shared.selectedEngine = selectedEngine
            if selectedEngine == "whisper" {
                loadAvailableModels()
            } else {
                initializeFluidAudioModels()
            }
            Task { @MainActor in
                TranscriptionService.shared.reloadEngine()
            }
        }
    }

    @Published var fluidAudioModelVersion: String {
        didSet {
            AppPreferences.shared.fluidAudioModelVersion = fluidAudioModelVersion
            if selectedEngine == "fluidaudio" {
                Task { @MainActor in
                    TranscriptionService.shared.reloadEngine()
                }
            }
            initializeFluidAudioModels()
        }
    }

    @Published var selectedModelURL: URL? {
        didSet {
            if let url = selectedModelURL {
                AppPreferences.shared.selectedWhisperModelPath = url.path
            }
        }
    }

    @Published var availableModels: [URL] = []

    @Published var downloadableModels: [SettingsDownloadableModel] = []
    @Published var downloadableFluidAudioModels: [SettingsFluidAudioModel] = []
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadingModelName: String?
    private var downloadTask: Task<Void, Error>?

    @Published var selectedLanguage: String {
        didSet {
            AppPreferences.shared.whisperLanguage = selectedLanguage
            NotificationCenter.default.post(name: .appPreferencesLanguageChanged, object: nil)
        }
    }

    @Published var translateToEnglish: Bool {
        didSet {
            AppPreferences.shared.translateToEnglish = translateToEnglish
        }
    }

    @Published var suppressBlankAudio: Bool {
        didSet {
            AppPreferences.shared.suppressBlankAudio = suppressBlankAudio
        }
    }

    @Published var showTimestamps: Bool {
        didSet {
            AppPreferences.shared.showTimestamps = showTimestamps
        }
    }

    @Published var temperature: Double {
        didSet {
            AppPreferences.shared.temperature = temperature
        }
    }

    @Published var noSpeechThreshold: Double {
        didSet {
            AppPreferences.shared.noSpeechThreshold = noSpeechThreshold
        }
    }

    @Published var useBeamSearch: Bool {
        didSet {
            AppPreferences.shared.useBeamSearch = useBeamSearch
        }
    }

    @Published var beamSize: Int {
        didSet {
            AppPreferences.shared.beamSize = beamSize
        }
    }

    @Published var debugMode: Bool {
        didSet {
            AppPreferences.shared.debugMode = debugMode
        }
    }

    @Published var playSoundOnRecordStart: Bool {
        didSet {
            AppPreferences.shared.playSoundOnRecordStart = playSoundOnRecordStart
        }
    }

    @Published var indicatorPosition: IndicatorPosition {
        didSet {
            AppPreferences.shared.indicatorPosition = indicatorPosition
        }
    }

    @Published var shortcutBindings: [ShortcutBinding] {
        didSet {
            AppPreferences.shared.shortcutBindings = shortcutBindings
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }

    init() {
        let prefs = AppPreferences.shared
        self.selectedEngine = prefs.selectedEngine
        self.fluidAudioModelVersion = prefs.fluidAudioModelVersion
        self.selectedLanguage = prefs.whisperLanguage
        self.translateToEnglish = prefs.translateToEnglish
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.debugMode = prefs.debugMode
        self.playSoundOnRecordStart = prefs.playSoundOnRecordStart
        self.indicatorPosition = prefs.indicatorPosition
        self.shortcutBindings = prefs.shortcutBindings

        if let savedPath = prefs.selectedWhisperModelPath ?? prefs.selectedModelPath {
            self.selectedModelURL = URL(fileURLWithPath: savedPath)
        }
        loadAvailableModels()
        initializeDownloadableModels()
        initializeFluidAudioModels()
    }

    // MARK: - Shortcut Binding Management

    func addShortcutBinding() {
        guard shortcutBindings.count < ShortcutBinding.maxBindings else { return }

        let slot = ShortcutBinding.nextAvailableSlot(excluding: shortcutBindings)

        shortcutBindings.append(ShortcutBinding(
            keyComboSlot: slot,
            engine: "fluidaudio",
            modelIdentifier: "v3",
            modelDisplayName: "Parakeet v3"
        ))
    }

    func removeShortcutBinding(id: UUID) {
        // Don't allow removing the last binding
        guard shortcutBindings.count > 1 else { return }

        if let binding = shortcutBindings.first(where: { $0.id == id }) {
            KeyboardShortcuts.reset(binding.keyboardShortcutsName)
        }

        shortcutBindings.removeAll { $0.id == id }
    }

    /// Returns available model choices for a given engine (all models, not just downloaded).
    func availableModelChoices(for engine: String) -> [(id: String, name: String, downloaded: Bool)] {
        if engine == "fluidaudio" {
            return downloadableFluidAudioModels.map {
                (id: $0.version, name: $0.name, downloaded: $0.isDownloaded)
            }
        } else {
            return downloadableModels.map {
                (id: $0.url.lastPathComponent, name: $0.name, downloaded: $0.isDownloaded)
            }
        }
    }

    // MARK: - Model Management

    func initializeFluidAudioModels() {
        downloadableFluidAudioModels = SettingsFluidAudioModels.availableModels.map { model in
            var updatedModel = model
            updatedModel.isDownloaded = isFluidAudioModelDownloaded(version: model.version)
            return updatedModel
        }
    }

    func isFluidAudioModelDownloaded(version: String) -> Bool {
        let asrVersion: AsrModelVersion = version == "v2" ? .v2 : .v3
        let cacheDirectory = AsrModels.defaultCacheDirectory(for: asrVersion)
        return AsrModels.modelsExist(at: cacheDirectory, version: asrVersion)
    }

    func initializeDownloadableModels() {
        let modelManager = WhisperModelManager.shared
        downloadableModels = SettingsDownloadableModels.availableModels.map { model in
            var updatedModel = model
            let filename = model.url.lastPathComponent
            updatedModel.isDownloaded = modelManager.isModelDownloaded(name: filename)
            return updatedModel
        }
    }

    func loadAvailableModels() {
        availableModels = WhisperModelManager.shared.getAvailableModels()
        if selectedModelURL == nil {
            selectedModelURL = availableModels.first
        }
        initializeDownloadableModels()
    }

    @MainActor
    func downloadModel(_ model: SettingsDownloadableModel) async throws {
        guard !isDownloading else { return }

        isDownloading = true
        downloadingModelName = model.name
        downloadProgress = 0.0

        downloadTask = Task {
            do {
                let filename = model.url.lastPathComponent

                try await WhisperModelManager.shared.downloadModel(url: model.url, name: filename) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        guard let task = self.downloadTask, !task.isCancelled else { return }

                        self.downloadProgress = progress
                        if let index = self.downloadableModels.firstIndex(where: { $0.name == model.name }) {
                            self.downloadableModels[index].downloadProgress = progress
                            if progress >= 1.0 {
                                self.downloadableModels[index].isDownloaded = true
                            }
                        }
                    }
                }

                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableModels.firstIndex(where: { $0.name == model.name }) {
                            self.downloadableModels[index].downloadProgress = 0.0
                        }
                    }
                    return
                }

                await MainActor.run {
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].isDownloaded = true
                        downloadableModels[index].downloadProgress = 0.0
                    }
                    loadAvailableModels()
                    let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(filename).path
                    selectedModelURL = URL(fileURLWithPath: modelPath)
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0

                    Task { @MainActor in
                        TranscriptionService.shared.reloadModel(with: modelPath)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].downloadProgress = 0.0
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].downloadProgress = 0.0
                    }
                }
                throw error
            }
        }

        try await downloadTask?.value
    }

    func cancelDownload() {
        downloadTask?.cancel()
        if let modelName = downloadingModelName {
            if selectedEngine == "whisper", let model = downloadableModels.first(where: { $0.name == modelName }) {
                let filename = model.url.lastPathComponent
                WhisperModelManager.shared.cancelDownload(name: filename)
            }
            if let index = downloadableModels.firstIndex(where: { $0.name == modelName }) {
                downloadableModels[index].downloadProgress = 0.0
            }
            if let index = downloadableFluidAudioModels.firstIndex(where: { $0.name == modelName }) {
                downloadableFluidAudioModels[index].downloadProgress = 0.0
            }
        }
        isDownloading = false
        downloadingModelName = nil
        downloadProgress = 0.0
    }

    @MainActor
    func downloadFluidAudioModel(_ model: SettingsFluidAudioModel) async throws {
        guard !isDownloading else { return }

        isDownloading = true
        downloadingModelName = model.name
        downloadProgress = 0.0

        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
            downloadableFluidAudioModels[index].downloadProgress = 0.0
        }

        var wasCancelled = false

        downloadTask = Task {
            do {
                let version: AsrModelVersion = model.version == "v2" ? .v2 : .v3

                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw CancellationError()
                }

                let models = try await AsrModels.downloadAndLoad(version: version)

                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw CancellationError()
                }

                let manager = AsrManager(config: .default)
                try await manager.initialize(models: models)

                await MainActor.run {
                    if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                        downloadableFluidAudioModels[index].isDownloaded = true
                        downloadableFluidAudioModels[index].downloadProgress = 1.0
                    }
                    fluidAudioModelVersion = model.version
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 1.0

                    Task { @MainActor in
                        TranscriptionService.shared.reloadEngine()
                    }
                }
            } catch is CancellationError {
                wasCancelled = true
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                        downloadableFluidAudioModels[index].downloadProgress = 0.0
                    }
                }
            } catch {
                if Task.isCancelled {
                    wasCancelled = true
                    await MainActor.run {
                        isDownloading = false
                        downloadingModelName = nil
                        downloadProgress = 0.0
                        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                } else {
                    await MainActor.run {
                        isDownloading = false
                        downloadingModelName = nil
                        downloadProgress = 0.0
                        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw error
                }
            }
        }

        do {
            try await downloadTask?.value
        } catch is CancellationError {
            wasCancelled = true
        } catch {
            if !wasCancelled {
                throw error
            }
        }
    }

    @MainActor
    func downloadFluidAudioModel() async throws {
        let versionString = AppPreferences.shared.fluidAudioModelVersion
        if let model = downloadableFluidAudioModels.first(where: { $0.version == versionString }) {
            try await downloadFluidAudioModel(model)
        }
    }
}

// MARK: - Model Data Structures

struct SettingsDownloadableModel: Identifiable {
    let id = UUID()
    let name: String
    var isDownloaded: Bool
    let url: URL
    let size: Int
    let description: String
    var downloadProgress: Double = 0.0

    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(size) * 1000000)
    }

    init(name: String, isDownloaded: Bool, url: URL, size: Int, description: String) {
        self.name = name
        self.isDownloaded = isDownloaded
        self.url = url
        self.size = size
        self.description = description
    }
}

struct SettingsDownloadableModels {
    static let availableModels = [
        SettingsDownloadableModel(
            name: "Turbo V3 large",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
            size: 1624,
            description: "Best quality (~2.5% WER). 99 languages. Supports initial prompt."
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 medium",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
            size: 874,
            description: "Near-best quality, quantized for speed. 99 languages. Supports initial prompt."
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 small",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
            size: 574,
            description: "Fast, compact quantization. 99 languages. Supports initial prompt."
        )
    ]
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    @State private var previousModelURL: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            shortcutSettings
                .tabItem {
                    Label("Shortcuts and models", systemImage: "command")
                }
                .tag(0)

            modelDownloadsTab
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .tag(1)

            transcriptionSettings
                .tabItem {
                    Label("Transcription", systemImage: "text.bubble")
                }
                .tag(2)

            advancedSettings
                .tabItem {
                    Label("Advanced", systemImage: "gear")
                }
                .tag(3)
        }
        .padding()
        .frame(minWidth: 650, maxWidth: .infinity)
        .background(Color(.windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Spacer()

                Link(destination: URL(string: "https://github.com/andrii-rubtsov/Wisp")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 10))
                        Text("GitHub")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .onAppear {
            previousModelURL = viewModel.selectedModelURL
            viewModel.initializeFluidAudioModels()
            viewModel.initializeDownloadableModels()
        }
    }

    // MARK: - Shortcuts Tab

    private var shortcutSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Shortcuts for models
                VStack(alignment: .leading, spacing: 16) {
                    Text("Shortcuts for models")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(spacing: 8) {
                        ForEach($viewModel.shortcutBindings) { $binding in
                            ShortcutBindingRow(
                                binding: $binding,
                                modelChoices: viewModel.availableModelChoices(for: binding.engine),
                                canDelete: viewModel.shortcutBindings.count > 1,
                                onDelete: { viewModel.removeShortcutBinding(id: binding.id) },
                                viewModel: viewModel
                            )
                        }

                        if viewModel.shortcutBindings.count < ShortcutBinding.maxBindings {
                            Button(action: { viewModel.addShortcutBinding() }) {
                                Label("Add shortcut for model", systemImage: "plus")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 4)
                        }
                    }

                    Text("Each shortcut triggers recording with its assigned engine, model, and initial prompt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Recording Behavior
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Behavior")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Play sound when recording starts")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.playSoundOnRecordStart)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                                .help("Play a notification sound when recording begins")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Recording Indicator Position
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Indicator")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Text("Position")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $viewModel.indicatorPosition) {
                            ForEach(IndicatorPosition.allCases) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    // MARK: - Model Downloads Tab

    private var modelDownloadsTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                modelDownloadSection
            }
            .padding()
        }
    }

    // MARK: - Model Download Section

    private var modelDownloadSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Downloads")
                .font(.headline)
                .foregroundColor(.primary)

            // Whisper Models
            VStack(alignment: .leading, spacing: 8) {
                Text("Whisper Models")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(spacing: 8) {
                    ForEach($viewModel.downloadableModels) { $model in
                        ModelDownloadItemView(model: $model, viewModel: viewModel)
                    }
                }
            }

            Divider()

            // Parakeet Models
            VStack(alignment: .leading, spacing: 8) {
                Text("Parakeet Models")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(spacing: 8) {
                    ForEach($viewModel.downloadableFluidAudioModels) { $model in
                        FluidAudioModelDownloadItemView(model: $model, viewModel: viewModel)
                    }
                }
            }

            // Download progress
            if viewModel.isDownloading {
                VStack(spacing: 8) {
                    HStack {
                        if viewModel.downloadProgress > 0 {
                            ProgressView(value: viewModel.downloadProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }

                        Spacer()

                        Button("Cancel") {
                            viewModel.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let downloadingName = viewModel.downloadingModelName {
                        Text("Downloading: \(downloadingName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    // MARK: - Transcription Tab

    private var transcriptionSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Language Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Language Settings")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcription Language")
                            .font(.subheadline)

                        Picker("Language", selection: $viewModel.selectedLanguage) {
                            ForEach(LanguageUtil.availableLanguages, id: \.self) { code in
                                Text(LanguageUtil.languageNames[code] ?? code)
                                    .tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Text("Translate to English")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.translateToEnglish)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Output Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Output Options")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Show Timestamps")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.showTimestamps)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }

                        HStack {
                            Text("Suppress Blank Audio")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.suppressBlankAudio)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Transcriptions Directory
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transcriptions Directory")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Directory:")
                                .font(.subheadline)
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(Recording.recordingsDirectory)
                            }) {
                                Label("Open Folder", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .help("Open transcriptions directory")
                        }

                        Text(Recording.recordingsDirectory.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    // MARK: - Advanced Tab

    private var advancedSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Decoding Strategy")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Whisper only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Use Beam Search")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.useBeamSearch)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                                .help("Beam search can provide better results but is slower")
                        }

                        if viewModel.useBeamSearch {
                            HStack {
                                Text("Beam Size:")
                                    .font(.subheadline)
                                Spacer()
                                Stepper("\(viewModel.beamSize)", value: $viewModel.beamSize, in: 1...10)
                                    .help("Number of beams to use in beam search")
                                    .frame(width: 120)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Model Parameters")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Whisper only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Temperature:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.temperature))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: $viewModel.temperature, in: 0.0...1.0, step: 0.1)
                                .help("Higher values make the output more random")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("No Speech Threshold:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.noSpeechThreshold))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: $viewModel.noSpeechThreshold, in: 0.0...1.0, step: 0.1)
                                .help("Threshold for detecting speech vs. silence")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Debug Options")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Text("Debug Mode")
                            .font(.subheadline)
                        Spacer()
                        Toggle("", isOn: $viewModel.debugMode)
                            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                            .labelsHidden()
                            .help("Enable additional logging and debugging information")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}

// MARK: - Shortcut Binding Row

struct ShortcutBindingRow: View {
    @Binding var binding: ShortcutBinding
    let modelChoices: [(id: String, name: String, downloaded: Bool)]
    let canDelete: Bool
    let onDelete: () -> Void
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""

    private var isModelDownloaded: Bool {
        modelChoices.first(where: { $0.id == binding.modelIdentifier })?.downloaded ?? false
    }

    private var modelSizeString: String? {
        if binding.engine == "whisper" {
            if let model = SettingsDownloadableModels.availableModels.first(where: { $0.url.lastPathComponent == binding.modelIdentifier }) {
                return model.sizeString
            }
        } else {
            if let model = SettingsFluidAudioModels.availableModels.first(where: { $0.version == binding.modelIdentifier }) {
                return model.sizeString
            }
        }
        return nil
    }

    private var modelDescription: String? {
        if binding.engine == "whisper" {
            return SettingsDownloadableModels.availableModels.first(where: { $0.url.lastPathComponent == binding.modelIdentifier })?.description
        } else {
            return SettingsFluidAudioModels.availableModels.first(where: { $0.version == binding.modelIdentifier })?.description
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // Key combination recorder
                KeyboardShortcuts.Recorder("", name: binding.keyboardShortcutsName)
                    .frame(width: 150)

                // Engine picker
                Picker("", selection: $binding.engine) {
                    Text("Whisper").tag("whisper")
                    Text("Parakeet").tag("fluidaudio")
                }
                .pickerStyle(.menu)
                .frame(width: 90)
                .onChange(of: binding.engine) { _, newEngine in
                    let choices = newEngine == "fluidaudio"
                        ? SettingsFluidAudioModels.availableModels.map { (id: $0.version, name: $0.name) }
                        : SettingsDownloadableModels.availableModels.map { (id: $0.url.lastPathComponent, name: $0.name) }
                    if let first = choices.first {
                        binding.modelIdentifier = first.id
                        binding.modelDisplayName = first.name
                    }
                }

                // Model picker
                Picker("", selection: $binding.modelIdentifier) {
                    ForEach(modelChoices, id: \.id) { choice in
                        HStack {
                            Text(choice.name)
                            if !choice.downloaded {
                                Text("(not downloaded)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(choice.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 120)
                .onChange(of: binding.modelIdentifier) { _, newId in
                    if let match = modelChoices.first(where: { $0.id == newId }) {
                        binding.modelDisplayName = match.name
                    }
                }

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(canDelete ? .secondary : .secondary.opacity(0.3))
                }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
            }

            // Model status: download prompt or ready indicator
            if !isModelDownloaded {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(binding.modelDisplayName) is not downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let size = modelSizeString, let desc = modelDescription {
                            Text("\(desc) — \(size)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }

                    Spacer()

                    if viewModel.isDownloading && viewModel.downloadingModelName == binding.modelDisplayName {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.6)
                        Button("Cancel") {
                            viewModel.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    } else {
                        Button(action: {
                            Task {
                                do {
                                    if binding.engine == "whisper" {
                                        if let model = viewModel.downloadableModels.first(where: { $0.url.lastPathComponent == binding.modelIdentifier }) {
                                            try await viewModel.downloadModel(model)
                                        }
                                    } else {
                                        if let model = viewModel.downloadableFluidAudioModels.first(where: { $0.version == binding.modelIdentifier }) {
                                            try await viewModel.downloadFluidAudioModel(model)
                                        }
                                    }
                                } catch is CancellationError {
                                } catch {
                                    errorMessage = error.localizedDescription
                                    showError = true
                                }
                            }
                        }) {
                            Label("Download", systemImage: "arrow.down.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(viewModel.isDownloading)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(binding.modelDisplayName) ready")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let size = modelSizeString {
                        Text("(\(size))")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            // Initial prompt (whisper only)
            if binding.engine == "whisper" {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Initial Prompt:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextEditor(text: $binding.initialPrompt)
                        .font(.system(size: 13))
                        .frame(height: 70)
                        .padding(4)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Model Download Item Views

struct SettingsFluidAudioModel: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    var isDownloaded: Bool
    let description: String
    let size: Int   // estimated size in MB
    var downloadProgress: Double = 0.0

    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(size) * 1000000)
    }
}

struct SettingsFluidAudioModels {
    static let availableModels = [
        SettingsFluidAudioModel(
            name: "Parakeet v3",
            version: "v3",
            isDownloaded: false,
            description: "Lightning fast (~6% WER). 25 European languages. No prompt support.",
            size: 550
        ),
        SettingsFluidAudioModel(
            name: "Parakeet v2",
            version: "v2",
            isDownloaded: false,
            description: "Lightning fast (~6% WER). English only. No prompt support.",
            size: 230
        )
    ]
}

enum OnboardingModelType {
    case whisper(url: URL, size: Int)
    case parakeet(version: String)
}

struct OnboardingUnifiedModel: Identifiable {
    let id = UUID()
    let name: String
    var isDownloaded: Bool
    let description: String
    let type: OnboardingModelType
    var downloadProgress: Double = 0.0
}

struct OnboardingUnifiedModels {
    static let availableModels = [
        OnboardingUnifiedModel(
            name: "Whisper V3 Large",
            isDownloaded: false,
            description: "Best quality (~2.5% WER). 99 languages. Supports initial prompt.",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
                size: 1624
            )
        ),
        OnboardingUnifiedModel(
            name: "Parakeet v3",
            isDownloaded: false,
            description: "Lightning fast (~6% WER). 25 European languages. No prompt support.",
            type: .parakeet(version: "v3")
        ),
        OnboardingUnifiedModel(
            name: "Parakeet v2",
            isDownloaded: false,
            description: "Lightning fast (~6% WER). English only. No prompt support.",
            type: .parakeet(version: "v2")
        ),
        OnboardingUnifiedModel(
            name: "Whisper Medium",
            isDownloaded: false,
            description: "Near-best quality, quantized for speed. 99 languages. Supports initial prompt.",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
                size: 874
            )
        ),
        OnboardingUnifiedModel(
            name: "Whisper Small",
            isDownloaded: false,
            description: "Fast, compact quantization. 99 languages. Supports initial prompt.",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
                size: 574
            )
        )
    ]
}

struct FluidAudioModelDownloadItemView: View {
    @Binding var model: SettingsFluidAudioModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("(\(model.sizeString))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 4)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .imageScale(.large)
            } else {
                Button(action: {
                    Task {
                        do {
                            try await viewModel.downloadFluidAudioModel(model)
                        } catch is CancellationError {
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDownloading)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

struct ModelDownloadItemView: View {
    @Binding var model: SettingsDownloadableModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("(\(model.sizeString))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 4)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .imageScale(.large)
            } else {
                Button(action: {
                    Task {
                        do {
                            try await viewModel.downloadModel(model)
                        } catch is CancellationError {
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDownloading)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}
