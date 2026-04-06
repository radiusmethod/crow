#!/usr/bin/env bash
# Sign, create DMG, notarize, and staple the Crow app bundle.
#
# Required:
#   DEVELOPER_ID_APPLICATION  — signing identity (e.g. "Developer ID Application: Radius Method (TEAMID)")
#
# Optional:
#   CROW_VERSION              — version string for DMG filename (default: "dev")
#   APPLE_ID                  — Apple ID for notarization
#   APPLE_APP_SPECIFIC_PASSWORD — app-specific password for notarization
#   APPLE_TEAM_ID             — Apple Developer Team ID for notarization
#
# If all three notarization vars are set, the DMG is submitted for notarization and stapled.
# Otherwise, signing and DMG creation proceed without notarization.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENTITLEMENTS="$ROOT_DIR/Crow.entitlements"
VERSION="${CROW_VERSION:-dev}"

# --- Validate inputs ---

APP_PATH="${1:-$ROOT_DIR/Crow.app}"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App bundle not found at $APP_PATH"
    echo "Run 'make release' first to build the app bundle."
    exit 1
fi

if [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
    echo "ERROR: DEVELOPER_ID_APPLICATION is not set."
    echo "Set it to your signing identity, e.g.:"
    echo "  export DEVELOPER_ID_APPLICATION=\"Developer ID Application: Your Name (TEAMID)\""
    exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "ERROR: Entitlements file not found at $ENTITLEMENTS"
    exit 1
fi

IDENTITY="$DEVELOPER_ID_APPLICATION"

# --- Step 1: Code sign the .app bundle ---

echo "==> Signing $APP_PATH..."
codesign --force --deep \
    --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "$APP_PATH"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "    Signature OK"

# --- Step 2: Create DMG ---

DMG_NAME="Crow-${VERSION}.dmg"
DMG_PATH="$ROOT_DIR/$DMG_NAME"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"

echo "==> Creating DMG: $DMG_NAME..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "Crow" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

# Sign the DMG
codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
echo "    DMG created and signed: $DMG_PATH"

# --- Step 3: Notarize (conditional) ---

if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    # --- Step 4: Staple ---

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    echo "    Notarization complete and stapled"
else
    echo "==> Skipping notarization (APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, or APPLE_TEAM_ID not set)"
fi

echo "==> Done! Output: $DMG_PATH"
