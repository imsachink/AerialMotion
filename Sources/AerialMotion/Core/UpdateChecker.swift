import Foundation
import AppKit

// MARK: - UpdateChecker
// Checks GitHub Releases API for new AerialMotion releases.

@MainActor
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()

    @Published var isChecking: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var releaseURL: URL?
    @Published var statusMessage: String?
    @Published var lastChecked: Date?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private let repo = "imsachink/AerialMotion"

    func checkForUpdates(userInitiated: Bool = true) async {
        guard !isChecking else { return }
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

            self.lastChecked = Date()

            if isVersion(remoteVer, greaterThan: localVer) {
                self.updateAvailable = true
                self.statusMessage = "New version \(tagName) available!"
                if userInitiated {
                    showUpdateAlert(newVersion: tagName, notes: self.releaseNotes, url: self.releaseURL)
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

    // MARK: - Native Alerts

    private func showUpdateAlert(newVersion: String, notes: String, url: URL?) {
        let alert = NSAlert()
        alert.messageText = "Update Available: \(newVersion)"
        alert.informativeText = notes.isEmpty
            ? "A new version of AerialMotion is available on GitHub."
            : "What's new:\n\n" + (notes.count > 300 ? String(notes.prefix(300)) + "..." : notes)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")

        if let icon = AppLogo.image {
            alert.icon = icon
        }

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn, let url = url {
            NSWorkspace.shared.open(url)
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
