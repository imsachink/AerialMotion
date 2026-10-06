import Foundation

// MARK: - IndexManager
// Updates Store/Index.plist so the active wallpaper slot points at the right assetID.

enum IndexManager {

    /// Walk the plist tree and update every aerial Configuration's assetID.
    /// Writes atomically. Caller is responsible for killing WallpaperAgent afterwards.
    static func point(at assetID: String) throws {
        guard fm.fileExists(atPath: indexFile.path) else { return }

        guard let data = try? Data(contentsOf: indexFile) else { return }
        var plist: Any = (try? PropertyListSerialization.propertyList(
            from: data, format: nil)) ?? [String: Any]()

        var count = 0
        walk(&plist, assetID: assetID, count: &count)

        // Atomic write
        let out  = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0)
        let tmp  = indexFile.appendingPathExtension("tmp")
        try out.write(to: tmp)
        _ = try fm.replaceItemAt(indexFile, withItemAt: tmp)

        // Touch so WallpaperAgent picks it up
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: indexFile.path)
    }

    // MARK: - Recursive plist walker

    private static func walk(_ node: inout Any, assetID: String, count: inout Int) {
        if var dict = node as? [String: Any] {
            let provider = dict["Provider"] as? String ?? ""
            if provider.contains("aerial"), var cfg = dict["Configuration"] as? Data {
                if var inner = (try? PropertyListSerialization.propertyList(
                    from: cfg, format: nil)) as? [String: Any],
                   inner["assetID"] != nil {
                    inner["assetID"] = assetID
                    if let newCfg = try? PropertyListSerialization.data(
                        fromPropertyList: inner, format: .binary, options: 0) {
                        cfg = newCfg
                        dict["Configuration"] = cfg
                        count += 1
                    }
                }
            }
            for key in dict.keys {
                walk(&dict[key]!, assetID: assetID, count: &count)
            }
            node = dict
        } else if var arr = node as? [Any] {
            for i in arr.indices {
                walk(&arr[i], assetID: assetID, count: &count)
            }
            node = arr
        }
    }
}

// MARK: - WallpaperAgent

enum WallpaperAgent {

    /// Kill WallpaperAgent so it re-reads the updated config.
    /// Sleeps 1.5s to prevent race condition where agent overwrites our changes.
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
