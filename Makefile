APP_NAME   = AerialMotion
BUILD_DIR  = .build/release
APP_BUNDLE = $(APP_NAME).app
DMG_NAME   = $(APP_NAME).dmg

.PHONY: build app dmg install clean open help

help:
	@echo ""
	@echo "  make app      — build + create $(APP_BUNDLE)"
	@echo "  make dmg      — package into $(DMG_NAME) for distribution"
	@echo "  make install  — build + copy to /Applications"
	@echo "  make open     — run the app directly"
	@echo "  make clean    — remove build artifacts and .dmg"
	@echo ""

build:
	swift build -c release
	@echo "✓ Build complete: $(BUILD_DIR)/$(APP_NAME)"

app: build
	@echo "→ Assembling $(APP_BUNDLE)..."
	rm -rf $(APP_BUNDLE)
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp $(BUILD_DIR)/$(APP_NAME) "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	cp Resources/AppIcon.png "$(APP_BUNDLE)/Contents/Resources/AppIcon.png"
	cp Resources/MenuBarIcon.png "$(APP_BUNDLE)/Contents/Resources/MenuBarIcon.png"
	cp Resources/MenuBarTemplate.png "$(APP_BUNDLE)/Contents/Resources/MenuBarTemplate.png"
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0"><dict>\n\
  <key>CFBundleIdentifier</key><string>com.aerialmotion.app</string>\n\
  <key>CFBundleName</key><string>AerialMotion</string>\n\
  <key>CFBundleDisplayName</key><string>AerialMotion</string>\n\
  <key>CFBundleExecutable</key><string>$(APP_NAME)</string>\n\
  <key>CFBundleIconFile</key><string>AppIcon</string>\n\
  <key>CFBundlePackageType</key><string>APPL</string>\n\
  <key>CFBundleShortVersionString</key><string>1.1.1</string>\n\
  <key>CFBundleVersion</key><string>1</string>\n\
  <key>LSMinimumSystemVersion</key><string>15.0</string>\n\
  <key>LSUIElement</key><true/>\n\
  <key>NSHighResolutionCapable</key><true/>\n\
  <key>NSPrincipalClass</key><string>NSApplication</string>\n\
  <key>NSHumanReadableCopyright</key><string>© 2026 Sachin Kaundal. MIT License.</string>\n\
</dict></plist>' > "$(APP_BUNDLE)/Contents/Info.plist"
	@echo "→ Ad-hoc code signing $(APP_BUNDLE)..."
	codesign --force --deep --sign - --timestamp=none "$(APP_BUNDLE)" || true
	@echo "✓ $(APP_BUNDLE) ready — drag to /Applications or run: make install"

dmg: app
	@echo "→ Packaging $(DMG_NAME)..."
	rm -rf dist $(DMG_NAME)
	mkdir -p dist/.background
	cp -R $(APP_BUNDLE) dist/
	ln -s /Applications dist/Applications
	cp Resources/installer_background.png dist/.background/installer_background.png
	cp Resources/dmg_ds_store dist/.DS_Store
	cp Resources/AppIcon.icns dist/.VolumeIcon.icns
	hdiutil create -volname "$(APP_NAME)" -srcfolder dist -ov -format UDZO $(DMG_NAME)
	rm -rf dist
	@echo "✓ $(DMG_NAME) created successfully!"

install: app
	cp -R $(APP_BUNDLE) /Applications/
	xattr -cr /Applications/$(APP_BUNDLE)
	@echo "✓ Installed to /Applications/$(APP_BUNDLE)"
	open /Applications/$(APP_BUNDLE)

open: build
	$(BUILD_DIR)/$(APP_NAME)

clean:
	rm -rf .build $(APP_BUNDLE) dist $(DMG_NAME)
	@echo "✓ Cleaned"
