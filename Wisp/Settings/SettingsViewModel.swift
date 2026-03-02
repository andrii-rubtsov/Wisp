import Combine
import FluidAudio
import Foundation
import KeyboardShortcuts

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
        didSet { AppPreferences.shared.translateToEnglish = translateToEnglish }
    }

    @Published var suppressBlankAudio: Bool {
        didSet { AppPreferences.shared.suppressBlankAudio = suppressBlankAudio }
    }

    @Published var showTimestamps: Bool {
        didSet { AppPreferences.shared.showTimestamps = showTimestamps }
    }

    @Published var temperature: Double {
        didSet { AppPreferences.shared.temperature = temperature }
    }

    @Published var noSpeechThreshold: Double {
        didSet { AppPreferences.shared.noSpeechThreshold = noSpeechThreshold }
    }

    @Published var useBeamSearch: Bool {
        didSet { AppPreferences.shared.useBeamSearch = useBeamSearch }
    }

    @Published var beamSize: Int {
        didSet { AppPreferences.shared.beamSize = beamSize }
    }

    @Published var debugMode: Bool {
        didSet { AppPreferences.shared.debugMode = debugMode }
    }

    @Published var playSoundOnRecordStart: Bool {
        didSet { AppPreferences.shared.playSoundOnRecordStart = playSoundOnRecordStart }
    }

    @Published var indicatorPosition: IndicatorPosition {
        didSet { AppPreferences.shared.indicatorPosition = indicatorPosition }
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
        guard shortcutBindings.count > 1 else { return }

        if let binding = shortcutBindings.first(where: { $0.id == id }) {
            KeyboardShortcuts.reset(binding.keyboardShortcutsName)
        }

        shortcutBindings.removeAll { $0.id == id }
    }

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
                        guard let self, !Task.isCancelled else { return }
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
                    await MainActor.run { self.resetDownloadState(modelName: model.name) }
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
                    resetDownloadState()

                    Task { @MainActor in
                        TranscriptionService.shared.reloadModel(with: modelPath)
                    }
                }
            } catch is CancellationError {
                await MainActor.run { self.resetDownloadState(modelName: model.name) }
            } catch {
                await MainActor.run { self.resetDownloadState(modelName: model.name) }
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
        resetDownloadState()
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
                    await MainActor.run { self.resetFluidAudioDownloadState(modelId: model.id) }
                    throw CancellationError()
                }

                let models = try await AsrModels.downloadAndLoad(version: version)

                guard !Task.isCancelled else {
                    await MainActor.run { self.resetFluidAudioDownloadState(modelId: model.id) }
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
                await MainActor.run { self.resetFluidAudioDownloadState(modelId: model.id) }
            } catch {
                if Task.isCancelled {
                    wasCancelled = true
                    await MainActor.run { self.resetFluidAudioDownloadState(modelId: model.id) }
                } else {
                    await MainActor.run { self.resetFluidAudioDownloadState(modelId: model.id) }
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

    // MARK: - Private Helpers

    private func resetDownloadState(modelName: String? = nil) {
        isDownloading = false
        downloadingModelName = nil
        downloadProgress = 0.0
        if let name = modelName, let index = downloadableModels.firstIndex(where: { $0.name == name }) {
            downloadableModels[index].downloadProgress = 0.0
        }
    }

    private func resetFluidAudioDownloadState(modelId: UUID) {
        isDownloading = false
        downloadingModelName = nil
        downloadProgress = 0.0
        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == modelId }) {
            downloadableFluidAudioModels[index].downloadProgress = 0.0
        }
    }
}
