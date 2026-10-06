import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Drop zone for adding new videos
// Full-area clickable button + drag-and-drop target.

struct DropZoneView: View {

    @EnvironmentObject var store: WallpaperStore
    @State private var isTargeted = false

    private var isProcessing: Bool { !store.processingStatus.isEmpty }

    var body: some View {
        Group {
            if isProcessing {
                processingView
            } else {
                dropTarget
            }
        }
        .animation(.spring(response: 0.25), value: isProcessing)
    }

    // MARK: - Drop target (idle)

    private var dropTarget: some View {
        Button {
            openFilePicker()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.04))
                    )

                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Video Wallpaper")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Click to choose file, or drag video here")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 56)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    // MARK: - Processing in-progress view

    private var processingView: some View {
        VStack(spacing: 6) {
            ForEach(Array(store.processingStatus.keys), id: \.self) { name in
                if let status = store.processingStatus[name] {
                    ProcessingRow(name: name, status: status)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
                else { return }
                DispatchQueue.main.async { store.add(url: url) }
            }
            handled = true
        }
        return handled
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Select an MP4 or MOV video for your wallpaper"
        panel.prompt = "Choose Video"

        if panel.runModal() == .OK, let url = panel.url {
            store.add(url: url)
        }
    }
}

// MARK: - Processing row (shows name + progress bar)

struct ProcessingRow: View {
    let name: String
    let status: ProcessingStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                if case .converting(let p) = status {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                } else {
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch status {
        case .converting:  return "arrow.clockwise"
        case .installing:  return "square.and.arrow.down"
        case .done:        return "checkmark.circle.fill"
        case .failed:      return "xmark.circle.fill"
        case .idle:        return "clock"
        }
    }

    private var iconColor: Color {
        switch status {
        case .done:    return .green
        case .failed:  return .red
        case .installing: return .blue
        default:       return .secondary
        }
    }

    private var statusLabel: String {
        switch status {
        case .installing:        return "Installing…"
        case .done:              return "Done!"
        case .failed(let msg):   return msg
        default:                 return ""
        }
    }
}
