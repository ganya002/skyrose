#!/bin/sh
# Boot daemon for SIP-off mode. install-sa-daemon.sh fills in the two values below and installs a
# root-owned copy, which launchd runs as root. It loads the helper into the user's Dock after
# login and again whenever the Dock restarts, and exits at once when SIP-off mode is off.
#
# Every file it runs is root-owned. The user's config is only read, with the user's own rights,
# and only decides whether to run. `skyrose wm panic` creates the pause file; /tmp is emptied at
# boot, so a panic lasts for this session only.
#
#   skyrose-sa-daemon.sh --decide <on|off|unknown> <paused:0|1> <dock:0|1> <loaded:0|1>
#   skyrose-sa-daemon.sh --config-state <file>
# print a decision and change nothing (test-sa-daemon.sh uses them).
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

TARGET_UID=__UID__
TARGET_HOME='__HOME__'
DIR="/Library/Application Support/SkyRose"
LOADER="$DIR/skyrose-sa-loader"

decide() { # config paused dock loaded
  [ "$1" = off ] && { echo exit; return; }
  [ "$2" = 1 ] && { echo wait; return; }
  [ "$3" = 0 ] && { echo wait; return; }
  [ "$1" = unknown ] && { echo wait; return; }
  [ "$4" = 1 ] && { echo skip; return; }
  echo load
}

PARSE='/^[ \t]*\[/ { s = ($0 ~ /^[ \t]*\[sipOff\][ \t]*(#.*)?$/); next }
s && /^[ \t]*enabled[ \t]*=/ { v = $0; sub(/#.*/, "", v); sub(/^[^=]*=/, "", v); gsub(/[ \t]/, "", v); print v; exit }'

state_of() { # value printed by the parser, exit status of the read
  [ "$2" = 0 ] || { echo unknown; return; }
  [ "$1" = true ] && echo on || echo off
}

config_state() {
  file="$TARGET_HOME/.config/skyrose/config.toml"
  value=$(/usr/bin/sudo -n -u "#$TARGET_UID" /usr/bin/awk "$PARSE" "$file" 2>/dev/null)
  status=$?
  # No config file at all means the default, which is off.
  if [ "$status" != 0 ] && /usr/bin/sudo -n -u "#$TARGET_UID" /bin/test ! -e "$file" 2>/dev/null; then echo off; return; fi
  state_of "$value" "$status"
}

case "${1:-}" in
  --decide) decide "$2" "$3" "$4" "$5"; exit 0 ;;
  --config-state)
    value=$(awk "$PARSE" "$2" 2>/dev/null); status=$?
    state_of "$value" "$status"; exit 0 ;;
esac

case "$TARGET_UID" in ''|*[!0-9]*) echo "skyrose-sa-daemon: not installed by install-sa-daemon.sh" >&2; exit 2 ;; esac
[ "$(id -u)" = 0 ] || { echo "skyrose-sa-daemon: must run as root under launchd" >&2; exit 2; }

PAUSE="/tmp/skyrose-sa-paused-$TARGET_UID"
SOCKET="/tmp/skyrose-sa-$TARGET_UID.socket"

[ "$(config_state)" = off ] && exit 0

last=""
tries=0
while :; do
  dock=$(pgrep -U "$TARGET_UID" -x Dock | head -n 1)
  if [ -n "$dock" ] && [ "$dock" != "$last" ] && [ ! -e "$PAUSE" ]; then
    /usr/bin/nc -z -U "$SOCKET" 2>/dev/null && loaded=1 || loaded=0
    case "$(decide "$(config_state)" 0 1 "$loaded")" in
      exit) exit 0 ;;
      skip) last=$dock ;;
      load)
        sleep 2
        if SUDO_UID=$TARGET_UID "$LOADER"; then
          last=$dock; tries=0
        else
          tries=$((tries + 1))
          if [ "$tries" -ge 3 ]; then
            echo "skyrose-sa-daemon: gave up on Dock pid $dock after 3 tries" >&2
            last=$dock; tries=0
          fi
        fi ;;
    esac
  fi
  sleep 5
done
