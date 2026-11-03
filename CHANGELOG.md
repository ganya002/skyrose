# Changelog

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
