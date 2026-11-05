#!/bin/bash
# Builds SkyRose (release) and assembles signed .app bundles into ./dist:
#   dist/SkyRose.app            agent app (no Dock icon): SkyRose WM + shell + IPC server + CLI
#   dist/SkyRose Settings.app   the Settings app and the first-run onboarding
#   dist/TestWindows.app        regression harness
#
# Usage: scripts/build.sh [--debug] [--no-sign] [--identity "Name"]
#
# Signing: uses the local code-signing certificate made by scripts/sign-setup.sh so TCC grants
# (Accessibility, Input Monitoring, Screen Recording) survive rebuilds. Machines set up before the
# rename have it as "Caelestia Local Signing"; that name is kept (renaming the certificate would
# change the signature and drop every grant). New machines get "SkyRose Local Signing". If neither
# exists the build is ad-hoc signed and a warning is printed. A Developer ID can be passed instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG=release
SIGN=1
IDENTITY="${SKYROSE_SIGN_IDENTITY:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG=debug ;;
    --no-sign) SIGN=0 ;;
    --identity) IDENTITY="$2"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 3 ;;
  esac
  shift
done
if [[ -z "$IDENTITY" ]]; then
  for candidate in "Caelestia Local Signing" "SkyRose Local Signing"; do
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$candidate\""; then IDENTITY="$candidate"; break; fi
  done
fi

# Always use the toolchain that ships with the selected Xcode; a swift.org toolchain on PATH
# (swiftly, etc.) does not match the SDK and fails to compile Foundation.
XCODE_TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin"
export PATH="$XCODE_TOOLCHAIN:$PATH"
SWIFT="$XCODE_TOOLCHAIN/swift"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "warning: SkyRose targets Apple Silicon; building on $(uname -m) anyway" >&2
fi

echo "==> swift build -c $CONFIG"
# One call per product: with several --product flags SwiftPM builds only the last one.
for PRODUCT in SkyRoseWM skyrose SkyRoseSettings TestWindows gen-keybind-docs; do
  "$SWIFT" build -c "$CONFIG" --product "$PRODUCT" 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' || true
done
BIN="$("$SWIFT" build -c "$CONFIG" --show-bin-path)"
for exe in SkyRoseWM skyrose SkyRoseSettings TestWindows; do
  test -x "$BIN/$exe" || { echo "build failed: $BIN/$exe missing" >&2; exit 1; }
done

VERSION="$(sed -n 's/.*public static let string = "\(.*\)".*/\1/p' Sources/CaelestiaCore/Version.swift | head -1)"
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

copy_resource_bundles() {
  for b in "$BIN"/SkyRose_*.bundle; do
    [[ -d "$b" ]] && cp -R "$b" "$1/Contents/Resources/"
  done
}

# --- SkyRose.app (agent app: WM + shell + IPC server + CLI) -------------------------------------
APP="$DIST/SkyRose.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN/SkyRoseWM" "$APP/Contents/MacOS/SkyRoseWM"
cp "$BIN/skyrose" "$APP/Contents/MacOS/skyrose"
# Deprecated alias for one release: `caelestia …` still works and prints a notice.
ln -s skyrose "$APP/Contents/MacOS/caelestia"
copy_resource_bundles "$APP"
[[ -d "$ROOT/Resources" ]] && cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"   # optional extra resources (untracked)
cp "$ROOT/Packaging/SkyRose.icns" "$ROOT/Packaging/SkyRoseWM.icns" "$APP/Contents/Resources/"   # scripts/make-icons.swift
sed "s/__VERSION__/$VERSION/g" "$ROOT/Packaging/SkyRose-Info.plist" > "$APP/Contents/Info.plist"
sed "s|__APP_PATH__|$HOME/Applications/SkyRose.app|g" "$ROOT/Packaging/com.skyrose.mac.plist" \
  > "$APP/Contents/Library/LaunchAgents/com.skyrose.mac.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# --- SkyRose Settings.app -----------------------------------------------------------------------
SET="$DIST/SkyRose Settings.app"
mkdir -p "$SET/Contents/MacOS" "$SET/Contents/Resources"
cp "$BIN/SkyRoseSettings" "$SET/Contents/MacOS/SkyRoseSettings"
copy_resource_bundles "$SET"
cp "$ROOT/Packaging/SkyRose.icns" "$ROOT/Packaging/SkyRoseWM.icns" "$SET/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Packaging/SkyRoseSettings-Info.plist" > "$SET/Contents/Info.plist"
printf 'APPL????' > "$SET/Contents/PkgInfo"

# --- TestWindows.app (Riko regression harness) --------------------------------------------------
TW="$DIST/TestWindows.app"
mkdir -p "$TW/Contents/MacOS" "$TW/Contents/Resources"
cp "$BIN/TestWindows" "$TW/Contents/MacOS/TestWindows"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Packaging/TestWindows-Info.plist" > "$TW/Contents/Info.plist"

# --- Signing ------------------------------------------------------------------------------------
sign_bundle() {
  local bundle="$1" entitlements="$2"
  if [[ $SIGN -eq 1 && -n "$IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --deep --options runtime --timestamp=none \
      --entitlements "$entitlements" --sign "$IDENTITY" "$bundle"
    echo "    signed $(basename "$bundle") with \"$IDENTITY\""
  else
    codesign --force --deep --sign - "$bundle"
    echo "    warning: ad-hoc signed $(basename "$bundle"); run scripts/sign-setup.sh so permissions survive rebuilds" >&2
  fi
}
echo "==> codesign"
sign_bundle "$APP" "$ROOT/Packaging/SkyRose.entitlements"
sign_bundle "$SET" "$ROOT/Packaging/SkyRoseSettings.entitlements"
sign_bundle "$TW" "$ROOT/Packaging/TestWindows.entitlements"
codesign --verify --deep --strict "$APP"
codesign --verify --deep --strict "$SET"

echo "==> done: $APP, $SET (v$VERSION, $CONFIG)"
