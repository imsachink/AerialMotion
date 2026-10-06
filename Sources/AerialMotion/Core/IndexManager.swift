import Foundation

// MARK: - IndexManager
// Updates Store/Index.plist so the active wallpaper slot points at the right assetID.

enum IndexManager {

    /// Update Index.plist so both Desktop (home screen) and Idle (lock screen)
    /// are Linked to the chosen aerial assetID.
    /// Writes atomically. Caller is responsible for reloading WallpaperAgent.
    static func point(at assetID: String) throws {
        guard fm.fileExists(atPath: indexFile.path) else { return }

        guard let data = try? Data(contentsOf: indexFile) else { return }
        var outer = (try? PropertyListSerialization.propertyList(
            from: data, format: nil)) as? [String: Any] ?? [String: Any]()

        let configData = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )

        let choice: [String: Any] = [
            "Configuration": configData,
            "Files": [Any](),
            "Provider": "com.apple.wallpaper.choice.aerials"
        ]

        let now = Date()
        let linked: [String: Any] = [
            "Content": [
                "Choices": [choice]
            ],
            "LastSet": now,
            "LastUse": now
        ]

        // Link both lock screen (Idle) and desktop (Home screen)
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            outer[key] = [
                "Type": "linked",
                "Linked": linked
            ]
        }

        // Clear display and Space overrides so all virtual desktops and screens inherit the linked aerial
        outer["Displays"] = [String: Any]()
        outer["Spaces"]   = [String: Any]()

        // Remove stale Space UUID keys from root (e.g. 5F18E1BE-..., 9C570187-...)
        for key in Array(outer.keys) {
            if key != "AllSpacesAndDisplays" && key != "SystemDefault" && key != "Displays" && key != "Spaces" {
                outer.removeValue(forKey: key)
            }
        }

        // Atomic write in binary format
        let out = try PropertyListSerialization.data(
            fromPropertyList: outer, format: .binary, options: 0)
        try out.write(to: indexFile, options: .atomic)

        // Touch so WallpaperAgent picks it up
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: indexFile.path)
    }
}

// MARK: - WallpaperAgent

enum WallpaperAgent {

    /// Kill WallpaperAgent so it re-reads the updated config.
    /// Non-blocking async so the UI thread remains responsive.
    static func reload() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                proc.arguments = ["-9", "WallpaperAgent", "WallpaperAerialsExtension"]
                try? proc.run()
                proc.waitUntilExit()
                continuation.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
}
