import SwiftUI
import AppKit

// MARK: - Settings view
// Liquid glass design, System Settings style layout.

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WallpaperStore
    @EnvironmentObject private var liveDesktop: LiveDesktopManager
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

                        // ── Desktop Motion & Battery ──────────────────────
                        section(title: "Desktop Motion & Battery") {
                            VStack(spacing: 10) {
                                row(
                                    label: "Play Motion on Home Screen",
                                    description: "Continuously loop wallpaper video on the desktop"
                                ) {
                                    Toggle("", isOn: $liveDesktop.isEnabled)
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                }

                                if liveDesktop.isEnabled {
                                    Divider()

                                    row(
                                        label: "Pause when on Battery",
                                        description: "Preserve battery runtime by pausing desktop video when unplugged"
                                    ) {
                                        Toggle("", isOn: $liveDesktop.pauseOnBattery)
                                            .labelsHidden()
                                            .toggleStyle(.switch)
                                    }

                                    Divider()

                                    row(
                                        label: "Pause in Low Power Mode",
                                        description: "Pause playback whenever macOS Low Power Mode is on"
                                    ) {
                                        Toggle("", isOn: $liveDesktop.pauseInLowPowerMode)
                                            .labelsHidden()
                                            .toggleStyle(.switch)
                                    }

                                    Divider()

                                    row(
                                        label: "Pause when Desktop Obscured",
                                        description: "Zero CPU & GPU when windows or full-screen apps cover desktop"
                                    ) {
                                        Toggle("", isOn: $liveDesktop.pauseWhenOccluded)
                                            .labelsHidden()
                                            .toggleStyle(.switch)
                                    }

                                    Divider()

                                    HStack {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(liveDesktop.isPlaying ? Color.green : (liveDesktop.pauseReason != nil ? Color.orange : Color.secondary))
                                                .frame(width: 8, height: 8)
                                            Text("Engine Status:")
                                                .font(.caption.weight(.medium))
                                            Text(liveDesktop.statusDescription)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(10)
                            .background(
                                Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }

                        // ── Engine status ──────────────────────────────────
                        section(title: "Hardware Acceleration") {
                            VStack(spacing: 6) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Apple Silicon Media Engine")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Zero-copy GPU hardware decoding (~0.5% CPU)")
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
                        section(title: "Updates") {
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
                                        if updateChecker.updateAvailable {
                                            Task { await updateChecker.installUpdate() }
                                        } else {
                                            Task { await updateChecker.checkForUpdates(userInitiated: true) }
                                        }
                                    } label: {
                                        if updateChecker.isChecking {
                                            ProgressView().controlSize(.small)
                                        } else if updateChecker.isUpdating {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Text(updateChecker.updateAvailable ? "Install Update" : "Check Now")
                                                .font(.caption)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(updateChecker.updateAvailable ? .green : .accentColor)
                                    .disabled(updateChecker.isChecking || updateChecker.isUpdating)
                                }

                                if updateChecker.updateAvailable && !updateChecker.releaseNotes.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("What's New in this update:")
                                            .font(.caption.weight(.semibold))
                                        ScrollView {
                                            Text(updateChecker.releaseNotes)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(maxHeight: 70)
                                    }
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                                }

                                if updateChecker.isUpdating {
                                    VStack(spacing: 4) {
                                        ProgressView(value: updateChecker.downloadProgress)
                                            .progressViewStyle(.linear)
                                        HStack {
                                            Text(updateChecker.updateStatus)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(String(format: "%.0f%%", updateChecker.downloadProgress * 100))
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.top, 4)
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
                                    Button("Release Notes") {
                                        NSWorkspace.shared.open(
                                            URL(string: "https://github.com/imsachink/AerialMotion/releases/tag/v\(updateChecker.currentVersion)")!)
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)

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
        .frame(width: 400, height: 560)
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
