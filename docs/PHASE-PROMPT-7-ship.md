# SkyRose Part 7 — first-ship installer and uninstaller

Work in `~/Projects/caelestia-mac` (public repo: https://github.com/ganya002/skyrose). CLI (not on PATH):

`~/Projects/caelestia-mac/dist/SkyRose.app/Contents/MacOS/skyrose`

Do this phase. Do not redo Parts 3–6 (SIP-off loader, screenshot, keep-awake, clamshell, blob surface, motion tokens, left-bar dock, wallpaper carousel). If a safety classifier mentions Dock injection, leave the loader alone.

Update `docs/phase-progress.md` with sections `Part 7a` … `Part 7d`. Commit on `main` after each part, then `git push origin main`. Never force-push.

## Already there — build on it, do not start from scratch

- Developer/from-source installer: `scripts/install.sh` (builds with Xcode, copies `SkyRose.app` and `SkyRose Settings.app` to `~/Applications`, optional `~/.local/bin/skyrose` symlink, no sudo). Keep this for people building from source.
- `skyrose uninstall [--yes]` already exists (`Sources/skyrose/LocalCommands.swift`, `struct Uninstaller`). It looks for `scripts/uninstall.sh` next to the app (`Contents/Resources/scripts/uninstall.sh` or `Contents/Resources/uninstall.sh`), then the repo, then Application Support. **The script is missing**, so today it only prints the manual steps.
- Restore manifest: `RestoreManifest` / `~/Library/Application Support/SkyRose/restore-manifest.json` records every system change. SIP reminder window already exists (`SkyRose Settings --sip-reminder`, 5 s minimum).
- Intended uninstall behaviour is documented in `docs/UNINSTALL.md`. Implement that. The Settings About page lists pending restores and can preview the SIP reminder, but there is no **Uninstall SkyRose** button yet.
- Kitty profile (`skyrose kitty install|uninstall`, theme file `skyrose-theme.conf`) and font pack (`skyrose fonts install|uninstall`) already exist. Onboarding already requests permissions.
- Signing is the local self-signed identity (“Caelestia Local Signing” / “SkyRose Local Signing”), not Apple Developer ID. Do not pretend the build is notarized.
- Version reported by the CLI today: `0.2.0`. Use that for the first GitHub Release tag (`v0.2.0`) unless the repo already has a more recent version string.

## Hard rules

- No sudo, no writing sudoers, no password prompts, no package installs, no system-settings changes except what the installer/uninstaller is *designed* to do for a normal user (and those must go through the restore manifest).
- Never close Gabby’s own apps (Cursor, Claude, browser, kitty he is using, etc.). TestWindows only if you need windows.
- **Do not run the uninstaller against Gabby’s real `~/.config/skyrose` or `~/Library/Application Support/SkyRose`.** Test with `--dry-run`, fixtures, and a temporary HOME / prefix. A live `skyrose uninstall --yes` on this Mac is forbidden.
- Do not delete `/etc/sudoers.d/clamshell` (that belongs to Clamshell Toggle). Only mention `/etc/sudoers.d/skyrose` if SkyRose itself created that file; 5c-fix uses the existing clamshell rule and may never have written `skyrose`.
- When you finish any live WM testing: `~/Projects/caelestia-mac/dist/SkyRose.app/Contents/MacOS/skyrose wm panic`
- Build and sign with the existing local signing setup. Run the test suite. All tests pass.
- Do not commit secrets, `dist/`, or `.build/`.


## Part 7a — Fix the launcher black flash (do this first)

Gabby’s launcher (the app drawer / spotlight-like search, opened with left ⌥) flashes a **black box or black outline** around the panel when it opens or closes.

He took a screenshot mid-bug: `docs/bugs/launcher-black-flash.png`. Look at it. In the still you can already see a thin dark vertical line on the right of the launcher that does not follow the rounded blob, and a rectangular frame that extends above the card — leftover window chrome, an opaque black `NSWindow`/`NSVisualEffectView` background, a rectangular clip, or a border drawing behind the Metal SDF. On open/close that flashes as a black box/line around the drawer.

Fix it so opening and closing the launcher never shows a black rectangle, black outline, or stray line. The visible shape should only be the blob/pill.

Likely places to check: the fullscreen blob overlay vs the launcher content panel; default black window background showing before the SDF is ready or after it fades; `ShellPanel` chrome; shadows; frozen `implicitHeight` during close; jelly/open animation revealing a rect behind the rounded content.

Live-test the real launcher (open and close it yourself). Capture before/after frames. Do not close Gabby’s apps; TestWindows only if you need extra windows. `skyrose wm panic` when that live test is done. Add a regression test if you can assert “no opaque black outside the blob during the open/close animation.”

## Part 7b — Uninstaller

Write `scripts/uninstall.sh` so that `skyrose uninstall` finds and runs it. Also keep a copy next to the installed app (`Contents/Resources/scripts/uninstall.sh`) so uninstall still works after the repo is gone.

Match `docs/UNINSTALL.md`, as a normal user, never sudo:

1. Stop the WM (`wm quit` / unpark every window; if the WM is not running, replay the parked-windows journal).
2. Reset cursors if Appearance › Cursor was used.
3. Restore every `defaults` key from the restore manifest (exact original value, or delete the key if it did not exist), including screenshot shortcut takeover (`symbolichotkeys`) if onboarding changed them.
4. Remove Caps Lock → F18 `hidutil` mapping if preset B was used.
5. Put lid-closed sleep back: `pmset disablesleep 0` only if SkyRose set it (same `sudo -n` path as clamshell; if the helper is missing, print the `sudo pmset disablesleep 0` line for the user — do not prompt for a password). Do not touch Clamshell Toggle’s sudoers file.
6. Remove the login item / launch agent `com.skyrose.mac`.
7. Restore previous wallpaper(s) if SkyRose changed them.
8. `skyrose kitty uninstall` if the profile was set up.
9. Move `~/Applications/SkyRose.app`, `~/Applications/SkyRose Settings.app`, `~/Applications/TestWindows.app` (only if SkyRose installed it) and the `~/.local/bin/skyrose` / deprecated `caelestia` symlink to the Trash (not `rm -rf`).
10. Ask whether to keep fonts installed into `~/Library/Fonts` and whether to keep `~/.config/skyrose` (Trash otherwise). `--yes` should have documented defaults (keep fonts, trash config is a product decision — pick the safer default: keep both unless the user said yes to removing them, and document it).
11. Optionally offer to remove the local signing certificate (`scripts/sign-setup.sh --remove`) — ask, default no.
12. If SIP-off mode was used and `csrutil status` is not fully enabled, show the existing SIP reminder (`SkyRose Settings --sip-reminder`) **before** removing Application Support. Never show it otherwise.
13. Print a report of everything done / skipped / left behind (TCC entries stay until the user removes them in System Settings).

Flags: `--dry-run` (print every action, change nothing), `--yes`, `--no-color`, `-h`. Readable, commented, no eval, no obfuscation. Idempotent.

Wire Settings → a real **Backup & uninstall** page (or a clear Uninstall button on About) that opens the SkyRose-styled uninstall GUI (see “SkyRose-styled GUI” under Part 7c). The GUI runs the same script/engine. Update `docs/UNINSTALL.md` so it no longer says the uninstaller is unbuilt.

Tests: dry-run; fixture HOME where the script restores mocked defaults, removes mocked files, and refuses to touch the real user account.

## Part 7c — User-facing release installer

The current `scripts/install.sh` stays as the from-source installer (Xcode + `scripts/build.sh`). Add a separate user bootstrap, e.g. `scripts/install-release.sh`, that is what the website and GitHub Releases publish as `install.sh`.

Follow the intent in `~/Projects/archify-site/docs/PLAN.md` section 3 (installer), with these corrections:

- Apps are `SkyRose.app` and `SkyRose Settings.app`, installed to `~/Applications` (not “SkyRose WM.app”).
- No sudo. Optional CLI symlink `~/.local/bin/skyrose` (ask; default No; read the answer from `/dev/tty` when stdin is a pipe).
- POSIX `sh`, `main()` at the end so a truncated download cannot run halfway.
- Flags: `--dry-run`, `--yes`, `--no-cli`, `--no-open`, `--version X`, `--no-color`, `-h`. `--uninstall` may delegate to `uninstall.sh` if that is clean; otherwise tell the user to run `skyrose uninstall`.
- Checks: arm64, macOS 14+, disk space.
- Downloads a **pinned** GitHub Release zip (`https://github.com/ganya002/skyrose/releases/...`), verifies SHA-256 against a hash published next to the script / baked into that script version, and only then strips quarantine (`xattr -dr com.apple.quarantine`).
- Quits a running copy gracefully, moves any previous `~/Applications/SkyRose.app` (and old `CaelestiaWM.app`) to the Trash, copies the new apps, verifies codesign, opens SkyRose so first-run onboarding starts.
- Honest Gatekeeper copy: this build is signed with a local/self-signed identity, not Developer ID, and is not notarized. Say that. Do not claim Homebrew works unless you also create a real tap (skip the tap for this phase; do not document `brew install --cask skyrose` as if it exists).
- Idempotent. Anything the installer changes that is not already journalled by the app must be recorded so 7a can reverse it.
- Primary documented path is download → checksum → `less` → `sh install.sh` (and `--dry-run`). A `curl | sh` one-liner may exist underneath with a warning; it must not be the only path. The project’s “no piped installers” safety promise should be updated to match this honest two-step, not silently broken.
- Under ~300 lines if possible, commented, no eval / base64.

Also add `--dry-run` to the from-source `scripts/install.sh` if it is cheap.


### SkyRose-styled GUI (required — not a stock wizard, not a bare Terminal as the shipped UI)

The scripts above are the engine (and what `--yes`, CI, and the download-check-`sh` path use). What a normal user *sees* must look like the rest of SkyRose: same design language as Settings and Onboarding (look tokens, type, cards, pills, sky-to-rose accents). Reuse that visual system. Do not ship a default AppKit installer template or a plain Terminal window as the primary experience.

**Installer window**
- Distinct stages (welcome → requirements / download or copy → verify → place apps → optional CLI / kitty / fonts → permissions reminder → done). Animate the transition between stages: Caelestia motion tokens at `durations.scale` 0.8 (expressiveDefaultSpatial ≈ 400 ms, interruptible). Content should slide/fade/morph, not hard-cut.
- A persistent **status/progress bar** that shows how close they are to a finished install (overall 0–100%, not only the current file copy). The fill should animate as stages complete. Label the current stage in plain language (“Verifying download…”, “Copying SkyRose…”).
- Reduce Motion: short fades, no jelly/overshoot, progress bar may still fill.
- Errors stay in the same chrome (one-line cause + what to do), not a crash dialog from another planet.
- Opening the downloaded release should present this GUI (a dedicated installer window inside the packaged app, or a small SkyRose Installer entry point — pick the cleaner option and document it). First-run onboarding can follow after install, and should still request permissions and show when setup is complete.

**Uninstaller window**
- Same chrome and motion as the installer, so they feel like one product. Stages (confirm → restore settings → remove profile bits → trash apps → report). Same style of progress/status bar.
- The Settings **Backup & uninstall** action opens this GUI (after a confirm). `skyrose uninstall` may open it when stdout is a TTY and `--yes` was not passed; `--yes` / non-TTY stays script-only.

The progress bar and stage list must reflect real work (drive them from the script/engine callbacks), not a fake timed animation that finishes before the copy does.

First-run: onboarding should still request every permission the WM needs and visually show when setup is complete. If kitty profile + font pack are not already offered there, add optional steps (user can skip). Do not make the installer itself `sudo` fonts or rewrite unrelated kitty settings.

## Part 7d — Package the first GitHub Release

1. Build the signed apps with the existing `scripts/build.sh`.
2. Produce `SkyRose-0.2.0-arm64.zip` (or whatever the version string is) containing the two apps, plus `install.sh` (the release bootstrap), `uninstall.sh`, and detached `.sha256` files.
3. Tag `v0.2.0` (or the matching version) on the commit you want to ship and create a **public** GitHub Release on `ganya002/skyrose` with those assets (`gh release create …`). Do not force-overwrite an existing tag.
4. Make sure `skyrose uninstall` can find `uninstall.sh` inside the installed app bundle.
5. Update README / LIMITATIONS / UNINSTALL / changelog so they describe the real install and uninstall paths. Point at https://github.com/ganya002/skyrose/releases.

Do not upload `docs/caelestia-reference/` into the zip (those are Arch reference shots, some personal).

## Done when

- Launcher open/close no longer flashes a black box or outline (screenshot the fix)
- `scripts/uninstall.sh` exists and `skyrose uninstall` runs it
- Installer and uninstaller GUIs match SkyRose (Settings/Onboarding look), with animated stage transitions and a real overall progress/status bar
- Settings has a confirmed uninstall action that opens that GUI
- A user can install from a GitHub Release zip without Xcode
- Checksums verify; `--dry-run` works on both scripts
- A public `v0.2.0` (or current version) Release is on GitHub
- Tests pass; `docs/phase-progress.md` updated; each part committed and pushed
- You did not uninstall or trash Gabby’s real config

Report: commit hashes, release URL, what a user types to install and uninstall, how the GUIs are launched, launcher before/after screenshot paths, anything you skipped (Homebrew, notarization), test commands, and any other screenshot paths.
