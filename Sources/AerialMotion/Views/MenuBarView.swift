import SwiftUI
import AppKit

// MARK: - Main MenuBar popover view
// Liquid glass design, responsive layout, clear library visibility.

struct MenuBarView: View {

    @EnvironmentObject private var store: WallpaperStore
    @EnvironmentObject private var liveDesktop: LiveDesktopManager
    @StateObject private var updateChecker = UpdateChecker.shared
    @State private var isTargeted = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)

                if updateChecker.isUpdating {
                    updatingBanner
                    Divider().opacity(0.3)
                }

                scrollContent
                Divider().opacity(0.3)
                footer
            }
        }
        .frame(width: 380, height: 490)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Whole-panel drop target
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        )
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(liveDesktop)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettingsRequested"))) { _ in
            showSettings = true
        }
        // Hidden keyboard shortcut for Cmd+Q
        .background(
            Button("") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .opacity(0)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let img = AppLogo.image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "video.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            Text("AerialMotion")
                .font(.system(size: 14, weight: .semibold))
            Spacer()

            // Quick add button
            Button {
                openFilePicker()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add Video Wallpaper (⌘O)")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit AerialMotion (⌘Q)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - In-App Update Banner

    private var updatingBanner: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text(updateChecker.updateStatus)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", updateChecker.downloadProgress * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: updateChecker.downloadProgress)
                .progressViewStyle(.linear)
        }
        .padding(10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Desktop Motion Quick Card

    private var desktopMotionCard: some View {
        HStack(spacing: 10) {
            Image(systemName: liveDesktop.isPlaying ? "display" : "display.slash")
                .font(.system(size: 16))
                .foregroundStyle(liveDesktop.isPlaying ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Desktop Live Motion")
                        .font(.system(size: 12, weight: .medium))
                    if liveDesktop.isEnabled {
                        Circle()
                            .fill(liveDesktop.isPlaying ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }

                HStack(spacing: 6) {
                    Text(liveDesktop.statusDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(liveDesktop.pauseReason != nil ? .orange : .secondary)

                    if liveDesktop.pauseReason == "Paused: Battery Saver" {
                        Button("Play on Battery") {
                            liveDesktop.pauseOnBattery = false
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(Color.blue)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: $liveDesktop.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Scrollable content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                if !CatalogManager.isSystemReady {
                    setupCard
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }

                desktopMotionCard
                    .padding(.horizontal, 12)
                    .padding(.top, CatalogManager.isSystemReady ? 10 : 0)

                DropZoneView()
                    .environmentObject(store)
                    .padding(.horizontal, 12)

                if store.items.isEmpty && store.processingStatus.isEmpty {
                    emptyState
                } else {
                    LibraryGridView()
                        .environmentObject(store)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Setup banner (for non-tech users on fresh Macs)

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("One-Time Mac Setup")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text("Click below, then select any Apple video wallpaper once to initialize macOS's engine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                CatalogManager.openSystemWallpaperSettings()
            } label: {
                HStack {
                    Text("Open Wallpaper Settings")
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No wallpapers added yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // Check / Install updates directly in-app
            Button {
                if updateChecker.updateAvailable {
                    Task { await updateChecker.installUpdate() }
                } else {
                    Task { await updateChecker.checkForUpdates(userInitiated: true) }
                }
            } label: {
                HStack(spacing: 4) {
                    if updateChecker.isChecking {
                        ProgressView().controlSize(.mini)
                    } else if updateChecker.updateAvailable {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(updateChecker.updateAvailable ? "Install Update" : "Check Updates")
                        .font(.system(size: 11, weight: updateChecker.updateAvailable ? .medium : .regular))
                }
                .foregroundStyle(updateChecker.updateAvailable ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(updateChecker.updateAvailable ? "Click to download and install update in-app" : "Check GitHub for new AerialMotion updates")

            if !store.items.isEmpty {
                Button {
                    store.restore()
                } label: {
                    Label("Restore Apple", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove all AerialMotion wallpapers and restore Apple's originals")
            }

            Spacer()

            // Quit AerialMotion
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 3) {
                    Text("Quit")
                        .font(.system(size: 11, weight: .medium))
                    Text("⌘Q")
                        .font(.system(size: 9))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit AerialMotion completely (⌘Q)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Drop & File Picker

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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
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
}

// MARK: - Visual effect background (glass)

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material    = .popover
        v.blendingMode = .behindWindow
        v.state       = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Error toast

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .shadow(radius: 4)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { onDismiss() }
        }
    }
}
