# SkyRose Part 8: shipped defaults + updater (then release v0.3.0)

Repo: ~/Projects/caelestia-mac (github.com/ganya002/skyrose). main is past v0.2.0 (tag v0.2.0 = 1bf9a30). Read docs/phase-progress.md and docs/PHASE-PROMPT-7-ship.md first for conventions.

## Hard rules (same as always)
- No sudo. Never close Gabby's running apps. Never force-push, never move or delete an existing tag.
- Don't touch disks, EFI, bootloader, SIP state. No curl|sh in anything you write.
- Test window-manager behaviour only with TestWindows; `skyrose wm panic` is the escape hatch.
- Everything SkyRose changes on the system must be recorded in the backup journal (Sources/CaelestiaCore/Backup/BackupJournal.swift) BEFORE it changes, and `scripts/uninstall.sh` must put it back. Add a fixture-HOME test for every new journal entry.
- Do not apply anything to Gabby's real setup until it is tested and you're 99% sure it can't break. Uninstaller and installer tests: `--dry-run` and a temporary HOME only.
- Commit and push after each part; report what you did and what you did NOT verify.

## 8a: Bibata cursor ships with SkyRose and is on by default
- Bundle `Bibata-Modern-Classic.cape` (copy from ~/Library/Application Support/SkyRose/cursors/) inside SkyRose.app resources. Bibata is GPL-3.0; add its license + credit to the bundle and THIRD_PARTY notices.
- CursorCapeLibrary should find the bundled cape. On first run (onboarding) and after install, Bibata Modern Classic is selected by default, with a toggle in Settings › Appearance › Cursor to go back to the macOS cursor. It must re-apply on every login (cursor themes are session-only).
- Remember the known limit in CursorTheme.swift (the Wait cursor can't be restored mid-session); say so in the UI copy.

## 8b: The Dock is GONE, not just auto-hidden
Auto-hide alone still pops the Dock up when the pointer hits the screen edge, which fights the bar and the tiling. Make it never appear:
- New SystemTweak "Remove the Dock" (recommended, on by default in onboarding): autohide = true, `com.apple.dock autohide-delay` = 1000 (float), `autohide-time-modifier` = 0, optionally `tilesize` small, then restart the Dock process so it takes effect (`killall Dock` is allowed; it's a system agent that relaunches itself, not one of Gabby's apps).
- Do NOT kill or disable the Dock permanently: it also runs Mission Control, Spaces, and app switching. Don't unload its launch agent.
- Journal the original values of autohide, autohide-delay, autohide-time-modifier, tilesize (including "key was absent"), and restore them in uninstall.sh, then restart the Dock.
- Add a Settings toggle and a `skyrose dock show|hide|status` command. Make sure SkyRose's launcher and bar cover what the Dock did (opening apps, seeing running apps). If something's missing, list it in your report instead of quietly leaving a gap.

## 8c: Pre-installed wallpapers
- Ship a small starter set (6–8 images, aim for under 40 MB total) inside the release, in its own collection, `SkyRose - <title>`. On install/first run, copy them into ~/Pictures/Wallpapers/Static/ (follow that folder's AGENTS.md naming rules; never overwrite an existing file, skip duplicates by hash), and set one as the default if the user has no SkyRose wallpaper yet.
- Pick from ~/Pictures/Wallpapers/Static/: strong, readable at 1440p+, and covering different palettes so the colour-scheme generator gets to show off. Downscale or recompress anything huge (no visible quality loss, keep the original aspect ratio).
- LICENSING: most of those are wallhaven downloads (other people's art). Before bundling one, check its wallhaven page and only ship images where redistribution is clearly OK. Otherwise list them for Gabby to decide, and put a CREDITS file next to the bundled wallpapers. Do not ship the Eris Greyrat (Mushoku Tensei) fan art.
- Uninstall: removes only the starter wallpapers SkyRose copied (journaled by hash), never the user's own.

## 8d: Updating SkyRose
There's no updater yet. Add one:
- `skyrose update [--check] [--yes]`: reads the latest release from the GitHub API (ganya002/skyrose), compares it to the installed version, downloads the zip + .sha256, verifies the SHA-256, and runs that release's install.sh in update mode (keep settings, config, journal and wallpapers; replace only the two apps; relaunch whatever was running). Never downgrade. Tell the user and keep the current install if the checksum fails or there's no network.
- Settings › About: shows the current version, a "Check for updates" button, and an opt-in "Check automatically once a day" toggle (off by default). The check only notifies; installing always needs a click. No silent auto-install.
- Tests: fake release JSON + a local zip + temporary HOME; cover newer, same, older, bad checksum, and offline.

## 8e: Corner calibration (rounded screen corners that actually match)
SkyRose's bar, drawer and border corners should line up with the display's real rounded corners (and the notch on built-in screens), not leave sharp or misaligned edges.
- Add a skippable calibration step to onboarding and to Settings › Appearance › Corners: a fullscreen overlay per display showing all four corners with a live radius preview. The user drags a slider (or uses the arrow keys) until SkyRose's corner hugs the real screen corner. Add a "this screen has square corners" toggle (most external monitors).
- Start from a sensible default: detect the built-in panel (known MacBook corner radii, notch via NSScreen.safeAreaInsets / auxiliaryTopLeftArea), and default external screens to square.
- Save the radius per display (keyed by a stable display UUID, not its index) in the ~/.config/skyrose config and apply it live without restarting the WM. Also add `skyrose corners calibrate`.
- Unit-test the per-display storage and default detection. Check visually only with TestWindows.

## 8f: Release v0.3.0
Build with scripts/build.sh, run `/usr/bin/swift test` (0 failures), sign with "Caelestia Local Signing", zip as SkyRose-0.3.0-arm64.zip with install.sh, uninstall.sh and .sha256 files, publish as GitHub release v0.3.0 (new tag, never move v0.2.0). Keep docs/caelestia-reference out of the zip. Update CHANGELOG and docs (UNINSTALL.md, a new UPDATING.md).
Report: commits, test counts, release URL, and a plain list of what was NOT verified on the real Mac.
