# Arch parity: progress (2026-11-05)

Phase brief: make SkyRose match Gabby's Arch Hyprland + Caelestia setup
(`~/caelestia-ref/full-2026-11-05/`, 5120x1440 @1x). The full audit table is in
`docs/arch-parity.md`. **Re-read this file first after a context compaction.**

## Gabby's picks

- Border colour fade **480 ms**, like Arch. This is the one exception to the
  350 ms cap, and `AnimationGuardTests` guards it.
- New window **follows the cursor** (Hyprland `force_split 0`). A cursor outside
  the focused tile goes to the right/bottom.

## Done (committed on main, not pushed)

1. `29ead98` Dwindle geometry
   - Hyprland's partition, which is gaps_out first and then gaps_in on interior
     sides only. n3 = 1258 | 1263, the same as the capture.
   - gapsOutSingle 20, split on the longer side, preserve_split.
   - pseudo, togglesplit, swapsplit and float centring.
   - Minimum tile size (excess windows float).
   - Opacity 0.95, bar 60, border fade 480 ms, close 240 ms, popin 0.8.
   - Group bar sits around the window.
2. `f468d85` Settings
   - Window radius 15, the same as the WM rounding. The blur is masked and the
     sidebar is an inset concentric panel, with no seam or double edge.
   - Live WM status: the IPC is probed and a process check is the fallback, so
     the status shows "running (busy)" instead of a false "not running".
   - The WM runs as a single instance: a second copy waits 6 s and then exits.
     A lost socket is rebound every 3 s.
3. `215b557` Shell
   - Caelestia `Interactions.qml` hover zones for the dashboard (top band,
     including the notch dip), utilities (bottom-right corner) and the OSD
     (right edge), with a 100 ms dwell.
   - Hover-opened drawers close on leave. Keybind-opened drawers ignore hover.
   - Standalone utilities drawer.
   - Session menu dims the screen (0.45).
4. This commit: **red traffic light quits the app** (Settings › Windows, default off)
   - It watches presses on the AX close button. When that pid's last window is
     destroyed, it checks the AX window count is 0 and the app is a regular Dock
     app, then calls `NSRunningApplication.terminate()`, a normal quit and never
     a force-quit.
   - Exceptions list (default Finder; `com.skyrose.*` is always exempt), editable
     in Settings.
   - Close-to-tray apps: their window closes but they keep a menu-bar presence.
     They are not exempt automatically, so add them to the exceptions list.
     Accessory/agent apps (no Dock icon) are never quit.
   - 8 unit tests plus a settings test. **Not live-tested yet.**

Tests: **889 pass** (`/usr/bin/swift test`).

Live-verified on the built-in display (ws4, TestWindows only):
- Tiling 708/708 at x 21/741, stacked y 53/500 h435.
- pseudo, togglesplit, swapsplit and float.
- Settings corners (cropped shots).
- Single instance and socket rebind.
- Hover dashboard, utilities and OSD; session dim.

Screenshots are in `/tmp/cwm/parity/{before,after}/`.

## Remaining

1. **Close-quit live test**, using TestWindows only:
   - Quit TestWindows and check `query monitors` FOCUSED.
   - Run `./scripts/build.sh`, then restart the WM once.
   - Temporarily set `rules set com.skyrose.mac.testwindows float` and
     `config set wm.closeQuitsApp true`.
   - Click the real close buttons: with 2 windows, one closes; with the last
     window, the app quits.
   - Revert the rule and the config afterwards.
2. **Cursor** (Appearance › Cursor, Bibata Modern Classic). Verdict pending; see
   the findings below.
3. Update `docs/arch-parity.md` (the remaining rows), `docs/LIMITATIONS.md` and
   CHANGELOG.
4. Final report: the parity table summary, what is still different and why, the
   cursor result, the test count, and the restart side effects (see below).

## Cursor findings so far

- The pack config says `sweet-cursors` size 24. The Bibata files are **not** in
  `~/caelestia-ref`; the cape lives in
  `~/Library/Application Support/Mousecape/capes`.
- Private SkyLight API: `CGSRegisterCursorWithImages` registers a cursor with
  its size and hotspot.
  - Legacy names (`Arrow`, `IBeam`) are a silent no-op on macOS 27.
  - The `com.apple.coregraphics.ArrowS` and `IBeamS` names work, with the exact
    24 pt size and hotspot.
- **Reversibility is not clean:**
  - `CoreCursorUnregisterAll` resets the `com.apple.cursor.N` set but not the
    coregraphics names.
  - ArrowS and IBeamS could be restored from a backup taken before applying.
  - `coregraphics.Wait` (the beachball) could **not** be restored:
    `CGSRemoveRegisteredCursor` gives err 1000, and re-registering the backup
    does not take.
  - **Side effect now:** the beachball stays Bibata's 18-frame cursor until
    Gabby logs out. No files were touched.
- Upstream (Mousecape #283 and #287, the SnowGlow fork) reports renamed keys,
  cursors reverting after apply on 26.x, and a 24-frame limit.
- Leaning verdict: **not reliable enough to ship as "session-only with reset"**.
  - Options: (a) report and do not ship; (b) ship only Arrow/IBeam with a backup
    and restore, never Wait, re-applied on wake/display change.
  - The brief says to report rather than ship a half-working version, so the
    default is (a), unless (b) passes a strict reapply/restore test.

## Side effects to report

- `ws focus 4` once hit the focused DELL; full-screen shots that caught Firefox
  were deleted. The DELL was restored to ws2.
- After the WM restarts, kitty and Grok on the DELL swapped sides, and windows
  on the visible workspace re-adopted to ws1. They were left as they are.
- The beachball cursor is Bibata until logout (above).

## Next steps (in order)

1. Run the close-quit live test (Remaining 1) and fix anything it finds.
2. Decide the cursor (the default is to report and not ship), then update the docs.
3. Run the full test suite, commit the docs, and write the final report.
