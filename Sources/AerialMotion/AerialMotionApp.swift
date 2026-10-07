import SwiftUI
import AppKit

@main
struct AerialMotionApp: App {

    @StateObject private var store = WallpaperStore.shared
    @StateObject private var liveDesktop = LiveDesktopManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("menuBarMonochrome") private var menuBarMonochrome: Bool = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(liveDesktop)
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
// Manages accessory activation, directory setup, and background lifecycle.

@MainActor
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

        // Initialize Live Desktop engine if enabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            LiveDesktopManager.shared.startWithActiveWallpaper()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
