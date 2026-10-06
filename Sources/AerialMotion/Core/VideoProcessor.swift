import Foundation
import AVFoundation
import AppKit

// MARK: - VideoProcessor
// Handles video remux/encode mp4 → mov and thumbnail extraction.
// Uses native macOS AVFoundation & /usr/bin/avconvert by default (ZERO dependencies required).
// ffmpeg is used opportunistically if already installed on the system.

enum VideoProcessorError: LocalizedError {
    case conversionFailed(String)
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let msg):
            return "Video conversion failed: \(msg)"
        case .thumbnailFailed:
            return "Could not extract thumbnail from video."
        }
    }
}

enum VideoProcessor {

    // MARK: - Public entry point

    /// Converts source video to .mov and extracts thumbnail.
    /// Progress callback is called on an arbitrary thread (caller wraps in @MainActor).
    static func process(
        source: URL,
        item: WallpaperItem,
        progress: @escaping (Double) -> Void
    ) async throws {

        // Ensure library dirs exist
        try fm.createDirectory(at: libDir,      withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbLibDir, withIntermediateDirectories: true)

        // Step 1: thumbnail (fast, extracted directly from video)
        progress(0.05)
        await extractThumbnail(source: source, dest: item.libraryThumbURL)
        progress(0.20)

        // Step 2: convert video (cached if already exists)
        if fm.fileExists(atPath: item.libraryVideoURL.path),
           let attrs = try? fm.attributesOfItem(atPath: item.libraryVideoURL.path),
           (attrs[.size] as? Int64 ?? 0) > 0 {
            progress(0.95)
        } else {
            try await convertVideo(source: source,
                                   dest: item.libraryVideoURL,
                                   progress: progress)
        }
        progress(1.0)
    }

    // MARK: - Thumbnail Extraction
    // Priority: Native AVFoundation AVAssetImageGenerator -> ffmpeg fallback

    private static func extractThumbnail(source: URL, dest: URL) async {
        // 1. Native AVFoundation (built-in, no external tool needed)
        if await extractThumbnailNative(source: source, dest: dest) {
            return
        }

        // 2. ffmpeg fallback if present
        if let ff = ffmpegPath() {
            let r = await run(ff, "-y", "-loglevel", "error",
                              "-ss", "1", "-i", source.path,
                              "-vframes", "1", "-vf", "scale=640:-1", dest.path)
            if r == 0 && fm.fileExists(atPath: dest.path) { return }

            _ = await run(ff, "-y", "-loglevel", "error",
                          "-i", source.path,
                          "-vframes", "1", "-vf", "scale=640:-1", dest.path)
        }
    }

    private static func extractThumbnailNative(source: URL, dest: URL) async -> Bool {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        var cgImage: CGImage? = nil

        do {
            let (img, _) = try await generator.image(at: time)
            cgImage = img
        } catch {
            do {
                let (img, _) = try await generator.image(at: .zero)
                cgImage = img
            } catch {
                return false
            }
        }

        guard let validCgImage = cgImage else { return false }
        let bitmapRep = NSBitmapImageRep(cgImage: validCgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return false }
        do {
            try pngData.write(to: dest)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Video conversion
    // Priority:
    // 1. ffmpeg stream-copy (if installed)
    // 2. Native macOS AVAssetExportSession
    // 3. Built-in macOS /usr/bin/avconvert tool
    // 4. ffmpeg VideoToolbox HEVC encoding

    private static func convertVideo(
        source: URL, dest: URL,
        progress: @escaping (Double) -> Void
    ) async throws {

        let tmpDest = dest.deletingPathExtension().appendingPathExtension("tmp.mov")
        defer { try? fm.removeItem(at: tmpDest) }

        // Method 1: ffmpeg stream-copy if available
        if let ff = ffmpegPath() {
            progress(0.3)
            let r = await run(ff, "-y", "-loglevel", "error",
                              "-i", source.path,
                              "-c:v", "copy", "-an",
                              "-movflags", "+faststart",
                              tmpDest.path)
            if r == 0,
               let attrs = try? fm.attributesOfItem(atPath: tmpDest.path),
               (attrs[.size] as? Int64 ?? 0) > 0 {
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: tmpDest, to: dest)
                progress(0.95)
                return
            }
        }

        // Method 2: Native AVAssetExportSession (no external tool needed)
        progress(0.4)
        if await convertVideoAVFoundation(source: source, dest: tmpDest) {
            if let attrs = try? fm.attributesOfItem(atPath: tmpDest.path),
               (attrs[.size] as? Int64 ?? 0) > 0 {
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: tmpDest, to: dest)
                progress(0.95)
                return
            }
        }

        // Method 3: Built-in macOS /usr/bin/avconvert (comes pre-installed on macOS)
        progress(0.6)
        if fm.fileExists(atPath: "/usr/bin/avconvert") {
            let r = await run("/usr/bin/avconvert",
                              "-s", source.path,
                              "-o", tmpDest.path,
                              "-p", "PresetPassthrough",
                              "--replace")
            if r == 0 && fm.fileExists(atPath: tmpDest.path) {
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: tmpDest, to: dest)
                progress(0.95)
                return
            }

            let r2 = await run("/usr/bin/avconvert",
                               "-s", source.path,
                               "-o", tmpDest.path,
                               "-p", "PresetHEVCHighestQuality",
                               "--replace")
            if r2 == 0 && fm.fileExists(atPath: tmpDest.path) {
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: tmpDest, to: dest)
                progress(0.95)
                return
            }
        }

        // Method 4: ffmpeg hardware encode fallback
        if let ff = ffmpegPath() {
            progress(0.7)
            let r = await run(ff, "-y", "-loglevel", "error",
                              "-i", source.path,
                              "-c:v", "hevc_videotoolbox",
                              "-tag:v", "hvc1",
                              "-q:v", "55",
                              "-pix_fmt", "yuv420p",
                              "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                              "-movflags", "+faststart",
                              "-an",
                              dest.path)
            if r == 0 && fm.fileExists(atPath: dest.path) {
                progress(0.95)
                return
            }
        }

        throw VideoProcessorError.conversionFailed(
            "Unable to convert video. Please ensure this is a valid video file."
        )
    }

    private static func convertVideoAVFoundation(source: URL, dest: URL) async -> Bool {
        let asset = AVURLAsset(url: source)
        let isPassthroughCompatible = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough,
            with: asset,
            outputFileType: .mov
        )
        let preset = isPassthroughCompatible
            ? AVAssetExportPresetPassthrough
            : AVAssetExportPresetHEVCHighestQuality

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            return false
        }

        exportSession.shouldOptimizeForNetworkUse = true

        do {
            try await exportSession.export(to: dest, as: .mov)
            return fm.fileExists(atPath: dest.path)
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    static func ffmpegPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        for p in candidates where fm.fileExists(atPath: p) { return p }
        let r = try? shellOutput("/usr/bin/which", "ffmpeg")
        return r?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
               ? r?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    @discardableResult
    static func run(_ args: String...) async -> Int32 {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: args[0])
                proc.arguments = Array(args.dropFirst())
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError  = FileHandle.nullDevice
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    cont.resume(returning: proc.terminationStatus)
                } catch {
                    cont.resume(returning: -1)
                }
            }
        }
    }

    private static func shellOutput(_ args: String...) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: args[0])
        proc.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
