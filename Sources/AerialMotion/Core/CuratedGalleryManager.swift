import Foundation
import Combine
import AppKit

// MARK: - CuratedGalleryManager
// Manages the curated catalog of free, verified CC0 ambient live wallpapers.
// Downloads are cached locally in ~/Library/Application Support/AerialMotion/CuratedCache/

@MainActor
final class CuratedGalleryManager: ObservableObject {

    static let shared = CuratedGalleryManager()

    @Published var items: [CuratedWallpaperItem] = []
    @Published var downloadingIDs: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]   // id -> 0.0 ... 1.0
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil

    private let baseDir: URL
    private let cacheDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseDir = appSupport.appendingPathComponent("AerialMotion", isDirectory: true)
        self.cacheDir = baseDir.appendingPathComponent("CuratedCache", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        loadLocalCatalog()
        Task {
            await refreshRemoteCatalog()
        }
    }

    // MARK: - Catalog Loading

    func loadLocalCatalog() {
        // 1. Load bundled or local development catalog as the baseline
        var baseCatalog: [CuratedWallpaperItem] = []
        if let bundleURL = Bundle.main.url(forResource: "curated_catalog", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let decoded = try? JSONDecoder().decode([CuratedWallpaperItem].self, from: data) {
            baseCatalog = decoded
        } else {
            let localDevPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources")
                .appendingPathComponent("curated_catalog.json")
            if let data = try? Data(contentsOf: localDevPath),
               let decoded = try? JSONDecoder().decode([CuratedWallpaperItem].self, from: data) {
                baseCatalog = decoded
            }
        }

        // 2. Try saved cached catalog from previous remote refresh if larger or equal
        let cachedCatalogFile = baseDir.appendingPathComponent("cached_curated_catalog.json")
        if let data = try? Data(contentsOf: cachedCatalogFile),
           let decoded = try? JSONDecoder().decode([CuratedWallpaperItem].self, from: data),
           decoded.count >= baseCatalog.count {
            self.items = decoded
            return
        }

        self.items = baseCatalog
    }

    func refreshRemoteCatalog() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let bustURL = URL(string: "https://raw.githubusercontent.com/imsachink/AerialMotion/main/Resources/curated_catalog.json?t=\(Int(Date().timeIntervalSince1970))")!
            var request = URLRequest(url: bustURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let decoded = try JSONDecoder().decode([CuratedWallpaperItem].self, from: data)
                if !decoded.isEmpty {
                    self.items = decoded
                    let cachedCatalogFile = self.baseDir.appendingPathComponent("cached_curated_catalog.json")
                    try? data.write(to: cachedCatalogFile, options: .atomic)
                }
            }
        } catch {
            // Keep using local bundled catalog silently on network failure
        }
    }

    // MARK: - Check Status

    func findExisting(item: CuratedWallpaperItem, store: WallpaperStore) -> WallpaperItem? {
        let localName = item.localFileName.map { ($0 as NSString).deletingPathExtension }
        return store.items.first {
            $0.name == item.name ||
            $0.name == item.id ||
            $0.name.lowercased() == item.id.lowercased() ||
            $0.name == localName ||
            $0.name.replacingOccurrences(of: "-", with: " ").lowercased() == item.name.lowercased()
        }
    }

    func isDownloaded(item: CuratedWallpaperItem) -> Bool {
        let target = cacheFile(for: item)
        return FileManager.default.fileExists(atPath: target.path)
    }

    func isInLibrary(item: CuratedWallpaperItem, store: WallpaperStore) -> Bool {
        return findExisting(item: item, store: store) != nil
    }

    func isApplied(item: CuratedWallpaperItem, store: WallpaperStore) -> Bool {
        guard let activeID = store.activeID,
              let activeItem = store.items.first(where: { $0.id == activeID }) else {
            return false
        }
        if let existing = findExisting(item: item, store: store) {
            return existing.id == activeItem.id
        }
        return false
    }

    // MARK: - Download and Apply

    func downloadAndApply(item: CuratedWallpaperItem, store: WallpaperStore) {
        // 1. If already in Library, activate directly!
        if let existing = findExisting(item: item, store: store) {
            store.activate(existing)
            return
        }

        // 2. If already downloaded in cache, add to store
        let cached = cacheFile(for: item)
        if FileManager.default.fileExists(atPath: cached.path) {
            store.add(url: cached, displayName: item.name)
            return
        }

        // 3. Check if local asset exists
        let candidates: [URL] = [
            item.localFileName.map { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop").appendingPathComponent($0) },
            item.localFileName.map { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads").appendingPathComponent($0) },
            item.localFileName.map { URL(fileURLWithPath: "/Users/sachinkaundal/my_work/AerialMotion/assets").appendingPathComponent($0) },
            URL(fileURLWithPath: "/Users/sachinkaundal/my_work/AerialMotion/assets").appendingPathComponent("\(item.id).mp4"),
            Bundle.main.url(forResource: item.id, withExtension: "mp4"),
            item.localFileName.flatMap { Bundle.main.url(forResource: ($0 as NSString).deletingPathExtension, withExtension: ($0 as NSString).pathExtension) }
        ].compactMap { $0 }

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                try? FileManager.default.removeItem(at: cached)
                if (try? FileManager.default.copyItem(at: candidate, to: cached)) != nil {
                    store.add(url: cached, displayName: item.name)
                    return
                }
            }
        }

        // 4. Download from network asynchronously using fast native URLSessionDownloadTask
        guard let url = URL(string: item.videoURL) else {
            errorMessage = "Invalid video URL"
            return
        }

        downloadingIDs.insert(item.id)
        downloadProgress[item.id] = 0.05

        let delegate = DownloadTaskDelegate(
            onProgress: { [weak self] p in
                Task { @MainActor in
                    self?.downloadProgress[item.id] = p
                }
            },
            onComplete: { [weak self] downloadedURL in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.activeSessions.removeValue(forKey: item.id)
                    self.downloadingIDs.remove(item.id)
                    self.downloadProgress[item.id] = 1.0

                    do {
                        try? FileManager.default.removeItem(at: cached)
                        try FileManager.default.moveItem(at: downloadedURL, to: cached)
                        store.add(url: cached, displayName: item.name)
                    } catch {
                        self.errorMessage = "Failed to save video: \(error.localizedDescription)"
                    }
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.activeSessions.removeValue(forKey: item.id)
                    self.downloadingIDs.remove(item.id)
                    self.downloadProgress[item.id] = nil

                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                        // Cancelled by user, ignore
                        return
                    }
                    self.errorMessage = "Download failed: \(error.localizedDescription)"
                }
            }
        )

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 300
        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        let downloadTask = session.downloadTask(with: url)
        activeSessions[item.id] = (session, downloadTask)
        downloadTask.resume()
    }

    // MARK: - Cancel / Stop Download

    func cancelDownload(item: CuratedWallpaperItem) {
        if let (session, task) = activeSessions[item.id] {
            task.cancel()
            session.invalidateAndCancel()
            activeSessions.removeValue(forKey: item.id)
        }
        downloadingIDs.remove(item.id)
        downloadProgress[item.id] = nil
        let temp = cacheDir.appendingPathComponent("temp_\(item.id).tmp")
        try? FileManager.default.removeItem(at: temp)
    }

    // MARK: - Private Helpers

    private var activeSessions: [String: (URLSession, URLSessionDownloadTask)] = [:]

    private func cacheFile(for item: CuratedWallpaperItem) -> URL {
        return cacheDir.appendingPathComponent("\(item.id).mp4")
    }
}

// MARK: - Native Fast Download Delegate

final class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void
    let onComplete: (URL) -> Void
    let onError: (Error) -> Void

    init(
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (URL) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            onProgress(min(p, 0.99))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempDest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try FileManager.default.moveItem(at: location, to: tempDest)
            onComplete(tempDest)
        } catch {
            onError(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onError(error)
        }
    }
}
