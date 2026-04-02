#!/usr/bin/env bash
# Build GhosttyKit.xcframework from the Ghostty submodule.
# Requires: zig 0.15.2, Xcode with Metal Toolchain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
GHOSTTY_DIR="$ROOT_DIR/vendor/ghostty"
FRAMEWORKS_DIR="$ROOT_DIR/Frameworks"
CACHE="$GHOSTTY_DIR/.zig-cache/o"
XCFW_DIR="$FRAMEWORKS_DIR/GhosttyKit.xcframework/macos-arm64"

# Ensure submodule is initialized
if [ ! -f "$GHOSTTY_DIR/build.zig" ]; then
    echo "==> Initializing Ghostty submodule..."
    git -C "$ROOT_DIR" submodule update --init vendor/ghostty
fi

# Check zig version
REQUIRED_ZIG="0.15.2"
CURRENT_ZIG=$(zig version 2>/dev/null || echo "not found")
if [ "$CURRENT_ZIG" != "$REQUIRED_ZIG" ]; then
    echo "ERROR: Zig $REQUIRED_ZIG required, found: $CURRENT_ZIG"
    echo "Install with: brew install zig"
    exit 1
fi

# Check Metal Toolchain
if ! xcrun -sdk macosx metal --version &>/dev/null; then
    echo "ERROR: Metal Toolchain not installed."
    echo "Run: xcodebuild -downloadComponent MetalToolchain"
    exit 1
fi

echo "==> Building GhosttyKit..."
cd "$GHOSTTY_DIR"

# Build (xcframework + app). The app link may fail but that's OK —
# we only need the xcframework and cached build artifacts.
zig build \
    -Demit-xcframework=true \
    -Dxcframework-target=native \
    -Doptimize=ReleaseFast || true

# Check that the xcframework was produced
XCFW_SRC="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
if [ ! -d "$XCFW_SRC" ]; then
    echo "ERROR: GhosttyKit.xcframework not found"
    exit 1
fi

echo "==> Assembling complete fat library..."
mkdir -p "$XCFW_DIR"

# Copy xcframework structure
cp "$XCFW_SRC/Info.plist" "$FRAMEWORKS_DIR/GhosttyKit.xcframework/"
cp -R "$XCFW_SRC/macos-arm64/Headers" "$XCFW_DIR/" 2>/dev/null || true

# Start with the dependency library from the xcframework
OUTPUT="$XCFW_DIR/libghostty-fat.a"
cp "$XCFW_SRC/macos-arm64/libghostty-fat.a" "$OUTPUT"

# Find and add the Zig-compiled ghostty API object (libghostty_zcu.o)
ZCU=$(find "$CACHE" -name "libghostty_zcu.o" -print -quit 2>/dev/null)
if [ -n "$ZCU" ]; then
    ar r "$OUTPUT" "$ZCU" 2>/dev/null
    echo "    Added libghostty_zcu.o"
fi

# Add remaining .o files from the API static library
API_DIR=$(dirname "$ZCU" 2>/dev/null || true)
if [ -n "$API_DIR" ]; then
    for obj in vt.o stb.o wuffs-v0.4.o base64.o codepoint_width.o index_of.o; do
        if [ -f "$API_DIR/$obj" ]; then
            ar r "$OUTPUT" "$API_DIR/$obj" 2>/dev/null
        fi
    done
fi

# Add individual dependency libraries that aren't in the fat lib
TMPEXTRACT="$ROOT_DIR/.build/_ghostty_extract_$$"
for libname in libglslang.a libspirv_cross.a libdcimgui.a libfreetype.a \
               liboniguruma.a libsentry.a libsimdutf.a libpng.a \
               libhighway.a libintl.a libmacos.a libutfcpp.a libbreakpad.a libz.a; do
    found=$(find "$CACHE" -name "$libname" -print -quit 2>/dev/null)
    if [ -n "$found" ]; then
        mkdir -p "$TMPEXTRACT"
        cd "$TMPEXTRACT"
        ar x "$found" 2>/dev/null
        chmod 644 *.o 2>/dev/null
        ar r "$OUTPUT" *.o 2>/dev/null
        cd "$ROOT_DIR"
        rm -rf "$TMPEXTRACT"
    fi
done

# Add the ImGui ext.o (C++ constructors)
IMGUI_EXT=$(find "$CACHE" -name "ext.o" -exec sh -c 'nm "$1" 2>/dev/null | grep -q "T _ImFontConfig_ImFontConfig" && echo "$1"' _ {} \; 2>/dev/null | head -1)
if [ -n "$IMGUI_EXT" ]; then
    ar r "$OUTPUT" "$IMGUI_EXT" 2>/dev/null
fi

# Add the full wuffs object (contains all image decoders)
WUFFS_FULL=$(find "$CACHE" -name "wuffs-v0.4.o" -exec sh -c 'nm "$1" 2>/dev/null | grep -q "T _wuffs_jpeg__decoder__decode_frame" && echo "$1"' _ {} \; 2>/dev/null | head -1)
if [ -n "$WUFFS_FULL" ]; then
    cp "$WUFFS_FULL" "$TMPEXTRACT.wuffs_full.o" 2>/dev/null || true
    if [ -f "$TMPEXTRACT.wuffs_full.o" ]; then
        ar r "$OUTPUT" "$TMPEXTRACT.wuffs_full.o" 2>/dev/null
        rm "$TMPEXTRACT.wuffs_full.o"
    fi
fi

# Add the SIMD vt.o (decode_utf8 functions)
SIMD_VT=$(find "$CACHE" -name "vt.o" -exec sh -c 'nm "$1" 2>/dev/null | grep -q "T _ghostty_simd_decode_utf8" && echo "$1"' _ {} \; 2>/dev/null | head -1)
if [ -n "$SIMD_VT" ]; then
    cp "$SIMD_VT" "$TMPEXTRACT.vt_simd.o" 2>/dev/null || true
    if [ -f "$TMPEXTRACT.vt_simd.o" ]; then
        ar r "$OUTPUT" "$TMPEXTRACT.vt_simd.o" 2>/dev/null
        rm "$TMPEXTRACT.vt_simd.o"
    fi
fi

# Regenerate symbol table
ranlib "$OUTPUT" 2>&1 || true

echo "    Fat library: $(stat -f%z "$OUTPUT") bytes"

# Copy Ghostty resources
RESOURCES_SRC="$GHOSTTY_DIR/zig-out/share/ghostty"
if [ -d "$RESOURCES_SRC" ]; then
    rm -rf "$FRAMEWORKS_DIR/ghostty-resources"
    cp -R "$RESOURCES_SRC" "$FRAMEWORKS_DIR/ghostty-resources"
    echo "    Bundled Ghostty resources"
fi

rm -rf "$TMPEXTRACT" 2>/dev/null || true

echo "==> Done! GhosttyKit.xcframework is ready."
echo "    Verify: swift build"
