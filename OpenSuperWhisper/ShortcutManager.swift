import AppKit
import ApplicationServices
import Carbon
import Cocoa
import Foundation
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let escape = Self("escape", default: .init(.escape))
}

class ShortcutManager {
    static let shared = ShortcutManager()

    private var activeVm: IndicatorViewModel?
    private var holdWorkItem: DispatchWorkItem?
    private let holdThreshold: TimeInterval = 0.3
    private var holdMode = false
    private var activeModifierKey: ModifierKey?
    private var bindings: [ShortcutBinding] = []

    private init() {
        print("ShortcutManager init")

        AppPreferences.shared.migrateToShortcutBindingsV2()
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
        holdMode = false
    }

    @objc private func hotkeySettingsChanged() {
        setupBindings()
    }

    @objc private func accessibilityPermissionGranted() {
        print("ShortcutManager: Accessibility permission granted, re-setting up bindings")
        setupBindings()
    }

    private func setupBindings() {
        // Clean up previous handlers
        KeyboardShortcuts.removeAllHandlers()
        ModifierKeyMonitor.shared.stop()

        bindings = AppPreferences.shared.shortcutBindings

        // Separate bindings by trigger type
        let modifierBindings = bindings.filter { $0.triggerType == .singleModifier }
        let comboBindings = bindings.filter { $0.triggerType == .keyCombination }

        // Set up modifier key bindings
        if !modifierBindings.isEmpty {
            let modifierKeys = Set(modifierBindings.map { $0.modifierKey })

            ModifierKeyMonitor.shared.onKeyDown = { [weak self] key in
                self?.activeModifierKey = key
                self?.applyBinding(forModifierKey: key)
                self?.handleKeyDown()
            }

            ModifierKeyMonitor.shared.onKeyUp = { [weak self] _ in
                self?.handleKeyUp()
                self?.activeModifierKey = nil
            }

            ModifierKeyMonitor.shared.start(modifierKeys: modifierKeys)
            let names = modifierKeys.map { $0.displayName }.joined(separator: ", ")
            print("ShortcutManager: Monitoring modifier keys: \(names)")
        }

        // Set up key combo bindings
        for binding in comboBindings {
            let name = binding.keyboardShortcutsName

            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                self?.applyBinding(forSlot: binding.keyComboSlot)
                self?.handleKeyDown()
            }

            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                self?.handleKeyUp()
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

        print("ShortcutManager: Set up \(modifierBindings.count) modifier + \(comboBindings.count) combo bindings")
    }

    private func applyBinding(forModifierKey key: ModifierKey) {
        guard let binding = bindings.first(where: { $0.triggerType == .singleModifier && $0.modifierKey == key }) else { return }
        binding.apply()
        Task { @MainActor in
            TranscriptionService.shared.reloadEngine()
        }
    }

    private func applyBinding(forSlot slot: String) {
        guard let binding = bindings.first(where: { $0.keyComboSlot == slot }) else { return }
        binding.apply()
        Task { @MainActor in
            TranscriptionService.shared.reloadEngine()
        }
    }

    private func handleKeyDown() {
        holdWorkItem?.cancel()
        holdMode = false

        // Disable hold-to-record for Command/Option keys (too easy to hold accidentally)
        let holdToRecordEnabled = AppPreferences.shared.holdToRecord
            && !(activeModifierKey?.isCommandOrOption ?? false)

        Task { @MainActor in
            if self.activeVm == nil {
                let cursorPosition = FocusUtils.getCurrentCursorPosition()
                let indicatorPoint: NSPoint?
                if let caret = FocusUtils.getCaretRect() {
                    indicatorPoint = FocusUtils.convertAXPointToCocoa(caret.origin)
                } else {
                    indicatorPoint = cursorPosition
                }
                let vm = IndicatorWindowManager.shared.show(nearPoint: indicatorPoint)
                vm.startRecording()
                self.activeVm = vm
            } else if !self.holdMode {
                IndicatorWindowManager.shared.stopRecording()
                self.activeVm = nil
            }
        }

        if holdToRecordEnabled {
            let workItem = DispatchWorkItem { [weak self] in
                self?.holdMode = true
            }
            holdWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: workItem)
        }
    }

    private func handleKeyUp() {
        holdWorkItem?.cancel()
        holdWorkItem = nil

        let holdToRecordEnabled = AppPreferences.shared.holdToRecord

        Task { @MainActor in
            if holdToRecordEnabled && self.holdMode {
                IndicatorWindowManager.shared.stopRecording()
                self.activeVm = nil
                self.holdMode = false
            }
        }
    }
}
