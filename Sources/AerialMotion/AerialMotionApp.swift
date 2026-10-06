import SwiftUI
import AppKit

// MARK: - App entry point

@main
struct AerialMotionApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = WallpaperStore.shared
    @StateObject private var liveDesktop = LiveDesktopManager.shared
    @AppStorage("menuBarMonochrome") private var menuBarMonochrome: Bool = false

    var body: some Scene {
        // Menu bar popover — custom branded app icon
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
// Manages accessory activation, status bar right-click menu, and global shortcuts.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var globalRightClickMonitor: Any?
    private var localRightClickMonitor: Any?

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

        // Attach right-click context menu to menu bar icon
        setupStatusBarRightClick()
    }

    private func setupStatusBarRightClick() {
        // Local event monitor when app/window is active
        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseUp]) { [weak self] event in
            if let window = event.window, NSStringFromClass(type(of: window)).contains("StatusBar") {
                self?.presentContextMenu(at: NSEvent.mouseLocation)
                return nil
            }
            return event
        }

        // Global monitor for right clicks in the menu bar area
        globalRightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseUp]) { [weak self] event in
            guard let screen = NSScreen.main else { return }
            let mouseLoc = NSEvent.mouseLocation
            // If right-clicked in top menu bar area (typically y >= height - 35)
            if mouseLoc.y >= (screen.frame.maxY - 35) {
                self?.presentContextMenu(at: mouseLoc)
            }
        }

        // Periodically attach gesture directly to the status bar button
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.attachGestureToStatusBarButton()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.attachGestureToStatusBarButton()
        }
    }

    private func attachGestureToStatusBarButton() {
        for window in NSApp.windows {
            if NSStringFromClass(type(of: window)).contains("StatusBar") {
                if let contentView = window.contentView {
                    findButtonAndAttachGesture(in: contentView)
                }
            }
        }
    }

    private func findButtonAndAttachGesture(in view: NSView) {
        if let button = view as? NSButton {
            let alreadyHas = button.gestureRecognizers.contains { $0 is NSClickGestureRecognizer }
            if !alreadyHas {
                let gesture = NSClickGestureRecognizer(target: self, action: #selector(handleStatusButtonRightClick(_:)))
                gesture.buttonMask = 0x2 // right click
                button.addGestureRecognizer(gesture)
            }
            return
        }
        for sub in view.subviews {
            findButtonAndAttachGesture(in: sub)
        }
    }

    @objc private func handleStatusButtonRightClick(_ gesture: NSClickGestureRecognizer) {
        if gesture.state == .ended {
            presentContextMenu(at: NSEvent.mouseLocation)
        }
    }

    func presentContextMenu(at location: NSPoint) {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "AerialMotion v\(UpdateChecker.shared.currentVersion)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let desktopMotionItem = NSMenuItem(title: "Continuous Desktop Motion", action: #selector(toggleDesktopMotionAction), keyEquivalent: "d")
        desktopMotionItem.target = self
        desktopMotionItem.state = LiveDesktopManager.shared.isEnabled ? .on : .off
        menu.addItem(desktopMotionItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesAction), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let openFolderItem = NSMenuItem(title: "Open Wallpapers Folder", action: #selector(openLibraryFolderAction), keyEquivalent: "o")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(NSMenuItem.separator())

        let coffeeItem = NSMenuItem(title: "Buy Me a Coffee ☕", action: #selector(coffeeAction), keyEquivalent: "")
        coffeeItem.target = self
        menu.addItem(coffeeItem)

        let gitHubItem = NSMenuItem(title: "GitHub Repository", action: #selector(gitHubAction), keyEquivalent: "")
        gitHubItem.target = self
        menu.addItem(gitHubItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit AerialMotion", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: location, in: nil)
    }

    @objc private func toggleDesktopMotionAction() {
        LiveDesktopManager.shared.isEnabled.toggle()
    }

    @objc private func checkForUpdatesAction() {
        Task { @MainActor in
            await UpdateChecker.shared.checkForUpdates(userInitiated: true)
        }
    }

    @objc private func openSettingsAction() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsRequested"), object: nil)
    }

    @objc private func openLibraryFolderAction() {
        NSWorkspace.shared.open(libDir)
    }

    @objc private func coffeeAction() {
        if let url = URL(string: "https://buymeacoffee.com/sachinkaundal") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func gitHubAction() {
        if let url = URL(string: "https://github.com/imsachink/AerialMotion") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
