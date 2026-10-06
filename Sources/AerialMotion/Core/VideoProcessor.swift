import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia
import AppKit

// MARK: - VideoProcessor errors

enum VideoProcessorError: LocalizedError {
    case unreadableVideo(String)
    case conversionFailed(String)
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .unreadableVideo(let m): return m
        case .conversionFailed(let m): return m
        case .thumbnailFailed: return "Could not generate wallpaper thumbnail."
        }
    }
}

// MARK: - VideoProcessor

enum VideoProcessor {

    private static var fm: FileManager { FileManager.default }

    // MARK: - Main pipeline

    static func process(
        source: URL,
        item: WallpaperItem,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // 1. Generate thumbnail
        progress(0.1)
        try await generateThumbnail(source: source, dest: item.libraryThumbURL)

        // 2. Hardware-accelerated 2-layer hierarchical HEVC conversion
        // (Mandatory for macOS WallpaperAerialsExtension desktop & lockscreen)
        progress(0.2)
        try await convertVideo(source: source, dest: item.libraryVideoURL, progress: progress)

        progress(1.0)
    }

    // MARK: - Thumbnail extraction

    static func generateThumbnail(source: URL, dest: URL) async throws {
        let asset = AVURLAsset(url: source)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 800, height: 450)

        let targetSec = UserDefaults.standard.integer(forKey: "thumbnailAt")
        let time = CMTime(seconds: Double(targetSec > 0 ? targetSec : 1), preferredTimescale: 600)

        guard let cgImage = try? await gen.image(at: time).image else {
            throw VideoProcessorError.thumbnailFailed
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw VideoProcessorError.thumbnailFailed
        }

        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData.write(to: dest, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
        _ = await run("/usr/bin/xattr", "-cr", dest.path)
    }

    // MARK: - 2-layer Hierarchical HEVC Conversion
    // Uses AVAssetWriter + VideoToolbox with BaseLayerFrameRate = srcFps / 2
    // to produce TSA temporal sub-layers required by macOS WallpaperAerialsExtension
    // so the desktop/home screen never turns black or gray.

    private static func convertVideo(
        source: URL, dest: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {

        let tmpDest = dest.deletingPathExtension().appendingPathExtension("tmp.mov")
        defer { try? fm.removeItem(at: tmpDest) }

        let asset = AVURLAsset(url: source)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw VideoProcessorError.unreadableVideo("Could not read video track: \(error.localizedDescription)")
        }

        guard let videoTrack = tracks.first else {
            throw VideoProcessorError.unreadableVideo("No video track found in file.")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFps = try await videoTrack.load(.nominalFrameRate)
        let srcFps = Double(nominalFps > 0 ? nominalFps : 30)
        let duration = try await asset.load(.duration)
        let durationSec = duration.seconds

        let targetWidth = 3840
        let targetHeight = 2160

        // Handle rotation / preferred transform
        let orientedSize = naturalSize.applying(preferredTransform)
        let srcW = abs(orientedSize.width)
        let srcH = abs(orientedSize.height)

        let scale = min(Double(targetWidth) / srcW, Double(targetHeight) / srcH)
        let scaledW = srcW * scale
        let scaledH = srcH * scale
        let offsetX = (Double(targetWidth) - scaledW) / 2.0
        let offsetY = (Double(targetHeight) - scaledH) / 2.0

        let transform = preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: targetWidth, height: targetHeight)
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(srcFps.rounded(), 1)))
        composition.instructions = [instruction]

        try? fm.removeItem(at: tmpDest)
        try fm.createDirectory(at: tmpDest.deletingLastPathComponent(), withIntermediateDirectories: true)

        let writer = try AVAssetWriter(outputURL: tmpDest, fileType: .mov)

        // 2-layer hierarchical HEVC compression settings
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: 18_000_000,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoExpectedSourceFrameRateKey: Int(srcFps.rounded()),
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
            AVVideoAllowFrameReorderingKey: true,
            kVTCompressionPropertyKey_BaseLayerFrameRate as String: srcFps / 2.0,
        ]

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        ]
        let trackOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: readerSettings
        )
        trackOutput.videoComposition = composition
        reader.add(trackOutput)

        guard writer.startWriting() else {
            throw VideoProcessorError.conversionFailed(writer.error?.localizedDescription ?? "writer.startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            throw VideoProcessorError.conversionFailed(reader.error?.localizedDescription ?? "reader.startReading failed")
        }

        final class AtomicState: @unchecked Sendable {
            let lock = NSLock()
            var isFinished = false
            func finish() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if isFinished { return false }
                isFinished = true
                return true
            }
        }
        let state = AtomicState()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) let r = reader
            nonisolated(unsafe) let to = trackOutput
            nonisolated(unsafe) let wi = writerInput

            let queue = DispatchQueue(label: "AerialMotion.encode")
            wi.requestMediaDataWhenReady(on: queue) {
                while wi.isReadyForMoreMediaData {
                    if let sample = to.copyNextSampleBuffer() {
                        if !wi.append(sample) {
                            if state.finish() {
                                wi.markAsFinished()
                                cont.resume(throwing: VideoProcessorError.conversionFailed("Writer append failed: \(wi.description)"))
                            }
                            return
                        }
                        if durationSec > 0 {
                            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                            if pts.isFinite {
                                let frac = min(0.95, max(0.2, 0.2 + (pts / durationSec) * 0.75))
                                progress(frac)
                            }
                        }
                    } else {
                        if state.finish() {
                            wi.markAsFinished()
                            if r.status == .failed {
                                cont.resume(throwing: VideoProcessorError.conversionFailed(r.error?.localizedDescription ?? "Reader failed"))
                            } else {
                                cont.resume()
                            }
                        }
                        return
                    }
                }
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) let w = writer
            w.finishWriting {
                if w.status == .completed {
                    cont.resume()
                } else {
                    cont.resume(throwing: VideoProcessorError.conversionFailed(
                        w.error?.localizedDescription ?? "writer status \(w.status.rawValue)"
                    ))
                }
            }
        }

        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tmpDest, to: dest)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
        _ = await run("/usr/bin/xattr", "-cr", dest.path)
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
