import Foundation
import AppKit

// MARK: - Shared path constants

nonisolated(unsafe) let fm = FileManager.default

private func appSupport() -> URL {
    fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
}

// macOS aerial catalog
let aerialsDir  = appSupport().appendingPathComponent("com.apple.wallpaper/aerials/videos")
let thumbsDir   = appSupport().appendingPathComponent("com.apple.wallpaper/aerials/thumbnails")
let entriesFile = appSupport().appendingPathComponent("com.apple.wallpaper/aerials/manifest/entries.json")
let indexFile   = appSupport().appendingPathComponent("com.apple.wallpaper/Store/Index.plist")

// AerialMotion library
let aerialMotionRoot = appSupport().appendingPathComponent("AerialMotion")
let libDir         = aerialMotionRoot.appendingPathComponent("library")
let thumbLibDir    = aerialMotionRoot.appendingPathComponent("thumbnails")
let stateFile      = aerialMotionRoot.appendingPathComponent("state.json")

// MARK: - Catalog IDs
let catID = "7C3A9E51-2B4F-4D8A-A1C3-E5F6071829A4"
let subID = "8D4B0F62-3C5A-4E9B-B2D4-F6A7182930B5"
let fallbackAerial = "4C108785-A7BA-422E-9C79-B0129F1D5550"  // Tahoe Day

// All URL keys that macOS lockscreen probes — register all to prevent black screen
let urlKeys = [
    "url-4K-SDR",
    "url-4K-SDR-240FPS",
    "url-1080-SDR",
    "url-4K-HDR",
]

// MARK: - WallpaperItem

struct WallpaperItem: Identifiable, Equatable, Codable {
    let id: String          // UUID used as aerial asset ID in macOS catalog
    var name: String
    var dateAdded: Date

    // Path of the .mov inside the macOS aerial catalog (active location)
    var catalogVideoURL: URL { aerialsDir.appendingPathComponent("\(id).mov") }
    var catalogThumbURL: URL { thumbsDir.appendingPathComponent("\(id).png") }

    // Path inside our library cache
    var libraryVideoURL: URL { libDir.appendingPathComponent("\(name).mov") }
    var libraryThumbURL: URL { thumbLibDir.appendingPathComponent("\(name).png") }

    var isInstalled: Bool {
        fm.fileExists(atPath: catalogVideoURL.path)
    }

    var fileSizeMB: Double {
        guard let attrs = try? fm.attributesOfItem(atPath: catalogVideoURL.path),
              let bytes = attrs[.size] as? Int64 else { return 0 }
        return Double(bytes) / 1_000_000
    }

    func thumbnail() -> NSImage? {
        if fm.fileExists(atPath: catalogThumbURL.path),
           let img = NSImage(contentsOf: catalogThumbURL) { return img }
        if fm.fileExists(atPath: libraryThumbURL.path),
           let img = NSImage(contentsOf: libraryThumbURL) { return img }
        return nil
    }
}
