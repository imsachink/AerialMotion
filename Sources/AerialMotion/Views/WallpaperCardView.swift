import SwiftUI

// MARK: - Individual wallpaper card

struct WallpaperCardView: View {

    let item: WallpaperItem
    @EnvironmentObject var store: WallpaperStore
    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    private var isActive: Bool { store.activeID == item.id }

    var body: some View {
        cardContent
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                if !showDeleteConfirm {
                    store.activate(item)
                }
            }
            .onHover { isHovered = $0 }
    }

    // MARK: - Card layout

    @ViewBuilder
    private var cardContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Thumbnail
                thumbnailImage
                    .frame(height: 90)
                    .clipped()

                // Name + size
                infoBar
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive
                            ? Color.accentColor
                            : (isHovered ? Color.primary.opacity(0.2) : Color.clear),
                        lineWidth: isActive ? 2 : 1
                    )
            )
            .scaleEffect(isHovered && !isActive ? 1.02 : 1.0)
            .shadow(
                color: isActive ? .accentColor.opacity(0.3) : .black.opacity(0.15),
                radius: isActive ? 6 : 3
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.25), value: isActive)

            // Active badge
            if isActive && !showDeleteConfirm {
                activeBadge
            }

            // Delete button (on hover)
            if isHovered && !showDeleteConfirm {
                deleteButton
            }

            // Inline in-card delete confirmation (prevents MenuBarExtra from collapsing)
            if showDeleteConfirm {
                deleteConfirmationOverlay
            }
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailImage: some View {
        if let img = item.thumbnail() {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 90)
                .clipped()
        } else {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: "video.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 90)
        }
    }

    // MARK: - Info bar

    private var infoBar: some View {
        HStack(spacing: 4) {
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)

            Spacer()

            if item.fileSizeMB > 0 {
                Text(String(format: "%.0fMB", item.fileSizeMB))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05))
    }

    // MARK: - Active badge (top-right checkmark)

    private var activeBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 15))
            .foregroundStyle(.white, Color.accentColor)
            .background(Circle().fill(Color.accentColor).padding(1))
            .padding(4)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Delete button

    private var deleteButton: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                showDeleteConfirm = true
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white, .black.opacity(0.6))
        }
        .buttonStyle(.plain)
        .padding(4)
        .transition(.opacity)
        .help("Remove '\(item.name)'")
    }

    // MARK: - In-Card Delete Confirmation Overlay

    private var deleteConfirmationOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)

            VStack(spacing: 8) {
                Text("Remove video?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDeleteConfirm = false
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDeleteConfirm = false
                        }
                        store.remove(item)
                    } label: {
                        Text("Remove")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
