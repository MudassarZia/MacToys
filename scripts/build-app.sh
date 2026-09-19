#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# ARCH=universal builds both supported CPU architectures. Defaults to this Mac.
ARCH="${ARCH:-$(uname -m)}"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/build}"
SCRATCH_PATH="${SCRATCH_PATH:-$PWD/.build}"
mkdir -p "$BUILD_ROOT" "$SCRATCH_PATH/ModuleCache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$SCRATCH_PATH/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
SWIFT_ARGS=(--disable-sandbox --scratch-path "$SCRATCH_PATH" -c "$CONFIGURATION")
if [[ "$ARCH" == universal ]]; then
    SWIFT_ARGS+=(--arch arm64 --arch x86_64)
elif [[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]]; then
    SWIFT_ARGS+=(--arch "$ARCH")
else
    echo "ARCH must be arm64, x86_64, or universal." >&2
    exit 1
fi
swift build "${SWIFT_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
APP="$BUILD_ROOT/MacToys.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacToys" "$APP/Contents/MacOS/MacToys"
cp scripts/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
swift scripts/make-icon.swift "$BUILD_ROOT/MacToys.iconset"
cp "$BUILD_ROOT/MacToys.icns" "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_ROOT/MacToys-0.1.0-$ARCH.zip"
echo "Built: $APP"
echo "Archive: $BUILD_ROOT/MacToys-0.1.0-$ARCH.zip"
if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
    echo "Local ad-hoc signature only. Public distribution requires Developer ID signing and notarization."
fi
