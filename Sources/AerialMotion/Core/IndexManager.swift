import Foundation
import AppKit

// MARK: - IndexManager
// Updates Store/Index.plist so the active wallpaper slot points at the right assetID.

enum IndexManager {

    /// Update Index.plist so both Desktop (home screen) and Idle (lock screen)
    /// across all virtual spaces and physical displays point to the chosen aerial assetID.
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
        let contentDict: [String: Any] = [
            "Choices": [choice],
            "EncodedOptionValues": "$null",
            "Shuffle": "$null"
        ]

        let itemDict: [String: Any] = [
            "Content": contentDict,
            "LastSet": now,
            "LastUse": now
        ]

        // 1. AllSpacesAndDisplays: set both Linked and Idle
        outer["AllSpacesAndDisplays"] = [
            "Type": "linked",
            "Linked": itemDict,
            "Idle": itemDict
        ]

        // 2. SystemDefault: set Desktop, Idle, and Linked
        outer["SystemDefault"] = [
            "Type": "individual",
            "Desktop": itemDict,
            "Idle": itemDict,
            "Linked": itemDict
        ]

        // 3. Resolve all active display UUIDs
        var displayUUIDs = Set<String>()
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let cfUUID = CGDisplayCreateUUIDFromDisplayID(num)?.takeRetainedValue() {
                displayUUIDs.insert(CFUUIDCreateString(nil, cfUUID) as String)
            }
        }
        if let existingDisplays = outer["Displays"] as? [String: Any] {
            for k in existingDisplays.keys { displayUUIDs.insert(k) }
        }

        // Build Displays dictionary with Desktop & Idle for each physical display
        var displaysDict: [String: Any] = [:]
        for dID in displayUUIDs {
            displaysDict[dID] = [
                "Type": "individual",
                "Desktop": itemDict,
                "Idle": itemDict,
                "Linked": itemDict
            ]
        }
        outer["Displays"] = displaysDict

        // 4. Spaces: ensure default space "" and any existing space UUIDs are pointed
        var spaceKeys = Set<String>([""])
        if let existingSpaces = outer["Spaces"] as? [String: Any] {
            for k in existingSpaces.keys { spaceKeys.insert(k) }
        }
        var spacesDict: [String: Any] = [:]
        for sKey in spaceKeys {
            spacesDict[sKey] = [
                "Default": [
                    "Type": "individual",
                    "Desktop": itemDict,
                    "Idle": itemDict,
                    "Linked": itemDict
                ],
                "Displays": displaysDict
            ]
        }
        outer["Spaces"] = spacesDict

        // 5. Clean up stale Space UUID keys from root (e.g. 5F18E1BE-..., 9C570187-...)
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
