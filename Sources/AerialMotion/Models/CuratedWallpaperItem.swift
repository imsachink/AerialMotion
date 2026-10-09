import Foundation
import AppKit

// MARK: - Curated Wallpaper Item Model
// Represents a verified, CC0 / Public Domain calm 4K ambient video wallpaper.

public struct CuratedWallpaperItem: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let category: String
    public let resolution: String
    public let license: String
    public let fileSizeMB: Double
    public let thumbnailName: String?
    public let thumbnailURL: String?
    public let videoURL: String
    public let localFileName: String?

    public init(
        id: String,
        name: String,
        subtitle: String,
        category: String,
        resolution: String,
        license: String,
        fileSizeMB: Double,
        thumbnailName: String? = nil,
        thumbnailURL: String? = nil,
        videoURL: String,
        localFileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.category = category
        self.resolution = resolution
        self.license = license
        self.fileSizeMB = fileSizeMB
        self.thumbnailName = thumbnailName
        self.thumbnailURL = thumbnailURL
        self.videoURL = videoURL
        self.localFileName = localFileName
    }

    /// Resolves local thumbnail from bundle or local cache if present
    public func localThumbnailImage() -> NSImage? {
        if let thumbName = thumbnailName {
            // Check bundle resources
            if let bundleURL = Bundle.main.url(forResource: (thumbName as NSString).deletingPathExtension,
                                               withExtension: (thumbName as NSString).pathExtension),
               let img = NSImage(contentsOf: bundleURL) {
                return img
            }
            // Check assets directory if running in dev
            let devAssetPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("assets")
                .appendingPathComponent(thumbName)
            if FileManager.default.fileExists(atPath: devAssetPath.path),
               let img = NSImage(contentsOf: devAssetPath) {
                return img
            }
        }
        return nil
    }
}
