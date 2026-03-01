import Foundation

struct ShortcutBinding: Codable, Identifiable, Equatable {
    let id: UUID
    var modifierKey: ModifierKey
    var engine: String              // "whisper" or "fluidaudio"
    var modelIdentifier: String     // whisper: model filename, fluidaudio: "v2"/"v3"
    var modelDisplayName: String    // human-readable: "Turbo V3 large", "Parakeet v3"

    init(id: UUID = UUID(), modifierKey: ModifierKey, engine: String, modelIdentifier: String, modelDisplayName: String) {
        self.id = id
        self.modifierKey = modifierKey
        self.engine = engine
        self.modelIdentifier = modelIdentifier
        self.modelDisplayName = modelDisplayName
    }

    /// Apply this binding's engine and model to AppPreferences.
    func apply() {
        let prefs = AppPreferences.shared
        prefs.selectedEngine = engine
        if engine == "whisper" {
            let modelsDir = WhisperModelManager.shared.modelsDirectory
            let fullPath = modelsDir.appendingPathComponent(modelIdentifier).path
            prefs.selectedWhisperModelPath = fullPath
        } else {
            prefs.fluidAudioModelVersion = modelIdentifier
        }
    }
}

extension AppPreferences {
    var shortcutBindings: [ShortcutBinding] {
        get {
            guard let json = UserDefaults.standard.string(forKey: "shortcutBindings"),
                  let data = json.data(using: .utf8),
                  let bindings = try? JSONDecoder().decode([ShortcutBinding].self, from: data) else {
                return []
            }
            return bindings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "shortcutBindings")
            }
        }
    }

    /// One-time migration from single modifierOnlyHotkey to shortcutBindings array.
    func migrateToShortcutBindings() {
        let migrated = UserDefaults.standard.bool(forKey: "shortcutBindingsMigrated")
        guard !migrated else { return }

        let modKey = ModifierKey(rawValue: modifierOnlyHotkey) ?? .none
        if modKey != .none {
            let engine = selectedEngine
            let modelId: String
            let modelName: String
            if engine == "fluidaudio" {
                modelId = fluidAudioModelVersion
                modelName = modelId == "v2" ? "Parakeet v2" : "Parakeet v3"
            } else {
                let path = selectedWhisperModelPath ?? ""
                modelId = (path as NSString).lastPathComponent
                modelName = modelId.isEmpty ? "Default" : modelId
                    .replacingOccurrences(of: "ggml-", with: "")
                    .replacingOccurrences(of: ".bin", with: "")
            }
            shortcutBindings = [ShortcutBinding(modifierKey: modKey, engine: engine, modelIdentifier: modelId, modelDisplayName: modelName)]
        }

        UserDefaults.standard.set(true, forKey: "shortcutBindingsMigrated")
    }
}
