import Foundation
import AppKit

// MARK: - CatalogManager
// Reads/writes the macOS aerial entries.json catalog.
// All methods are async so they run off the main thread.

enum CatalogError: LocalizedError {
    case catalogNotFound
    case aerialsNotFound

    var errorDescription: String? {
        switch self {
        case .catalogNotFound:
            return "Aerial catalog not found. Click 'Open Wallpaper Settings' to prime Apple's wallpaper engine."
        case .aerialsNotFound:
            return "Aerials folder not found. Click 'Open Wallpaper Settings' and select any aerial once."
        }
    }
}

enum CatalogManager {

    // MARK: - System status

    static var isSystemReady: Bool {
        fm.fileExists(atPath: entriesFile.path) && fm.fileExists(atPath: aerialsDir.path)
    }

    static func openSystemWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Install (upsert) an asset

    static func install(item: WallpaperItem) async throws {
        guard fm.fileExists(atPath: entriesFile.path) else {
            throw CatalogError.catalogNotFound
        }
        guard fm.fileExists(atPath: aerialsDir.path) else {
            throw CatalogError.aerialsNotFound
        }

        // Copy .mov into the macOS aerial catalog directory
        let dst = item.catalogVideoURL
        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
        try fm.copyItem(at: item.libraryVideoURL, to: dst)

        // Copy thumbnail
        let dstThumb = item.catalogThumbURL
        if fm.fileExists(atPath: dstThumb.path) { try? fm.removeItem(at: dstThumb) }
        if fm.fileExists(atPath: item.libraryThumbURL.path) {
            try fm.copyItem(at: item.libraryThumbURL, to: dstThumb)
        }

        // Mutate entries.json
        var catalog = try loadCatalog()
        ensureCategory(&catalog)
        upsertAsset(item: item, into: &catalog)
        try writeCatalog(catalog)
    }

    // MARK: - Remove an asset

    static func remove(item: WallpaperItem) async throws {
        // Delete files from macOS catalog
        for url in [item.catalogVideoURL, item.catalogThumbURL] {
            try? fm.removeItem(at: url)
        }
        // Delete from our library cache
        for url in [item.libraryVideoURL, item.libraryThumbURL] {
            try? fm.removeItem(at: url)
        }

        guard fm.fileExists(atPath: entriesFile.path) else { return }
        var catalog = try loadCatalog()
        catalog["assets"] = (catalog["assets"] as? [[String: Any]] ?? [])
            .filter { ($0["id"] as? String) != item.id }
        try writeCatalog(catalog)
    }

    // MARK: - Private helpers

    private static func loadCatalog() throws -> [String: Any] {
        let data = try Data(contentsOf: entriesFile)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func writeCatalog(_ catalog: [String: Any]) throws {
        // Backup once
        let bak = entriesFile.appendingPathExtension("aerialmotion-backup")
        if !fm.fileExists(atPath: bak.path) {
            try? fm.copyItem(at: entriesFile, to: bak)
        }
        let data = try JSONSerialization.data(withJSONObject: catalog,
                                              options: [.prettyPrinted, .sortedKeys])
        // Atomic write
        let tmp = entriesFile.appendingPathExtension("tmp")
        try data.write(to: tmp)
        _ = try fm.replaceItemAt(entriesFile, withItemAt: tmp)
    }

    private static func ensureCategory(_ catalog: inout [String: Any]) {
        var categories = catalog["categories"] as? [[String: Any]] ?? []
        if !categories.contains(where: { ($0["id"] as? String) == catID }) {
            categories.append([
                "id": catID,
                "localizedDescriptionKey": "AerialMotion",
                "localizedNameKey": "AerialMotion",
                "preferredOrder": 999,
                "previewImage": "",
                "representativeAssetID": "",
                "subcategories": [[
                    "id": subID,
                    "localizedDescriptionKey": "AerialMotion",
                    "localizedNameKey": "AerialMotion",
                    "preferredOrder": 0,
                    "previewImage": "",
                    "representativeAssetID": "",
                ]],
            ])
            catalog["categories"] = categories
        }
    }

    private static func upsertAsset(item: WallpaperItem, into catalog: inout [String: Any]) {
        var assets = catalog["assets"] as? [[String: Any]] ?? []
        assets.removeAll { ($0["id"] as? String) == item.id }

        let maxOrder = assets.compactMap { $0["preferredOrder"] as? Int }.max() ?? 0
        let thumbURI = item.catalogThumbURL.absoluteString
        let vidURI   = item.catalogVideoURL.absoluteString

        // Register ALL URL keys so macOS lockscreen always finds a match (black screen fix)
        var entry: [String: Any] = [
            "accessibilityLabel": item.name,
            "categories":         [catID],
            "id":                 item.id,
            "includeInShuffle":   true,
            "localizedNameKey":   "AerialMotion",
            "pointsOfInterest":   [String: String](),
            "preferredOrder":     maxOrder + 1,
            "previewImage":       thumbURI,
            "shotID":             "AERIALMOTION",
            "showInTopLevel":     true,
            "subcategories":      [subID],
        ]
        for key in urlKeys { entry[key] = vidURI }
        assets.append(entry)
        catalog["assets"] = assets

        // Update category representative
        if var cats = catalog["categories"] as? [[String: Any]] {
            for i in cats.indices where cats[i]["id"] as? String == catID {
                cats[i]["representativeAssetID"] = item.id
                cats[i]["previewImage"] = thumbURI
                if var subs = cats[i]["subcategories"] as? [[String: Any]] {
                    for j in subs.indices where subs[j]["id"] as? String == subID {
                        subs[j]["representativeAssetID"] = item.id
                        subs[j]["previewImage"] = thumbURI
                    }
                    cats[i]["subcategories"] = subs
                }
            }
            catalog["categories"] = cats
        }
    }
}
