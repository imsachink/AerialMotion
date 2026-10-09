import SwiftUI

// MARK: - CuratedGalleryView
// In-app gallery showcasing verified, slow, non-dizzy CC0 ambient 4K live wallpapers.

struct CuratedGalleryView: View {

    @EnvironmentObject var store: WallpaperStore
    @ObservedObject var gallery = CuratedGalleryManager.shared
    @State private var selectedCategory: String = "All"

    private let categories = ["All", "Zen & Japan"]

    private var filteredItems: [CuratedWallpaperItem] {
        if selectedCategory == "All" {
            return gallery.items
        }
        return gallery.items.filter { $0.category == selectedCategory }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Category pills
            categoryFilterBar

            // Wallpapers Grid
            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No wallpapers found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredItems) { item in
                        CuratedCardView(item: item)
                            .environmentObject(store)
                    }
                }
            }

            // Legal & Quality guarantee badge
            qualityBadge
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        HStack(spacing: 6) {
            ForEach(categories, id: \.self) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedCategory = category
                    }
                } label: {
                    Text(categoryLabel(category))
                        .font(.system(size: 10, weight: selectedCategory == category ? .semibold : .regular))
                        .foregroundStyle(selectedCategory == category ? Color.primary : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(selectedCategory == category ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()

            Button {
                Task {
                    await gallery.refreshRemoteCatalog()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                        .rotationEffect(.degrees(gallery.isRefreshing ? 360 : 0))
                        .animation(gallery.isRefreshing ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: gallery.isRefreshing)
                    if gallery.isRefreshing {
                        Text("Syncing...")
                            .font(.system(size: 8.5))
                    }
                }
                .foregroundStyle(gallery.isRefreshing ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .disabled(gallery.isRefreshing)
            .help("Refresh Discover Catalog from GitHub")
        }
    }

    private func categoryLabel(_ cat: String) -> String {
        switch cat {
        case "Zen & Japan": return "⛩️ Zen & Japan"
        default: return "✨ All"
        }
    }

    // MARK: - Quality Badge

    private var qualityBadge: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("100% Free & Open Source • Zero Ads • Native Apple Silicon")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }

            Text("New wallpapers added to GitHub appear here automatically")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }
}
