#!/bin/bash
# Builds Caelestia for Mac (release) and assembles signed .app bundles into ./dist.
#
# Usage: scripts/build.sh [--debug] [--no-sign] [--identity "Name"]
#
# Signing: uses the local certificate "Caelestia Local Signing" created by scripts/sign-setup.sh
# so TCC grants (Accessibility, Input Monitoring, Screen Recording) survive rebuilds. If the
# certificate is missing the build is ad-hoc signed and a warning is printed (permissions will
# have to be re-granted after every rebuild). A Developer ID identity can be passed instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG=release
SIGN=1
IDENTITY="${CAELESTIA_SIGN_IDENTITY:-Caelestia Local Signing}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG=debug ;;
    --no-sign) SIGN=0 ;;
    --identity) IDENTITY="$2"; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 3 ;;
  esac
  shift
done

# Always use the toolchain that ships with the selected Xcode; a swift.org toolchain on PATH
# (swiftly, etc.) does not match the SDK and fails to compile Foundation.
XCODE_TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin"
export PATH="$XCODE_TOOLCHAIN:$PATH"
SWIFT="$XCODE_TOOLCHAIN/swift"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "warning: Caelestia for Mac targets Apple Silicon; building on $(uname -m) anyway" >&2
fi

echo "==> swift build -c $CONFIG"
"$SWIFT" build -c "$CONFIG" --product CaelestiaWM --product caelestia --product TestWindows --product gen-keybind-docs 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' || true
BIN="$("$SWIFT" build -c "$CONFIG" --show-bin-path)"
test -x "$BIN/CaelestiaWM" || { echo "build failed: $BIN/CaelestiaWM missing" >&2; exit 1; }

VERSION="$(sed -n 's/.*public static let string = "\(.*\)".*/\1/p' Sources/CaelestiaCore/Version.swift | head -1)"
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

# --- CaelestiaWM.app (agent app: WM + shell + IPC server + CLI) ---------------------------------
APP="$DIST/CaelestiaWM.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN/CaelestiaWM" "$APP/Contents/MacOS/CaelestiaWM"
cp "$BIN/caelestia" "$APP/Contents/MacOS/caelestia"
# SwiftPM resource bundles (keymap/config/rules defaults, schemes, shell assets)
for b in "$BIN"/CaelestiaMac_*.bundle; do
  [[ -d "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done
cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Packaging/CaelestiaWM-Info.plist" > "$APP/Contents/Info.plist"
sed "s|__APP_PATH__|$HOME/Applications/CaelestiaWM.app|g" "$ROOT/Packaging/com.caelestia.mac.wm.plist" \
  > "$APP/Contents/Library/LaunchAgents/com.caelestia.mac.wm.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# --- TestWindows.app (Riko regression harness) --------------------------------------------------
TW="$DIST/TestWindows.app"
mkdir -p "$TW/Contents/MacOS" "$TW/Contents/Resources"
cp "$BIN/TestWindows" "$TW/Contents/MacOS/TestWindows"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Packaging/TestWindows-Info.plist" > "$TW/Contents/Info.plist"

# --- Signing ------------------------------------------------------------------------------------
sign_bundle() {
  local bundle="$1" entitlements="$2"
  if [[ $SIGN -eq 1 ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --deep --options runtime --timestamp=none \
      --entitlements "$entitlements" --sign "$IDENTITY" "$bundle"
    echo "    signed $(basename "$bundle") with \"$IDENTITY\""
  else
    codesign --force --deep --sign - "$bundle"
    echo "    warning: ad-hoc signed $(basename "$bundle"); run scripts/sign-setup.sh so permissions survive rebuilds" >&2
  fi
}
echo "==> codesign"
sign_bundle "$APP" "$ROOT/Packaging/CaelestiaWM.entitlements"
sign_bundle "$TW" "$ROOT/Packaging/TestWindows.entitlements"
codesign --verify --deep --strict "$APP"

echo "==> done: $APP (v$VERSION, $CONFIG)"
