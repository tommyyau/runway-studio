#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
swift build -c release --product studio-docs
BUILD_DIR="$(swift build -c release --show-bin-path)"
DOCS_BUNDLE="$ROOT_DIR/dist/StudioDocs.app"
mkdir -p "$DOCS_BUNDLE/Contents/MacOS" "$DOCS_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/studio-docs" "$DOCS_BUNDLE/Contents/MacOS/studio-docs"
cp -R "$BUILD_DIR/Runway_Runway.bundle" "$DOCS_BUNDLE/Contents/Resources/"
bash script/embed_sparkle.sh "$DOCS_BUNDLE" "$DOCS_BUNDLE/Contents/MacOS/studio-docs" -
cat > "$DOCS_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>studio-docs</string>
<key>CFBundleIdentifier</key><string>local.runway.studio.documentation</string>
<key>CFBundleName</key><string>Studio Documentation</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$DOCS_BUNDLE"
"$DOCS_BUNDLE/Contents/MacOS/studio-docs" "$ROOT_DIR/assets/studio"
