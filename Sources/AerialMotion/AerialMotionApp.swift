import SwiftUI
import AppKit

// MARK: - App entry point

@main
struct AerialMotionApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = WallpaperStore.shared
    @AppStorage("menuBarMonochrome") private var menuBarMonochrome: Bool = false

    var body: some Scene {
        // Menu bar popover — custom branded app icon
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            if let icon = currentMenuBarIcon {
                Image(nsImage: icon)
            } else {
                Label("AerialMotion", systemImage: "photo.tv")
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var currentMenuBarIcon: NSImage? {
        if menuBarMonochrome {
            return AppLogo.menuBarTemplateIcon ?? AppLogo.menuBarColorIcon
        } else {
            return AppLogo.menuBarColorIcon ?? AppLogo.menuBarTemplateIcon
        }
    }
}

// MARK: - AppDelegate
// Hides dock icon (LSUIElement equivalent via code).

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock — this app lives only in the menu bar
        NSApp.setActivationPolicy(.accessory)

        // Ensure library directories exist on first launch
        let dirs = [libDir, thumbLibDir, aerialMotionRoot]
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing any window (e.g. settings sheet) should NOT quit the app
        false
    }
}
