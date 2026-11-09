# SkyRose — design decisions

> SkyRose was formerly "Caelestia for Mac". Historic decisions below keep the old names where they
> describe the repository at the time; Swift module names (`CaelestiaCore`, ...) are unchanged.

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

`SkyRose.app` hosts the tiler **and** the shell panels. Reasons:

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
`~/Library/Application Support/SkyRose/parked-windows.json` (atomic write). On every
launch the journal is replayed *first*, before the tiler starts. The LaunchAgent plist
(`Packaging/com.skyrose.mac.plist`, registered with `SMAppService.agent`) has
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
| `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` / `DisplayServicesCanChangeBrightness` (and `DisplayServicesBrightnessChanged` when present) | `BrightnessService` (`dlopen` of the DisplayServices framework, symbols looked up at run time) | read and set the brightness of built-in / Apple displays, which have no public API | IOKit display brightness, then (if nothing is controllable) the key is posted on to macOS, which shows its own HUD |
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

F-row media keys arrive as `NX_SYSDEFINED` aux events. The first version passed them through so
macOS did the change and we only added the OSD; live testing showed two faults: Apple's HUD
appeared next to ours, and the brightness keys opened the *volume* OSD, because brightness was
"unavailable" through public APIs on the built-in panel so the OSD had only its volume slider.

Now the event tap intercepts the aux keys (volume up/down/mute, brightness up/down) and swallows
one when SkyRose can do it itself: CoreAudio volume settable, or DisplayServices brightness
controllable (D12). It then applies the change (volume in 1/16 steps, ⌥⇧ quarter steps, unmute on
volume up; brightness through `BrightnessService`) and shows only its own OSD, so Apple's HUD no
longer appears. The target display is the one under the pointer if controllable, else the
built-in. If brightness cannot be controlled the key passes through to macOS (Apple HUD only,
never SkyRose's volume OSD). The decision is the pure table `MediaKeyRouting.route`, tested
without the tap. `input.interceptMediaKeys` (default true) set to false restores the old
pass-through (both HUDs).

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
   New windows pop in from 85 % (`windowsIn`; 80 % in the first version) **only** from a still that shows them at their
   final size: the cache is checked and one capture is tried with a deadline of one frame. In
   practice there never is one (the window is new, so it is not even in the cached shareable
   content; live: 0 of 2 opens), so the new window is shown live through a hole cut in the
   cover's desktop backdrop at its final frame while its neighbours animate.
5. When every channel has settled (within 0.5 pt and under 40 pt/s) the cover fades out in 80 ms,
   showing the real windows exactly where the tiles were. Covers are pooled.

**Core Animation drives the tiles (round 4).** The first version positioned every tile from the
main thread on each display-link tick. Any main-thread stall (the commit's synchronous AX writes,
focus/raise, captures) froze the animation, which then jumped to where it should be ("plays half,
then snaps"). `SnapshotCover.sync` now mirrors every motion-model channel segment as a Core
Animation animation, so the render server plays it at display rate whatever the main thread does:
a spring segment becomes a `CASpringAnimation` with the same mass/stiffness/damping and the
initial velocity normalised by the travel; a Bézier segment a `CABasicAnimation` with the curve as
its timing function. Position channels are additive (`position.x/y`), `beginTime` is the segment
start and `fillMode` is backwards. A retarget replaces the channel's animation, starting from the
current presentation value and velocity: animations are interruptible and never queued.
`CATransaction.flush` runs before the AX writes. Related fixes from the same finding:
- A new change kind `.reveal`: a window that reappears is revealed live while the other tiles keep
  animating (before, it cancelled the whole cover and every moving window snapped to its end).
- `didChangeScreenParameters` (Dock or menu bar changes) invalidates running animations only when
  display frames really changed.
- Motion starts one display refresh after a new cover has been composited (before, the first
  20-40 % of the motion happened off-screen).
- A settled cover waits at most 150 ms for the fresh capture of a window that was resized.
- `WindowAnimator.frameApplied`: when a write reads back a frame the app chose itself (a refused
  size), the animation retargets to the real frame, so the cover never fades onto a different
  size (before, a refused-size window's tile faded onto a smaller real window).

The workspace slide (`WorkspaceSlide`) is Core Animation too. Its "snappy" Bézier (0.05, 0.9, 0.1,
1.05) covered 62 % of a full-screen slide in its first 7 % of the time (about 900 pt in one
frame), so slides use the spring now; key presses no longer abort a slide (clicks and scroll
still do) and the timeout scales with the duration.

Timings (`gabby-springy`): the new `Spring.snappy` (mass 1, stiffness 800, damping 46; ζ ≈ 0.81,
≈ 1.2 % overshoot, settles in 303 ms) drives `windowsIn` (popin 85 %), `windowsMove` and all
workspace slides. `windowsOut` is a 180 ms accelerating shrink and fade, fade/fadeDim 200 ms,
border 240 ms: nothing in the window set runs over 350 ms (it was the riko spring, about 593 ms).
The curve name `spring` now means snappy; `riko` is still available. `animations.speed` (default
1.0, range (0, 10]) divides durations and combines with `globalMultiplier`. Reduce Motion turns
the window table into 120 ms fades and the shell into fades of at most 120 ms without slides.
Every shell panel also fades in and out (`ShellPanel.fadeIn`/`fadeOut`, window-server alpha)
together with its slide; a fresh panel renders its hidden state first.

### Liquid motion (2026-11-05)

Caelestia feels liquid because things overshoot and squash, not because they are slow.
`CaelestiaCore/Motion/LiquidMotion.swift` holds every number; each spring is built from a damping
ratio and a settling time (|x − 1| < 0.001), so nothing runs over ~350 ms:

- Windows: `windowsIn` = ζ 0.58 spring from popin 80 % (swells to ≈ 102 %, settles in 300 ms);
  `windowsMove` = ζ 0.72 (≈ 3.9 % swing past the slot), 300 ms; `windowsOut` unchanged (240 ms
  accelerating shrink + fade). No anisotropic squash on the cover (composing a second
  `transform.scale.y` animation on the snapshot layers was not safe enough).
- Workspaces: back to Arch's snappy Bézier (.05, .9, .1, 1.05), 320 ms, as the phase brief asks.
  It front-loads (≈ 55 % of the travel in the first 60 Hz frame) and overshoots 0.85 %; the
  spring it replaced was smoother but not Arch's curve.
- Shell drawers (`Support/LiquidDrawer.swift`): the frosted body scales out of its edge on a
  spring tuned to swing ~16 pt past full size whatever the drawer's depth (overshoot 2.5–8 %),
  settling in 380 ms × 0.8 = 304 ms. Its "neck" along the edge starts at 84 % and widens on a
  critically damped spring 10 % slower, so the joint to the frame stretches and settles. Drawers
  spanning a whole edge (the sidebar) have no neck, as in Caelestia. Content rides the same
  spring as an offset and fades in 30 ms after the body starts. Panels are `overshootRoom` points
  bigger on the far side (transparent, click-through) so the swing is not clipped; the panel alpha
  comes in over 50 ms instead of a 180 ms cross-fade. Closing keeps `emphasizedAccel` (shrinks
  back into the frame) with the panel fade.
- Bar: `ShellTween` gained a spring mode that keeps its velocity when retargeted. The reveal is
  ζ 0.62 (≈ 8 %), 304 ms; the screen frame's band may swell up to reveal 1.12 while springing,
  and the bar content moves by half the swell so it stays centred. Hiding keeps the Bézier.
- Toasts: insert = slide from the trailing edge + scale 80 % + fade on the drawer spring; removal
  shrinks and fades.
- Reduce Motion: no scale, no offset, no swell; the panels cross-fade (≤ 120 ms) and the window
  table is the 120 ms fade table, as before.

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
- Total animation (first version, riko spring): open ~690–750 ms, retile/swap ~595 ms, close
  ~600–660 ms, leave ~605 ms. With the snappy spring (round 4, 60 fps recordings): window
  open/close covers 326/336 ms, a drag swap 331 ms (about 8 pt overshoot), slides 300-370 ms.
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
pass instant (`InstantWindowAnimator` behaviour). Debug aid: `SKYROSE_DUMP_STILLS=<dir>` in the
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
is calibrated by eye (`skyrose frame calibrate`), never derived from screenshots: a screenshot
contains the pixels the hardware corner hides. `ConfigFileEditor` writes the one key into the
user's config.toml without rewriting it.

## D19. Native drags and resizes of tiled windows

A title-bar drag or edge resize of a tiled window looks to AX exactly like the app moving its own
window. The first version re-applied the slot twice (`maxSnapBackRetries = 2`) and then gave up,
leaving the window overlapping its neighbours. The event tap now reports left-button press and
release (`onLeftMouse` → `WindowManager.pointerPressed` / `pointerReleased`; a 30 Hz pointer poll
is the fallback). While the button is down on a tiled window nothing is written. On release:
- a move returns the window to its slot, swaps it with the window under the drop point, or moves it
  to the active workspace of another display;
- an edge resize changes the split ratio (re-derived from the tree at drag start; the neighbours
  follow live at 30 Hz) instead of leaving the window free;
- late AX notifications within a 0.6 s grace are re-applied, not treated as new drags.

Floating windows stay where dropped. An app that keeps moving or resizing its own tiled window is
re-applied up to 2 times and then left until the reconcile pass (1 s, or the next wake / Space
change) puts it back. It stays tiled. Counters: `snapBacks`, `nativeDrops`, `nativeResizes`,
`autoFloats` (always 0), `minSizesLearned`, `reconciles`, `splitFlips`, `monocleLayouts`.

## D20. Minimum window sizes

AX exposes no minimum-size attribute (probed on Finder, Firefox, T3 Code, kitty, Cursor and
Teams: only `AXSize`), so a minimum is learned from frame read-backs and accepted only when a
second, identical read-back confirms it. `DwindleTree.layout(area:params:minSizes:)` then gives
the side of a split the room its minimum needs (`minimumAwareFirstSize`); stored ratios are not
changed, so the layout returns to normal when the window goes. Gaps and borders are counted
conservatively, so a window may get a few points more than its minimum (825 for an 800 one).
When it is impossible, `Placement.overflows` is true and the frame stays inside its slot (it does
not cover the neighbour). The WM then tries the other split direction, and if that still cannot
fit, stacks the workspace so one window fills the area and the others are parked. Nothing is
floated for lack of room. A per-app hint (`appMinSizes`, a max over the app's windows) seeds new
windows of the same app but never floats one: a hint that would overflow is dropped. There is
never a resize loop; an app that refuses to shrink stays tiled at the best fit (LIMITATIONS).
`skyrose doctor` prints the tiling notes (`query state`'s `tilingNotes`).

## D21. Per-app window rules

`AppRuleBook` (`CaelestiaCore/Rules/AppRules.swift`) decides tile or float per bundle id.
Precedence, highest first: dialogs, sheets, pickers, popovers, utility panels and fixed-size
windows always float (subrole heuristics), even with "tile"; the user's `[appRules]` entry in
config.toml (`"bundle.id" = "tile" | "float" | "auto"`, quoted keys); the built-in floating list
(`AppRuleBook.builtInFloating`: System Settings, Calculator, Archive Utility, System Information,
Digital Color Meter, Screen Sharing, Installer, Print Center, Font Book, Bluetooth File Exchange,
location/password/system prompts, login window, iPhone Mirroring); `rules.toml`; then the
heuristics. Calculator was removed from the tag 50-60 rule (it floats at its own size).

The API for the future Settings app is on `WindowManager`: `appRuleEntries()`,
`appRuleEntry(for:)`, `focusedAppRule()` and `setAppRule(_:for:)`. `setAppRule` persists through
`ConfigFileEditor` (quoted keys, comments preserved; clearing the last rule removes the empty
table, so set then clear leaves the file unchanged) and applies at once to open windows. IPC:
`rules.apps`, `rules.set`, `rules.focused`; CLI `skyrose rules apps|set <bundle>
<tile|float|auto>|focused`.
