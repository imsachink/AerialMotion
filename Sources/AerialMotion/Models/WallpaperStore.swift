import Foundation
import Combine
import AppKit

// MARK: - Processing status for an item being added

enum ProcessingStatus: Equatable {
    case idle
    case converting(progress: Double)   // 0.0 – 1.0
    case installing
    case done
    case failed(String)
}

// MARK: - WallpaperStore

/// Central ObservableObject — all UI reads from / writes to this.
/// Heavy work runs in Swift concurrency Tasks; @MainActor ensures UI updates
/// happen on the main thread with zero manual DispatchQueue calls.
@MainActor
final class WallpaperStore: ObservableObject {

    static let shared = WallpaperStore()

    @Published var items: [WallpaperItem] = []
    @Published var activeID: String? = nil
    @Published var processingStatus: [String: ProcessingStatus] = [:]  // name → status
    @Published var errorMessage: String? = nil

    private init() {
        load()
    }

    // MARK: - Load from disk

    func load() {
        guard let data = try? Data(contentsOf: stateFile),
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            items = []
            return
        }
        items = state.assets.map { entry in
            WallpaperItem(id: entry.value, name: entry.key,
                          dateAdded: state.dates?[entry.key] ?? .distantPast)
        }.sorted { $0.name < $1.name }
        activeID = state.activeID

        if let id = activeID, let item = items.first(where: { $0.id == id }) {
            let videoURL = fm.fileExists(atPath: item.libraryVideoURL.path) ? item.libraryVideoURL : item.catalogVideoURL
            if fm.fileExists(atPath: videoURL.path) {
                LiveDesktopManager.shared.setVideoURL(videoURL)
            }
            // Ensure lock screen Index.plist is verified and synced with active wallpaper at launch
            Task {
                try? await CatalogManager.install(item: item)
                try? IndexManager.point(at: id)
                await WallpaperAgent.reload()
            }
        }
    }

    // MARK: - Add a new video

    func add(url: URL, displayName: String? = nil) {
        let defaultName = url.deletingPathExtension().lastPathComponent
        let name = displayName ?? defaultName

        // If already in library, activate directly!
        if let existing = items.first(where: {
            $0.name == name ||
            $0.name == defaultName ||
            $0.name.lowercased() == defaultName.lowercased() ||
            $0.name.replacingOccurrences(of: "-", with: " ").lowercased() == name.lowercased()
        }) {
            activate(existing)
            return
        }

        let id = UUID().uuidString.uppercased()
        let item = WallpaperItem(id: id, name: name, dateAdded: .now)
        items.append(item)
        processingStatus[name] = .converting(progress: 0)
        if name != defaultName {
            processingStatus[defaultName] = .converting(progress: 0)
        }

        Task {
            do {
                try await VideoProcessor.process(source: url, item: item) { @Sendable p in
                    Task { @MainActor [weak self] in
                        self?.processingStatus[name] = .converting(progress: p)
                        if name != defaultName {
                            self?.processingStatus[defaultName] = .converting(progress: p)
                        }
                    }
                }
                await MainActor.run {
                    processingStatus[name] = .installing
                    if name != defaultName {
                        processingStatus[defaultName] = .installing
                    }
                }
                try await CatalogManager.install(item: item)
                try IndexManager.point(at: id)
                await WallpaperAgent.reload()
                await MainActor.run {
                    processingStatus[name] = .done
                    if name != defaultName {
                        processingStatus[defaultName] = .done
                    }
                    activeID = id
                    save()
                    let videoURL = fm.fileExists(atPath: item.libraryVideoURL.path) ? item.libraryVideoURL : item.catalogVideoURL
                    LiveDesktopManager.shared.setVideoURL(videoURL)
                }
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { [weak self] in
                    self?.processingStatus[name] = nil
                    self?.processingStatus[defaultName] = nil
                }
            } catch {
                await MainActor.run {
                    processingStatus[name] = .failed(error.localizedDescription)
                    if name != defaultName {
                        processingStatus[defaultName] = .failed(error.localizedDescription)
                    }
                    items.removeAll { $0.id == id }
                    errorMessage = error.localizedDescription
                }
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run { [weak self] in
                    self?.processingStatus[name] = nil
                    self?.processingStatus[defaultName] = nil
                    if self?.errorMessage == error.localizedDescription {
                        self?.errorMessage = nil
                    }
                }
            }
        }
    }

    // MARK: - Activate an existing wallpaper

    func activate(_ item: WallpaperItem, force: Bool = false) {
        if !force && activeID == item.id {
            // Even if activeID matches, ensure Index.plist and LockScreen are in sync
            Task {
                try? await CatalogManager.install(item: item)
                try? IndexManager.point(at: item.id)
                await WallpaperAgent.reload()
            }
            return
        }
        Task {
            do {
                try await CatalogManager.install(item: item)
                try IndexManager.point(at: item.id)
                await WallpaperAgent.reload()
                await MainActor.run {
                    activeID = item.id
                    save()
                    let videoURL = fm.fileExists(atPath: item.libraryVideoURL.path) ? item.libraryVideoURL : item.catalogVideoURL
                    LiveDesktopManager.shared.setVideoURL(videoURL)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Remove

    func remove(_ item: WallpaperItem) {
        let remaining = items.filter { $0.id != item.id && $0.name != item.name }
        items = remaining
        if activeID == item.id {
            activeID = remaining.first?.id
            if let nextItem = remaining.first {
                let videoURL = fm.fileExists(atPath: nextItem.libraryVideoURL.path) ? nextItem.libraryVideoURL : nextItem.catalogVideoURL
                LiveDesktopManager.shared.setVideoURL(videoURL)
            } else {
                LiveDesktopManager.shared.stopPlayback()
            }
        }
        save()

        Task {
            do {
                try await CatalogManager.remove(item: item)
                let fallback = remaining.first?.id ?? fallbackAerial
                try IndexManager.point(at: fallback)
                await WallpaperAgent.reload()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Restore Apple originals

    func restore() {
        items = []
        activeID = nil
        save()
        LiveDesktopManager.shared.stopPlayback()

        Task {
            do {
                try await CatalogManager.cleanAllCustomEntries()
                try IndexManager.point(at: fallbackAerial)
                await WallpaperAgent.reload()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Persist state

    private func save() {
        var assetsMap: [String: String] = [:]
        var datesMap:  [String: Date]   = [:]
        for item in items {
            assetsMap[item.name] = item.id
            datesMap[item.name]  = item.dateAdded
        }
        let state = State(assets: assetsMap, dates: datesMap, activeID: activeID)
        if let data = try? JSONEncoder().encode(state) {
            try? fm.createDirectory(at: aerialMotionRoot, withIntermediateDirectories: true)
            try? data.write(to: stateFile, options: .atomic)
        }
    }

    // MARK: - Codable state schema

    private struct State: Codable {
        var assets:   [String: String]
        var dates:    [String: Date]?
        var activeID: String?
    }
}
