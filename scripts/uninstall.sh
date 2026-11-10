#!/bin/sh
# SkyRose uninstaller. Puts the Mac back the way it was before SkyRose, as your normal user. The
# one password prompt: if you installed the SIP-off boot daemon, it asks before removing it.
#
#   uninstall.sh [--dry-run] [--yes] [--remove-fonts] [--remove-config] [--remove-cert]
#                [--no-color] [--progress] [-h]
#
#   --dry-run        print every action, change nothing
#   --yes            no questions: keep the fonts, keep ~/.config/skyrose and keep the signing
#                    certificate (the safe defaults) unless a --remove-* flag says otherwise
#   --remove-fonts   also remove the fonts SkyRose copied into ~/Library/Fonts
#   --remove-config  also move ~/.config/skyrose to the Trash
#   --remove-cert    also delete the local code-signing certificate from the login keychain
#   --no-color       plain output (also when NO_COLOR is set or stdout is not a terminal)
#   --progress       machine-readable progress lines for the SkyRose uninstall window
#                    ("::stage", "::done", "::skip", "::left", "::fail", "::sip", "::finished");
#                    no questions. After "::sip" the script reads one line from stdin and does not
#                    move the apps or SkyRose's data until that line is "ack" (the window sends it
#                    when the SIP reminder is dismissed). A closed stdin is not an acknowledgement.
#
# In order (each step checks first, so running it twice is safe):
#    1. stop the WM (it brings every parked window back). If it is still running afterwards, stop:
#       nothing else is changed. Not running: replay the parked-windows journal through System Events
#    2. macOS cursors back (quitting the WM does it; else `skyrose cursor reset`)
#    3. every recorded setting back to its original value (deleted if it did not exist): defaults
#       of every type (bool, number, string, date, data, array, dictionary), symbolic hotkeys,
#       hidutil, wallpapers per display, and files SkyRose replaced. A failed restore keeps
#       Application Support (the manifest stays) and the script exits non-zero
#    4. lid-closed sleep back on (`pmset disablesleep 0`) only if SkyRose turned it off
#    5. login item / launch agent com.skyrose.mac removed; SIP-off boot daemon removed (asks, and
#       needs your password; without a terminal it prints the command to run instead)
#    6. kitty profile removed (`skyrose kitty uninstall`), fonts (asked), ~/.config/skyrose (asked)
#    7. SIP reminder if SkyRose's SIP-off mode was used and SIP is not fully back on. The script
#       waits until it is acknowledged, and does not trash the apps or SkyRose's data before that
#    8. apps and the `skyrose` / `caelestia` symlinks to the Trash (never rm -rf), certificate (asked)
#    9. ~/Library/Logs/SkyRose to the Trash. Application Support goes too, unless a restore failed:
#       then it is kept so the manifest can be tried again. The script exits non-zero in that case
#
# Permissions granted in System Settings stay listed there until you remove them; they do
# nothing once the app is gone.

set -u

# ---------------------------------------------------------------------------------------------
# Options

DRY=0 YES=0 PROGRESS=0 COLOR=1 RM_FONTS=ask RM_CONFIG=ask RM_CERT=ask
usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --yes|-y) YES=1 ;;
    --remove-fonts) RM_FONTS=yes ;;
    --remove-config) RM_CONFIG=yes ;;
    --remove-cert) RM_CERT=yes ;;
    --no-color) COLOR=0 ;;
    --progress) PROGRESS=1; YES=1; COLOR=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "uninstall.sh: unknown option: $arg" >&2; usage >&2; exit 3 ;;
  esac
done
[ -t 1 ] || COLOR=0
[ -n "${NO_COLOR:-}" ] && COLOR=0

# ---------------------------------------------------------------------------------------------
# Locations (all under $HOME; nothing outside the user's account is touched)

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then echo "uninstall.sh: HOME is not set" >&2; exit 1; fi
APPS="$HOME/Applications"
SUPPORT="$HOME/Library/Application Support/SkyRose"
MANIFEST="$SUPPORT/restore-manifest.json"
PARKED="$SUPPORT/parked-windows.json"
RECORD="$SUPPORT/install-record.txt"      # what the release installer put in place
CONFIG="$HOME/.config/skyrose"
LOGS="$HOME/Library/Logs/SkyRose"
WM_APP="$APPS/SkyRose.app"
SETTINGS_APP="$APPS/SkyRose Settings.app"
HERE=$(cd "$(dirname "$0")" && pwd)

# Fixture runs (tests) set SKYROSE_UNINSTALL_SANDBOX=1 with a temporary HOME and stub commands
# first on PATH. Refuse if that would reach the real account.
if [ "${SKYROSE_UNINSTALL_SANDBOX:-0}" = 1 ]; then
  real_home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory: //')
  if [ -z "$real_home" ] || [ "$HOME" = "$real_home" ] || [ "$(command -v defaults)" = /usr/bin/defaults ]; then
    echo "uninstall.sh: sandbox run refused: HOME or the stub commands point at the real account" >&2
    exit 4
  fi
fi

# The skyrose CLI: the one next to this script inside the app, the installed app's, or the
# tests' stub. Without it the script still restores settings itself.
CLI=""
for c in "${SKYROSE_CLI:-}" "$HERE/../../MacOS/skyrose" "$WM_APP/Contents/MacOS/skyrose" \
         "$HERE/../dist/SkyRose.app/Contents/MacOS/skyrose" "$(command -v skyrose 2>/dev/null)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then CLI=$c; break; fi
done
[ "${SKYROSE_UNINSTALL_SANDBOX:-0}" = 1 ] && CLI="${SKYROSE_CLI:-}"
# SkyRose Settings shows the SIP reminder: the installed one, else the one next to the CLI's app.
REMINDER_APP="$SETTINGS_APP"
if [ ! -d "$REMINDER_APP" ] && [ -n "$CLI" ]; then REMINDER_APP="$(cd "$(dirname "$CLI")/../../.." 2>/dev/null && pwd)/SkyRose Settings.app"; fi

# ---------------------------------------------------------------------------------------------
# Output: human lines, or "::" lines for the GUI. Every result also goes to the final report.

REPORT=$(mktemp "${TMPDIR:-/tmp}/skyrose-uninstall.XXXXXX") || exit 1
HELPER=$(mktemp "${TMPDIR:-/tmp}/skyrose-uninstall-helper.XXXXXX") || exit 1
trap 'rm -f "$REPORT" "$HELPER"' EXIT
# Turns a manifest value into `defaults` arguments, merges one symbolic hotkey back into a
# plist, and turns a display number into the same UUID WallpaperService records. No eval.
cat > "$HELPER" <<'PY'
import base64, datetime, json, plistlib, sys

def die(msg):
    sys.stderr.write("uninstall helper: " + msg + "\n")
    raise SystemExit(2)

def unwrap(v):
    if not isinstance(v, dict) or "type" not in v:
        die("backup value is not a typed object")
    kind = v["type"]
    if kind == "absent":
        return ("absent", None)
    if kind not in ("string", "int", "double", "bool", "date", "data", "array", "dict"):
        die("unknown backup type " + str(kind))
    if "value" not in v:
        die("backup value has no value")
    raw = v["value"]
    if kind == "string":
        return ("string", "" if raw is None else str(raw))
    if kind == "int":
        return ("int", int(raw))
    if kind == "double":
        return ("double", float(raw))
    if kind == "bool":
        return ("bool", bool(raw))
    if kind == "date":
        return ("date", date_text(str(raw).strip()))
    if kind == "data":
        return ("data", base64.b64decode(raw))
    if kind == "array":
        return ("array", [unwrap(item) for item in raw])
    return ("dict", {str(k): unwrap(item) for k, item in raw.items()})

def date_text(text):
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    if "." in text:
        head, tail = text.split(".", 1)
        zone = ""
        for i, ch in enumerate(tail):
            if ch in "+-" and i > 0:
                zone = tail[i:]
                break
        text = head + (zone or "+00:00")
    when = datetime.datetime.fromisoformat(text)
    if when.tzinfo is None:
        when = when.replace(tzinfo=datetime.timezone.utc)
    return when.astimezone(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S +0000")

def flags(node, out):
    kind, val = node
    if kind == "string":
        out += ["-string", val]
    elif kind == "int":
        out += ["-int", str(val)]
    elif kind == "double":
        out += ["-float", format(val, ".15g")]
    elif kind == "bool":
        out += ["-bool", "true" if val else "false"]
    elif kind == "date":
        out += ["-date", val]
    elif kind == "data":
        out += ["-data", val.hex()]
    elif kind == "array":
        out.append("-array")
        for item in val:
            flags(item, out)
    elif kind == "dict":
        out.append("-dict")
        for key in sorted(val):
            out.append(key)
            flags(val[key], out)
    else:
        die("cannot write a " + kind + " with defaults")

def to_plist(node):
    kind, val = node
    if kind == "absent":
        return None
    if kind == "date":
        return datetime.datetime.strptime(val, "%Y-%m-%d %H:%M:%S %z")
    if kind == "array":
        return [to_plist(item) for item in val]
    if kind == "dict":
        return {key: to_plist(item) for key, item in val.items() if item[0] != "absent"}
    return val

def cmd_defaults_args(src, dest):
    with open(src, encoding="utf-8") as handle:
        node = unwrap(json.load(handle))
    out = []
    flags(node, out)
    with open(dest, "wb") as handle:
        handle.write(b"\0".join(part.encode("utf-8") for part in out) + b"\0")

def cmd_hotkey(exported, key, old_json, dest):
    with open(old_json, encoding="utf-8") as handle:
        node = unwrap(json.load(handle))
    root = {}
    try:
        with open(exported, "rb") as handle:
            loaded = plistlib.load(handle)
        if isinstance(loaded, dict):
            root = loaded
    except Exception:
        root = {}
    hotkeys = root.get("AppleSymbolicHotKeys")
    if not isinstance(hotkeys, dict):
        hotkeys = {}
    hotkeys.pop(str(key), None)
    hotkeys.pop(key, None)
    if node[0] != "absent":
        hotkeys[str(key)] = to_plist(node)
    root["AppleSymbolicHotKeys"] = hotkeys
    with open(dest, "wb") as handle:
        plistlib.dump(root, handle)

def cmd_uuid(number):
    import ctypes
    cs = ctypes.CDLL("/System/Library/Frameworks/ColorSync.framework/ColorSync")
    cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    cs.CGDisplayCreateUUIDFromDisplayID.argtypes = [ctypes.c_uint32]
    cs.CGDisplayCreateUUIDFromDisplayID.restype = ctypes.c_void_p
    cf.CFUUIDCreateString.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    cf.CFUUIDCreateString.restype = ctypes.c_void_p
    cf.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
    cf.CFStringGetCString.restype = ctypes.c_bool
    uuid = cs.CGDisplayCreateUUIDFromDisplayID(int(number))
    if not uuid:
        raise SystemExit(1)
    text = cf.CFUUIDCreateString(None, uuid)
    buf = ctypes.create_string_buffer(80)
    if not text or not cf.CFStringGetCString(text, buf, 80, 0x08000100):
        raise SystemExit(1)
    sys.stdout.write(buf.value.decode())

ops = {
    "defaults-args": lambda: cmd_defaults_args(sys.argv[2], sys.argv[3]),
    "hotkey": lambda: cmd_hotkey(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]),
    "display-uuid": lambda: cmd_uuid(sys.argv[2]),
}
if len(sys.argv) < 2 or sys.argv[1] not in ops:
    die("unknown request")
ops[sys.argv[1]]()
PY
if [ "$COLOR" = 1 ]; then B=$(printf '\033[1m'); G=$(printf '\033[32m'); Y=$(printf '\033[33m'); R=$(printf '\033[31m'); D=$(printf '\033[2m'); N=$(printf '\033[0m')
else B="" G="" Y="" R="" D="" N=""; fi

STAGES=9 STAGE=0
stage() {  # stage <id> <label>
  STAGE=$((STAGE + 1))
  if [ "$PROGRESS" = 1 ]; then echo "::stage $STAGE $STAGES $1 $2"; else echo; echo "${B}[$STAGE/$STAGES] $2${N}"; fi
}
done_() {
  echo "done	$*" >> "$REPORT"
  if [ "$PROGRESS" = 1 ]; then echo "::done $*"; elif [ "$DRY" = 1 ]; then echo "  ${G}✓${N} ${D}(would)${N} $*"; else echo "  ${G}✓${N} $*"; fi
}
skip()  { echo "skip	$*" >> "$REPORT"; if [ "$PROGRESS" = 1 ]; then echo "::skip $*"; else echo "  ${D}- $*${N}"; fi; }
left()  { echo "left	$*" >> "$REPORT"; if [ "$PROGRESS" = 1 ]; then echo "::left $*"; else echo "  ${Y}! $*${N}"; fi; }
fail()  { echo "fail	$*" >> "$REPORT"; if [ "$PROGRESS" = 1 ]; then echo "::fail $*"; else echo "  ${R}✗ $*${N}"; fi; }

# Prints the report and exits. A non-zero status means a restore failed, the WM would not quit,
# or the SIP reminder was not acknowledged. ::finished is only sent when everything succeeded,
# so the window does not call a stopped run "done".
finish() {
  code=$1
  if [ "$PROGRESS" = 1 ]; then
    [ "$code" = 0 ] && echo "::finished"
    exit "$code"
  fi
  echo
  echo "${B}Report${N}"
  printf '  %s done, %s skipped, %s left for you, %s failed\n' "$(grep -c '^done' "$REPORT")" "$(grep -c '^skip' "$REPORT")" "$(grep -c '^left' "$REPORT")" "$(grep -c '^fail' "$REPORT")"
  if grep -q '^fail' "$REPORT"; then echo "  Failed:"; grep '^fail' "$REPORT" | cut -f2- | sed 's/^/    - /'; fi
  if grep -q '^left' "$REPORT"; then echo "  Left for you:"; grep '^left' "$REPORT" | cut -f2- | sed 's/^/    - /'; fi
  echo "  macOS keeps the Accessibility, Input Monitoring and Screen Recording entries in System Settings >"
  echo "  Privacy & Security until you remove them. They do nothing without the app."
  [ "$DRY" = 1 ] && echo "${Y}Dry run: nothing was changed.${N}"
  exit "$code"
}

# Runs a command, or only prints it with --dry-run (on fd 3, so a caller's >/dev/null does not
# hide it). Arguments are passed as they are (no eval).
exec 3>&1
run() {
  if [ "$DRY" = 1 ]; then
    if [ "$PROGRESS" = 1 ]; then echo "::dry $*" >&3; else echo "  ${D}would run:${N} $*" >&3; fi
    return 0
  fi
  "$@"
}

# ask <question> <default y|n>: yes/no from the terminal (also when stdin is a pipe); the
# default without a terminal, with --yes and with --progress.
ask() {
  if [ "$YES" = 1 ]; then [ "$2" = y ]; return; fi
  if [ -t 0 ]; then tty=/dev/stdin; elif [ -r /dev/tty ]; then tty=/dev/tty; else [ "$2" = y ]; return; fi
  if [ "$2" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf '  %s %s ' "$1" "$hint"
  read -r answer < "$tty" || answer=""
  case "$answer" in [Yy]*) return 0 ;; [Nn]*) return 1 ;; *) [ "$2" = y ] ;; esac
}

# Moves a file or folder to the Trash: /usr/bin/trash (macOS 15+), else Finder, else ~/.Trash.
to_trash() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if [ "$DRY" = 1 ]; then run trash "$1"; return 0; fi
  if command -v trash >/dev/null 2>&1; then trash "$1" && return 0; fi
  if osascript -e 'on run argv' -e 'tell application "Finder" to delete POSIX file (item 1 of argv)' -e 'end run' "$1" </dev/null >/dev/null 2>&1; then return 0; fi
  mkdir -p "$HOME/.Trash" && mv "$1" "$HOME/.Trash/$(basename "$1").$(date +%s)"
}

# Manifest fields (plutil reads the JSON as is): field <index> <path>, e.g. field 3 oldValue.type
field() { plutil -extract "entries.$1.$2" raw -o - "$MANIFEST" 2>/dev/null; }
entry_count() { [ -r "$MANIFEST" ] && plutil -extract entries raw -o - "$MANIFEST" 2>/dev/null || echo 0; }

# The first entry of each (kind, domain, key) holds the original value. Prints their indexes,
# newest change first, so restoring in order undoes SkyRose's changes in reverse.
originals() {
  n=$(entry_count) i=0 seen="" out=""
  while [ "$i" -lt "$n" ]; do
    id="<$(field "$i" kind)|$(field "$i" domain)|$(field "$i" key)>"
    case "$seen" in *"$id"*) ;; *) seen="$seen$id" out="$i $out" ;; esac
    i=$((i + 1))
  done
  echo "$out"
}

wm_running() { pgrep -x SkyRoseWM >/dev/null 2>&1; }

# ---------------------------------------------------------------------------------------------
# Plan

if [ "$PROGRESS" = 0 ]; then
  echo "${B}SkyRose uninstaller${N}${D} (as $(id -un), no sudo)${N}"
  [ "$DRY" = 1 ] && echo "${Y}Dry run: nothing is changed.${N}"
  if [ -r "$MANIFEST" ]; then echo "Restore manifest: $MANIFEST ($(entry_count) entries)"; else echo "No restore manifest: no settings to put back."; fi
fi
if [ "$PROGRESS" = 0 ] && [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then
  ask "Uninstall SkyRose now?" n || { echo "Cancelled."; exit 0; }
fi
# Answers first, so nothing stops halfway for a question.
if [ "$RM_FONTS" = ask ]; then if [ -r "$SUPPORT/Fonts/installed.json" ] && ask "Remove the fonts SkyRose installed into ~/Library/Fonts?" n; then RM_FONTS=yes; else RM_FONTS=no; fi; fi
if [ "$RM_CONFIG" = ask ]; then if [ -d "$CONFIG" ] && ask "Move your SkyRose config (~/.config/skyrose) to the Trash?" n; then RM_CONFIG=yes; else RM_CONFIG=no; fi; fi
CERT=""
for name in "SkyRose Local Signing" "Caelestia Local Signing"; do
  security find-certificate -c "$name" >/dev/null 2>&1 && CERT=$name && break
done
if [ "$RM_CERT" = ask ]; then if [ -n "$CERT" ] && ask "Delete the \"$CERT\" code-signing certificate from your login keychain?" n; then RM_CERT=yes; else RM_CERT=no; fi; fi

# The SIP reminder is decided now, before anything recording it is moved away.
SIP_REMINDER=0
if [ -e "$SUPPORT/sipOff-mode-used" ] || { [ -r "$MANIFEST" ] && grep -q '"skyrose.mode"' "$MANIFEST" && grep -q '"sipOff"' "$MANIFEST"; }; then
  sip=$(csrutil status 2>/dev/null | tr '[:upper:]' '[:lower:]')
  case "$sip" in *"custom configuration"*|*"status: disabled"*|"") SIP_REMINDER=1 ;; *"status: enabled"*) ;; *) SIP_REMINDER=1 ;; esac
fi

# ---------------------------------------------------------------------------------------------
# 1. Windows

stage windows "Stopping the window manager"
if wm_running; then
  if [ -n "$CLI" ] && run "$CLI" wm quit >/dev/null 2>&1; then
    :
  else
    run osascript -e 'tell application id "com.skyrose.mac" to quit' </dev/null >/dev/null 2>&1
  fi
  if [ "$DRY" = 1 ]; then
    done_ "SkyRose WM quit (every window brought back first)"
  else
    # Sandbox tests do not need the real 5 s wait; a live quit still gets 20 × 0.25 s.
    pause=0.25
    [ "${SKYROSE_UNINSTALL_SANDBOX:-0}" = 1 ] && pause=0
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do wm_running || break; sleep "$pause"; done
    if wm_running; then
      fail "SkyRose WM is still running. Quit it from its menu, then run this again. Nothing else was changed."
      finish 1
    fi
    done_ "SkyRose WM quit (every window brought back first)"
  fi
else
  skip "SkyRose WM was not running"
fi
# Windows a crashed WM left parked off-screen: put each one back through System Events.
parked=0
if [ -r "$PARKED" ]; then parked=$(plutil -extract windows raw -o - "$PARKED" 2>/dev/null || echo 0); fi
if [ "$parked" -gt 0 ] && ! wm_running; then
  i=0
  while [ "$i" -lt "$parked" ]; do
    p() { plutil -extract "windows.$i.$1" raw -o - "$PARKED" 2>/dev/null; }
    bid=$(p bundleID) title=$(p title) x=$(p restoreFrame.0.0) y=$(p restoreFrame.0.1) w=$(p restoreFrame.1.0) h=$(p restoreFrame.1.1)
    if run osascript - "$bid" "$title" "${x%.*}" "${y%.*}" "${w%.*}" "${h%.*}" >/dev/null 2>&1 <<'EOF'
on run argv
  tell application "System Events"
    tell (first process whose bundle identifier is (item 1 of argv))
      set win to (first window whose name is (item 2 of argv))
      set position of win to {(item 3 of argv) as integer, (item 4 of argv) as integer}
      set size of win to {(item 5 of argv) as integer, (item 6 of argv) as integer}
    end tell
  end tell
end run
EOF
    then done_ "window \"$title\" ($bid) back on screen"; else left "window \"$title\" ($bid) not found: it may have closed"; fi
    i=$((i + 1))
  done
else
  skip "no parked windows"
fi

# ---------------------------------------------------------------------------------------------
# 2. Cursors

stage cursor "Putting the macOS cursors back"
if grep -Eq '^[[:space:]]*cursor[[:space:]]*=[[:space:]]*"[^"]' "$CONFIG/config.toml" 2>/dev/null; then
  if [ -n "$CLI" ] && run "$CLI" cursor reset >/dev/null 2>&1; then done_ "macOS cursors back (appearance.cursor cleared)"
  else left "log out once to get the macOS cursors back"; fi
else
  skip "no cursor theme in use (quitting the WM resets it; logging out does too)"
fi

# ---------------------------------------------------------------------------------------------
# 3. Settings from the restore manifest

stage settings "Restoring macOS settings"
dock=0 menubar=0
# ISO-8601 from the manifest ("2026-11-09T10:43:00Z") to the text `defaults write -date` accepts.
defaults_date() {
  printf '%s\n' "$1" | sed -E 's/\.[0-9]+//; s/T/ /; s/Z$/ +0000/; s/([+-])([0-9]{2}):([0-9]{2})$/ \1\2\3/'
}
restore_default() {  # restore_default <index>
  domain=$(field "$1" domain) key=$(field "$1" key) type=$(field "$1" oldValue.type) value=$(field "$1" oldValue.value)
  d=$domain; [ "$d" = NSGlobalDomain ] && d=-g
  case "$type" in
    absent)
      if defaults read "$d" "$key" >/dev/null 2>&1 && ! run defaults delete "$d" "$key"; then fail "$domain $key: defaults delete failed"
      else done_ "$domain $key: removed (it did not exist before SkyRose)"; fi ;;
    bool) if run defaults write "$d" "$key" -bool "$value"; then done_ "$domain $key = $value"; else fail "$domain $key: defaults write failed"; fi ;;
    int) if run defaults write "$d" "$key" -int "$value"; then done_ "$domain $key = $value"; else fail "$domain $key: defaults write failed"; fi ;;
    double) if run defaults write "$d" "$key" -float "$value"; then done_ "$domain $key = $value"; else fail "$domain $key: defaults write failed"; fi ;;
    string) if run defaults write "$d" "$key" -string "$value"; then done_ "$domain $key = \"$value\""; else fail "$domain $key: defaults write failed"; fi ;;
    date)
      when=$(defaults_date "$value")
      if run defaults write "$d" "$key" -date "$when"; then done_ "$domain $key = $when"; else fail "$domain $key: defaults write failed"; fi ;;
    data) if run defaults write "$d" "$key" -data "$(printf %s "$value" | base64 -D | xxd -p | tr -d '\n')"; then done_ "$domain $key (data) restored"; else fail "$domain $key: defaults write failed"; fi ;;
    array|dict) restore_structured_default "$1" "$d" "$domain" "$key" "$type" ;;
    *) fail "$domain $key: original is a $type, which this uninstaller cannot write back" ;;
  esac
  case "$domain" in com.apple.dock) dock=1 ;; esac
  case "$key" in _HIHideMenuBar|AppleMenuBarVisibleInFullscreen) menubar=1 ;; esac
}
# Arrays and dictionaries: one `defaults write` whose arguments come from the helper (NUL-separated,
# so values may contain spaces). The rest of the domain is left alone.
restore_structured_default() {  # index defaults-domain real-domain key type
  idx=$1 d=$2 domain=$3 key=$4 type=$5
  work=$(mktemp -d "${TMPDIR:-/tmp}/skyrose-defaults.XXXXXX") || { fail "$domain $key: could not stage the saved value"; return; }
  if ! plutil -extract "entries.$idx.oldValue" json -o "$work/old.json" "$MANIFEST" \
     || ! /usr/bin/python3 "$HELPER" defaults-args "$work/old.json" "$work/args"; then
    fail "$domain $key: could not encode the saved $type"
    rm -rf "$work"
    return
  fi
  # Saved before set --, which replaces this function's own arguments.
  set --
  while IFS= read -r -d '' arg; do set -- "$@" "$arg"; done < "$work/args"
  if run defaults write "$d" "$key" "$@"; then done_ "$domain $key ($type) restored"; else fail "$domain $key: defaults write failed"; fi
  rm -rf "$work"
}
# One symbolic hotkey (key = its number) inside AppleSymbolicHotKeys. Absent deletes only that
# number; anything else in the domain, including other shortcuts, stays.
restore_symbolichotkey() {  # index
  domain=$(field "$1" domain) key=$(field "$1" key) type=$(field "$1" oldValue.type)
  [ -n "$domain" ] || domain=com.apple.symbolichotkeys
  if [ "$DRY" = 1 ]; then
    run defaults export "$domain" "symbolichotkeys.plist"
    run defaults import "$domain" "symbolichotkeys.plist"
    if [ "$type" = absent ]; then done_ "shortcut #$key removed (it did not exist before SkyRose)"; else done_ "shortcut #$key restored"; fi
    return
  fi
  work=$(mktemp -d "${TMPDIR:-/tmp}/skyrose-hotkey.XXXXXX") || { fail "shortcut #$key: could not stage the saved shortcut"; return; }
  if ! plutil -extract "entries.$1.oldValue" json -o "$work/old.json" "$MANIFEST"; then
    fail "shortcut #$key: could not read the saved shortcut"
    rm -rf "$work"
    return
  fi
  if ! defaults export "$domain" "$work/current.plist" 2>/dev/null; then
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' '<plist version="1.0"><dict/>' '</plist>' > "$work/current.plist"
  fi
  if ! /usr/bin/python3 "$HELPER" hotkey "$work/current.plist" "$key" "$work/old.json" "$work/merged.plist"; then
    fail "shortcut #$key: could not build the restored shortcut"
    rm -rf "$work"
    return
  fi
  if run defaults import "$domain" "$work/merged.plist"; then
    if [ "$type" = absent ]; then done_ "shortcut #$key removed (it did not exist before SkyRose)"; else done_ "shortcut #$key restored"; fi
  else
    fail "shortcut #$key: defaults import failed"
  fi
  rm -rf "$work"
}
# uuid, display number, current picture. Tests pass SKYROSE_WALLPAPER_SCREENS so this never asks
# the live desktop. Otherwise each screen's number is turned into WallpaperService's UUID.
screen_table() {
  if [ -n "${SKYROSE_WALLPAPER_SCREENS:-}" ] && [ -r "$SKYROSE_WALLPAPER_SCREENS" ]; then cat "$SKYROSE_WALLPAPER_SCREENS"; return 0; fi
  listed=$(mktemp "${TMPDIR:-/tmp}/skyrose-screen-list.XXXXXX") || return 1
  if ! osascript -l JavaScript > "$listed" <<'EOF'
ObjC.import("AppKit");
function run() {
  const ws = $.NSWorkspace.sharedWorkspace, screens = $.NSScreen.screens, lines = [];
  for (let i = 0; i < screens.count; i++) {
    const s = screens.objectAtIndex(i);
    const num = s.deviceDescription.objectForKey("NSScreenNumber").unsignedIntValue;
    const cur = ws.desktopImageURLForScreen(s);
    const path = (cur && !cur.isNil() && cur.path) ? String(cur.path.js) : "";
    lines.push(String(num) + "\t" + path);
  }
  return lines.join("\n");
}
EOF
  then rm -f "$listed"; return 1; fi
  tab=$(printf '\t')
  num=""
  while IFS="$tab" read -r num path || [ -n "$num" ]; do
    [ -n "$num" ] || continue
    uuid=$(/usr/bin/python3 "$HELPER" display-uuid "$num" 2>/dev/null) || uuid="display-$num"
    [ -n "$uuid" ] || uuid="display-$num"
    printf '%s\t%s\t%s\n' "$uuid" "$num" "$path"
    num=""
  done < "$listed"
  rm -f "$listed"
}
# Wallpaper: the recorded display only, and only while it still shows the picture SkyRose set
# last. Another display that happens to show the same picture keeps its own original.
restore_wallpaper() {  # restore_wallpaper <index of the first entry for that display>
  display=$(field "$1" domain) old=$(field "$1" oldValue.value) type=$(field "$1" oldValue.type)
  n=$(entry_count) i=0 latest=""
  while [ "$i" -lt "$n" ]; do
    [ "$(field "$i" kind)" = wallpaper ] && [ "$(field "$i" domain)" = "$display" ] && latest=$(field "$i" newValue.value)
    i=$((i + 1))
  done
  if [ "$type" != string ] || [ ! -e "$old" ]; then left "wallpaper on $display: the original picture is gone; pick one in System Settings"; return; fi
  table=$(mktemp "${TMPDIR:-/tmp}/skyrose-screens.XXXXXX") || { fail "wallpaper on $display: could not list screens"; return; }
  if ! screen_table > "$table"; then fail "wallpaper on $display: could not list screens"; rm -f "$table"; return; fi
  number="" current="" tab=$(printf '\t') id=""
  # A final row with no newline still counts (`read` reports EOF for that row).
  while IFS="$tab" read -r id num picture || [ -n "$id" ]; do
    if [ -n "$id" ] && [ "$id" = "$display" ]; then number=$num; current=$picture; break; fi
    id=""
  done < "$table"
  rm -f "$table"
  if [ -z "$number" ]; then left "wallpaper on $display: that display is not connected"; return; fi
  if [ "$current" != "$latest" ]; then left "wallpaper on $display: it no longer shows SkyRose's picture, so it was left as it is"; return; fi
  # argv[0] is that display's number. Screens with any other number are not touched, even when
  # they show the same file.
  if run osascript -l JavaScript - "$number" "$old" >/dev/null 2>&1 <<'EOF'
ObjC.import("AppKit");
function run(argv) {
  const want = String(argv[0]), old = argv[1];
  const ws = $.NSWorkspace.sharedWorkspace, screens = $.NSScreen.screens;
  for (let i = 0; i < screens.count; i++) {
    const s = screens.objectAtIndex(i);
    const num = String(s.deviceDescription.objectForKey("NSScreenNumber").unsignedIntValue);
    if (num !== want) continue;
    const ok = ws.setDesktopImageURLForScreenOptionsError($.NSURL.fileURLWithPath(old), s, $({}), null);
    if (!ok) throw new Error("could not set the picture on display " + want);
    return "ok";
  }
  throw new Error("display " + want + " is not connected");
}
EOF
  then done_ "wallpaper on $(field "$1" note || echo "$display") back to $(basename "$old")"
  else fail "wallpaper on $display: could not set the picture"; fi
}
# A file SkyRose replaced. oldValue is the copyOriginal path, or absent when the file is new.
restore_file() {  # index
  dest=$(field "$1" key) type=$(field "$1" oldValue.type) src=$(field "$1" oldValue.value)
  if [ "$type" = absent ]; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if run to_trash "$dest"; then done_ "$dest removed (it did not exist before SkyRose)"; else fail "$dest: could not move it to the Trash"; fi
    else done_ "$dest already gone"; fi
  elif [ "$type" = string ] && [ -e "$src" ]; then
    if run cp "$src" "$dest"; then done_ "$dest restored from the saved copy"; else fail "$dest: could not copy the saved original back"; fi
  else
    fail "$dest: the saved original is missing"
  fi
}
list=$(originals)
before=$(grep -c . "$REPORT")
for i in $list; do
  case "$(field "$i" kind)" in
    defaults) restore_default "$i" ;;
    hidutil)
      old=$(field "$i" oldValue.value)
      if run hidutil property --set "$old" >/dev/null 2>&1; then done_ "key remaps back to before SkyRose (Caps Lock -> F18 removed)"; else fail "key remaps: hidutil property --set failed"; fi ;;
    symbolichotkeys) restore_symbolichotkey "$i" ;;
    wallpaper) restore_wallpaper "$i" ;;
    kittyConfig|font) ;;  # the profile step removes the kitty include and, when asked, the fonts
    loginItem)
      if [ "$(field "$i" oldValue.type)" = absent ]; then done_ "login item $(field "$i" key) goes away with the app"
      else left "login item $(field "$i" key) existed before SkyRose; it was left in place"; fi ;;
    file) restore_file "$i" ;;
    mode) ;;  # nothing to write; the SIP step reads skyrose.mode
    *) fail "$(field "$i" kind) $(field "$i" domain) $(field "$i" key): this uninstaller does not know how to restore it" ;;
  esac
done
[ "$(grep -c . "$REPORT")" = "$before" ] && skip "no macOS settings to put back"
[ "$dock" = 1 ] && run killall Dock >/dev/null 2>&1 && done_ "Dock reloaded"
if [ "$menubar" = 1 ]; then
  run osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('AppleInterfaceMenuBarHidingChangedNotification', \$(), \$(), true)" </dev/null >/dev/null 2>&1
  done_ "menu bar told to re-read its setting"
fi

# ---------------------------------------------------------------------------------------------
# 4. Lid-closed sleep

stage sleep "Putting lid-closed sleep back"
if [ -e "$SUPPORT/sleep-disabled-by-skyrose" ]; then
  # Same scoped, passwordless sudo rule Clamshell uses; -n never prompts.
  if run sudo -n /usr/bin/pmset disablesleep 0 >/dev/null 2>&1; then done_ "pmset disablesleep 0 (lid-closed sleep is back)"
  else left "run once in a terminal: sudo pmset disablesleep 0   (the Mac would not sleep with the lid closed)"; fi
else
  skip "SkyRose did not turn lid-closed sleep off"
fi
if [ -e /etc/sudoers.d/skyrose ]; then left "you installed SkyRose's sudo helper; remove it with: sudo rm /etc/sudoers.d/skyrose"; fi

# ---------------------------------------------------------------------------------------------
# 5. Login item

stage login "Removing the login item"
sa_daemon_plist=/Library/LaunchDaemons/com.skyrose.sa-loader.plist
sa_daemon_remove="/Library/Application Support/SkyRose/uninstall-sa-daemon.sh"
if [ ! -e "$sa_daemon_plist" ]; then
  skip "no SIP-off boot daemon installed"
elif [ "$DRY" = 1 ]; then
  run sudo "$sa_daemon_remove"
elif [ "$YES" = 0 ] && [ -t 0 ] && ask "Remove the SIP-off boot daemon? (asks for your password)" y && sudo "$sa_daemon_remove"; then
  done_ "SIP-off boot daemon removed"
else
  left "the SIP-off boot daemon is still installed; remove it with: sudo '$sa_daemon_remove'"
fi

agent="$HOME/Library/LaunchAgents/com.skyrose.mac.plist"
if launchctl print "gui/$(id -u)/com.skyrose.mac" >/dev/null 2>&1; then run launchctl bootout "gui/$(id -u)/com.skyrose.mac" >/dev/null 2>&1; done_ "launch agent com.skyrose.mac unloaded"; fi
if [ -e "$agent" ]; then run to_trash "$agent" && done_ "~/Library/LaunchAgents/com.skyrose.mac.plist to the Trash"; fi
skip "Open at login goes away with the app (System Settings > General > Login Items)"

# ---------------------------------------------------------------------------------------------
# 6. Profile bits: kitty, fonts, config

stage profile "Removing the kitty profile, fonts and config"
if grep -q "skyrose.conf" "$HOME/.config/kitty/kitty.conf" 2>/dev/null || [ -e "$HOME/.config/kitty/skyrose.conf" ]; then
  if [ -n "$CLI" ] && run "$CLI" kitty uninstall >/dev/null 2>&1; then done_ "kitty profile removed (your kitty.conf is otherwise unchanged)"
  else left "kitty: remove the 'include skyrose.conf' line from ~/.config/kitty/kitty.conf and the two skyrose*.conf files"; fi
else
  skip "no SkyRose kitty profile"
fi
if [ -r "$SUPPORT/Fonts/installed.json" ]; then
  if [ "$RM_FONTS" = yes ]; then
    if [ -n "$CLI" ] && run "$CLI" fonts uninstall >/dev/null 2>&1; then done_ "fonts SkyRose installed removed from ~/Library/Fonts"
    else left "fonts: remove the files listed in $SUPPORT/Fonts/installed.json from ~/Library/Fonts"; fi
  else
    skip "fonts kept in ~/Library/Fonts (default)"
  fi
else
  skip "no fonts installed by SkyRose"
fi
if [ -d "$CONFIG" ]; then
  if [ "$RM_CONFIG" = yes ]; then run to_trash "$CONFIG" && done_ "~/.config/skyrose to the Trash"
  else skip "~/.config/skyrose kept (default)"; fi
else
  skip "no ~/.config/skyrose"
fi

# ---------------------------------------------------------------------------------------------
# 7. SIP reminder (only after SIP-off mode, only while SIP is not fully on)

stage sip "Checking System Integrity Protection"
if [ "$SIP_REMINDER" = 1 ]; then
  left "SIP-off mode was used: turn SIP back on in Recovery (hold power > Options > Utilities > Terminal: csrutil enable)"
  # Nothing is trashed until this returns. Dry-run only says it would wait.
  if [ "$DRY" = 1 ]; then
    [ "$PROGRESS" = 1 ] && echo "::sip"
    [ "$PROGRESS" = 0 ] && echo "  would show the SIP reminder and wait until it is acknowledged"
  elif [ "$PROGRESS" = 1 ]; then
    echo "::sip"
    ack=""
    if ! IFS= read -r ack; then ack=""; fi
    ack=$(printf '%s' "$ack" | tr -d '[:space:]')
    case "$ack" in
      ack|understood|yes|continue) ;;
      *) fail "SIP reminder was not acknowledged. Apps and SkyRose's data were kept."; finish 1 ;;
    esac
  elif [ -d "$REMINDER_APP" ] && run open -W -n -a "$REMINDER_APP" --args --sip-reminder; then
    : # open -W returns when the reminder is dismissed and that Settings instance quits
  else
    fail "the SIP reminder could not be shown. Apps and SkyRose's data were kept."
    finish 1
  fi
else
  skip "no reminder needed"
fi

# ---------------------------------------------------------------------------------------------
# 8. Apps, CLI links, certificate

stage apps "Moving the apps to the Trash"
for app in "$WM_APP" "$SETTINGS_APP" "$APPS/CaelestiaWM.app"; do
  if [ -d "$app" ]; then run to_trash "$app" && done_ "$(basename "$app") to the Trash"; fi
done
if [ -d "$APPS/TestWindows.app" ]; then
  if grep -qx "app $APPS/TestWindows.app" "$RECORD" 2>/dev/null; then run to_trash "$APPS/TestWindows.app" && done_ "TestWindows.app to the Trash"
  else skip "TestWindows.app kept (SkyRose's installer did not put it there)"; fi
fi
for link in "$HOME/.local/bin/skyrose" "$HOME/.local/bin/caelestia"; do
  if [ -L "$link" ]; then
    case "$(readlink "$link")" in
      *SkyRose.app/*|*CaelestiaWM.app/*) run to_trash "$link" && done_ "${link#"$HOME"/} link to the Trash" ;;
      *) skip "${link#"$HOME"/} points elsewhere: kept" ;;
    esac
  fi
done
[ -L /usr/local/bin/skyrose ] && left "/usr/local/bin/skyrose is a link you made: remove it with rm"
if [ -n "$CERT" ] && [ "$RM_CERT" = yes ]; then
  run security delete-identity -c "$CERT" >/dev/null 2>&1
  run security delete-certificate -c "$CERT" >/dev/null 2>&1 && done_ "\"$CERT\" certificate deleted" || left "certificate: delete \"$CERT\" in Keychain Access"
elif [ -n "$CERT" ]; then
  skip "\"$CERT\" certificate kept (default)"
fi

# ---------------------------------------------------------------------------------------------
# 9. SkyRose's own data, report

stage data "Removing SkyRose's data"
restore_failed=0
grep -q '^fail' "$REPORT" && restore_failed=1
for dir in "$SUPPORT" "$LOGS" "$HOME/Library/Caches/com.skyrose.mac"; do
  if [ "$dir" = "$SUPPORT" ] && [ "$restore_failed" = 1 ]; then
    left "kept Application Support: a restore failed, so the manifest is still there. Fix it and run this again."
    continue
  fi
  if [ -e "$dir" ]; then run to_trash "$dir" && done_ "${dir#"$HOME"/} to the Trash"; fi
done

if [ "$restore_failed" = 1 ]; then finish 1; fi
finish 0
