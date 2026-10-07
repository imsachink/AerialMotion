import Foundation
import AppKit

// MARK: - UpdateChecker
// Checks GitHub Releases API for new AerialMotion releases, downloads updates in-app,
// extracts the DMG, replaces the app bundle, and relaunches automatically.

@MainActor
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()

    // MARK: - Published State

    @Published var isChecking: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var releaseURL: URL?
    @Published var downloadURL: URL?
    @Published var downloadSize: Int64 = 0

    @Published var isUpdating: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var updateStatus: String = ""
    @Published var updateError: String? = nil

    @Published var statusMessage: String?
    @Published var lastChecked: Date?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.2"
    }

    private let repo = "imsachink/AerialMotion"

    // MARK: - Check for Updates

    func checkForUpdates(userInitiated: Bool = true) async {
        guard !isChecking && !isUpdating else { return }
        isChecking = true
        statusMessage = "Checking for updates..."

        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            statusMessage = "Invalid update URL."
            return
        }

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("AerialMotion/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if userInitiated {
                    statusMessage = "No releases found on GitHub."
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                statusMessage = "Could not parse release information."
                return
            }

            let remoteVer = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let localVer  = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

            self.latestVersion = tagName
            self.releaseNotes  = json["body"] as? String ?? ""
            if let htmlURLStr = json["html_url"] as? String, let htmlURL = URL(string: htmlURLStr) {
                self.releaseURL = htmlURL
            }

            // Parse DMG asset for direct in-app downloading
            self.downloadURL = nil
            self.downloadSize = 0
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String, name.lowercased().hasSuffix(".dmg"),
                       let dlStr = asset["browser_download_url"] as? String,
                       let dlURL = URL(string: dlStr) {
                        self.downloadURL = dlURL
                        self.downloadSize = (asset["size"] as? Int64) ?? 0
                        break
                    }
                }
            }

            self.lastChecked = Date()

            if isVersion(remoteVer, greaterThan: localVer) {
                self.updateAvailable = true
                self.statusMessage = "New version \(tagName) available!"
                if userInitiated {
                    showUpdateAlert(newVersion: tagName, notes: self.releaseNotes)
                }
            } else {
                self.updateAvailable = false
                self.statusMessage = "AerialMotion is up to date (v\(localVer))."
                if userInitiated {
                    showUpToDateAlert(version: localVer)
                }
            }
        } catch {
            if userInitiated {
                self.statusMessage = "Could not reach GitHub: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Semver comparator

    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let p1 = v1.split(separator: ".").compactMap { Int($0) }
        let p2 = v2.split(separator: ".").compactMap { Int($0) }

        let count = max(p1.count, p2.count)
        for i in 0..<count {
            let num1 = i < p1.count ? p1[i] : 0
            let num2 = i < p2.count ? p2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }

    // MARK: - Direct In-App Auto-Update

    func installUpdate() async {
        guard let url = downloadURL else {
            // Fallback only if no DMG was uploaded in release assets
            if let relURL = self.releaseURL {
                NSWorkspace.shared.open(relURL)
            }
            return
        }

        isUpdating = true
        downloadProgress = 0.0
        updateStatus = "Downloading AerialMotion \(latestVersion)..."
        updateError = nil

        let tempDMG = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AerialMotion_Update_\(UUID().uuidString).dmg")
        try? FileManager.default.removeItem(at: tempDMG)

        do {
            // 1. Download DMG with live progress tracking
            try await downloadDMG(from: url, to: tempDMG)

            // 2. Install update and relaunch
            updateStatus = "Installing update..."
            downloadProgress = 1.0

            try await applyDMG(dmgURL: tempDMG)
        } catch {
            isUpdating = false
            updateError = error.localizedDescription
            updateStatus = "Update failed: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: tempDMG)

            let alert = NSAlert()
            alert.messageText = "Update Failed"
            alert.informativeText = "Unable to complete in-app update: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func downloadDMG(from url: URL, to destination: URL) async throws {
        var req = URLRequest(url: url)
        req.setValue("AerialMotion/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : self.downloadSize

        guard let outputStream = OutputStream(url: destination, append: false) else {
            throw NSError(domain: "UpdateChecker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open temporary file stream."])
        }
        outputStream.open()
        defer { outputStream.close() }

        var count: Int64 = 0
        var buffer = [UInt8]()
        buffer.reserveCapacity(65536)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 65536 {
                _ = buffer.withUnsafeBufferPointer { ptr in
                    outputStream.write(ptr.baseAddress!, maxLength: buffer.count)
                }
                count += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if total > 0 {
                    let progress = Double(count) / Double(total)
                    await MainActor.run {
                        self.downloadProgress = min(progress, 0.99)
                        let dlMB = Double(count) / 1_000_000
                        let totMB = Double(total) / 1_000_000
                        self.updateStatus = String(format: "Downloading: %.1f MB / %.1f MB (%.0f%%)", dlMB, totMB, progress * 100)
                    }
                }
            }
        }

        if !buffer.isEmpty {
            _ = buffer.withUnsafeBufferPointer { ptr in
                outputStream.write(ptr.baseAddress!, maxLength: buffer.count)
            }
            count += Int64(buffer.count)
        }
    }

    private func applyDMG(dmgURL: URL) async throws {
        let mountPoint = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AerialMotion_Mount_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint.path, "-force", "-quiet"]
            try? detach.run()
            detach.waitUntilExit()
            try? FileManager.default.removeItem(at: mountPoint)
            try? FileManager.default.removeItem(at: dmgURL)
        }

        // Attach DMG
        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", dmgURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else {
            throw NSError(domain: "UpdateChecker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to mount update package."])
        }

        // Locate new app bundle
        let appInDMG = mountPoint.appendingPathComponent("AerialMotion.app")
        guard FileManager.default.fileExists(atPath: appInDMG.path) else {
            throw NSError(domain: "UpdateChecker", code: 3, userInfo: [NSLocalizedDescriptionKey: "No AerialMotion.app bundle inside update."])
        }

        // Determine target application path
        let targetAppURL: URL
        let currentBundle = Bundle.main.bundleURL
        if currentBundle.pathExtension == "app" {
            targetAppURL = currentBundle
        } else {
            targetAppURL = URL(fileURLWithPath: "/Applications/AerialMotion.app")
        }

        // Stage and remove quarantine
        let stagedApp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AerialMotion_Staged_\(UUID().uuidString).app")
        try? FileManager.default.removeItem(at: stagedApp)
        try FileManager.default.copyItem(at: appInDMG, to: stagedApp)

        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-cr", stagedApp.path]
        try? xattr.run()
        xattr.waitUntilExit()

        // Replace destination app
        if FileManager.default.fileExists(atPath: targetAppURL.path) {
            try? FileManager.default.removeItem(at: targetAppURL)
        }
        try FileManager.default.copyItem(at: stagedApp, to: targetAppURL)
        try? FileManager.default.removeItem(at: stagedApp)

        await MainActor.run {
            self.updateStatus = "Update applied! Relaunching..."
        }

        // Background script waits for current PID to exit, then launches updated app
        let pid = ProcessInfo.processInfo.processIdentifier
        let relaunchScript = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done
        open -n "\(targetAppURL.path)"
        """

        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", relaunchScript]
        try relauncher.run()

        // Terminate current process
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Native Alerts

    private func showUpdateAlert(newVersion: String, notes: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available: \(newVersion)"
        alert.informativeText = notes.isEmpty
            ? "A new version of AerialMotion is ready to install."
            : "What's new:\n\n" + (notes.count > 300 ? String(notes.prefix(300)) + "..." : notes)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")

        if let icon = AppLogo.image {
            alert.icon = icon
        }

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            Task { @MainActor in
                await self.installUpdate()
            }
        }
    }

    private func showUpToDateAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "AerialMotion is Up to Date"
        alert.informativeText = "You're running the latest version (v\(version))."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        if let icon = AppLogo.image {
            alert.icon = icon
        }

        alert.runModal()
    }
}
