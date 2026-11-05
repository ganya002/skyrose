#!/bin/bash
# Installs SkyRose for the current user. No sudo, no piped installers, no system files.
#
#   scripts/install.sh [--no-build] [--no-cli] [--no-open]
#
# What it does, in order (each step is idempotent, running it twice is safe):
#   1. checks Apple Silicon + macOS 14 or newer + Xcode command line tools;
#   2. builds dist/SkyRose.app and dist/SkyRose Settings.app with scripts/build.sh (unless --no-build);
#   3. quits a running SkyRose (or a pre-rename CaelestiaWM), copies both apps to ~/Applications
#      (previous copies, including a pre-rename CaelestiaWM.app, go to the Trash);
#   4. offers to symlink the `skyrose` CLI into ~/.local/bin (asks first); an existing `caelestia`
#      link there is pointed at the new app (deprecated alias, kept for one release);
#   5. opens SkyRose. On first run it moves your old ~/.config/caelestia-mac and
#      ~/Library/Application Support/CaelestiaMac over and opens the onboarding.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD=1 CLI=1 OPEN=1
for a in "$@"; do case "$a" in --no-build) BUILD=0;; --no-cli) CLI=0;; --no-open) OPEN=0;; -h|--help) sed -n '2,15p' "$0"; exit 0;; esac; done

if [[ "$(uname -m)" != "arm64" ]]; then echo "error: SkyRose needs an Apple Silicon Mac." >&2; exit 1; fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if (( MAJOR < 14 )); then echo "error: macOS 14 Sonoma or newer is required (found $(sw_vers -productVersion))." >&2; exit 1; fi
xcode-select -p >/dev/null 2>&1 || { echo "error: Xcode (or the Command Line Tools) is required: xcode-select --install" >&2; exit 1; }

if [[ $BUILD -eq 1 ]]; then "$ROOT/scripts/build.sh"; fi
for src in "$ROOT/dist/SkyRose.app" "$ROOT/dist/SkyRose Settings.app"; do
  [[ -d "$src" ]] || { echo "error: $src not found (run without --no-build)" >&2; exit 1; }
done

mkdir -p "$HOME/Applications"
DEST="$HOME/Applications/SkyRose.app"
SETTINGS="$HOME/Applications/SkyRose Settings.app"

quit_wm() {  # $1 process name, $2 CLI path, $3 bundle id
  if pgrep -x "$1" >/dev/null; then
    echo "==> quitting the running $1 (it restores parked windows first)"
    "$2" wm quit 2>/dev/null || osascript -e "tell application id \"$3\" to quit" 2>/dev/null || true
    for _ in $(seq 1 50); do pgrep -x "$1" >/dev/null || break; sleep 0.1; done
  fi
}
quit_wm SkyRoseWM "$DEST/Contents/MacOS/skyrose" com.skyrose.mac
quit_wm CaelestiaWM "$HOME/Applications/CaelestiaWM.app/Contents/MacOS/caelestia" com.caelestia.mac.wm

trash() { osascript -e "tell application \"Finder\" to delete POSIX file \"$1\"" >/dev/null; }
for old in "$DEST" "$SETTINGS" "$HOME/Applications/CaelestiaWM.app"; do
  if [[ -d "$old" ]]; then echo "==> moving $(basename "$old") to the Trash"; trash "$old"; fi
done
echo "==> installing to ~/Applications"
cp -R "$ROOT/dist/SkyRose.app" "$DEST"
cp -R "$ROOT/dist/SkyRose Settings.app" "$SETTINGS"
xattr -dr com.apple.quarantine "$DEST" "$SETTINGS" 2>/dev/null || true

if [[ $CLI -eq 1 ]]; then
  LINK="$HOME/.local/bin/skyrose"
  echo
  read -r -p "Symlink the skyrose CLI to $LINK? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$DEST/Contents/MacOS/skyrose" "$LINK"
    echo "    linked. Make sure ~/.local/bin is on your PATH."
  fi
  OLD="$HOME/.local/bin/caelestia"
  if [[ -L "$OLD" ]]; then
    ln -sfn "$DEST/Contents/MacOS/caelestia" "$OLD"
    echo "    ~/.local/bin/caelestia now points at SkyRose (deprecated: use skyrose)."
  fi
fi

echo
echo "Installed. SkyRose changes nothing at system level without asking, and every change it makes"
echo "is recorded so the uninstaller can put it back."
if [[ $OPEN -eq 1 ]]; then
  echo "==> opening SkyRose"
  open "$DEST"
fi
