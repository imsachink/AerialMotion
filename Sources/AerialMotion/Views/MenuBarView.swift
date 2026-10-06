import SwiftUI
import AppKit

// MARK: - Main MenuBar popover view
// Liquid glass design, fully responsive, zero-margin layout.

struct MenuBarView: View {

    @EnvironmentObject private var store: WallpaperStore
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
                scrollContent
                Divider().opacity(0.3)
                footer
            }
        }
        .frame(width: 380)
        .frame(minHeight: 160, maxHeight: 520)
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
            .frame(width: 0, height: 0)
        )
        // Error toast
        .overlay(alignment: .bottom) {
            if let err = store.errorMessage {
                ErrorToast(message: err) { store.errorMessage = nil }
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: store.errorMessage)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let logo = AppLogo.image {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "video.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            Text("AerialMotion")
                .font(.system(size: 14, weight: .semibold))
            Spacer()

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

    // MARK: - Scrollable content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                if !CatalogManager.isSystemReady {
                    setupCard
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }

                DropZoneView()
                    .environmentObject(store)
                    .padding(.horizontal, 12)
                    .padding(.top, CatalogManager.isSystemReady ? 10 : 0)

                if store.items.isEmpty && store.processingStatus.isEmpty {
                    emptyState
                } else {
                    LibraryGridView()
                        .environmentObject(store)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 10)
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
            Text("Drop a video to get started")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // Check for updates
            Button {
                Task { await updateChecker.checkForUpdates(userInitiated: true) }
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
                    Text(updateChecker.updateAvailable ? "Update Available!" : "Check Updates")
                        .font(.system(size: 11))
                }
                .foregroundStyle(updateChecker.updateAvailable ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Check GitHub for new AerialMotion updates")

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

    // MARK: - Drop handler

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
