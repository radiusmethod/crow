#!/usr/bin/env bash
# Bundle rm-ai-ide into a .app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/RmAiIde.app"
FRAMEWORKS_DIR="$ROOT_DIR/Frameworks"

echo "==> Generating build info..."
bash "$SCRIPT_DIR/generate-build-info.sh"

echo "==> Building release..."
cd "$ROOT_DIR"
swift build -c release

echo "==> Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/RmAiIde" "$APP_DIR/Contents/MacOS/"

# Copy Ghostty resources if available
if [ -d "$FRAMEWORKS_DIR/ghostty-resources" ]; then
    cp -R "$FRAMEWORKS_DIR/ghostty-resources" "$APP_DIR/Contents/Resources/ghostty"
    echo "    Bundled Ghostty resources"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>RmAiIde</string>
    <key>CFBundleIdentifier</key>
    <string>com.radiusmethod.rm-ai-ide</string>
    <key>CFBundleName</key>
    <string>rm-ai-ide</string>
    <key>CFBundleDisplayName</key>
    <string>rm-ai-ide</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

echo "==> App bundle created at: $APP_DIR"
