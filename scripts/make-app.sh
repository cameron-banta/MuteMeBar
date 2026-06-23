#!/usr/bin/env bash
# make-app.sh - Build MuteMeBar and assemble a .app bundle at a stable path.
#
# WHY: macOS TCC (Privacy permissions) are tied to a binary path. When you run
# via `swift run`, the binary path changes each build and permissions go stale.
# This script always outputs to ./build/MuteMeBar.app so TCC grants persist.
#
# USAGE:
#   ./scripts/make-app.sh           # release build (default)
#   ./scripts/make-app.sh --debug   # debug build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIGURATION="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIGURATION="debug"
fi

APP_NAME="MuteMeBar"
BUNDLE_PATH="$ROOT/build/${APP_NAME}.app"
BINARY_NAME="MuteMeBar"
PLIST_SRC="$ROOT/Sources/MuteMeBar/Info.plist"

echo "==> Building $APP_NAME ($CONFIGURATION)..."
cd "$ROOT"
swift build -c "$CONFIGURATION"

# SPM places the binary under .build/<arch>-apple-macosx/<config>/
# Try the arch-qualified path first, fall back to the symlink.
ARCH="$(uname -m)-apple-macosx"
BINARY_SRC=""

if [[ -f "$ROOT/.build/$ARCH/$CONFIGURATION/$BINARY_NAME" ]]; then
    BINARY_SRC="$ROOT/.build/$ARCH/$CONFIGURATION/$BINARY_NAME"
elif [[ -f "$ROOT/.build/$CONFIGURATION/$BINARY_NAME" ]]; then
    BINARY_SRC="$ROOT/.build/$CONFIGURATION/$BINARY_NAME"
else
    echo "ERROR: Binary not found. Tried:"
    echo "  $ROOT/.build/$ARCH/$CONFIGURATION/$BINARY_NAME"
    echo "  $ROOT/.build/$CONFIGURATION/$BINARY_NAME"
    exit 1
fi

echo "==> Assembling $BUNDLE_PATH..."
rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS"
mkdir -p "$BUNDLE_PATH/Contents/Resources"

cp "$BINARY_SRC" "$BUNDLE_PATH/Contents/MacOS/$BINARY_NAME"
cp "$PLIST_SRC"  "$BUNDLE_PATH/Contents/Info.plist"
chmod +x "$BUNDLE_PATH/Contents/MacOS/$BINARY_NAME"

# Code sign so macOS TCC (Accessibility / Input Monitoring) grants persist.
# Prefer the stable self-signed identity (created by create-signing-cert.sh) so
# permissions survive rebuilds. Fall back to ad-hoc, which at least keeps grants
# stable between launches of the SAME build.
CERT_NAME="MuteMe Self-Signed"
# Resolve the identity's SHA-1 hash; codesign finds identities by hash far more
# reliably than by name. Format: "  1) <HASH> \"MuteMe Self-Signed\""
IDENTITY_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "$CERT_NAME" | head -1 | awk '{print $2}')"

if [[ -n "$IDENTITY_HASH" ]]; then
    echo "==> Signing with stable identity '$CERT_NAME' ($IDENTITY_HASH)..."
    codesign --force \
        --identifier "com.muteme.bar" \
        --sign "$IDENTITY_HASH" \
        "$BUNDLE_PATH"
    SIGN_MODE="stable (permissions persist across rebuilds)"
else
    echo "==> No stable identity found; signing ad-hoc..."
    echo "    (Run ./scripts/create-signing-cert.sh once so permissions persist across rebuilds.)"
    codesign --force \
        --identifier "com.muteme.bar" \
        --sign - \
        "$BUNDLE_PATH"
    SIGN_MODE="ad-hoc (re-grant permissions after each rebuild)"
fi

echo "==> Verifying signature..."
codesign --verify --verbose "$BUNDLE_PATH" 2>&1 || true

echo ""
echo "==> Done: $BUNDLE_PATH"
echo "    Signing: $SIGN_MODE"
echo ""
echo "To launch:"
echo "  open '$BUNDLE_PATH'"
echo ""
echo "On first launch, grant both permission prompts:"
echo "  - Input Monitoring  (System Settings -> Privacy & Security -> Input Monitoring)"
echo "  - Accessibility     (System Settings -> Privacy & Security -> Accessibility)"
echo ""
echo "Then in Zoom -> Settings -> Keyboard Shortcuts, check 'Enable Global Shortcut'"
echo "for 'Mute/Unmute My Audio' (Cmd+Shift+A)."
echo ""
echo "Always use this script to rebuild - it keeps the binary at a stable path"
echo "so your TCC permission grants are not lost between builds."
