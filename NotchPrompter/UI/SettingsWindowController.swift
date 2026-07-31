import AppKit
import SwiftUI

/// Single settings window, managed by hand so the menu-bar app keeps full control
/// over when it appears and whether the app shows up in the Dock.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        // A real menu bar while the window is open, so ⌘C / ⌘V / ⌘Z behave normally.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchPrompter"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsWindowView())
        window.setFrameAutosaveName("NotchPrompterSettings")
        if window.frame.origin == .zero { window.center() }
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only once the window goes away.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
