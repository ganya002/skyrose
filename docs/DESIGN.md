# Caelestia for Mac — design decisions

Every non-obvious decision, with its reason. The spec (`docs/SPEC.txt`) said "ask nothing;
decide and write it down", so this file is the record. Section numbers refer to the spec.

## D1. Repository location and the earlier AeroSpace staging

`~/caelestia-mac` already contained a Phase-1 attempt that *staged an AeroSpace configuration*
(no native WM). This spec asks for a native WM, so the new code lives in a fresh repo
(`~/Projects/caelestia-mac`, where the other projects live) and the earlier tree is left exactly
as it was. Its reference dumps (`hyprland-binds.json`, `caelestia-shell.json`, `scheme.json`,
`bordersrc`, `hyprland-options`) were copied into `Tests/fixtures/` and later superseded by
the full export in `Tests/fixtures/ref/` (section 14 attachments). Gabby's screenshots are kept
on disk for visual reference but are git-ignored (they contain her chat history).

## D2. Toolchain

`swift` on this Mac resolves to a swift.org toolchain (swiftly 6.1.2) that cannot compile
against the Xcode 27.2 SDK. All scripts therefore pin `$(xcode-select -p)/Toolchains/
XcodeDefault.xctoolchain/usr/bin` (Swift 6.4.2). Deployment target is macOS 14 as required;
the package builds with any Xcode ≥ 16.

## D3. One process for WM + shell (0.3, 9)

`CaelestiaWM.app` hosts the tiler **and** the shell panels. Reasons:

- one event tap, one set of AX observers, one TCC grant each for Accessibility / Input
  Monitoring / Screen Recording instead of two apps to approve;
- the bar and drawers need the live layout state (focused window, workspace occupancy) at
  display-refresh rate; an IPC hop per frame is avoidable overhead on a 16 GB laptop;
- startup to working tiling < 2 s is easier with one launch.

The downside the spec names (a shell crash takes tiling down) is mitigated by the crash
journal + launchd `KeepAlive` (D9) and by isolating every shell panel behind `do/catch` and
window-level error containment; a panel failure disables that panel, not the process. If the
shell ever needs to be split, it already talks to the WM only through `WMFacade`, the same
surface the IPC server uses.

Status: shell part 1 (frame, bar, launcher, session menu, OSD, toasts) is built this way; see
SHELL.md. `ShellBridge` mirrors WM state into the shell's `ShellState` after each layout pass.

## D4. SwiftPM first, XcodeGen second (9)

The build is `swift build` + `scripts/build.sh`, which assembles the `.app` bundles (Info.plist,
SwiftPM resource bundles, LaunchAgent plist) and signs them. `Packaging/project.yml` is provided
for XcodeGen when someone wants Xcode's debugger, but it is not needed to ship. One build path
to maintain.

## D5. Language modes

Pure modules (`CaelestiaCore`, `CaelestiaLayout`, `CaelestiaIPC`) build in Swift 6 language
mode with strict concurrency — they are value-typed and have no global mutable state.
AppKit/ApplicationServices modules build in Swift 5 mode with `StrictConcurrency` as an
upcoming feature, because the C callbacks of AXObserver / CGEventTap and many AppKit APIs are
not annotated well enough to be worth fighting in a first release.

## D6. Dependencies

- **TOMLKit 0.6.0** (MIT) for TOML parse/serialise. Vetted, widely used, pure Swift + toml++.
- No other third-party code. Material color utilities are re-implemented in Swift (P7) from
  the published algorithm; yabai/AeroSpace/JankyBorders are *inspirations* (MIT), not copied.

## D7. Keymap is the single source of truth (3.2)

`Sources/CaelestiaCore/Resources/keymap.default.toml` carries every one of the 153 Hyprland
binds with its original chord in `linux = …`; `BindsCoverageTests` fails if any
`(modmask, key)` pair of the live dump `Tests/fixtures/binds.json` is missing.
`NoHardcodedBindsTests` scans the sources and fails on any chord literal outside the keymap
module; the only allowed exception is the panic chord (10.10), marked with
`// caelestia:allow-hardcoded-chord`.

Chords are matched by **key code**, never by character (3.4 note on the Norwegian layout).
The cheat sheet shows the characters of the *current* layout through `UCKeyTranslate`.

Resize binds are **percent**: the original `fn.resize_active_window(-10, 0)` resizes by −10 %
of the window's current size (relative), not by 10 px. The keymap documents this and the WM
converts percent to points from the current placement.

## D8. Modifier mapping (3.1)

Preset A (default) maps SUPER→⌥L, ALT→⌘L. Sides are told apart with the device-dependent
`NX_DEVICE*KEYMASK` bits. Right Option and Right Command are never WM modifiers, so Norwegian
Option characters typed with ⌥R keep working. When an event carries a family flag but no side
bit (some remote-desktop/virtual keyboards) the side is treated as *left* (configurable) so
hotkeys still work there.

⌘Tab is not stolen by default (`takeOverCmdTab = false`); ALT+Tab from Linux lands on ⌥L+Tab.

## D9. Crash safety (4.4, 10.10)

Before a window is parked off-screen its original frame is appended to
`~/Library/Application Support/CaelestiaMac/parked-windows.json` (atomic write). On every
launch the journal is replayed *first*, before the tiler starts. The LaunchAgent plist
(`Packaging/com.caelestia.mac.wm.plist`, registered with `SMAppService.agent`) has
`KeepAlive.SuccessfulExit = false`, so a crash relaunches the WM and a clean quit does not.
`scripts/uninstall.sh` replays the same journal through System Events when the app is gone.
The panic chord ⌃⌥⌘⇧Esc is hard-matched in the event tap as well as present in the keymap.

## D10. Standard-mode window geometry (4.3)

Hyprland stores the window size *excluding* the border. We keep the same numbers: the AX frame
is the Hyprland `at`/`size`, and the border is an overlay window drawn 1 px outside it. The
golden dump (two windows on 5120×1440 with 10 px reserved per edge → (21,21,2533×1398) and
(2566,21,2533×1398)) is a unit test in `CaelestiaLayoutTests`, plus 1/3/4-window cases and the
MacBook Air / Pro sizes.

Node boxes partition the usable area; a leaf is inset by `gapsOut` on sides touching the usable
area edge and `gapsIn` elsewhere, then by `borderSize`. With exactly one tiled window (or one
maximized window) `gapsOutSingle` (20) replaces `gapsOut` — the two Hyprland workspace rules
`w[tv1]s[false]` / `f[1]s[false]`.

## D11. Coordinates (4.6)

One converter (`CoordinateConverter`) flips between AppKit (bottom-left, y up) and CG/AX
(top-left, y down) using only the primary display's height. Everything inside the WM is
CG/AX space; AppKit windows are converted at the edge. Unit-tested with displays left of,
right of, above and below the primary one.

## D12. Private API inventory (9, "each private API use is listed")

| Symbol | Where | Why | Fallback |
|---|---|---|---|
| `_AXUIElementGetWindow` | `CShims` (weak-linked) | map an AX window to its `CGWindowID` so overlays, CGWindowList reconciliation and the journal can address it; used by AeroSpace, yabai, Rectangle; needs no SIP change | if the symbol is missing the window is matched by PID + frame + title through `CGWindowListCopyWindowInfo` (slower, still works) |
| `kCGSSessionSecureInputPID` (IORegistry property read) | `SecureInput` | name the app holding Secure Event Input in the OSD | OSD says "another app" |
| SkyLight / CGS calls | `CaelestiaEnhanced` only, behind a runtime handshake with `CaelestiaSA` | Enhanced mode (opacity, scale, instant moves) | Standard mode behaviour |

Everything else is public API.

## D13. Lock screen (5.8)

`⌥L+L` posts ⌃⌘Q (the public system shortcut) through a CGEvent. The real macOS lock screen
with Touch ID protects the session; we never draw a fake lock screen.

## D14. Sleep / session actions (5.7)

`pmset sleepnow` / `pmset displaysleepnow` need no root. Log out / restart / shut down send the
documented loginwindow Apple events (`kAELogOut`, `kAERestart`, `kAEShutDown`, and their
"show dialog" variants for the confirm step). Never `sudo`.

## D15. Media keys (3.4)

F-row media keys are observed as `NX_SYSDEFINED` events and *passed through* so macOS performs
the actual volume/brightness change; we only add the Caelestia OSD. Suppressing Apple's HUD
needs private API, so both show (listed in LIMITATIONS).

## D16. Window title access

Reading other apps' window titles via AX works with Accessibility alone; CGWindowList titles
additionally need Screen Recording on macOS 14+. We use AX titles and never require Screen
Recording for tiling.

## D17. Window animations in Standard mode (snapshot cover)

Real windows of other apps cannot be animated without the window server: every AX frame write is
a synchronous round trip into the app, so "animating" by writing 60 frames a second makes most
apps lag and tear. Instead each layout pass goes through `WindowAnimator`
(`CaelestiaOverlay/WindowAnimation`, see ENHANCED_MODE.md "Window animation hook"):

1. The WM computes the pass (moves, opens, closes, windows leaving for a hidden workspace) and
   hands it to the animator *before* any AX write, with a `commit` closure that does all writes.
2. `SnapshotWindowAnimator` puts up one click-through cover panel per affected display (level
   `.floating`: above normal windows, below the shell frame/bar and the Dock). The cover shows the
   display's desktop still (wallpaper + icons only: windows with a layer below 0) and one tile
   per visible managed window, i.e. its still plus its border ring, at the *old* frames, so the
   screen looks unchanged.
3. After `CATransaction.flush` it waits out the rest of one display refresh (so the cover is on
   screen) and runs `commit`: every real window gets its final frame once, under the cover.
4. The tiles spring to the new frames (`windowsMove`), closing/leaving windows shrink and fade
   (`windowsOut`). The pure model is `WindowMotionModel`; retargeting keeps the spring's velocity.
   A still is **never scaled to another aspect**: it is drawn 1:1 in points, anchored top-left
   and clipped to the tile, over the still's average colour (so a growing tile shows that fill,
   a shrinking one cuts the still off, like a live resize). When the size changes, the window is
   captured again after the commit (attempts at 40–400 ms, until a capture shows the whole window
   at its new size) and that capture cross-fades in over 120 ms.
   New windows pop in from 80 % (`windowsIn`) **only** from a still that shows them at their
   final size: the cache is checked and one capture is tried with a deadline of one frame. In
   practice there never is one (the window is new, so it is not even in the cached shareable
   content; live: 0 of 2 opens), so the new window is shown live through a hole cut in the
   cover's desktop backdrop at its final frame while its neighbours animate.
5. When every channel has settled (within 0.5 pt and under 40 pt/s) the cover fades out in 80 ms,
   showing the real windows exactly where the tiles were. Covers are pooled.

Stills come from `SnapshotCache` (ScreenCaptureKit `SCScreenshotManager`, one
`desktopIndependentWindow` filter per window at its own display's backing scale, 4 Mpx cap,
opaque-bounds crop for windows captured mid-resize). Captures never sit on the animation path:
they run in the background 0.35 s after the layout goes quiet, and every 4 s for visible windows
whose still is older than that (about one ~18 ms capture per second with four windows). A pass
whose stills are missing is an instant move. The workspace slide shares the cache's
`SCShareableContent`.

Measured on the MacBook Air (60 Hz) + DELL U3417W, release build:
- Extra latency before the real windows move (commit latency): 16.8–19 ms (one refresh), 0 ms
  when a cover is already up. Showing the cover: 2.4–8.5 ms.
- Total animation: open ~690–750 ms, retile/swap ~595 ms, close ~600–660 ms, leave ~605 ms
  (default `gabbySpringy` table, including the 80 ms fade of the cover).
- Captures: window p50 17.6 ms / p90 73.5 ms (215 captures), desktop p50 123 ms / p90 261 ms.

Drags of tiled windows: `beginDrag` puts the cover up; the still follows the pointer 1:1 (lifted
to 102.5 % with a shadow) while the real window stays in its slot underneath, a tinted preview
marks the slot the drop would swap into, and on release the following pass animates the swap.

Closes: macOS removes a window before the AX "destroyed" notification arrives, so a close the app
does itself can't be animated without flashing the window back. The WM's own close action calls
`prepareClose` first (the cover goes up with the window still on it), so those closes shrink and
fade.

Never animated (live finding: focusing or switching apps showed stretched stills for about a
second): a frame written again unchanged (snap-back after an app moved its own window, a forced
re-apply on focus), a pass in which a window reappears (its app was unhidden or activated, it was
unminimized, a window id managed again), a hide/minimize pass, and windows discovered at start.
Those passes are instant and cancel any cover still up. Focus changes alone never produce a change.

The cover draws into its own geometry-flipped root layer: AppKit owns the flip of a view's
backing layer, and setting it there did not stick, so stacked windows swapped places while a
cover was up (live finding in this phase; side-by-side layouts hid it before).

`animations.windows = "off"`, game mode, Reduce Motion or a disabled animation preset make every
pass instant (`InstantWindowAnimator` behaviour). Debug aid: `CAELESTIA_DUMP_STILLS=<dir>` in the
daemon's environment writes every still as PNG plus its size and capture time.

## D18. Notch-aware frame

Cutouts are computed per display from `NSScreen` (safe-area top strip minus the two auxiliary top
areas) in `DisplayGeometry.cutoutRects`, so any future shape or count works and no model list
exists. `DisplayInfo.topCutouts` / `shownMenuBarHeight` carry the result; the frame path
(`FramePath.path(…cutouts:thickness:)`) is an even-odd band whose inner edge is a rounded polygon
dipping around each cutout. Windows still keep clear of the full safe-area strip (`menuBarHeight`):
the strip beside the notch is where the auto-hidden menu bar appears.

The outer edge follows the display's physical corners (`frame.displayCornerRadius` for the top
pair, `frame.displayBottomCornerRadius` for the bottom pair, see SHELL.md):
`DisplayLayout.physicalCorners` marks the corners of the frame area that coincide with the
display's own, `outerRadii` rounds those, `innerRadii` = max(0, outer − band) there (concentric,
so the band's width is the same on the corner diagonal as on the edges; the first version used
outer + band, which made the band ~1.8× wider on the diagonal) and the theme's frame rounding
elsewhere. Auto radii key off `DisplayInfo.hasNotch` (top safe area > 0): notched MacBook panels
round only their top corners, and an outer radius larger than the hardware's exposes wallpaper,
so the bottom pair defaults to square on built-in panels. `FramePath` builds both edges as rounded polygons (even-odd fill). The value
is calibrated by eye (`caelestia frame calibrate`), never derived from screenshots: a screenshot
contains the pixels the hardware corner hides. `ConfigFileEditor` writes the one key into the
user's config.toml without rewriting it.
