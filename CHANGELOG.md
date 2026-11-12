# Changelog

## Unreleased

- **Fix: `skyrose ws focus` and `ws move` work with CatWM.** They changed SkyRose's own workspace state, which is not what shows when CatWM is the engine, so nothing happened.
- **SkyStore app addons.** A new addon kind, `app`, installs a whole macOS app from reviewed source: SkyRose checks the Mac (Apple Silicon, macOS version, free disk), offers Apple's Command Line Tools installer when needed, downloads only pinned and SHA-256-checked runtimes, builds the app with `xcrun swift build`, signs it ad hoc and starts it as its own process. Every step shows on the Store card, with real bytes, speed and time left. Off, panic and revocation stop the app; `skyrose store uninstall <id> --purge` also removes its data. First-party only for now. New: `skyrose store setup <id>`, the `microphone`, `accessibility`, `keychain` and `login` permissions, and `SKYROSE_HOME` for isolated test runs. An index with a kind this SkyRose does not know no longer breaks the Store.

## 0.5.0 (2026-11-12)

CatWM tiles the windows, and the bar takes over Wi-Fi, Bluetooth and Control Center. https://github.com/ganya002/skyrose/releases/tag/v0.5.0

- **CatWM is the window manager.** Window management powered by CatWM by Per William Krogstad-Østensen (@noxaur), https://github.com/noxaur/CatWM, used with permission. SkyRose keeps its bar, panels, binds and IPC; CatWM tiles the windows (Hyprland dwindle with `togglesplit`, `swapsplit`, `pseudo`, `pin` and special workspaces). SkyRose's own engine stays available as `[wm] engine = "skyrose"` (work in progress, not recommended).
- **Settings › CatWM.** The settings window morphs into a CatWM panel: the engine switch (with a restart button), the layouts the cycle bind steps through and the start layout, drag to swap and resize, floating for small windows and chosen apps, and extra CatWM config lines. These live in `[wm.catwm]`.
- **Fix: floating windows no longer vanish** when sent to another workspace (or group). They used to stay parked off-screen when that workspace was shown.
- **Smooth window motion.** Workspace slides and tiling moves run at the display's refresh rate (60 fps on a MacBook Air, 120 on a ProMotion MacBook Pro). The display link no longer lets macOS drop to 30 fps, and borders follow an animation without querying the window server every frame (ticks went from ~8 ms to under 1 ms).
- **Motion options in Settings › CatWM.** Curve (SkyRose's, ease-out, ease-in-out, linear, spring, bounce, overshoot), speed (SkyRose's, fast, normal, slow) and bounciness: `[wm.catwm] motionStyle`, `motionSpeed`, `motionBounce`.
- **Volume and brightness display in Caelestia's layout.** Two tall sliders slide out of the right edge, joined to the frame. The knob shows the percentage while the value moves; drag and scroll change it; it hides after 2 seconds.
- **Media tab in Caelestia's layout.** Round cover art that turns while playing, inside a radial visualiser fed by the real audio spectrum; title, album and artist; transport with the round play-pause; a seek bar with a handle and times; the source pill (brings the player forward), player switch and close; lyrics; the bongo cat on the right. Works with any Now Playing source.
- **Wi-Fi that works from the bar.** Hover the network icon for the connected network, strength and frequency; click for the full panel: Wi-Fi on/off, scan, join open and secured networks (password field with show/hide, Enter joins, wrong-password error), leave, forget, and live Connecting/Connected/Failed states. Passwords go straight to macOS (CoreWLAN) and are never stored or logged by SkyRose. `skyrose wifi status|on|off|scan|connect|disconnect|forget`. Scanning needs Location: it is in onboarding and the permissions pages.
- **Bluetooth panel.** On/off, paired devices with battery levels, connect/disconnect on click, pair new devices (PIN and number confirmation), forget. `skyrose bluetooth status|on|off|connect|disconnect`. Bluetooth permission is in onboarding.
- **Controls button** (`bar.controlsButton`, under the status icons): Wi-Fi, Bluetooth, SkyRose Do Not Disturb (with a link to macOS Focus, which apps cannot switch), Night Shift, Low Power Mode (macOS asks for an administrator password: `pmset` needs root), AirDrop (opens the AirDrop window; who can see you is set there, as there is no API for it), volume and output/input device pickers with mic mute, brightness, keyboard input source, now playing, and other apps' menu bar items. On macOS 26 and later every menu bar item is drawn by MenuBarAgent, and third-party items were not reachable through Accessibility in testing: the panel then says so and Super + Shift + B shows the real menu bar for 5 seconds.

## 0.4.1 (2026-11-11)

The SIP-off helper without Terminal, a restart command, and a closer Caelestia look. https://github.com/ganya002/skyrose/releases/tag/v0.4.1

- **SIP-off helper card.** When SIP-off mode is on and the helper is not loaded, a card offers Enable. It uses the standard macOS password prompt; SkyRose never sees the password. Root only runs a root-owned, signature-checked copy of the loader. "Do it in Terminal instead" opens the command with a Copy button. `skyrose sa enable` and Settings › SIP-off mode show the card again.
- **Boot daemon (opt-in).** "Do this automatically every restart" installs a LaunchDaemon that loads the helper at boot. It runs as root; every file it uses is root-owned. Uninstall with `sudo /bin/sh "/Library/Application Support/SkyRose/uninstall-sa-daemon.sh"`.
- **Menu bar in SIP-off mode** can be removed completely, and a peek puts it back.
- **`skyrose restart`.** Quits SkyRose (windows restored), waits for it, and starts the same app again; starts it if it is not running. Also Settings › About › Restart, the session menu's last button, and `>restart` in the launcher. SkyRose is now always started by path, so a copy in another account is never launched.
- **Hover focus** never raises or picks a window hidden behind the one under the pointer (no more Teams flicker behind OneNote).
- **Caelestia parity.** Dashboard tabs, cards, media arc and calendar; launcher, sidebar and bar sizes and colours from the upstream source. Notifications and toasts grow out of the top-right corner of the frame. Utilities has a screen recorder card (status, timer, recent recordings); the `record.screen` bind now works. Drawer timings re-measured frame by frame on the reference recordings.
- **Clipboard** picker rebuilt, with configurable limits. **Borders** follow windows that resize themselves and no longer shift by half a point. **Media**: browsers and other players through Now Playing, the bongo cat hears the kick in a full mix, lyrics found when the album name is wrong.
- **Release zip** `SkyRose-0.4.1-arm64.zip` with the two apps, `install.sh`, and `uninstall.sh`, plus detached `.sha256` files. Signed with the local identity, not an Apple Developer ID, and not notarized. Earlier tags are unchanged.

## 0.4.0 (2026-11-10)

Focus, a shorter setup, and a clipboard. https://github.com/ganya002/skyrose/releases/tag/v0.4.0

- **Resize.** A keyboard or tiling resize finishes on a fixed ease-out (default 150 ms, scaled by `animations.speed`; 0 snaps). The size is committed once and only the origin eases, so the window stays sharp. A mouse-edge drag tracks the cursor. Glide (`animations.windows = "snapshot"`) is the default again.
- **Borders.** Each window's own corner radius, read from SkyLight when SIP is on. The stroke is even on all four sides.
- **No end flash.** Drawers and popouts are ordered out while they are still transparent, so they do not blink back for a frame.
- **Cursor follows focus.** Keyboard, workspace, launcher and close focus move the pointer to the window. A click, a drag, a held button, or a pointer already inside the window does not. See docs/FOCUS.md.
- **Focus follows mouse.** Hover focuses after `focusFollowsMouseDelayMs` (default 100). Floating windows are not raised unless `raiseOnHover` is on. Invisible overlays are not the window under the pointer.
- **Setup.** First run is mode, permissions, one Use recommended button, then optional kitty and fonts. `skyrose doctor --fix` repairs a missing config, a Dock or menu bar SkyRose had hidden, an empty cursor setting, and a leftover socket. It cannot tick permission boxes. The installer is one Install button.
- **SIP-off assistant.** Settings lists only this Mac's Recovery and Terminal steps, with Copy and a QR code. SkyRose still never changes SIP or NVRAM.
- **Menu bar.** Settings › Appearance: Shown, Auto-hide, or Off. Off stops reserving the bar and keeps the notch. With SIP on, the top edge can still reveal Apple's bar. ⌥L⇧B shows it for 5 seconds.
- **Clipboard.** ⌥V opens a local history of text and images. Return pastes, ⇧Return copies. Concealed and transient items are never stored. Uninstall removes the history.
- **Media.** The dashboard cat follows system-output beats only while the dashboard is open. Synced lyrics come from LRCLIB and are cached on this Mac. Either can be turned off in Settings › Bar and Shell.
- **Release zip** `SkyRose-0.4.0-arm64.zip` with the two apps, `install.sh`, and `uninstall.sh`, plus detached `.sha256` files. Signed with the local identity, not an Apple Developer ID, and not notarized. Tags `v0.2.0` and `v0.3.0` are unchanged.

## 0.3.0 (2026-11-09)

Shipped defaults and an updater. https://github.com/ganya002/skyrose/releases/tag/v0.3.0

- **Bibata Modern Classic** ships inside the app (GPL-3.0) and is the cursor for a new config. The wait cursor stays macOS's until logout. Settings › Appearance › Cursor can put the macOS cursor back. The theme is re-applied for the login session.
- **Dock.** A recommended tweak hides the Dock (a long autohide delay, then `killall Dock`) without unloading it, so Mission Control keeps working. `skyrose dock show|hide|status`. The original values are journaled and put back on uninstall. The launcher opens apps; the bar shows what is running. Dock stacks, recent items, and the Downloads folder are not replaced.
- **Starter wallpapers.** The copier can place a SkyRose collection in `~/Pictures/Wallpapers/Static/` without overwriting a file or a duplicate hash, and uninstall removes only those copies. This release ships none: the candidates were fan art without a redistribution license.
- **Updates.** `skyrose update [--check] [--yes]` and Settings › About. The check only notifies. `--yes` or Install verifies SHA-256 and replaces the two apps, keeping config, the journal, and wallpapers. No downgrade. A bad checksum or no network keeps the current install. A daily check is off unless you turn it on.
- **Corners.** Onboarding can skip a calibration step. Settings › Appearance and `skyrose corners calibrate` show a live outline on each display. A slider or the arrow keys set the radius; external screens start square; a notched built-in screen starts at 10 pt on the top corners. Saved per display UUID and applied without restarting the WM.
- **Release zip** `SkyRose-0.3.0-arm64.zip` with the two apps, `install.sh`, and `uninstall.sh`, plus detached `.sha256` files. Signed with the local identity, not an Apple Developer ID, and not notarized. Tag `v0.2.0` is unchanged.

## 0.2.0 first public build (2026-11-09)

Install and uninstall, from https://github.com/ganya002/skyrose/releases/tag/v0.2.0

- **Release zip** `SkyRose-0.2.0-arm64.zip` with `SkyRose.app`, `SkyRose Settings.app`, `install.sh` and `uninstall.sh`, plus detached `.sha256` files. Signed with the local identity, not an Apple Developer ID, and not notarized. No Homebrew cask.
- **install.sh** checks Apple Silicon and macOS 14, verifies the zip's SHA-256, then copies the apps to `~/Applications`. In a terminal it opens the SkyRose installer window. `--yes` stays in the terminal. `--dry-run` changes nothing.
- **Uninstall** with `skyrose uninstall` or Settings › Backup & uninstall. It puts back the restore manifest, including symbolic hotkeys and per-display wallpapers, and waits for the SIP reminder before anything is trashed.

## Unreleased: Arch parity

### Added
- **Hyprland-exact dwindle geometry** (gaps_out partition, then gaps_in on interior sides only),
  `gapsOutSingle` 20, split on the longer side, preserve_split, pseudo, togglesplit, swapsplit,
  float centring, a minimum tile size (windows that do not fit float centred).
- **Edge and corner hover reveals** as captured (Caelestia `Interactions.qml`): dashboard from the
  top band, utilities from the bottom-right corner (now its own drawer), OSD from the right edge,
  100 ms dwell; the session menu dims the screen.
- **Red button quits the app** (Settings › Windows, off by default, per-app exceptions, Finder by
  default).
- **Appearance › Cursor**: Bibata Modern Classic (Mousecape cape) for the login session; the wait
  cursor stays macOS's; `skyrose cursor list|status|set|reset`; reset on every WM quit path.
- **WM restarts keep every window on its workspace and side** (`session.json`).

### Changed
- Opacity 0.95, bar 60 pt, border colour fade 480 ms (Arch), close 240 ms, popin 80 %.
- Settings: window corners match the WM rounding (15), the sidebar is an inset concentric panel;
  "SkyRose is running" is live; a second WM instance waits for the first and then exits.

### Fixed
- Corner calibration: the Auto/Manual control was squeezed into a column next to the slider.

## 0.2.0 "SkyRose" (2026-11-04)

The project is renamed from "Caelestia for Mac" / CaelestiaWM to **SkyRose** (brand) and
**SkyRose WM** (window manager). Entries below this one use the old names as they were at the time.
Swift module names (`CaelestiaCore`, ...) are unchanged.

### Added
- **Rename.** `SkyRose.app` (executable `SkyRoseWM`, bundle id `com.skyrose.mac`, LaunchAgent label
  `com.skyrose.mac`), `SkyRose Settings.app` (`com.skyrose.mac.settings`), CLI `skyrose`.
  `caelestia` still works as a deprecated alias for one release and prints a notice. Paths:
  `~/.config/skyrose`, `~/Library/Application Support/SkyRose`, `~/Library/Logs/SkyRose`;
  `backup.json` is now `restore-manifest.json`; kitty theme file `skyrose-theme.conf`; env vars
  `CAELESTIA_*` are now `SKYROSE_*`; schemes `skyrose-default` / `skyrose-dynamic` /
  `skyrose-dynamic-dark` (old `caelestia-*` names still accepted). `TestWindows.app` is unchanged.
- **One-time migration** of the old config, data, logs and kitty theme on the first SkyRose start
  (also `skyrose migrate`); skipped while the old CaelestiaWM is running.
- **SkyRose Settings app**: General, Appearance, Windows, Window rules, Keybinds, Bar and Shell,
  Terminal, Permissions, About. Changes apply live; when SkyRose is not running it writes
  `config.toml` directly.
- **Onboarding** (first run; re-run from Settings > General or `skyrose onboarding`): Welcome, Mode,
  Permissions (Accessibility, Input Monitoring, Screen Recording; live status, opens the exact
  pane), Recommended macOS tweaks (auto-hide Dock / menu bar; only on click, undoable, recorded in
  the restore manifest), Done with a cheat sheet. When a permission is lost later only that step is
  reopened. `--simulate-missing a,b` / `SKYROSE_SIMULATE_MISSING` simulate missing permissions for
  testing.
- **WM-only mode and module toggles**: `[general] mode = "full" | "wm"` (WM-only = tiling, binds,
  borders; no bar, shell or frame); `[shell] enabled` plus per-module toggles (launcher, dashboard,
  sidebar, session, osd, notifications, wallpaperPicker); `bar.show*` module toggles;
  `wm.bordersEnabled`; `animations.reduceMotion` (animations become short cross-fades).
- **Config API over IPC** (protocol version 2): `config.get`, `config.set`, `config.reset`
  (comments kept, validated, rolled back if invalid, applied live), also `skyrose config get|set|reset`.
- **`keys.pause`** (hotkeys pass through for a few seconds so Settings can record a chord) and
  **`permissions.request`** (ask macOS for a permission from the WM process and open its pane).
- **Terminal choice** (kitty / Rex / other) in Settings and `[apps] terminal`. The `app.*` launch
  actions (terminal, browser, editor, files, audioSettings, exec) are now actually handled; before
  this they were bound but unhandled and did nothing.
- **Restore manifest** recording system changes made by SkyRose, and the **SIP reminder popup**
  component (shown for at least 5 s, cannot be dismissed early) for the future uninstaller.
- New app and Settings icons.
- **Permission status without the WM.** `SkyRoseWM --permissions-probe <file>` reports SkyRose's
  own grants and exits. Settings starts it through Launch Services, so macOS checks SkyRose's
  grants and not Settings', every 2 s while the WM is not running or busy. The cards stay live,
  and "Open System Settings" still adds SkyRose to the list (`--request <kind>`).
- SkyRose Settings floats by default (built-in window rule).

### Fixed (from live testing in this phase)
- The onboarding window floated over Settings and blocked it. It is now a normal window.
- Onboarding said "SkyRose is not running" while the WM was running but busy, for example
  tiling every window right after Accessibility was granted. A request timeout now counts as
  "busy", not "not running", and the permission status comes from the probe meanwhile.
- `skyrose onboarding` / `skyrose settings` did nothing when Settings was already running
  (`open --args` drops arguments). They now message the running app.

### Changed
- IPC protocol version 1 to 2; version 0.1.0 to 0.2.0. A mismatched CLI/WM is refused.
- Docs, schema and README renamed to match.

### Limits / not yet
- The **uninstaller is not built** (`skyrose uninstall` only prints manual steps; there is no
  `scripts/uninstall.sh`). **SIP-off mode does not exist.**
- The bundle id changed, so macOS treats SkyRose.app as a new app: **permissions must be granted
  again** (Accessibility, Input Monitoring, Screen Recording).
- `scripts/sign-setup.sh` now creates "SkyRose Local Signing"; an existing "Caelestia Local
  Signing" certificate is kept and used.
- Seen live, not fixed (comes from round 4, not this phase): switching between WM-only and full
  mode can make the WM learn a false minimum width. The app briefly reports its old size while
  the layout changes, so a 50/50 split can end up about 48/52.
- The permission probe was tested with all three grants on. Settings and the probe report the same
  values, but a real "missing" grant was only simulated (`--simulate-missing`), not revoked.
- Not in this phase: screenshot tool, clamshell handling, kitty / fonts / cursor / Rex setup,
  installer, SIP-off mode, module store, full uninstaller.

Tests: 848 passing (764 before this phase).

## Unreleased — Core fix round 4 (2026-11-04)

From real-hardware testing on the MacBook Air + DELL U3417W. Recordings (60 fps, `.mp4` with
per-frame PNGs in `frames/` and a `track.json`) are in `/tmp/cwm/fix4/`.

### Fixed
- **Tiling snap-back (critical).** A native title-bar drag or edge resize of a tiled window looked
  like the app moving its own window; the WM re-applied twice (`maxSnapBackRetries = 2`), gave up
  and left it overlapping. Now the event tap reports left-button press/release (`onLeftMouse` →
  `WindowManager.pointerPressed` / `pointerReleased`, plus a 30 Hz pointer poll fallback). While
  the button is down on a tiled window nothing is written. On release a move returns to the slot,
  swaps with the window under the drop point, or moves to the active workspace of another display;
  an edge resize changes the split ratio (live, neighbours follow at 30 Hz, re-derived from the
  tree at drag start) instead of leaving the window free; late AX notifications within a 0.6 s
  grace are re-applied. Floating windows stay where dropped. An app that keeps moving or resizing
  its own tiled window is re-applied up to 2 times, then auto-floated (centred, clamped
  on-screen) instead of fought. New counters: `snapBacks`, `nativeDrops`, `nativeResizes`,
  `autoFloats`, `minSizesLearned`.
- **Animations "play half, then snap".** Root cause: the snapshot cover's tiles were positioned
  from the main thread every display-link tick, so any main-thread stall (synchronous AX writes in
  the commit, focus/raise, captures) froze the animation and it jumped to where it should be.
  Also fixed: a reappearing window cancelled the whole cover (every moving window snapped to its
  end); a `didChangeScreenParameters` notification (Dock/menu bar) invalidated running animations;
  motion started before a new cover reached the screen (first 20-40 % skipped); the workspace
  slide's "snappy" Bézier (0.05, 0.9, 0.1, 1.05) covered 62 % of a full-screen slide in its first
  7 % of time (~900 pt in one frame); key presses aborted slides mid-way.
  - `SnapshotCover.sync` mirrors every motion-model channel segment as a Core Animation animation
    (`CASpringAnimation` with the same mass/stiffness/damping and normalised initial velocity, or
    `CABasicAnimation` with the Bézier as timing function; additive `position.x/y`, `beginTime` =
    segment start, `fillMode` backwards), so the render server plays it at display rate. Retargets
    replace a channel's animation from the current value and velocity (interruptible, never
    queued). `CATransaction.flush` before AX writes.
  - New `.reveal` change kind: shown windows are revealed live, the others keep animating.
  - Screen-params invalidation only when display frames really change.
  - Motion starts one refresh after a new cover is composited; a settled cover waits up to 150 ms
    for a resized window's fresh capture.
  - Workspace slides are Core Animation too; keys no longer abort them (clicks/scroll still do);
    the timeout scales with the duration.
- **Refused-size windows**: when a write reads back a frame the app chose itself, the animation
  retargets to the real frame (`WindowAnimator.frameApplied`), so the cover never fades onto a
  different size (before, a refused-size window's tile faded onto a smaller real window).
- **Brightness keys showed the volume OSD.** On the built-in panel brightness was "unavailable"
  through public APIs, so the OSD opened with only its volume slider. See OSD / media keys below.
- **Keep awake IPC.** Verified with `pmset -g assertions`: `PreventUserIdleDisplaySleep named:
  "Caelestia keep awake"` is held by CaelestiaWM while on and gone when off. The assertion code
  was correct; the IPC commands `shell.idleInhibitor.toggle` / `enable` / `disable` / `isEnabled`
  were declared but unhandled (only the sidebar toggle worked). Now handled.

- **Bug sweep before commit.** A live edge resize restored the tree from drag start even if a
  window had opened or closed meanwhile (it would have been dropped or resurrected): now only
  while the window set is unchanged. Delaying motion until a new cover is composited also froze
  windows on another display whose cover was already up: now limited to the new covers. Setting
  then clearing an app rule left an empty `[appRules]` header in config.toml: the editor now
  removes a table left empty, so the round trip leaves the file unchanged.

### Added
- **Minimum window sizes.** AX exposes no minimum-size attribute (probe of Finder, Firefox, T3
  Code, kitty, Cursor, Teams: only `AXSize`), so minimums are learned from frame read-backs,
  confirmed by a second identical read-back. `DwindleTree.layout(area:params:minSizes:)` gives a
  split side the room its minimum needs (`minimumAwareFirstSize`; stored ratios unchanged;
  gaps/borders counted conservatively, so a window may get a few points more than its minimum,
  e.g. 825 for an 800 minimum). `Placement.overflows` when impossible: the WM floats the newest
  overflowing window, centred and on-screen. A per-app hint (`appMinSizes`) seeds new windows of
  the same app but never floats a window (live finding: one TestWindows window's 800 pt minimum
  floated every new window of the app; fixed, the hint is dropped when it would overflow). Never
  a resize loop. Firefox's minimum width (~512 pt) was learned live and its split widened.
- **Window rules per app**: config.toml `[appRules]`, bundle id = `"tile"` | `"float"` | `"auto"`
  (quoted keys). Built-in floating apps (`AppRuleBook.builtInFloating`): System Settings,
  Calculator, Archive Utility, System Information, Digital Color Meter, Screen Sharing, Installer,
  Print Center, Font Book, Bluetooth File Exchange, location/password/system prompts, login
  window, iPhone Mirroring. Dialogs, sheets, pickers, popovers, utility panels and fixed-size
  windows always float (subrole heuristics), even with "tile". Calculator removed from the tag
  50-60 rule (floats at its own size). API for the future Settings app:
  `WindowManager.appRuleEntries()`, `appRuleEntry(for:)`, `focusedAppRule()`,
  `setAppRule(_:for:)` (persists through `ConfigFileEditor`: quoted keys, comment-preserving;
  clearing the last rule removes the empty table, so set+clear leaves the file unchanged; applies
  at once to open windows). IPC `rules.apps` / `rules.set` / `rules.focused`; CLI
  `caelestia rules apps|set <bundle> <tile|float|auto>|focused`.
- **OSD / media keys.** DisplayServices (private framework, `dlopen`: `DisplayServicesGet` /
  `Set` / `CanChangeBrightness`; `BrightnessChanged` when present) controls built-in/Apple
  displays (target: display under the pointer if controllable, else built-in). The event tap
  intercepts `NX_SYSDEFINED` aux keys (volume up/down/mute, brightness up/down) and swallows them
  when Caelestia can do them (CoreAudio volume settable / DisplayServices brightness): it applies
  volume (1/16 steps, ⌥⇧ quarter steps, unmute on volume up) and brightness itself and shows only
  Caelestia's OSD, so Apple's HUD no longer appears. Brightness uncontrollable: the key passes
  through to macOS (Apple HUD only, never Caelestia's volume OSD). Config
  `input.interceptMediaKeys` (default true; false = old pass-through, both HUDs). Pure routing
  table `MediaKeyRouting.route`.
- `animations.speed` (default 1.0, range (0, 10]): durations ÷ speed, combined with
  `globalMultiplier`.
- Every shell panel (launcher, dashboard, sidebar, session, popouts, wallpaper picker, OSD, toasts,
  frame calibration) fades in and out (`ShellPanel.fadeIn` / `fadeOut`, window-server alpha)
  together with its slide; a fresh panel renders its hidden state first.

### Changed
- Timings (`gabby-springy` preset): new `Spring.snappy` (mass 1, stiffness 800, damping 46;
  ζ ≈ 0.81, ≈ 1.2 % overshoot, settles in 303 ms) for `windowsIn` (popin 85 %), `windowsMove` and
  all workspace slides; `windowsOut` 180 ms accelerating shrink+fade; fade/fadeDim 200 ms; border
  240 ms; nothing in the window set over 350 ms (was the riko spring, ≈ 593 ms). The curve name
  `spring` now means snappy; `riko` is still available.
- Reduce Motion: window table → 120 ms fades; shell: ≤ 120 ms fades, no slide.

### Tests
- 764 XCTest tests, 0 failures (was 661). New: `NativeDragTests`, `MinSizeWMTests`,
  `AppRulesWMTests`, `MinSizeLayoutTests`, `AppRuleTests`, `MediaKeyRoutingTests`,
  `MediaKeyInterceptorTests`, `AnimationGuardTests`, `RulesCLITests`, `SnapshotCoverSyncTests`,
  plus `BrightnessService.stepped`, `frameApplied` / retarget and config round-trip tests.

### Verified live (60 fps recordings, `/tmp/cwm/fix4/`)
- Title-bar drag back to its slot: 292 ms (cover), no snap. Drag-to-swap: 331 ms cover, ~283 ms
  motion, ~8 pt spring overshoot. Edge resize tracked at ~30 Hz, no jump at release.
- Window open/close covers 326/336 ms, no end-of-cover jump after the retarget fix.
- Workspace slide ≈ 300-370 ms with a spring ramp (36, 53, 50, 47 … mean-diff steps).
- OSD in 250-283 ms, out 167-183 ms; launcher/dashboard/session/sidebar in 117-283 ms, out
  150-167 ms.
- Keep awake assertion present/absent via `pmset -g assertions`.

### Known limits
See LIMITATIONS.md: minimums only learned after a refusal, apps that refuse to grow, app-closed
windows vanishing at once, dropped first frames of a slide under WindowServer load, one dropped
frame at drawer opening, no retarget across workspace switches, external displays not
brightness-controllable.


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
