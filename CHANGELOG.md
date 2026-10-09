# 📋 AerialMotion Changelog

All notable changes to **AerialMotion** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v1.2.0] - 2026-10-09

### ✨ New Features
* **Discover 4K Curated Community Gallery**: Added an in-app gallery tab showcasing verified, non-dizzy, slow-motion CC0 video wallpapers with 1-click download and instant apply.
* **Dynamic Live Catalog Refresh**: Added a live **Sync (🔄)** button that pulls updated catalog manifests from GitHub with cache-busting, allowing new open-source community wallpapers to appear without requiring app updates.
* **Native Fast Downloader with Stop/Cancel Control**: Replaced chunked loops with native `URLSessionDownloadTask` kernel streaming. Added an immediate **Stop Download** button to abort and clean up in-progress downloads at any time.
* **Full-Area Interactive Tab Pills**: Upgraded navigation tabs (`My Library` vs `Discover 4K`) and category pills with generous hit testing (`.contentShape(Rectangle())`), ensuring instant responsiveness when clicking anywhere inside the button.

---

## [v1.1.2] - 2026-10-07

### 🐛 Bug Fixes & Improvements
* **Removed Global Menu Bar Right-Click Monitors**: Completely removed top-edge event monitors and gesture recognizers that intercepted right-clicks across the macOS menu bar. The interface now operates via standard Mac 1-click popover.
* **Seamless Process Lifecycle on Install**: Updated installation scripts to automatically terminate running instances before replacing the app in `/Applications`.

---

## [v1.1.1] - 2026-10-06

### ✨ New Features
* **1-Click Native Video File Picker**: The entire drop zone card in the menu bar popover is now an interactive button that launches macOS's native `NSOpenPanel`. Users can import `.mp4`, `.mov`, and `.m4v` video files with a single click without needing to drag-and-drop.
* **Right-Click Menu Shortcut**: Added `Add Video Wallpaper… (⌘N)` to the status bar icon right-click context menu for instant file selection.

### 🐛 Bug Fixes & Improvements
* **Desktop Window Layer Positioning**: Adjusted window server level to `-2147483604` using `orderFrontRegardless()`. This positions the live desktop video above Dock's wallpaper backdrop and underneath Finder desktop icons and desktop widgets.
* **Battery Saver Default & Quick Resume**: Set `pauseOnBattery` to default `false` so continuous desktop motion plays out-of-the-box on battery. Added an instant `Play on Battery` action button directly on the menu bar card if Battery Saver is ever engaged.
* **Popover Layout Sizing**: Fixed popover clipping by setting an explicit `380×490` frame, ensuring all saved wallpapers and library cards remain fully visible without collapsing.

---

## [v1.1.0] - 2026-10-06

### ✨ New Features
* **Continuous Desktop Live Motion**: Introduced continuous live video looping on the macOS Home Screen (Desktop) using hardware-accelerated `AVPlayerLayer` rendering (~1.5% CPU).
* **Wallspace-Grade Ultra-Low Battery Saver**:
  * 🔋 **Pause on Battery**: Option to automatically pause playback on battery power to maximize runtime.
  * ⚡ **Low Power Mode**: Automatically pauses when macOS Low Power Mode is enabled.
  * 🪟 **Desktop Occlusion Sensing**: Drops to 0% CPU/GPU whenever full-screen windows or active apps cover the desktop.
  * 💤 **Sleep & Lock Sleep**: Instantly pauses playback when displays sleep or screen is locked.
* **Direct In-App Auto-Updater**: Clicking "Install Update" downloads the latest release `.dmg` directly inside the app, verifies it, extracts the update, replaces `/Applications/AerialMotion.app`, and automatically relaunches. Zero browser visits required!

---

## [v1.0.1] - 2026-10-06

### 🐛 Bug Fixes & Engineering
* **Apple VideoToolbox 2-Layer Hierarchical HEVC**: Resolved the black desktop wallpaper bug in macOS Sonoma/Sequoia by encoding dual-layer HEVC (`temporal_id=0/1`), matching Apple's internal `WallpaperAerialsExtension` parser specifications.
* **Mission Control Space Desync**: Cleared orphaned space UUIDs in `Index.plist` to prevent blank spaces when switching desktops.
* **Status Bar Right-Click Menu**: Implemented AppKit gesture recognizer on status bar button offering `Check for Updates`, `Settings`, `Buy Me a Coffee`, and `Quit (⌘Q)`.
* **Update Checker**: Added automated GitHub Releases update checking.

---

## [v1.0.0] - 2026-10-06

### 🚀 Initial Public Release
* Native macOS Sonoma & Sequoia dynamic aerial lock screen and desktop wallpaper support.
* Drag-and-drop video importer with hardware-accelerated video remuxing.
* Custom wallpaper library with 1-click wallpaper switching.
* 100% reversible: 1-click restore to Apple original wallpapers.
* MIT Licensed, free and open-source.
