#!/bin/sh
# Installs the SIP-off boot daemon. Run it yourself, once, and again after updating SkyRose:
#
#   sudo /path/to/SkyRose.app/Contents/Resources/sa/install-sa-daemon.sh [--dry-run]
#
# It copies the loader, helper and daemon script to a root-owned folder and points launchd at
# that copy, so root never runs a file your account can change. --dry-run needs no sudo and
# prints every step without changing anything.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  *) echo "usage: install-sa-daemon.sh [--dry-run]" >&2; exit 3 ;;
esac

LABEL=com.skyrose.sa-loader
PARENT="/Library/Application Support"
DIR="$PARENT/SkyRose"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SRC=$(cd -P "$(dirname "$0")" && pwd)

fail() { echo "install-sa-daemon: $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then echo "would run: $*"; else "$@"; fi; }

if [ "$DRY" = 0 ] && [ "$(id -u)" != 0 ]; then fail "run it with sudo (or use --dry-run)"; fi
if [ "$DRY" = 1 ]; then TARGET_UID=${SUDO_UID:-$(id -u)}; else TARGET_UID=${SUDO_UID:-}; fi
case "$TARGET_UID" in ''|*[!0-9]*) fail "run it with sudo from your own account" ;; esac
[ "$TARGET_UID" != 0 ] || fail "run it with sudo from your own account, not as root"
NAME=$(id -un "$TARGET_UID") || fail "no user with uid $TARGET_UID"
TARGET_HOME=$(dscl . -read "/Users/$NAME" NFSHomeDirectory | sed 's/^NFSHomeDirectory: //')
case "$TARGET_HOME" in /*) ;; *) fail "no home folder for $NAME" ;; esac
case "$TARGET_HOME" in *\'*|*\&*|*\|*|*\\*) fail "unsupported characters in home folder: $TARGET_HOME" ;; esac

for f in skyrose-sa-loader SkyRoseSA.dylib skyrose-sa-daemon.sh uninstall-sa-daemon.sh "$LABEL.plist"; do
  [ -f "$SRC/$f" ] && [ ! -L "$SRC/$f" ] || fail "$SRC/$f is missing"
done

# Anyone who can write to these folders could swap what root runs.
for d in "$PARENT" /Library/LaunchDaemons; do
  [ "$(stat -f %u "$d")" = 0 ] || fail "$d is not owned by root"
  case "$(stat -f %Lp "$d")" in *[2367]?|*[2367]) fail "$d is writable by a group or other users" ;; esac
done
[ ! -L "$DIR" ] || fail "$DIR is a symbolic link"
if [ -e "$DIR" ] && [ "$(stat -f %u "$DIR")" != 0 ]; then fail "$DIR exists and is not owned by root"; fi

place() { # source, name, mode: written beside the target, then renamed over it
  run install -o root -g wheel -m "$3" "$1" "$DIR/.$2.new"
  run mv -f "$DIR/.$2.new" "$DIR/$2"
}

run install -d -o root -g wheel -m 755 "$DIR"
place "$SRC/skyrose-sa-loader" skyrose-sa-loader 755
place "$SRC/SkyRoseSA.dylib" SkyRoseSA.dylib 755
place "$SRC/uninstall-sa-daemon.sh" uninstall-sa-daemon.sh 755
if [ "$DRY" = 1 ]; then
  echo "would write: $DIR/skyrose-sa-daemon.sh for uid $TARGET_UID, home $TARGET_HOME"
else
  sed -e "s|__UID__|$TARGET_UID|" -e "s|__HOME__|$TARGET_HOME|" "$SRC/skyrose-sa-daemon.sh" > "$DIR/.daemon.new"
  chown root:wheel "$DIR/.daemon.new"
  chmod 755 "$DIR/.daemon.new"
  mv -f "$DIR/.daemon.new" "$DIR/skyrose-sa-daemon.sh"
fi
run install -o root -g wheel -m 644 "$SRC/$LABEL.plist" "$PLIST"

if [ "$DRY" = 1 ]; then
  echo "would run: launchctl bootout system/$LABEL (if loaded)"
else
  launchctl bootout "system/$LABEL" 2>/dev/null || true
fi
run launchctl bootstrap system "$PLIST"
echo "SkyRose boot daemon installed. It loads the helper while SIP-off mode is on in Settings."
