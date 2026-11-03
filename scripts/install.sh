#!/bin/bash
# Installs Caelestia for Mac for the current user. No sudo, no piped installers, no system files.
#
#   scripts/install.sh [--no-build] [--no-cli] [--no-open]
#
# What it does, in order (each step is idempotent, running it twice is safe):
#   1. checks Apple Silicon + macOS 14 or newer + Xcode command line tools;
#   2. builds dist/CaelestiaWM.app with scripts/build.sh (unless --no-build);
#   3. quits a running CaelestiaWM, copies the app to ~/Applications (previous copy moved to the Trash);
#   4. offers to symlink the `caelestia` CLI into ~/.local/bin (asks first);
#   5. opens the app, which shows the first-run wizard (permissions, "make it look like Arch",
#      kitty, fonts, cursor). The wizard registers the login item only when you say yes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD=1 CLI=1 OPEN=1
for a in "$@"; do case "$a" in --no-build) BUILD=0;; --no-cli) CLI=0;; --no-open) OPEN=0;; -h|--help) sed -n '2,13p' "$0"; exit 0;; esac; done

if [[ "$(uname -m)" != "arm64" ]]; then echo "error: Caelestia for Mac needs an Apple Silicon Mac." >&2; exit 1; fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if (( MAJOR < 14 )); then echo "error: macOS 14 Sonoma or newer is required (found $(sw_vers -productVersion))." >&2; exit 1; fi
xcode-select -p >/dev/null 2>&1 || { echo "error: Xcode (or the Command Line Tools) is required: xcode-select --install" >&2; exit 1; }

if [[ $BUILD -eq 1 ]]; then "$ROOT/scripts/build.sh"; fi
SRC="$ROOT/dist/CaelestiaWM.app"
[[ -d "$SRC" ]] || { echo "error: $SRC not found (run without --no-build)" >&2; exit 1; }

DEST="$HOME/Applications/CaelestiaWM.app"
mkdir -p "$HOME/Applications"
if pgrep -x CaelestiaWM >/dev/null; then
  echo "==> quitting the running CaelestiaWM (it restores parked windows first)"
  "$DEST/Contents/MacOS/caelestia" shell kill 2>/dev/null || osascript -e 'tell application id "com.caelestia.mac.wm" to quit' 2>/dev/null || true
  for _ in $(seq 1 50); do pgrep -x CaelestiaWM >/dev/null || break; sleep 0.1; done
fi
if [[ -d "$DEST" ]]; then
  echo "==> moving the previous copy to the Trash"
  osascript -e "tell application \"Finder\" to delete POSIX file \"$DEST\"" >/dev/null
fi
echo "==> installing to $DEST"
cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

if [[ $CLI -eq 1 ]]; then
  LINK="$HOME/.local/bin/caelestia"
  echo
  read -r -p "Symlink the caelestia CLI to $LINK? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$DEST/Contents/MacOS/caelestia" "$LINK"
    echo "    linked. Make sure ~/.local/bin is on your PATH."
  fi
fi

echo
echo "Installed. Standard mode changes nothing at system level without asking; on a school laptop"
echo "check the IT rules before enabling Enhanced mode (docs/ENHANCED_MODE.md)."
if [[ $OPEN -eq 1 ]]; then
  echo "==> opening CaelestiaWM (first-run wizard)"
  open "$DEST"
fi
