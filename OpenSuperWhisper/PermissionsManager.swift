import AVFoundation
import AppKit
import Foundation

enum Permission {
    case microphone
    case accessibility
}

class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var isMicrophonePermissionGranted = false
    @Published var isAccessibilityPermissionGranted = false

    private var permissionCheckTimer: Timer?
    private var backgroundAccessibilityTimer: Timer?
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        checkMicrophonePermission()
        checkAccessibilityPermission()

        setupWindowObservers()
        startBackgroundAccessibilityPolling()
    }

    deinit {
        stopPermissionChecking()
        backgroundAccessibilityTimer?.invalidate()
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupWindowObservers() {
        let showObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startPermissionChecking()
        }

        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPermissionChecking()
        }

        let hideObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPermissionChecking()
        }

        windowObservers = [showObserver, closeObserver, hideObserver]

        if let window = NSApplication.shared.mainWindow, window.isKeyWindow {
            startPermissionChecking()
        }
    }

    /// Polls accessibility permission continuously (even when window not visible)
    /// so that ShortcutManager can be notified immediately when permission is granted.
    private func startBackgroundAccessibilityPolling() {
        guard backgroundAccessibilityTimer == nil else { return }
        backgroundAccessibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            let granted = AXIsProcessTrusted()
            guard let self else {
                timer.invalidate()
                return
            }
            let wasGranted = self.isAccessibilityPermissionGranted
            DispatchQueue.main.async {
                self.isAccessibilityPermissionGranted = granted
            }
            if granted && !wasGranted {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
                }
            }
            // Once granted, slow down polling
            if granted {
                timer.invalidate()
                self.backgroundAccessibilityTimer = nil
            }
        }
    }

    private func startPermissionChecking() {
        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkMicrophonePermission()
            self?.checkAccessibilityPermission()
        }
    }

    private func stopPermissionChecking() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        DispatchQueue.main.async { [weak self] in
            switch status {
            case .authorized:
                self?.isMicrophonePermissionGranted = true
            default:
                self?.isMicrophonePermissionGranted = false
            }
        }
    }

    func checkAccessibilityPermission() {
        let granted = AXIsProcessTrusted()
        let wasGranted = isAccessibilityPermissionGranted
        DispatchQueue.main.async { [weak self] in
            self?.isAccessibilityPermissionGranted = granted
        }
        if granted && !wasGranted {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
            }
            // Stop background polling since permission is now granted
            backgroundAccessibilityTimer?.invalidate()
            backgroundAccessibilityTimer = nil
        }
    }

    func requestMicrophonePermissionOrOpenSystemPreferences() {

        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isMicrophonePermissionGranted = granted
                }
            }
        case .authorized:
            self.isMicrophonePermissionGranted = true
        default:
            openSystemPreferences(for: .microphone)
        }
    }

    func openSystemPreferences(for permission: Permission) {
        let urlString: String
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString =
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        if let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
