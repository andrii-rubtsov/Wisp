import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let escape = Self("escape", default: .init(.escape))
}

class ShortcutManager {
    static let shared = ShortcutManager()

    private var activeVm: IndicatorViewModel?
    private var bindings: [ShortcutBinding] = []
    private var activeBinding: ShortcutBinding?

    private init() {
        print("ShortcutManager init")

        AppPreferences.shared.migrateToShortcutBindingsV3()
        AppPreferences.shared.ensureDefaultBinding()

        setupBindings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeySettingsChanged),
            name: .hotkeySettingsChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indicatorWindowDidHide),
            name: .indicatorWindowDidHide,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityPermissionGranted),
            name: .accessibilityPermissionGranted,
            object: nil
        )
    }

    @objc private func indicatorWindowDidHide() {
        activeVm = nil
    }

    @objc private func hotkeySettingsChanged() {
        setupBindings()
    }

    @objc private func accessibilityPermissionGranted() {
        print("ShortcutManager: Accessibility permission granted, re-setting up bindings")
        setupBindings()
    }

    private func setupBindings() {
        KeyboardShortcuts.removeAllHandlers()

        bindings = AppPreferences.shared.shortcutBindings

        for binding in bindings {
            let name = binding.keyboardShortcutsName

            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                self?.applyBinding(forSlot: binding.keyComboSlot)
                self?.handleKeyDown()
            }

            if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
                print("ShortcutManager: Key combo [\(binding.keyComboSlot)]: \(shortcut)")
            } else {
                print("ShortcutManager: Key combo [\(binding.keyComboSlot)]: (not yet assigned)")
            }
        }

        // Escape key — always registered for force-stop
        KeyboardShortcuts.onKeyUp(for: .escape) { [weak self] in
            Task { @MainActor in
                if self?.activeVm != nil {
                    IndicatorWindowManager.shared.stopForce()
                    self?.activeVm = nil
                }
            }
        }
        KeyboardShortcuts.disable(.escape)

        print("ShortcutManager: Set up \(bindings.count) combo bindings")
    }

    private func applyBinding(forSlot slot: String) {
        guard let binding = bindings.first(where: { $0.keyComboSlot == slot }) else { return }
        activeBinding = binding
        binding.apply()
        Task { @MainActor in
            TranscriptionService.shared.reloadEngine()
        }
    }

    private func handleKeyDown() {
        Task { @MainActor in
            // Ignore shortcut while transcription is in progress
            if TranscriptionService.shared.isTranscribing || TranscriptionQueue.shared.isProcessing {
                return
            }

            if self.activeVm == nil {
                let cursorPosition = FocusUtils.getCurrentCursorPosition()
                let indicatorPoint: NSPoint?
                if let caret = FocusUtils.getCaretRect() {
                    indicatorPoint = FocusUtils.convertAXPointToCocoa(caret.origin)
                } else {
                    indicatorPoint = cursorPosition
                }
                let vm = IndicatorWindowManager.shared.show(nearPoint: indicatorPoint)
                vm.activeBinding = self.activeBinding
                vm.startRecording()
                self.activeVm = vm
            } else {
                IndicatorWindowManager.shared.stopRecording()
                self.activeVm = nil
            }
        }
    }
}
