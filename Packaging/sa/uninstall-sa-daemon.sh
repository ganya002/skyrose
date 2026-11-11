#!/bin/sh
# Removes the SIP-off boot daemon and its root-owned files. Run it yourself:
#
#   sudo "/Library/Application Support/SkyRose/uninstall-sa-daemon.sh" [--dry-run]
#
# The helper already in the Dock stays until the Dock restarts or you reboot.
# --dry-run needs no sudo and prints every step without changing anything.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  *) echo "usage: uninstall-sa-daemon.sh [--dry-run]" >&2; exit 3 ;;
esac
if [ "$DRY" = 0 ] && [ "$(id -u)" != 0 ]; then echo "uninstall-sa-daemon: run it with sudo (or use --dry-run)" >&2; exit 1; fi

LABEL=com.skyrose.sa-loader
DIR="/Library/Application Support/SkyRose"
run() { if [ "$DRY" = 1 ]; then echo "would run: $*"; else "$@"; fi; }

if [ "$DRY" = 1 ]; then
  echo "would run: launchctl bootout system/$LABEL (if loaded)"
else
  launchctl bootout "system/$LABEL" 2>/dev/null || true
fi
run rm -f "/Library/LaunchDaemons/$LABEL.plist" /var/log/skyrose-sa-loader.log
for f in skyrose-sa-daemon.sh skyrose-sa-loader SkyRoseSA.dylib uninstall-sa-daemon.sh; do run rm -f "$DIR/$f"; done
if [ "$DRY" = 1 ]; then echo "would run: rmdir $DIR (if empty)"; else rmdir "$DIR" 2>/dev/null || true; fi
echo "SkyRose boot daemon removed."
