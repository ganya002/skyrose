#!/bin/sh
# SkyRose release installer. No sudo, no Xcode. The copy people download is this file, named install.sh.
#
# Do this, in order. A truncated download stops before main, so it cannot install halfway.
#   curl -fsSLO https://github.com/ganya002/skyrose/releases/download/v0.2.0/install.sh
#   curl -fsSLO https://github.com/ganya002/skyrose/releases/download/v0.2.0/install.sh.sha256
#   shasum -a 256 -c install.sh.sha256
#   less install.sh
#   sh install.sh --dry-run
#   sh install.sh
#
#   sh install.sh [--dry-run] [--yes] [--no-cli] [--cli] [--no-open] [--version X]
#                 [--payload DIR] [--no-color] [--progress] [--uninstall] [-h]
#
#   --dry-run    print every action, change nothing
#   --yes        no questions. The CLI symlink stays off (the default) unless --cli is also set
#   --no-cli     do not ask about ~/.local/bin/skyrose, and do not create it
#   --cli        create the symlink without asking
#   --no-open    do not open SkyRose at the end
#   --version X  download vX instead of the version baked into this file
#   --payload D  install from a folder of apps that was already checked (the window uses this)
#   --progress   machine-readable ::stage / ::done / ::skip / ::fail / ::finished lines
#   --uninstall  run uninstall.sh next to this file
#
# This build is signed with a local identity, not an Apple Developer ID, and it is not notarized.
# Gatekeeper will say it cannot check the app for malicious software. The script strips the
# quarantine flag only after the zip's SHA-256 matches. A `curl | sh` one-liner can run this file,
# but it skips the less step: download the file and read it first.
#
# Zip hash: baked below when a release is cut, otherwise the sibling file
# SkyRose-<version>-arm64.zip.sha256 on the same GitHub release. Tests set SKYROSE_RELEASE_ZIP
# and SKYROSE_RELEASE_SHA256. SKYROSE_RELEASE_PAYLOAD is a folder of apps that is already checked.

VERSION=0.2.0
BAKED_SHA256=""

main() {
  DRY=0 YES=0 CLI=ask OPEN=1 PROGRESS=0 COLOR=1 UNINSTALL=0
  payload=${SKYROSE_RELEASE_PAYLOAD:-}
  prev=""
  for arg in "$@"; do
    if [ "$prev" = --version ]; then VERSION=$arg; prev=""; continue; fi
    if [ "$prev" = --payload ]; then payload=$arg; prev=""; continue; fi
    case "$arg" in
      --dry-run) DRY=1 ;;
      --yes|-y) YES=1 ;;
      --no-cli) CLI=no ;;
      --cli) CLI=yes ;;
      --no-open) OPEN=0 ;;
      --no-color) COLOR=0 ;;
      --progress) PROGRESS=1; YES=1; COLOR=0 ;;
      --uninstall) UNINSTALL=1 ;;
      --version) prev=--version ;;
      --payload) prev=--payload ;;
      -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "install.sh: unknown option: $arg" >&2; exit 3 ;;
    esac
  done
  [ -t 1 ] || COLOR=0
  [ -n "${NO_COLOR:-}" ] && COLOR=0

  if [ "$UNINSTALL" = 1 ]; then
    script=$(cd "$(dirname "$0")" && pwd)/uninstall.sh
    [ -f "$script" ] || script=$(cd "$(dirname "$0")" && pwd)/../uninstall.sh
    if [ ! -f "$script" ]; then echo "install.sh: uninstall.sh was not next to this file. Run: skyrose uninstall" >&2; exit 1; fi
    set --
    [ "$DRY" = 1 ] && set -- "$@" --dry-run
    [ "$YES" = 1 ] && set -- "$@" --yes
    [ "$COLOR" = 0 ] && set -- "$@" --no-color
    [ "$PROGRESS" = 1 ] && set -- "$@" --progress
    exec /bin/sh "$script" "$@"
  fi

  if [ -z "${HOME:-}" ] || [ "$HOME" = / ]; then echo "install.sh: HOME is not set" >&2; exit 1; fi
  if [ "${SKYROSE_INSTALL_SANDBOX:-0}" = 1 ]; then
    real_home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory: //')
    if [ -z "$real_home" ] || [ "$HOME" = "$real_home" ]; then
      echo "install.sh: sandbox run refused: HOME is the real account" >&2
      exit 4
    fi
  fi

  if [ "$COLOR" = 1 ]; then B=$(printf '\033[1m'); G=$(printf '\033[32m'); Y=$(printf '\033[33m'); R=$(printf '\033[31m'); D=$(printf '\033[2m'); N=$(printf '\033[0m')
  else B="" G="" Y="" R="" D="" N=""; fi
  REPORT=$(mktemp "${TMPDIR:-/tmp}/skyrose-install.XXXXXX") || exit 1
  trap 'rm -f "$REPORT"' EXIT
  STAGES=7 STAGE=0
  stage() { STAGE=$((STAGE + 1)); if [ "$PROGRESS" = 1 ]; then echo "::stage $STAGE $STAGES $1 $2"; else echo; echo "${B}[$STAGE/$STAGES] $2${N}"; fi; }
  done_() { echo "done	$*" >> "$REPORT"; if [ "$PROGRESS" = 1 ]; then echo "::done $*"; elif [ "$DRY" = 1 ]; then echo "  ${G}✓${N} ${D}(would)${N} $*"; else echo "  ${G}✓${N} $*"; fi; }
  skip() { echo "skip	$*" >> "$REPORT"; if [ "$PROGRESS" = 1 ]; then echo "::skip $*"; else echo "  ${D}- $*${N}"; fi; }
  fail() { echo "fail	$*" >> "$REPORT"; if [ "$PROGRESS" = 1 ]; then echo "::fail $*"; else echo "  ${R}✗ $*${N}" >&2; fi; }
  finish() {
    code=$1
    if [ "$PROGRESS" = 1 ]; then [ "$code" = 0 ] && echo "::finished"; exit "$code"; fi
    echo; echo "${B}Report${N}"
    printf '  %s done, %s skipped, %s failed\n' "$(grep -c '^done' "$REPORT")" "$(grep -c '^skip' "$REPORT")" "$(grep -c '^fail' "$REPORT")"
    if grep -q '^fail' "$REPORT"; then echo "  Failed:"; grep '^fail' "$REPORT" | cut -f2- | sed 's/^/    - /'; fi
    [ "$DRY" = 1 ] && echo "${Y}Dry run: nothing was changed.${N}"
    if [ "$code" = 0 ]; then
      echo "  SkyRose is signed with a local identity, not an Apple Developer ID, and it is not notarized."
      echo "  The first launch asks for Accessibility, Input Monitoring and Screen Recording."
    fi
    exit "$code"
  }
  run() { if [ "$DRY" = 1 ]; then echo "  ${D}would run:${N} $*"; return 0; fi; "$@"; }

  if [ "$PROGRESS" = 0 ]; then
    echo "${B}SkyRose installer${N} ${D}v$VERSION, as $(id -un), no sudo${N}"
    echo "This build is not notarized. It is signed on the build machine, not with an Apple Developer ID."
    [ "$DRY" = 1 ] && echo "${Y}Dry run: nothing is changed.${N}"
  fi

  # 1. This Mac
  stage check "Checking this Mac"
  if [ "$(uname -m)" != arm64 ]; then fail "SkyRose needs an Apple Silicon Mac (this one is $(uname -m))."; finish 2; fi
  major=$(sw_vers -productVersion | cut -d. -f1)
  if [ "$major" -lt 14 ]; then fail "macOS 14 or newer is required (this one is $(sw_vers -productVersion))."; finish 2; fi
  avail=$(df -k "$HOME" | awk 'NR==2 { print $4 }')
  if [ -n "$avail" ] && [ "$avail" -lt 512000 ]; then fail "Need about 500 MB free in your home folder."; finish 2; fi
  done_ "Apple Silicon, macOS $(sw_vers -productVersion), enough free space"

  work=$(mktemp -d "${TMPDIR:-/tmp}/skyrose-release.XXXXXX") || exit 1
  zip=${SKYROSE_RELEASE_ZIP:-}

  # 2–3. Download and check, unless the caller already unpacked a checked copy.
  stage download "Downloading SkyRose"
  if [ -n "$payload" ]; then
    skip "using the copy that was already checked"
  elif [ -n "$zip" ]; then
    done_ "using the zip at $zip"
  else
    url="https://github.com/ganya002/skyrose/releases/download/v${VERSION}/SkyRose-${VERSION}-arm64.zip"
    zip="$work/SkyRose.zip"
    if [ "$DRY" = 1 ]; then done_ "would download $url"; else
      if ! curl -fsSL --retry 2 -o "$zip" "$url"; then fail "The download failed. Check the network and try again."; finish 3; fi
      done_ "downloaded SkyRose ${VERSION}"
    fi
  fi

  stage verify "Verifying the download"
  if [ -n "$payload" ]; then
    skip "the folder was already verified"
  elif [ "$DRY" = 1 ] && [ -z "$zip" ]; then
    done_ "would check SHA-256 before stripping quarantine"
  else
    if [ -n "${SKYROSE_RELEASE_SHA256:-}" ]; then expect=$SKYROSE_RELEASE_SHA256
    elif [ -n "$BAKED_SHA256" ]; then expect=$BAKED_SHA256
    elif [ -n "${SKYROSE_RELEASE_ZIP:-}" ] && [ -f "${SKYROSE_RELEASE_ZIP}.sha256" ]; then expect=$(awk 'NR==1 { print $1 }' "${SKYROSE_RELEASE_ZIP}.sha256")
    else
      hashurl="https://github.com/ganya002/skyrose/releases/download/v${VERSION}/SkyRose-${VERSION}-arm64.zip.sha256"
      if [ "$DRY" = 1 ]; then expect=""; else
        if ! curl -fsSL --retry 2 -o "$work/zip.sha256" "$hashurl"; then fail "Could not download the checksum."; finish 3; fi
        expect=$(awk 'NR==1 { print $1 }' "$work/zip.sha256")
      fi
    fi
    if [ "$DRY" = 1 ]; then done_ "would require SHA-256 ${expect:-"(from the release)"}"
    else
      got=$(shasum -a 256 "$zip" | awk '{ print $1 }')
      if [ -z "$expect" ] || [ "$got" != "$expect" ]; then
        fail "SHA-256 did not match. The zip was not opened and quarantine was not removed."
        finish 4
      fi
      done_ "SHA-256 matches"
      run xattr -dr com.apple.quarantine "$zip" || true
      payload="$work/unpacked"
      mkdir -p "$payload"
      if ! ditto -x -k "$zip" "$payload"; then fail "Could not open the zip."; finish 1; fi
    fi
  fi
  if [ "$DRY" = 0 ] && [ -z "$payload" ]; then fail "Nothing to install."; finish 1; fi

  # A terminal run without --yes opens the SkyRose window, which runs this script again with --progress.
  if [ "$DRY" = 0 ] && [ "$YES" = 0 ] && [ "$PROGRESS" = 0 ] && [ -t 1 ] && [ -d "$payload/SkyRose Settings.app" ]; then
    echo "Opening the SkyRose installer. Nothing is copied until you press Install there."
    open -W -n -a "$payload/SkyRose Settings.app" --args --installer --payload "$payload"
    exit $?
  fi

  # 4. Replace any previous apps, then copy and check the signature.
  stage place "Copying SkyRose"
  if [ "$DRY" = 0 ] && [ "${SKYROSE_INSTALL_SANDBOX:-0}" != 1 ]; then
    old="$HOME/Applications/SkyRose.app/Contents/MacOS/skyrose"
    if [ -x "$old" ] && pgrep -x SkyRoseWM >/dev/null 2>&1; then
      "$old" wm quit >/dev/null 2>&1 || osascript -e 'tell application id "com.skyrose.mac" to quit' </dev/null >/dev/null 2>&1 || true
      i=0
      while [ "$i" -lt 20 ]; do pgrep -x SkyRoseWM >/dev/null 2>&1 || break; i=$((i + 1)); sleep 0.25; done
      if pgrep -x SkyRoseWM >/dev/null 2>&1; then fail "SkyRose is still running. Quit it, then run this again."; finish 1; fi
      done_ "the running SkyRose quit"
    fi
  fi
  mkdir -p "$HOME/Applications" "$HOME/Library/Application Support/SkyRose"
  record="$HOME/Library/Application Support/SkyRose/install-record.txt"
  for app in "SkyRose.app" "SkyRose Settings.app" "CaelestiaWM.app"; do
    dest="$HOME/Applications/$app"
    if [ "$app" = "CaelestiaWM.app" ]; then
      if [ -d "$dest" ]; then run to_trash "$dest" && done_ "CaelestiaWM.app to the Trash"; fi
      continue
    fi
    src="$payload/$app"
    if [ "$DRY" = 1 ]; then done_ "would install $app to ~/Applications"; continue; fi
    if [ ! -d "$src" ]; then fail "$app is not in the download."; finish 1; fi
    if [ -d "$dest" ]; then to_trash "$dest" || { fail "Could not move the old $app to the Trash."; finish 1; }; fi
    if ! cp -R "$src" "$dest"; then fail "Could not copy $app."; finish 1; fi
    xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
    if ! codesign --verify --deep --strict "$dest" 2>/dev/null; then
      fail "$app failed the signature check. It was moved to the Trash."
      to_trash "$dest" || true
      finish 1
    fi
    printf 'app %s\n' "$dest" >> "$record"
    done_ "$app installed"
  done

  # 5. Optional CLI. Default is no. Kitty and fonts are asked in onboarding, not here.
  stage optional "Optional command line"
  if [ "$CLI" = ask ]; then
    if [ "$YES" = 1 ] || [ "$DRY" = 1 ]; then CLI=no
    elif [ -t 0 ]; then tty=/dev/stdin; elif [ -r /dev/tty ]; then tty=/dev/tty; else CLI=no; tty=""; fi
    if [ "$CLI" = ask ]; then
      printf '  Symlink skyrose into ~/.local/bin? [y/N] '
      read -r answer < "$tty" || answer=""
      case "$answer" in [Yy]*) CLI=yes ;; *) CLI=no ;; esac
    fi
  fi
  if [ "$CLI" = yes ]; then
    if [ "$DRY" = 1 ]; then done_ "would link ~/.local/bin/skyrose"; else
      mkdir -p "$HOME/.local/bin"
      ln -sfn "$HOME/Applications/SkyRose.app/Contents/MacOS/skyrose" "$HOME/.local/bin/skyrose"
      printf 'link %s\n' "$HOME/.local/bin/skyrose" >> "$record"
      done_ "~/.local/bin/skyrose linked (add ~/.local/bin to your PATH if needed)"
    fi
  else
    skip "no CLI symlink (the default)"
  fi
  skip "kitty profile and fonts are optional steps in first-run onboarding"

  # 6. Permissions are asked by onboarding, not by this script.
  stage permissions "Permissions"
  done_ "On first open, SkyRose asks for Accessibility, Input Monitoring and Screen Recording"

  # 7. Open.
  stage done "Opening SkyRose"
  if [ "$OPEN" = 1 ]; then
    if run open "$HOME/Applications/SkyRose.app"; then done_ "SkyRose opened"; else fail "Could not open SkyRose. Open it from ~/Applications."; finish 1; fi
  else
    skip "not opened"
  fi
  finish 0
}

# Moves a file to the Trash. Never rm -rf.
to_trash() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if command -v trash >/dev/null 2>&1; then trash "$1" && return 0; fi
  osascript -e 'on run argv' -e 'tell application "Finder" to delete POSIX file (item 1 of argv)' -e 'end run' "$1" </dev/null >/dev/null 2>&1 && return 0
  mkdir -p "$HOME/.Trash" && mv "$1" "$HOME/.Trash/$(basename "$1").$(date +%s)"
}

main "$@"
