#!/usr/bin/env bash
# Create a DMG from Crow.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="${1:-$ROOT_DIR/Crow.app}"

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: App bundle not found at $APP_DIR"
    exit 1
fi

# --- Version ---
if [ -n "${VERSION:-}" ]; then
    APP_VERSION="$VERSION"
elif [ -f "$ROOT_DIR/VERSION" ]; then
    APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
else
    APP_VERSION="0.1.0"
fi

DMG_NAME="Crow-${APP_VERSION}-arm64.dmg"
DMG_PATH="$ROOT_DIR/$DMG_NAME"

# Remove existing DMG
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
    echo "==> Creating DMG with create-dmg..."
    create-dmg \
        --volname "Crow" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "Crow.app" 150 190 \
        --app-drop-link 450 190 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$APP_DIR"
else
    echo "==> Creating DMG with hdiutil (install create-dmg for a nicer result)..."
    STAGING_DIR="$(mktemp -d)"
    cp -R "$APP_DIR" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"

    hdiutil create -volname "Crow" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$STAGING_DIR"
fi

echo "==> DMG created: $DMG_PATH"
