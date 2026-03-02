import Foundation
import KeyboardShortcuts

struct ShortcutBinding: Codable, Identifiable, Equatable {
    let id: UUID
    var keyComboSlot: String             // "binding-0" etc, used for KeyboardShortcuts.Name
    var engine: String                   // "whisper" or "fluidaudio"
    var modelIdentifier: String          // whisper: model filename, fluidaudio: "v2"/"v3"
    var modelDisplayName: String         // human-readable: "Turbo V3 large", "Parakeet v3"
    var initialPrompt: String            // whisper only: per-binding initial prompt

    init(
        id: UUID = UUID(),
        keyComboSlot: String = "",
        engine: String,
        modelIdentifier: String,
        modelDisplayName: String,
        initialPrompt: String = ""
    ) {
        self.id = id
        self.keyComboSlot = keyComboSlot
        self.engine = engine
        self.modelIdentifier = modelIdentifier
        self.modelDisplayName = modelDisplayName
        self.initialPrompt = initialPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyComboSlot = try container.decode(String.self, forKey: .keyComboSlot)
        engine = try container.decode(String.self, forKey: .engine)
        modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
        modelDisplayName = try container.decode(String.self, forKey: .modelDisplayName)
        initialPrompt = try container.decodeIfPresent(String.self, forKey: .initialPrompt) ?? ""
    }

    /// The KeyboardShortcuts.Name for this binding's key combo slot.
    var keyboardShortcutsName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name(keyComboSlot)
    }

    /// Apply this binding's engine, model, and initial prompt to AppPreferences.
    func apply() {
        let prefs = AppPreferences.shared
        prefs.selectedEngine = engine
        if engine == "whisper" {
            let modelsDir = WhisperModelManager.shared.modelsDirectory
            let fullPath = modelsDir.appendingPathComponent(modelIdentifier).path
            prefs.selectedWhisperModelPath = fullPath
            prefs.initialPrompt = initialPrompt
        } else {
            prefs.fluidAudioModelVersion = modelIdentifier
            prefs.initialPrompt = ""
        }
    }
}

// MARK: - Slot management

extension ShortcutBinding {
    static let maxBindings = 5
    static let slotNames = (0..<maxBindings).map { "binding-\($0)" }

    /// Returns the first available slot not used by existing bindings.
    static func nextAvailableSlot(excluding bindings: [ShortcutBinding]) -> String {
        let used = Set(bindings.map { $0.keyComboSlot })
        return slotNames.first { !used.contains($0) } ?? slotNames.last!
    }
}

// MARK: - AppPreferences extension

extension AppPreferences {
    var shortcutBindings: [ShortcutBinding] {
        get {
            guard let json = UserDefaults.standard.string(forKey: "shortcutBindingsV3"),
                  let data = json.data(using: .utf8),
                  let bindings = try? JSONDecoder().decode([ShortcutBinding].self, from: data) else {
                return []
            }
            return bindings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "shortcutBindingsV3")
            }
        }
    }

    /// Migrate from v2 shortcutBindings (had triggerType/modifierKey) to v3 (key combo only).
    func migrateToShortcutBindingsV3() {
        let migrated = UserDefaults.standard.bool(forKey: "shortcutBindingsV3Migrated")
        guard !migrated else { return }

        // Try migrating from v2 bindings — drop singleModifier fields, keep key combo ones
        if let json = UserDefaults.standard.string(forKey: "shortcutBindingsV2"),
           let data = json.data(using: .utf8),
           let oldBindings = try? JSONDecoder().decode([ShortcutBindingV2].self, from: data),
           !oldBindings.isEmpty {
            let comboBindings = oldBindings.filter { $0.triggerType == "keyCombination" }
            let newBindings = comboBindings.map { old in
                ShortcutBinding(
                    id: old.id,
                    keyComboSlot: old.keyComboSlot,
                    engine: old.engine,
                    modelIdentifier: old.modelIdentifier,
                    modelDisplayName: old.modelDisplayName,
                    initialPrompt: old.initialPrompt ?? ""
                )
            }
            if !newBindings.isEmpty {
                shortcutBindings = Array(newBindings.prefix(ShortcutBinding.maxBindings))
            }
        }

        UserDefaults.standard.set(true, forKey: "shortcutBindingsV3Migrated")
    }

    /// Ensure at least one binding exists; create a default with Parakeet v3.
    func ensureDefaultBinding() {
        guard shortcutBindings.isEmpty else { return }
        shortcutBindings = [ShortcutBinding(
            keyComboSlot: "binding-0",
            engine: "fluidaudio",
            modelIdentifier: "v3",
            modelDisplayName: "Parakeet v3"
        )]
    }
}

// MARK: - V2 migration helper

private struct ShortcutBindingV2: Codable {
    let id: UUID
    let triggerType: String
    let keyComboSlot: String
    let engine: String
    let modelIdentifier: String
    let modelDisplayName: String
    let initialPrompt: String?
}
