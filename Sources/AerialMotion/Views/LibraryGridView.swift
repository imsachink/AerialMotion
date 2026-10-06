import SwiftUI

// MARK: - Library grid (2-column card grid)

struct LibraryGridView: View {

    @EnvironmentObject var store: WallpaperStore

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(store.items) { item in
                WallpaperCardView(item: item)
                    .environmentObject(store)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.items.map(\.id))
    }
}
