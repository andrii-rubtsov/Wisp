import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
class IndicatorWindowManager: IndicatorViewDelegate {
    static let shared = IndicatorWindowManager()
    
    var window: NSWindow?
    var viewModel: IndicatorViewModel?
    
    private init() {}
    
    func show(nearPoint point: NSPoint? = nil) -> IndicatorViewModel {
        
        KeyboardShortcuts.enable(.escape)
        
        // Create new view model
        let newViewModel = IndicatorViewModel()
        newViewModel.delegate = self
        viewModel = newViewModel
        
        if window == nil {
            // Create window if it doesn't exist - using NSPanel for full-screen compatibility
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 230, height: 60),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            panel.isFloatingPanel = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            
            self.window = panel
        }
        
        // Position window
        let position = AppPreferences.shared.indicatorPosition
        let targetScreen: NSScreen?
        if position == .nearCursor {
            targetScreen = point.flatMap { FocusUtils.screenContaining(point: $0) } ?? NSScreen.main
        } else {
            targetScreen = NSScreen.main
        }

        if let window = window, let screen = targetScreen {
            let windowFrame = window.frame
            let screenFrame = screen.visibleFrame
            let margin: CGFloat = 20

            var x: CGFloat
            var y: CGFloat

            switch position {
            case .nearCursor:
                if let point = point {
                    x = point.x - windowFrame.width / 2
                    y = point.y + 20
                } else {
                    x = screenFrame.midX - windowFrame.width / 2
                    y = screenFrame.maxY - windowFrame.height - 100
                }
            case .lowerLeft:
                x = screenFrame.minX + margin
                y = screenFrame.minY + margin
            case .lowerRight:
                x = screenFrame.maxX - windowFrame.width - margin
                y = screenFrame.minY + margin
            case .upperLeft:
                x = screenFrame.minX + margin
                y = screenFrame.maxY - windowFrame.height - margin
            case .upperRight:
                x = screenFrame.maxX - windowFrame.width - margin
                y = screenFrame.maxY - windowFrame.height - margin
            }

            // Clamp to screen bounds
            x = max(screenFrame.minX, min(x, screenFrame.maxX - windowFrame.width))
            y = max(screenFrame.minY, min(y, screenFrame.maxY - windowFrame.height))

            window.setFrameOrigin(NSPoint(x: x, y: y))

            // Set content view
            let hostingView = NSHostingView(rootView: IndicatorWindow(viewModel: newViewModel))
            window.contentView = hostingView
        }
        
        window?.orderFront(nil)
        return newViewModel
    }
    
    func stopRecording() {
        viewModel?.startDecoding()
    }
    
    func stopForce() {
        viewModel?.cancelRecording()
        viewModel?.cleanup()
        hide()
    }

    func hide() {
        KeyboardShortcuts.disable(.escape)
        
        Task {
            guard let viewModel = self.viewModel else { return }
            
            await viewModel.hideWithAnimation()
            viewModel.cleanup()
            
            self.window?.contentView = nil
            self.window?.orderOut(nil)
            self.viewModel = nil
            
            NotificationCenter.default.post(name: .indicatorWindowDidHide, object: nil)
        }
    }
    
    func didFinishDecoding() {
        hide()
    }
}
