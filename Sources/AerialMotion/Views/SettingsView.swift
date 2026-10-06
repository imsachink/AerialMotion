import SwiftUI

// MARK: - Settings panel

struct SettingsView: View {

    @EnvironmentObject var store: WallpaperStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("thumbnailAt")   private var thumbnailAt:   Int    = 1
    @AppStorage("stripAudio")    private var stripAudio:    Bool   = true
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool   = false
    @AppStorage("menuBarMonochrome") private var menuBarMonochrome: Bool = false

    private var ffmpegInstalled: Bool { VideoProcessor.ffmpegPath() != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── App Header / About ─────────────────────────────────
                    HStack(spacing: 14) {
                        if let logo = AppLogo.image {
                            Image(nsImage: logo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AerialMotion")
                                .font(.system(size: 15, weight: .bold))
                            Text("Version 1.0.0 • Native Live Wallpapers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Built for macOS 14+ Sonoma & Sequoia")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)

                    Divider()

                    // ── Engine status ──────────────────────────────────────
                    section(title: "Conversion Engine") {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Native Apple AVFoundation")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Built-in macOS hardware acceleration (Zero dependencies)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Active")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.green)
                            }

                            HStack {
                                Image(systemName: ffmpegInstalled ? "bolt.fill" : "bolt.slash")
                                    .foregroundStyle(ffmpegInstalled ? .blue : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ffmpegInstalled ? "ffmpeg accelerator active" : "ffmpeg (Optional)")
                                        .font(.system(size: 12, weight: .medium))
                                    Text(ffmpegInstalled ? "Fast stream-copy enabled" : "Optional fallback for esoteric codecs")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .padding(10)
                        .background(
                            Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }

                    // ── Video options ──────────────────────────────────────
                    section(title: "Video") {
                        VStack(spacing: 10) {
                            row(label: "Thumbnail at", description: "Second of video used for preview image") {
                                HStack(spacing: 6) {
                                    Stepper("", value: $thumbnailAt, in: 0...30)
                                        .labelsHidden()
                                    Text("\(thumbnailAt)s")
                                        .font(.system(size: 12, design: .monospaced))
                                        .frame(width: 28)
                                }
                            }

                            Divider()

                            row(label: "Strip audio", description: "Remove audio track from wallpaper video") {
                                Toggle("", isOn: $stripAudio)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                        }
                    }

                    // ── App ────────────────────────────────────────────────
                    section(title: "App & Appearance") {
                        row(label: "Launch at login", description: "Start AerialMotion automatically when you log in") {
                            Toggle("", isOn: $launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .onChange(of: launchAtLogin) { _, enabled in
                                    setLaunchAtLogin(enabled)
                                }
                        }

                        row(label: "Monochrome Menu Bar Icon", description: "Use outline symbol instead of full-color app logo") {
                            Toggle("", isOn: $menuBarMonochrome)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    // ── Library ────────────────────────────────────────────
                    section(title: "Library") {
                        HStack(spacing: 8) {
                            Button("Open Library Folder") {
                                NSWorkspace.shared.open(libDir)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)

                            Button("Restore Apple Originals") {
                                store.restore()
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }

                    // ── About & Support ────────────────────────────────────
                    section(title: "About & Support") {
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AerialMotion v1.0.0")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Native live video wallpapers for macOS")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("GitHub") {
                                    NSWorkspace.shared.open(
                                        URL(string: "https://github.com/imsachink/AerialMotion")!)
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }

                            Divider()

                            HStack {
                                Text("Enjoying AerialMotion?")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Buy Me a Coffee ☕") {
                                    NSWorkspace.shared.open(
                                        URL(string: "https://buymeacoffee.com/sachinkaundal")!)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.orange)
                                .font(.caption)
                            }
                        }
                        .padding(10)
                        .background(
                            Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }
                .padding()
            }
        }
        .frame(width: 380, height: 480)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func row<Control: View>(
        label: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12))
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            control()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // Use SMAppService on macOS 13+
        // For simplicity, open Login Items System Settings
        if enabled {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
    }
}
