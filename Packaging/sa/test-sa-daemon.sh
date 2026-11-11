#!/bin/sh
# Checks the boot daemon's decisions and the dry runs of its scripts. Needs no sudo, changes nothing.
set -u
cd "$(dirname "$0")"
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', expected '$3'"; fails=$((fails + 1)); fi; }
d() { sh skyrose-sa-daemon.sh --decide "$@"; }
check "off exits" "$(d off 0 1 0)" exit
check "off exits even when paused" "$(d off 1 1 0)" exit
check "paused waits" "$(d on 1 1 0)" wait
check "no Dock waits" "$(d on 0 0 0)" wait
check "unreadable config waits" "$(d unknown 0 1 0)" wait
check "already loaded skips" "$(d on 0 1 1)" skip
check "on loads" "$(d on 0 1 0)" load

t=$(mktemp -d)
c() { printf "$1" > "$t/c.toml"; sh skyrose-sa-daemon.sh --config-state "$t/c.toml"; }
check "enabled" "$(c '[wm]\nenabled = false\n[sipOff]\nenabled = true\n')" on
check "disabled" "$(c '[sipOff]\nenabled = false\n')" off
check "other table does not count" "$(c '[wm]\nenabled = true\n[sipOff]\nanimations = true\n')" off
check "comment after the value" "$(c '[sipOff]\nenabled = true # yes\n')" on
check "commented out" "$(c '[sipOff]\n# enabled = true\n')" off
check "missing file is unknown here" "$(sh skyrose-sa-daemon.sh --config-state "$t/none.toml")" unknown

# The installer needs the built files next to it, and must never reach for dist/ or ~/Projects.
for f in skyrose-sa-loader SkyRoseSA.dylib; do : > "$t/$f"; done
cp skyrose-sa-daemon.sh install-sa-daemon.sh uninstall-sa-daemon.sh com.skyrose.sa-loader.plist "$t/"
out=$(sh "$t/install-sa-daemon.sh" --dry-run 2>&1); status=$?
check "install dry run succeeds" "$status" 0
check "install changes nothing outside the plan" "$(echo "$out" | grep -c '^would')" "$(echo "$out" | grep -vc '^SkyRose boot daemon')"
check "plist points at the root-owned copy" "$(grep -c '/Library/Application Support/SkyRose/skyrose-sa-daemon.sh' com.skyrose.sa-loader.plist)" 1
check "plist never points at a build" "$(grep -cE 'dist/|Projects|/Users/' com.skyrose.sa-loader.plist)" 0
check "loader installed root:wheel" "$(echo "$out" | grep -c 'install -o root -g wheel -m 755 .*skyrose-sa-loader')" 1
check "plist installed 644" "$(echo "$out" | grep -c 'install -o root -g wheel -m 644 .*LaunchDaemons')" 1
out=$(sh uninstall-sa-daemon.sh --dry-run 2>&1); status=$?
check "uninstall dry run succeeds" "$status" 0
check "uninstall removes the plist" "$(echo "$out" | grep -c 'rm -f /Library/LaunchDaemons/com.skyrose.sa-loader.plist')" 1
sh install-sa-daemon.sh >/dev/null 2>&1; check "install without sudo refuses" "$?" 1
sh uninstall-sa-daemon.sh >/dev/null 2>&1; check "uninstall without sudo refuses" "$?" 1
rm -rf "$t"
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
