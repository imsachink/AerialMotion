import SwiftUI

// MARK: - CuratedCardView
// Premium card for browsing and applying curated 4K ambient video loops.

struct CuratedCardView: View {

    let item: CuratedWallpaperItem
    @EnvironmentObject var store: WallpaperStore
    @ObservedObject var gallery = CuratedGalleryManager.shared

    @State private var isHovered = false

    private var isApplied: Bool {
        gallery.isApplied(item: item, store: store)
    }

    private var isInLibrary: Bool {
        gallery.isInLibrary(item: item, store: store)
    }

    private var isDownloading: Bool {
        gallery.downloadingIDs.contains(item.id)
    }

    private var isProcessing: Bool {
        if let existing = gallery.findExisting(item: item, store: store) {
            return store.processingStatus[existing.name] != nil
        }
        return store.processingStatus[item.name] != nil || store.processingStatus[item.id] != nil
    }

    private var progress: Double {
        gallery.downloadProgress[item.id] ?? 0.0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview thumbnail with badges
            thumbnailSection

            // Content details & 1-click action
            actionSection
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isApplied
                        ? Color.accentColor
                        : (isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.08)),
                    lineWidth: isApplied ? 2 : 1
                )
        )
        .scaleEffect(isHovered && !isApplied ? 1.01 : 1.0)
        .shadow(
            color: isApplied ? Color.accentColor.opacity(0.25) : Color.black.opacity(0.1),
            radius: isApplied ? 5 : 2
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.25), value: isApplied)
        .onHover { isHovered = $0 }
    }

    // MARK: - Thumbnail Section

    private var thumbnailSection: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let localImg = item.localThumbnailImage() {
                    Image(nsImage: localImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let urlStr = item.thumbnailURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            fallbackThumbnail
                        case .empty:
                            ZStack {
                                Color.secondary.opacity(0.12)
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        @unknown default:
                            fallbackThumbnail
                        }
                    }
                } else {
                    fallbackThumbnail
                }
            }
            .frame(height: 96)
            .clipped()

            // Badges overlay
            HStack {
                Text(item.resolution)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.65), in: Capsule())

                Spacer()

                if isApplied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Active")
                    }
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.accentColor, in: Capsule())
                } else {
                    Text(item.license)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55), in: Capsule())
                }
            }
            .padding(6)
        }
    }

    private var fallbackThumbnail: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "video.fill")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Action & Details Section

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(item.subtitle)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)

                    if let credit = item.credit {
                        HStack(spacing: 2) {
                            Text("Credit:")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            if let creditURL = item.creditURL, let url = URL(string: creditURL) {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    Text(credit)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(Color.accentColor.opacity(0.85))
                                        .underline()
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(credit)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 1)
                    }
                }

                Spacer()

                if item.fileSizeMB > 0 {
                    Text(String(format: "%.1f MB", item.fileSizeMB))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
            }

            if isDownloading {
                VStack(spacing: 4) {
                    HStack {
                        Text("Downloading...")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)

                    Button {
                        gallery.cancelDownload(item: item)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Stop Download")
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.top, 2)
            } else {
                Button {
                    gallery.downloadAndApply(item: item, store: store)
                } label: {
                    HStack(spacing: 4) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Setting...")
                        } else if isApplied {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Active • Re-sync")
                        } else if isInLibrary {
                            Image(systemName: "play.fill")
                            Text("Switch to this")
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download & Set")
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3.5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(isApplied ? Color.secondary.opacity(0.3) : (isProcessing ? Color.orange : (isInLibrary ? Color.blue : Color.accentColor)))
                .disabled(isProcessing)
                .padding(.top, 2)
            }
        }
        .padding(8)
    }
}
