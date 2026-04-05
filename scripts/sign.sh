#!/usr/bin/env bash
# Sign Crow.app with Developer ID or ad-hoc
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="${1:-$ROOT_DIR/Crow.app}"
ENTITLEMENTS="$ROOT_DIR/Crow.entitlements"

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: App bundle not found at $APP_DIR"
    exit 1
fi

IDENTITY="${DEVELOPER_ID_APPLICATION:--}"

if [ "$IDENTITY" = "-" ]; then
    echo "==> Signing ad-hoc (no Developer ID)..."
else
    echo "==> Signing with: $IDENTITY"
fi

# Sign the main binary first, then the bundle (inside-out)
codesign --force --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$APP_DIR/Contents/MacOS/CrowApp"

codesign --force --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$APP_DIR"

echo "==> Verifying signature..."
codesign --verify --verbose=2 "$APP_DIR"
echo "==> Signed: $APP_DIR"
