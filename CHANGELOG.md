# Changelog

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
