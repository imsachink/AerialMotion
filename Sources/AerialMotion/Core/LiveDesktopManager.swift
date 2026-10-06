import Foundation
import AppKit
import AVFoundation
import IOKit.ps
import Combine

// MARK: - Desktop Player Layer View
// Backed directly by AVPlayerLayer for zero-copy hardware GPU rendering.

final class DesktopPlayerView: NSView {
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Desktop Window
// Sits directly above desktop wallpaper but underneath Finder desktop icons.

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var playerView: DesktopPlayerView? {
        contentView as? DesktopPlayerView
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Positioned between Apple static wallpaper (-2147483623) and Finder icons (-2147483603)
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = true
        self.isOpaque = true
        self.hasShadow = false
        self.backgroundColor = .black
        self.contentView = DesktopPlayerView()
        self.setFrame(screen.frame, display: true)
    }
}

// MARK: - LiveDesktopManager
// Manages continuous wallpaper motion on the Home Screen (Desktop) with
// extreme battery and power optimization inspired by Wallspace.

@MainActor
final class LiveDesktopManager: ObservableObject {

    static let shared = LiveDesktopManager()

    // MARK: - Settings (persisted)

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "liveDesktopEnabled")
            updatePlayback()
        }
    }

    @Published var pauseOnBattery: Bool {
        didSet {
            UserDefaults.standard.set(pauseOnBattery, forKey: "pauseOnBattery")
            evaluatePlaybackState()
        }
    }

    @Published var pauseInLowPowerMode: Bool {
        didSet {
            UserDefaults.standard.set(pauseInLowPowerMode, forKey: "pauseInLowPowerMode")
            evaluatePlaybackState()
        }
    }

    @Published var pauseWhenOccluded: Bool {
        didSet {
            UserDefaults.standard.set(pauseWhenOccluded, forKey: "pauseWhenOccluded")
            evaluatePlaybackState()
        }
    }

    // MARK: - Playback State

    @Published var isPlaying: Bool = false
    @Published var pauseReason: String? = nil

    var statusDescription: String {
        if !isEnabled {
            return "Off (Static Apple Desktop)"
        }
        if let reason = pauseReason {
            return reason
        }
        if isPlaying {
            return "Active (Hardware Accelerated)"
        }
        return "Idle"
    }

    // MARK: - Private State

    private var desktopWindows: [DesktopWindow] = []
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var activeVideoURL: URL?

    private var isScreenLocked: Bool = false
    private var isScreenSleeping: Bool = false
    private var isDesktopOccluded: Bool = false

    private init() {
        let savedEnabled = UserDefaults.standard.object(forKey: "liveDesktopEnabled") as? Bool ?? true
        let savedBattery = UserDefaults.standard.object(forKey: "pauseOnBattery") as? Bool ?? true
        let savedLPM = UserDefaults.standard.object(forKey: "pauseInLowPowerMode") as? Bool ?? true
        let savedOccluded = UserDefaults.standard.object(forKey: "pauseWhenOccluded") as? Bool ?? true

        self.isEnabled = savedEnabled
        self.pauseOnBattery = savedBattery
        self.pauseInLowPowerMode = savedLPM
        self.pauseWhenOccluded = savedOccluded

        setupMonitors()
    }

    // MARK: - Power & Environmental Monitors

    private func setupMonitors() {
        // 1. Screen Sleep & Wake
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenSleeping = true
                self?.evaluatePlaybackState()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenSleeping = false
                self?.evaluatePlaybackState()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenSleeping = true
                self?.evaluatePlaybackState()
            }
        }
        wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenSleeping = false
                self?.evaluatePlaybackState()
            }
        }

        // 2. Lock Screen Detect (distributed notifications)
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = true
                self?.evaluatePlaybackState()
            }
        }
        distCenter.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = false
                self?.evaluatePlaybackState()
            }
        }

        // 3. Low Power Mode (macOS Foundation)
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluatePlaybackState()
            }
        }

        // 4. Multi-Display Plug/Unplug & Resolution Changes
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconfigureScreens()
            }
        }

        // 5. Battery / Power Source Changes
        let powerSourceCallback: IOPowerSourceCallbackType = { _ in
            Task { @MainActor in
                LiveDesktopManager.shared.evaluatePlaybackState()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(powerSourceCallback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Battery Query

    private func isRunningOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                if state == (kIOPSBatteryPowerValue as String) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Occlusion Handling

    private func handleOcclusionChange() {
        guard !desktopWindows.isEmpty else { return }
        let anyVisible = desktopWindows.contains { $0.occlusionState.contains(.visible) }
        self.isDesktopOccluded = !anyVisible
        evaluatePlaybackState()
    }

    // MARK: - Window Management

    private func setupWindows() {
        closeWindows()
        guard isEnabled else { return }

        for screen in NSScreen.screens {
            let win = DesktopWindow(screen: screen)
            if let player = queuePlayer {
                win.playerView?.playerLayer.player = player
            }
            win.orderBack(nil)
            desktopWindows.append(win)

            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleOcclusionChange()
                }
            }
        }
    }

    private func closeWindows() {
        for win in desktopWindows {
            NotificationCenter.default.removeObserver(win)
            win.playerView?.playerLayer.player = nil
            win.orderOut(nil)
        }
        desktopWindows.removeAll()
    }

    private func reconfigureScreens() {
        guard isEnabled else { return }
        setupWindows()
        evaluatePlaybackState()
    }

    // MARK: - Wallpaper Control

    func startWithActiveWallpaper() {
        guard let activeID = WallpaperStore.shared.activeID,
              let item = WallpaperStore.shared.items.first(where: { $0.id == activeID }) else {
            return
        }
        let videoURL = fm.fileExists(atPath: item.libraryVideoURL.path) ? item.libraryVideoURL : item.catalogVideoURL
        if fm.fileExists(atPath: videoURL.path) {
            setVideoURL(videoURL)
        }
    }

    func setVideoURL(_ url: URL) {
        guard fm.fileExists(atPath: url.path) else { return }
        activeVideoURL = url

        guard isEnabled else {
            stopPlayback()
            return
        }

        // Initialize single hardware-accelerated looping player
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: item)
        self.playerLooper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.queuePlayer = player

        // Reconnect windows
        if desktopWindows.isEmpty {
            setupWindows()
        } else {
            for win in desktopWindows {
                win.playerView?.playerLayer.player = player
            }
        }

        evaluatePlaybackState()
    }

    func stopPlayback() {
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        playerLooper = nil
        queuePlayer = nil
        activeVideoURL = nil
        closeWindows()
        isPlaying = false
        pauseReason = nil
    }

    private func updatePlayback() {
        if isEnabled {
            if let url = activeVideoURL {
                setVideoURL(url)
            } else {
                startWithActiveWallpaper()
            }
        } else {
            stopPlayback()
        }
    }

    // MARK: - Smart Playback State Evaluator

    func evaluatePlaybackState() {
        guard isEnabled else {
            if isPlaying {
                queuePlayer?.pause()
                isPlaying = false
            }
            pauseReason = "Disabled"
            return
        }

        guard let player = queuePlayer else {
            isPlaying = false
            pauseReason = "No active wallpaper"
            return
        }

        // Priority 1: Screen sleep or locked
        if isScreenSleeping || isScreenLocked {
            player.pause()
            isPlaying = false
            pauseReason = "Display locked / asleep"
            return
        }

        // Priority 2: Low Power Mode
        if pauseInLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled {
            player.pause()
            isPlaying = false
            pauseReason = "Paused: Low Power Mode"
            return
        }

        // Priority 3: Battery Saver (Wallspace rule)
        if pauseOnBattery && isRunningOnBattery() {
            player.pause()
            isPlaying = false
            pauseReason = "Paused: Battery Saver"
            return
        }

        // Priority 4: Desktop Obscured (all windows covering desktop)
        if pauseWhenOccluded && isDesktopOccluded {
            player.pause()
            isPlaying = false
            pauseReason = "Paused: Desktop Hidden"
            return
        }

        // All checks clear — play smoothly!
        player.play()
        isPlaying = true
        pauseReason = nil
    }
}
