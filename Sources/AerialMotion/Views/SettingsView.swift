import SwiftUI
import AppKit

// MARK: - Settings view
// Liquid glass design, System Settings style layout.

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WallpaperStore
    @StateObject private var updateChecker = UpdateChecker.shared

    @AppStorage("thumbnailAt")       private var thumbnailAt: Int = 1
    @AppStorage("stripAudio")         private var stripAudio: Bool = true
    @AppStorage("launchAtLogin")      private var launchAtLogin: Bool = false
    @AppStorage("menuBarMonochrome")  private var menuBarMonochrome: Bool = false

    private var ffmpegInstalled: Bool { VideoProcessor.ffmpegPath() != nil }

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Engine status ──────────────────────────────────
                        section(title: "Engine Status") {
                            VStack(spacing: 6) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Apple Silicon Hardware Acceleration")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("VideoToolbox 10-bit HEVC encoder active")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("Active")
                                        .font(.caption)
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

                        // ── Video options ──────────────────────────────────
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

                        // ── App & Appearance ───────────────────────────────
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

                        // ── Updates ────────────────────────────────────────
                        section(title: "Software Updates") {
                            VStack(spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("AerialMotion v\(updateChecker.currentVersion)")
                                            .font(.system(size: 12, weight: .medium))
                                        if let msg = updateChecker.statusMessage {
                                            Text(msg)
                                                .font(.caption)
                                                .foregroundStyle(updateChecker.updateAvailable ? .green : .secondary)
                                        } else {
                                            Text("Check GitHub for the latest release")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()

                                    Button {
                                        Task { await updateChecker.checkForUpdates(userInitiated: true) }
                                    } label: {
                                        if updateChecker.isChecking {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Text(updateChecker.updateAvailable ? "Download" : "Check Now")
                                                .font(.caption)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(updateChecker.updateAvailable ? .green : .accentColor)
                                }
                            }
                            .padding(10)
                            .background(
                                Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }

                        // ── Library ────────────────────────────────────────
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

                        // ── About & Support ────────────────────────────────
                        section(title: "About & Support") {
                            VStack(spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("AerialMotion")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Created by Sachin Kaundal • MIT License")
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

                        // ── Danger Zone / Quit ─────────────────────────────
                        section(title: "Application Control") {
                            Button {
                                NSApplication.shared.terminate(nil)
                            } label: {
                                HStack {
                                    Image(systemName: "power")
                                    Text("Quit AerialMotion")
                                    Spacer()
                                    Text("⌘Q")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 380, height: 520)
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
        if enabled {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
    }
}
