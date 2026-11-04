# Changelog

## Unreleased — Corner fit, round 2 (2026-11-04)

From the user's photos of the MacBook Air after 8a7fea2: the bottom-right corner showed a small
wedge of wallpaper outside the frame's rounded outer corner. A frame corner rounded *more* than the
hardware leaves pixels uncovered that the hardware still shows, so the panel's bottom corners are
square or much tighter than 10 pt (notched MacBook panels round their top corners).

### Changed
- Top and bottom corners have separate radii: `frame.displayCornerRadius` (top) and the new
  `frame.displayBottomCornerRadius` (also per display). Auto top: 10 pt on a built-in panel with a
  notch (`DisplayInfo.hasNotch`, top safe area > 0), 0 elsewhere (pre-notch MacBook panels are
  square; this replaces the "built-in Apple Silicon" rule). Auto bottom: 0 on built-in panels,
  else the top value.
- Inner corners where the outer corner is rounded are now concentric: outer − band (was outer +
  band, which made the band ~1.8× wider on the corner diagonal). With the 10 pt default and the
  10 pt band the top inner corners are square. A test measures the band along the diagonal.
- `caelestia frame calibrate`: Tab switches between the top and bottom corners (the pair being
  tuned is drawn bright, the other dim); Return saves only the values that changed, each under its
  own key.
- Tests: 661 passing.

### Not verified
- Not checked live on the hardware this round (unit tests only); the shell was not started. The
  10 pt top radius is still an eyeballed default, to be tuned with `caelestia frame calibrate`.

## Unreleased — Fixes from real-hardware testing: corners, stretched stills, edge jumps (2026-11-04)

Verified live on the MacBook Air (notch) + DELL U3417W with TestWindows only, on workspace 4.
Frame sequences, videos and screenshots are in `/tmp/cwm/fix3/`. The build was signed with
"Caelestia Local Signing"; no permission was re-granted, nothing installed, no system setting
changed. The calibration's test `~/.config/caelestia-mac/config.toml` was removed afterwards.

### Added
- `frame.displayCornerRadius` (global) and `[displays."<uuid>"] displayCornerRadius`: the screen
  frame's outer edge follows the display's rounded physical corners (only at corners that are real
  display corners), and its inner corners there use outer radius + band. Auto (`-1`): 10 pt on a
  built-in Apple Silicon panel, 0 on externals (`DisplayInfo.isBuiltIn` from `CGDisplayIsBuiltin`).
- `caelestia frame calibrate [display]` (IPC `frame.calibrate`): a bright 1.5 pt outline along the
  display edge plus a live-updating frame; ↑/↓ ±0.5 pt, ⇧ ±0.1 pt, ←/→ other display, Return
  saves each changed display's value into config.toml (one key, comments and other settings kept;
  `ConfigFileEditor`), Esc cancels. Live: ↑×4 then ⇧↓×5 read 12.00 → 11.50; Esc wrote nothing;
  Return saved 11.5 (built-in) and 1.0 (DELL) into their tables, replacing earlier values, and the
  toast confirmed both.
- Tests: 653 passing (109 new, including the cover-flip regression test; the bar-reservation tests that expected a retile were rewritten to expect none).

### Fixed
- **Windows jumped when the pointer reached an edge**: revealing the auto-hidden bar reserved its
  width and retiled (dwindle could flip the split, moving windows up and down). An auto-hidden
  bar and every drawer now overlay the windows; only a persistent bar reserves. Live: a frame log
  at 50 Hz during left/right/top edge hovers showed exactly one frame per window; the bar slid in
  over the windows (`/tmp/cwm/fix3/edges-sheet.png`). Tests drive the real shell pointer path and
  every drawer and assert no frame changes and no layout pass.
- **Stretched / low-res windows on open, focus and app switch**:
  - Stills are never scaled to another aspect: drawn 1:1, anchored top-left and clipped to the
    tile over the still's average colour, then cross-faded (120 ms) to a fresh capture at the
    new size once the app has redrawn (attempts 40–400 ms after the commit).
  - Opens pop in only from a still at the final size within one frame; otherwise (in practice
    always: 0 of 2 live opens) the new window is shown live in its slot through a hole in the
    cover while the neighbours animate. The old path waited for a capture and popped in from a
    buffer of the wrong size.
  - Focus changes, snap-backs (frame re-applied unchanged), app activation, hide/unhide,
    minimize/unminimize and windows found at start never animate. Live: activating either of two
    TestWindows apps, hiding and unhiding one and moving focus with the pointer produced no
    animation at all; hide/unhide retiled instantly.
- **Snapshot cover drew stacked windows swapped top-to-bottom** (found live in this phase; the
  last phase only tested side-by-side layouts): AppKit owns the flip of a view's backing layer,
  so the cover now draws in its own flipped root layer. Recorded open/close on the DELL with a
  vertical split now shows every tile in place (`/tmp/cwm/fix3/open2-sheet.png`,
  `close2-sheet.png`). This may be part of what looked "stretched" on real hardware.

### Measured
- Commit latency unchanged: 16.7–17.7 ms; animations ~585–603 ms.
- One-frame open capture: never hit, because new windows are not in the cached shareable content.

### Known limitations
- Opens no longer pop in in practice (see above); the brief allowed skipping when no correct-size
  capture exists within a frame.
- App switch / hide / minimize passes are instant, including the neighbours' retile.
- The corner radius is a by-eye value; the auto 10 pt is a starting point, not a measurement.
- With outer radius R and band b the user-specified inner radius R + b makes the band about 1.8 b
  wide on the corner diagonal (a strictly even band would need R − b); it can be revisited after
  calibrating.

## Unreleased — Notch-aware frame, window animations, shell part 2 leftovers (2026-11-04)

Verified live on the MacBook Air (1470x956, notch) + DELL U3417W (3440x1440) with TestWindows on
a separate workspace. Frame sequences, video frames and screenshots are in `/tmp/cwm/anim/`. The
build was signed with "Caelestia Local Signing"; no permission was re-granted. No system setting
was changed; the temporary `~/.config/caelestia-mac/config.toml` used for the watcher/colour checks
was removed again.

### Added
- **Notch-aware screen frame**: an even 10 pt band on every side; on a display with a cutout the
  top band dips around it with rounded inner corners instead of a dark full menu-bar strip.
  Cutouts come from `NSScreen` (safe-area top strip minus `auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea`), never from a model list, so any number/shape works; externals get the
  plain band. Windows still keep clear of the safe-area strip (reserved top 42 on the Air, 10 on
  the DELL); dashboard/sidebar/popouts start below a cutout only where they overlap it; a menu bar
  set to always show moves the frame below it. Hot-plug re-evaluates (display equality includes
  the cutouts). `DisplayInfo.topCutouts`, `shownMenuBarHeight`.
- **Window animations** (`animations.windows = "snapshot"` default, `"off"`): Hyprland-style
  springs/beziers from the animation table (`windowsMove`, `windowsIn`, `windowsOut`, speed and
  curve from `[animations]`). A per-display overlay cover shows ScreenCaptureKit stills of the
  windows (and the desktop behind them) moving from the old to the new frames; the real windows
  get their final frame once underneath, then the cover fades out (80 ms). Covers retile, swap,
  open (pop-in from 80 %), WM close (shrink + fade), moving to another workspace (fade), and drag:
  a dragged tiled window's still follows the pointer live with a lift and shadow, a tinted drop
  preview shows the slot, and the drop animates the swap. Borders are drawn on the tiles, the real
  border windows snap underneath. Instant fallback when a still is missing, Screen Recording is
  not granted, or animations are off (game mode, Reduce Motion, preset off).
- `WindowAnimator` protocol (`CaelestiaOverlay/WindowAnimation`): the hook an Enhanced-mode (SIP
  off) animator would implement; documented in ENHANCED_MODE.md, not implemented.
- Notification history is kept across restarts in
  `~/Library/Application Support/CaelestiaMac/notifications.json` (the app's existing support
  folder rather than a new `Caelestia` one; latest 100, atomic writes).
- `CAELESTIA_DUMP_STILLS=<dir>` debug aid (stills as PNG + capture timing).
- Tests: 545 passing (67 new: cutout detection, notch frame path and drawer clearance,
  motion model, WM ↔ animator integration with a fake animator, config watcher on a missing
  directory, notification history file).

### Measured (release build, 60 Hz)
- Extra latency before the real windows move: 16.8–19 ms (one display refresh); 0 ms when a cover
  is already up. Putting the cover on screen: 2.4–8.5 ms.
- Animation length with the default table: open ~690–750 ms, retile/swap ~595 ms, WM close
  ~600–660 ms, leave ~605 ms; a 1.2 s drag plus drop took ~2.3 s from press to cover gone.
- Captures (background only): window p50 17.6 ms, p90 73.5 ms (n = 215); desktop p50 123 ms,
  p90 261 ms (n = 14).
- Recorded sequences (`/tmp/cwm/anim/loop-*`, `*-video/` at 60 fps) of open, retile, close, drag
  and leave: no frame shows both a still and its real window, a gap where a window should be, or a
  half-drawn window.

### Fixed
- **Bar and drawer clicks with a real pointer** did nothing: `NSHostingView.hitTest` returns the
  hosting view itself for every point, so "pass through where SwiftUI is empty" passed every click
  through. Panels now take clicks inside their frame. Verified with CGEvent clicks at the real
  cursor: audio and Wi-Fi icons open their popouts, the clock opens the dashboard.
- **`config.toml` created while the daemon runs** is now picked up: the watcher watches the
  nearest existing parent directory and re-arms as directories appear (live: creating, deleting
  and re-creating `~/.config/caelestia-mac/config.toml` applied/reverted within 3 s).
- Window stills sized from live CG bounds and the window's own display scale (stale shareable
  frames and the highest-display `pointPixelScale` gave squeezed or partial stills).

### Verified live
- Borders follow dynamic colours: active ring #bbc4e7 static → #bac4f3 dynamic on the same pixel
  (blue wallpaper, so the shift is small), applied on config change without restart.

### Known limitations
- Closes done by the app itself (⌘W, red button) animate only the neighbours: macOS removes the
  window before the WM hears of it.
- Stills are pictures: content is stretched while a window changes size and can be a few seconds
  old; the first pass after start (no stills yet) is instant.
- Group bars are not drawn on the cover; other apps' floating-level windows are hidden under the
  cover while it is up (~0.6 s).
- Background refresh captures each visible window every 4 s while idle (≈ one 18 ms capture per
  second with four windows).

## Unreleased — Shell part 2: dashboard, sidebar, popouts, wallpaper, dynamic colours (2026-11-04)

Verified live on the MacBook Air (1470x956, one display this run) with TestWindows; screenshots and
reference comparisons are in `/tmp/cwm/shell-p2/`. The build was signed with the "Caelestia Local
Signing" certificate and Accessibility, Input Monitoring and Screen Recording were still granted
after the rebuild. The user's wallpaper was restored afterwards and the temporary `config.toml`
removed. No system setting was changed.

### Added
- **Dashboard** (`caelestia shell dashboard`, `shell drawers toggle dashboard`, the bar clock,
  `panels.showAll` / `dashboard.toggle` keybinds): a top drawer sized from the reference (860x560, scaled
  down uniformly on small screens). Tabs Overview, Media, Performance.
  - Overview: weather card (placeholder "Weather not set up": no weather service), user card
    (initial avatar, macOS version, uptime), vertical clock with seconds (`dashboard.showClockSeconds`),
    month calendar (arrows, scroll, today as a cookie), CPU / memory / storage gauges, media card.
  - Performance: CPU and memory with 60 s history, storage, GPU (IOAccelerator, shown only when it
    reports), network down/up, battery (only on a Mac with a battery, `dashboard.showBattery`),
    thermal pressure. Temperatures in degrees are hidden: they need root or private API.
  - Media: big cover, progress, controls. Reads Spotify and Music (AppleScript). MediaRemote is
    restricted to Apple processes on current macOS, so no other player is shown; the tab says so.
  - Sampling runs at 1 Hz only while the dashboard is open.
- **Sidebar** (`shell sidebar`, `sidebar.toggle` keybind): right drawer with notification history
  (our own toasts and `caelestia notify`, grouped by app, dismiss, clear all, in memory only), Keep
  awake, volume and brightness sliders (brightness hidden when unavailable) and quick toggles.
  Real toggles: Wi-Fi (CoreWLAN), Do-not-disturb (Caelestia's own toasts), Keep awake. Bluetooth and
  dark mode show their state and open System Settings (no public API to switch them).
- **Bar popouts**: clicking the audio / network / Bluetooth / battery status icon opens a drawer
  next to the bar (audio output picker + volume + mute, Wi-Fi switch + on-demand scan, Bluetooth
  state and connected devices, battery state). Also `shell drawers toggle popout.<kind>`.
- **Wallpaper picker** (`>wallpaper`, `shell drawers toggle wallpaper`, sidebar button): thumbnail
  strip from `appearance.wallpaperFolder` (default `~/Pictures/Wallpapers`), thumbnails made off the
  main thread and cached in `~/Library/Caches/CaelestiaMac/wallpaper-thumbs`. A missing or empty
  folder shows a message. Picking sets the wallpaper on every display. `caelestia wallpaper
  set|get|list|random` and `>random` work too.
- **Dynamic colours**: `appearance.schemeMode = "static" | "dynamic"` (default static = periwinkle).
  Dynamic extracts a Material You tonal-spot scheme from the current wallpaper (Wu quantizer, source
  scoring, CAM16/HCT tonal palettes, all in `CaelestiaCore/Palette`, no packages) and applies it live
  to the frame, bar, launcher, session menu, dashboard, sidebar, OSD, toasts and the border overlay.
  Grey or unreadable wallpapers fall back to static; `appearance.accentOverride` pins the source;
  `appearance.variant` picks dark/light. `caelestia config reload` applies mode changes live.
- Config: `appearance.schemeMode`, `[dashboard] showClockSeconds, showBattery, defaultTab`.
- IPC: `shell.dashboard|sidebar|showall|clear-notifs`, `shell.notifs.*`, `notify`,
  `shell.wallpaper.set|get|list`, `wallpaper.random`; drawers `dashboard`, `sidebar`, `utilities`,
  `wallpaper`.
- Tests: 478 passing (46 new: HCT/quantizer/scheme determinism and fallback, config keys, wallpaper
  scan, drawer sizing on notched/external/ultrawide/small/portrait screens, calendar, clock,
  notifications, quick toggles, system-stat parsers).

### Fixed
- Panels now accept the first click (`acceptsFirstMouse`), as they are never key or active.

### Not verified live
- Clicking the bar status icons and clock with a real pointer: synthetic mouse events were not
  reliable in this harness, so popouts were opened through the IPC route. The click code path is
  the same `Button` the logo uses.
- A real Spotify/Music session in the media card, the Wi-Fi switch and scan, the Keep awake switch
  (these change system state), and a second display.
- A new `config.toml` created while the daemon runs was not picked up within 2 s; `caelestia config
  reload` applied it.

### Known limitations
- No Weather tab or weather data, no screen recorder card, no opening the dashboard from the top
  edge, no bongo-cat art, avatar is an initial (not the account picture).

## Unreleased — Shell part 1 + borders fade on move (2026-11-04)

Native SwiftUI/AppKit shell (`CaelestiaShell`) wired into the WM daemon via `ShellBridge`.
Verified live on the MacBook Air (1470×956) plus an external Dell U3417W (3440×1440), stopped
with `caelestia wm panic`. Screenshots and reference comparisons are in `/tmp/cwm/shell-p1/`.
No system setting was changed: this Mac already auto-hides the menu bar and the Dock.

### Changed
- **Borders no longer trail a retile.** When a window starts moving (retile, bar reveal, drag,
  app resize) its border fades out in place (70 ms), stays hidden until the frame has been still
  for 150 ms, jumps to the final frame while invisible and fades in (140 ms). Frames are never
  interpolated. Live trace over a bar-reveal retile: the border x was only ever 20 or 58, hidden
  between 0.03 s and 0.14 s, fully back at 0.25 s. With animations off, borders snap with the
  window.
- **The bar replaces the frame band on its edge**: the left reservation is max(frame, bar) = 48,
  not 10 + 48. An auto-hidden bar reserves its width while it is revealed (Caelestia's
  exclusive zone), so windows retile around it. Added `WindowManager.setBarRevealed`.

### Added
- **Screen frame**, one click-through panel per display: 10 pt band, inner radius 25, surface at
  0.75 over a behind-window blur. On notched Macs it also covers the menu-bar/notch strip, and a
  revealed menu bar draws above it.
- **Left bar** (`bar.persistent = false` by default): slides in when the pointer touches the left
  band and widens it to 48 pt, then hides 0.25 s after the pointer leaves. Top to bottom:
  - logo (opens the launcher);
  - workspace pills (click to focus, scroll to switch);
  - active window icon and vertical title;
  - tray button (reveals the auto-hidden menu bar);
  - HH/MM clock;
  - status icons (Caps Lock, audio, network, …);
  - power button (opens the session menu).
- **Launcher** (left ⌥ tap, ⌥Space, `caelestia shell launcher`): a bottom-centre drawer with
  concave fillets into the frame, sized from `1-launcher.jpg` (600×57 rows, pitch 65, 32 pt icons,
  48 pt search pill, at most 7 rows).
  - fzf-style fuzzy search, ranked by how often each app is launched;
  - `>` commands and an `=` calculator (Enter copies the result);
  - ↑/↓, Tab, ⌃J/⌃K, Enter, Esc; a click outside closes it;
  - the panel is non-activating, so focus stays with the previous app.
- **Session menu** (⌃⌥⌫, the power button, `caelestia shell session`): a right-edge pill with
  Log out, Shut down, an image slot, Sleep and Restart. Every action needs a second press
  within 3 s. It uses public routes only (System Events, `pmset sleepnow`); lock posts ⌃⌘Q.
- **OSD**: a right-edge drawer with volume and brightness sliders, shown on change and hidden
  1.5 s after the last one.
- **Toasts**: top-right, up to 4, shown for 5 s.
- IPC: `shell launcher|session|kill|restart`, `shell drawers toggle|isOpen|list`,
  `shell toaster *`, `shell brightness get|set`. The shell answers `shell.*` IPC before the WM.
- R5: surfaces are re-asserted on display change, wake, Space change and screen-parameter
  change, immediately and again after 0.3 s. Live: after `shell restart`, the frame and bar were
  back on both displays within 400 ms.
- Tests: the suite is now 432 tests, all passing. New: 102 in `CaelestiaShellTests`, plus
  `ShellIntegrationTests` and new border move-fade tests. Older tests that expected the spring
  or the 58 pt reservation were updated. Docs: `docs/SHELL.md`, and `docs/LIMITATIONS.md` updated.

### Fixed during the live test
- The screen frame blurred the whole display: the window server ignored the cap insets of the
  9-slice blur mask. The blur is now masked by a `CAShapeLayer`.
- The panel fill sat under the blur subview and never showed, so panels looked light grey. The
  fill now has its own view above the blur, and the darkest material (`underWindowBackground`) is
  used. The launcher measures #14151a against the reference's #141821.
- The panels were at level 3: `isFloatingPanel` resets the level, so it is now set before the
  level (mainMenu − 1 for the frame and bar, popUpMenu for drawers).
- The vertical window title showed its end instead of truncating its tail.
- A new launcher query now selects the first result.

### Known limitations
- Rubik, Inter, CaskaydiaCove and Material Symbols are not installed, and nothing was installed:
  the shell falls back to SF Pro and SF Symbols. Bundling Material Symbols is still TODO.
- The session image slot is a drawn moon glyph (no character art).
- macOS's own volume/brightness HUD also shows, and there is no public way to hide it.
- The brightness slider is hidden when `BrightnessService` reports it unavailable (as on this
  setup).
- Other apps' menu extras can't be shown in the tray.
- Bar hover popouts are not built yet.
- The bar ignores `CGWarpMouseCursorPosition`, because it posts no mouse-moved events. Real
  pointer movement works.
- The dashboard, sidebar, Settings app, wallpaper/dynamic colour and the "Make it look like Arch"
  wizard are not built.

## Unreleased — P4 overlay: borders, animations, group bars, workspace slide (2026-11-03)

`CaelestiaOverlay` is built and wired into the WM daemon. Verified live on the MacBook Air with
real ⌥1/⌥2 keystrokes, screenshots and screen recordings (`/tmp/cwm/p4/`). Shell not started.

### Added
- **Borders**: one click-through, non-activating panel per visible managed window, ordered directly
  above it. 1 pt, 15 pt corners (+1 for the ring), active `#bac5ee` @ 90 %, inactive `#a9aab5` @ 7 %
  (the "current" scheme). Only changed borders are redrawn; the display link stops when idle.
- **Animations** (Motion module, `animations` preset, Reduce Motion, game mode = off):
  pop-in from 80 % on the riko spring (`windowsIn`), retile on the riko spring with velocity kept
  across retargets (`windowsMove`), fade-out + shrink on close/minimize (`windowsOut`,
  emphasizedAccel 240 ms), active/inactive color blend (`border`). Windows the user or the app
  moves (floating drags, snap-backs) are tracked 1:1 from CGWindowList, no spring lag.
- **Group bars**: one tab per member (active primary, inactive outline, locked variants, onPrimary
  text, height 25, gaps 3, rounding 5); the layout reserves the strip (`wm.groupBarHeight`,
  `wm.groupBarGaps`).
- **Workspace slide** (spec 4.7): the layout waits (≤ 120 ms, hard cap 300 ms in the WM) for a
  ScreenCaptureKit still of the outgoing workspace, a cover shows it, the WM lays out behind it,
  and the outgoing and incoming stills slide (snappy 320 ms, 20 pt gap; special workspaces
  slidefadevert 15 %). The cover goes after the animation, on any input, or after 600 ms. Without
  Screen Recording: a surface-colored cross-fade.
- **Debug overlay**: `caelestia debug overlay [on|off]` draws usable areas, every target frame with
  id/kind/size, and counters (layout passes, setFrame, borders, surfaces, slides).
- `caelestia query overlays` (`query.overlays`): one entry per border window (Riko R2).
- Tests: `CaelestiaOverlayTests` (41: animated values, engine, controller R2 bookkeeping,
  geometry) and `OverlayIntegrationTests` + `SlideKeyTests` (16: scenes, pop-in once, fade vs.
  instant, retile spring, drag tracking, group bar, slide gate, R2 across every scenario and 300
  random steps, panic, game mode, IPC).

### Fixed during the live test
- **Ghost borders for windows on another native Space** (R2). Finder/Firefox windows on another
  Space are managed; after ⌥2/⌥1 their recreated borders appeared on the current Space. Borders
  are now drawn only while their window is on screen (re-checked per scene, 150 ms later, and on
  Space changes).
- **Empty incoming slide**: a still taken right after the layout showed only the wallpaper (apps
  redraw un-parked windows a few frames later). The incoming still is now the one taken when that
  workspace was last left, used only if its content key (window ids, frames, focus) is unchanged;
  otherwise the outgoing still fades out over the real windows.
- New borders are ordered straight above their window (no one-frame flash at the front).
- The floating-window path now schedules a layout so the border follows a user move.
- Debug overlay drew upside down (AppKit owns the backing layer's flip).

### Live results
- R2: CGWindowList borders owned by CaelestiaWM == on-screen managed windows after launch, open,
  ⌥2/⌥1 (×4), 24-step open/close/switch churn, and SIGKILL of TestWindows. 1 s after each.
- R1: no black frame in any slide or pop-in frame. The pixel scan is inconclusive on this desktop:
  T3 Code / Grok Bot draw pure #000000 areas (a 200 px black square is there before the WM starts).

### Known limitations
- Standard mode: real windows snap; on a retile the border springs to the new frame (~0.5 s), so
  it briefly trails the window. `wm.animatedTiling` (interpolated AX frames) is still not built.
- The first ScreenCaptureKit capture on macOS 15+ shows a system "bypass the private window
  picker" prompt; until it is allowed the slide is skipped (never a black frame).
- The incoming still can show slightly stale app content (it is from when the workspace was left).
- The WM manages windows on other native Spaces (their borders now stay hidden); not changed here.
- `scripts/sign-setup.sh` was run: builds are signed "Caelestia Local Signing" and keep TCC grants.

## Unreleased — WM live-test fixes (2026-11-03)

First live run on the MacBook Air (1470×956). The first test was run while CatWM was also running
in the background. Re-tested without it, launched with `open dist/CaelestiaWM.app`, with real
⌥1/⌥2 keystrokes. Screenshots are in `/tmp/cwm/`.

### Fixed
- **Bug 1, discovery found only kitty and Grok Bot.** Not a bug in discovery. At the time Firefox
  and Terminal had no windows, T3 Code was minimized, and Finder only had its desktop. With real
  windows open, all 8 were managed (kitty, Grok Bot, Finder, TextEdit, 4 TestWindows). Regression
  test added.
- **Bug 2, `query windows` didn't match the screen.** Root cause: two WMs (CatWM + Caelestia)
  moving the same windows, while the query printed the frame Caelestia *asked for*. The query now
  reports the real AX frame, so it always matches the screen (verified live, including parked
  windows on hidden workspaces).
- **Bug 3, thin white vertical line after ⌥1/⌥2.** Not reproduced without CatWM: workspace 2 is
  clean and ⌥1 brings every window back to the same frame. Note: macOS keeps at least
  1 × 28 pt of a parked window on screen. Caelestia already parks in the bottom-right corner, so
  the most you can see is a 1 pt sliver there. The future Shell screen frame will cover it.
- **Bug 4, `open dist/CaelestiaWM.app` silently did nothing.** Launched without a terminal, it
  exited on a missing Accessibility grant, writing only to stderr. It now shows an alert (Open
  System Settings / Quit), opens the pane, and starts by itself as soon as access is granted. The
  text also names the newer pane title, "Device Control and Data Access".
- **Tile with a large minimum width went off screen** (found during the re-test). Finder needs
  475 pt; centred on its 350 pt slot at the left edge, it landed at x = −44. Tiles are now
  shifted back inside the usable area, keeping their size.

### Added
- `LaunchChecks`: the daemon refuses to start, with an alert, while another known window manager
  is running (CatWM, AeroSpace, yabai, Amethyst, chunkwm, Spacey).
- App icon for `CaelestiaWM.app` (night sky, crescent moon, tiled windows), generated by
  `scripts/make-icon.swift` into `Packaging/CaelestiaWM.icns`, so the new build can be told apart
  in System Settings.
- `LiveTestRegressionTests` (5 tests).

### Notes
- `dist/` is ad-hoc signed: every rebuild invalidates the Accessibility and Input Monitoring
  grants. Remove the old entries (`tccutil reset Accessibility com.caelestia.mac.wm`,
  `tccutil reset ListenEvent com.caelestia.mac.wm`) and grant the new build again, or run
  `scripts/sign-setup.sh` once so grants survive rebuilds.

## Unreleased — WM daemon (CaelestiaWMKit + CaelestiaWM) (2026-11-03)

Tiling now works end to end in code: window discovery, dwindle tiling, workspaces 1–10 (and the
groups up to 50) plus special workspaces, focus/move/resize binds through the hotkey engine,
off-screen parking, crash restore and the panic chord. All of it is covered by headless tests over
fake windows/displays; **the daemon has not been run against a real screen yet.** Overlay and
Shell were not started.

### Added
- `CaelestiaWMKit`
  - `WindowSystem` / `WindowHandle` / `DisplayProvider` protocols. `AXWindow`, `WindowDiscovery`
    (via `AXWindowSystem`) and `DisplayMonitor` are the real implementations; tests use fakes.
  - `WindowManager` (main actor): owns `WorkspaceState`. One coalesced layout pass per run-loop
    turn. A frame is written only when its target changes. Our own AX echoes are ignored, minimum
    sizes are learned from read-backs (converges in ≤ 3 passes), and an app that snaps its window
    back is re-applied at most twice per target. Windows of hidden workspaces and inactive group
    tabs are parked 1 pt into a display corner. The journal record is written first, and a failed
    write leaves the window visible. Parked windows are re-parked when the display arrangement
    changes, so an old corner never shows on a new neighbour. Special workspaces and floating
    windows are raised when shown. Focus follows Hyprland `focus_on_close = 1` (window under the
    cursor, then history). macOS focusing a parked window (⌘Tab, Dock) switches to its
    workspace, except within 0.5 s of parking: that is macOS handing focus to a sibling, and
    following it would bounce back.
  - Windows: anything that is not an `AXWindow` (sheets, popovers) is ignored. Dialogs,
    fixed-size and non-standard windows float centred. Rules apply float/size/move/workspace/pin/
    noInitialFocus/noBorder (e.g. Spotify → `special:music`). Minimized windows and hidden apps
    leave the layout and come back to their workspace. Windows already minimized at start are
    managed once restored.
  - Displays: workspaces per display. A new display gets the next free workspace. Unplugging
    moves its workspaces to the primary. An empty display list (sleep/clamshell) is ignored.
    Usable area = frame − menu bar/notch − Dock − screen frame − bar (when persistent, on its
    edge), with per-display overrides.
  - Actions: every workspace/window/group action in `ActionKind` (focus/move/move-silent/groups,
    next/prev, specials, focus/swap across displays, keyboard resize as % of the window,
    ⌥L-drag move/resize, float, fullscreen, maximize, pin, PiP, normalize, center, close, group
    toggle/lock/next/prev/move-out). Shell/app/capture/media actions go to `onUnhandledAction`
    (logged).
  - Safety: `shutdown()` (quit, panic chord, `wm.quit`, `wm.panic`, SIGTERM/SIGINT/SIGHUP)
    restores every parked window, replays the rest of the journal and rescues any tracked window
    found off-screen. `start()` replays a left-over journal before discovery (crash restore).
    `wm.restoreAll` moves hidden workspaces' windows onto the visible workspace without
    quitting.
  - IPC handler: `ws.*`, `window.*`, `action`, `query.windows|workspaces|monitors|binds|state`
    (hyprctl-compatible fields, special workspaces −99/−98…), `keys.list`, `config.reload`,
    `rules.reload`, `wm.*`, `permissions.status` (read-only), `doctor`. Shell targets answer with
    an error.
  - `WMDaemon`: loads config/keymap/rules, then starts the WM, the event tap (hotkeys + panic
    chord), the IPC server, and hot reload of config.toml/keymap.toml. Exits with a message (and
    the system Accessibility prompt) when Accessibility is not granted.
- `CaelestiaWM/main.swift` runs `WMDaemon` (it only printed its name before).
- Tests: `CaelestiaWMKitTests` (32, all headless; 243 tests in total, all passing)
  - Tiling/workspaces/binds: clients.json golden frames through the WM, single-window gaps under
    the menu bar, split-on-focused, workspace switch parks and restores exact frames, ⌥L+1…0,
    move/move-silent, special toggle, focus/swap/resize binds through the real `ChordMatcher`,
    float/fullscreen, close focus, minimize/restore, ⌘Tab to a parked window, rules, display
    unplug, focus across displays, IPC queries/commands.
  - Riko R1–R6 (`RikoRegressionTests`), headless parts:
    - R1: 200 open/close/switch cycles; every shown tile is a real, non-empty, on-screen window
      at its tile frame, and nothing hidden is left on-screen. **Not covered:** ScreenCaptureKit
      pixel checks and panel alpha (need a screen and the shell).
    - R2: the WM's border model (`borderFrames`, what the overlay will draw) equals the visible
      windows after move/close/switch/unplug/SIGKILL'd app/sleep-wake. **Not covered:** real
      overlay windows in CGWindowList (Overlay not built).
    - R3: fully covered: 0 setFrame and ≤ 1 pass when idle; a min size bigger than its slot
      converges in ≤ 3 passes; snap-back and write-ignoring apps do not loop.
    - R4: fully covered at the WM level. The frames the windows actually receive, plus borders
      and gaps, tile the usable area exactly: 1–4 windows, 6 display sizes, menu bar hidden/33/
      38 (notch), Dock shown/hidden, bar persistent/auto-hide.
    - R5: WM side only. The bar's width is reserved on every display and edge after connect,
      disconnect, wake and config changes. **Not covered:** that the bar window is visible and
      correctly layered (Shell not built).
    - R6: covered with the fake window system: relaunch after kill -9 with parked windows puts
      all on-screen during `start()` and empties the journal. Also covered: vanished windows
      dropped, panic chord via the matcher, `wm.quit`/`wm.panic`, a failed journal write never
      parks, shutdown rescues off-screen windows.

### Changed
- **Bar default is now `persistent = false`**, matching the Arch `shell.json` (the bar overlays
  and slides in on hover; it reserves no width). Changed in `BarConfig` and
  `config.default.toml`. Set `[bar] persistent = true` for an always-visible bar that reserves
  its width. This deliberately departs from spec 5.2, which made `true` the Mac default.

### Small changes to existing modules (only these)
- `Package.swift`: added the `CaelestiaWMKitTests` test target.
- `CaelestiaCore/Config/Config.swift` + `Resources/config.default.toml`: the bar default above.
- Removed the placeholder `CaelestiaWMKit/Module.swift` (a one-line comment).
- No other module was edited. `WindowParker` is not used by WMKit, because it only works on
  `AXWindow`. WMKit parks through `ParkingJournal` + `ParkingPlanner` behind the `WindowHandle`
  protocol so the logic is testable.

### Not done / known limitations
- No live test yet: AX timing, focus stealing by real apps and echo filtering are untested on
  hardware.
- Workspace assignments are not persisted across a clean WM restart (spec 4.4); after a restart
  every window lands on the visible workspace of its display.
- Named scratchpads do not launch or fetch their app (`place_apps`); the special just opens.
- Native (green-button) fullscreen windows are ignored, and a window leaving native fullscreen is
  not picked up until its app announces it again.
- Windows that AX reports after their app's observer registers late are placed on the focused
  display, not the one they are on.
- Far more than ~10 windows on one workspace makes dwindle (CaelestiaLayout) hand out 0×0 slots.
  Apps clamp them to their minimum size, which overlaps.
- App launch binds (terminal, browser…), `exec`, capture and media actions are logged, not run.

## Unreleased — P0–P5 audit and repair (2026-11-03)

The previous run stopped partway through, and the 0.1.0 entry below overstated what had shipped
(see "Correction"). This pass fixed the build/test setup, filled in the testable gaps and added
the missing tests. It did not touch Overlay, Shell or the WM daemon.

### Fixed
- `Package.swift`: the Services target now declares `Resources` (bundled `emoji.json`), and
  `CaelestiaIPC/Schema.md` is excluded. The two "Source files for target … should be located
  under" warnings were caused by the empty `CaelestiaLayoutTests` and `CaelestiaServicesTests`
  folders (the paths were already correct) and are gone now that both have tests. The build has
  no manifest or compiler warnings.
- Default rules: VLC's bundle id was `com.videolan.vlc`; it is `org.videolan.vlc` (in both
  `rules.default.toml` and `RuleSet.defaults`), so VLC is now matched as an opaque media app.
- Removed `RulesDumpTests`, a debug test that wrote a file to a hard-coded per-machine temp path.
- CI also runs `CaelestiaServicesTests` (all pure, no hardware needed).

### Added
- `CaelestiaPlatform`
  - `Display/DisplayGeometry` (pure): NSScreen facts → `DisplayInfo` in top-left space. Covers
    menu bar vs. notch (`safeAreaInsets.top` stays reserved when the menu bar is hidden), Dock
    on any edge (the auto-hide sliver is ignored), reserved zones (screen frame + persistent
    bar), the display for a point/rect, and the neighbour display in a direction.
  - `Display/DisplayMonitor`: live `NSScreen` list with stable UUIDs, debounced refresh on
    screen-parameter, Space, wake, Dock and menu-bar auto-hide changes.
  - `Parking/ParkingPlanner` (pure): AeroSpace-style 1 pt corner parking that avoids
    neighbouring displays, off-screen detection, and a visible restore frame (frames from
    unplugged displays are re-centred and shrunk to fit).
  - `Parking/ParkingJournal`: on-disk crash journal (`parked-windows.json`). Each record is
    written before the window moves and removed after it is back. Re-parking keeps the first
    restore frame. A corrupt file is moved aside, never deleted.
  - `Parking/WindowParker`: park/unpark through AX, `restoreAll` (relaunch after a crash, panic,
    `wm restore-all`, uninstall) and `rescueOffScreen`.
  - `System/Permissions`: Accessibility / Input Monitoring / Screen Recording checks (no
    prompt), requests, and System Settings deep links.
  - `System/HIDKeyMapping`: preset B (Caps Lock → F18) applied on top of the user's existing
    `hidutil` mappings. The original mapping is backed up first and restored exactly (the old
    `capsLockRestoreMapping` would have wiped every user remap).
  - `System/DefaultsBackup`: journaled `defaults` writes plus restore-and-verify. Keys that were
    absent are deleted on restore.
  - `System/LoginItem`: `SMAppService.mainApp` wrapper.
- Tests (211 total, all passing; previously 5 suites, 4 of them placeholders)
  - Layout (42): golden numbers from `clients.json` on 5120×1440 (and checked against the fixture
    itself), the border overlay frame, the single-window 20 px gaps (off on special workspaces),
    3/4-window splits, the Air 13" case, an R4 coverage invariant (frames + gaps + borders tile the
    usable area exactly for 1–6 windows on six display sizes, with and without the menu bar),
    remove/swap/move/toggleSplit/ratio clamping/resize ±10/min-size clipping/groups/locked
    groups, and workspace state (group math, move/move_silent, bar list, specials,
    specialWsCloseAny, focus_on_close, float/pin/fullscreen, display hot-plug, Codable journal).
  - Platform (38): coordinate converter with displays left/right/above/below, negative origins
    and the notch; parking corners and journal crash-safety; hidutil parse/apply/restore with a
    fake `hidutil`; defaults backup/restore; `ChordMatcher` (⌥L vs ⌥R, Super tap timing and
    cancellation by typing or clicking, configurable tap window, panic chord with an empty
    keymap, secure input, lock screen, hot reload).
  - IPC (8): CLI parsing and usage errors, every target/function in `ipc-commands.txt` maps with
    the same arity, JSON-lines round trip, a real Unix-socket server/client exchange (socket
    mode 0600 checked), and "not running" detection.
  - Core: rules matching (settings/utility/file-dialog sizes, Bitwarden, PiP bottom-right,
    special-workspace assignments, opaque viewers, game tag, user overrides, shipped TOML ==
    built-ins), config (shipped TOML == built-ins, spec geometry, round trip, validation, hot
    reload within 1 s that keeps the last good config on a parse error), schemes (all four
    built-ins complete, spec colours, derived border/shadow/group-bar alphas, accent override,
    Caelestia JSON).
  - Services (7): battery parsing, throughput counter wrap, Wi-Fi bars, state storage, bundled
    emoji resource.

### Still missing (needed before P0–P5 are complete)
- `CaelestiaOverlay`: border overlays, group bars, workspace slide, debug overlay (P1/P4).
- `CaelestiaShell`: screen frame, bar, launcher, OSDs, session menu, lock (P5). Only
  `ShellContracts.swift` exists.
- ~~`CaelestiaWMKit` / `CaelestiaWM`~~: done, see the entry above (untested on hardware).
- Permissions first-run wizard UI (the checks are done; the window is not).
- Riko regression suite R1–R6 (12.2): the headless parts are done (entry above). The pixel,
  overlay-window and bar-window checks still need Overlay, Shell and a real screen.

### Correction to 0.1.0
The 0.1.0 entry listed displays, parking, permissions, defaults backup, hidutil, login item,
Overlay and Shell, and Layout golden tests. None of these existed in the tree. All except Overlay,
Shell and the daemon are added above.

## 0.1.0 — first native build (P0–P5 core)

- SwiftPM project, `scripts/build.sh` (signed bundles), `scripts/sign-setup.sh`, CI workflow.
- `CaelestiaCore`: config/keymap/rules/scheme TOML with hot reload, all 153 Hyprland binds
  mapped under modifier presets A/B/C, binds-coverage and no-hard-coded-binds tests, conflict
  checker (duplicates, macOS system shortcuts, app shortcuts, Option characters, missing keys),
  Motion module (Caelestia curves + the riko spring), backup journal, kitty theme writer.
- `CaelestiaLayout`: Hyprland dwindle (preserve_split, smart_resizing, groups, min-size
  clipping), workspaces 1–50 with Caelestia group math, special workspaces, golden tests from
  Gabby's `clients.json`.
- `CaelestiaPlatform`: AX window control, discovery with echo filtering, displays + the single
  coordinate converter, off-screen parking with a crash journal, permissions, defaults backup,
  hidutil presets, login item, event-tap hotkey engine with left/right modifier detection,
  Super tap, mouse/scroll binds, media keys, panic chord, secure-input awareness.
- `CaelestiaOverlay`: border overlays (active/inactive colours, 15 px corners, pop-in / spring
  move / fade-out), group bars, workspace slide, debug overlay.
- `CaelestiaShell`: screen frame, left bar, launcher, session menu, OSDs/toasts.
- `CaelestiaIPC` + `caelestia` CLI: `hyprctl`-style queries and every Linux IPC target.
