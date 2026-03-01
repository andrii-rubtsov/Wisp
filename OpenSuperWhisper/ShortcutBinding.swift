import Foundation
import KeyboardShortcuts

enum ShortcutTriggerType: String, Codable, CaseIterable, Identifiable {
    case singleModifier
    case keyCombination

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleModifier: return "Single Key"
        case .keyCombination: return "Key Combo"
        }
    }
}

struct ShortcutBinding: Codable, Identifiable, Equatable {
    let id: UUID
    var triggerType: ShortcutTriggerType
    var modifierKey: ModifierKey         // used when triggerType == .singleModifier
    var keyComboSlot: String             // "binding-0" etc, used for KeyboardShortcuts.Name
    var engine: String                   // "whisper" or "fluidaudio"
    var modelIdentifier: String          // whisper: model filename, fluidaudio: "v2"/"v3"
    var modelDisplayName: String         // human-readable: "Turbo V3 large", "Parakeet v3"
    var initialPrompt: String            // whisper only: per-binding initial prompt

    init(
        id: UUID = UUID(),
        triggerType: ShortcutTriggerType = .singleModifier,
        modifierKey: ModifierKey = .leftCommand,
        keyComboSlot: String = "",
        engine: String,
        modelIdentifier: String,
        modelDisplayName: String,
        initialPrompt: String = ""
    ) {
        self.id = id
        self.triggerType = triggerType
        self.modifierKey = modifierKey
        self.keyComboSlot = keyComboSlot
        self.engine = engine
        self.modelIdentifier = modelIdentifier
        self.modelDisplayName = modelDisplayName
        self.initialPrompt = initialPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        triggerType = try container.decode(ShortcutTriggerType.self, forKey: .triggerType)
        modifierKey = try container.decode(ModifierKey.self, forKey: .modifierKey)
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
            guard let json = UserDefaults.standard.string(forKey: "shortcutBindingsV2"),
                  let data = json.data(using: .utf8),
                  let bindings = try? JSONDecoder().decode([ShortcutBinding].self, from: data) else {
                return []
            }
            return bindings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "shortcutBindingsV2")
            }
        }
    }

    /// Migrate from v1 shortcutBindings (no triggerType) or legacy modifierOnlyHotkey.
    func migrateToShortcutBindingsV2() {
        let migrated = UserDefaults.standard.bool(forKey: "shortcutBindingsV2Migrated")
        guard !migrated else { return }

        // Try migrating from v1 bindings first
        if let json = UserDefaults.standard.string(forKey: "shortcutBindings"),
           let data = json.data(using: .utf8),
           let oldBindings = try? JSONDecoder().decode([ShortcutBindingV1].self, from: data),
           !oldBindings.isEmpty {
            let newBindings = oldBindings.enumerated().map { (index, old) in
                ShortcutBinding(
                    id: old.id,
                    triggerType: .singleModifier,
                    modifierKey: old.modifierKey,
                    keyComboSlot: ShortcutBinding.slotNames[index],
                    engine: old.engine,
                    modelIdentifier: old.modelIdentifier,
                    modelDisplayName: old.modelDisplayName
                )
            }
            shortcutBindings = Array(newBindings.prefix(ShortcutBinding.maxBindings))
            UserDefaults.standard.set(true, forKey: "shortcutBindingsV2Migrated")
            return
        }

        // Try migrating from legacy modifierOnlyHotkey
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
            shortcutBindings = [ShortcutBinding(
                triggerType: .singleModifier,
                modifierKey: modKey,
                keyComboSlot: "binding-0",
                engine: engine,
                modelIdentifier: modelId,
                modelDisplayName: modelName
            )]
        }

        UserDefaults.standard.set(true, forKey: "shortcutBindingsV2Migrated")
    }

    /// Ensure at least one binding exists; create a default with Parakeet v3.
    func ensureDefaultBinding() {
        guard shortcutBindings.isEmpty else { return }
        shortcutBindings = [ShortcutBinding(
            triggerType: .singleModifier,
            modifierKey: .leftCommand,
            keyComboSlot: "binding-0",
            engine: "fluidaudio",
            modelIdentifier: "v3",
            modelDisplayName: "Parakeet v3"
        )]
    }
}

// MARK: - V1 migration helper

private struct ShortcutBindingV1: Codable, Identifiable {
    let id: UUID
    var modifierKey: ModifierKey
    var engine: String
    var modelIdentifier: String
    var modelDisplayName: String
}
