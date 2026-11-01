#!/usr/bin/env bash
set -euo pipefail

# Native Studio build. Shared parsers link Runway's existing frameworks without starting its updater.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
swift build -c release --product RunwayStudio
swift build -c release --product runway-studio
BUILD_DIR="$(swift build -c release --show-bin-path)"
STUDIO_BUNDLE="$ROOT_DIR/dist/Runway Studio.app"
mkdir -p "$STUDIO_BUNDLE/Contents/MacOS" "$STUDIO_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/RunwayStudio" "$STUDIO_BUNDLE/Contents/MacOS/RunwayStudio"
cp "$BUILD_DIR/runway-studio" "$STUDIO_BUNDLE/Contents/MacOS/runway-studio"
codesign --force --sign - "$STUDIO_BUNDLE/Contents/MacOS/runway-studio"
cp LICENSE "$STUDIO_BUNDLE/Contents/Resources/LICENSE"
cp ACKNOWLEDGEMENTS.md "$STUDIO_BUNDLE/Contents/Resources/ACKNOWLEDGEMENTS.md"
cp -R "$BUILD_DIR/Runway_Runway.bundle" "$STUDIO_BUNDLE/Contents/Resources/"
bash "$ROOT_DIR/script/embed_sparkle.sh" "$STUDIO_BUNDLE" "$STUDIO_BUNDLE/Contents/MacOS/RunwayStudio" -
ICON_DIR="$ROOT_DIR/dist/Studio.iconset"
swift "$ROOT_DIR/script/studio_icon.swift" "$ICON_DIR"
iconutil -c icns "$ICON_DIR" -o "$STUDIO_BUNDLE/Contents/Resources/Studio.icns"
cat > "$STUDIO_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RunwayStudio</string>
<key>CFBundleIdentifier</key><string>local.runway.studio</string>
<key>CFBundleName</key><string>Runway Studio</string>
<key>CFBundleDisplayName</key><string>Runway Studio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Studio</string>
<key>CFBundleShortVersionString</key><string>dev</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Local MIT-licensed dashboard. Built on Runway by mstallone and OpenUsage by Robin Ebers.</string>
</dict></plist>
PLIST
codesign --force --sign - "$STUDIO_BUNDLE"
codesign --verify --deep --strict "$STUDIO_BUNDLE"
echo "Built: $STUDIO_BUNDLE"
