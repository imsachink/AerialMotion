import AppKit
import SwiftUI

// MARK: - SettingsWindowManager
// Manages a dedicated, native macOS Settings window so that interaction with buttons,
// file pickers, or system preferences never collapses the settings interface.

@MainActor
final class SettingsWindowManager: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(WallpaperStore.shared)
            .environmentObject(LiveDesktopManager.shared)

        let hosting = NSHostingController(rootView: settingsView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "AerialMotion Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.window = nil
        }
    }
}
