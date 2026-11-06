# Phase: launcher + wallpapers, SIP-off mode, then Material icons / screenshots / Clamshell (started 2026-11-05)

Resume here after a context reset. Read `docs/parity-progress.md` and `docs/arch-parity.md` first.
Strict order (Gabby is low on usage): 1 quick fixes → 2 wallpapers → 3 SIP-off mode → 4 Material
Symbols → 5 screenshots, keep-awake, Clamshell. Commit on main after each part (not pushed).

## Status

| Part | State | Commit |
|---|---|---|
| 1. Launcher index + empty-workspace jump | done, live-checked | see `git log` ("Phase 5 part 1") |
| 2. Wallpaper subfolders + live wallpapers | done, live-tested | see `git log` ("Phase 5 part 2") |
| 3. SIP-off mode | done, live-tested in the Dock (3b) | "Phase 5 part 3a", "3a-fix", "3b" |
| 4. Material Symbols | done, live-checked (dashboard + sidebar) | "Phase 5 part 4" |
| 5. Screenshots, keep-awake, Clamshell | 5a screenshots done, live-tested; 5b keep-awake timers done, live-tested; 5c Clamshell done (lid-closed path unit-tested only, needs a dock) | "Phase 5 part 5a", "5b", "5c" |

**Phase 5 is complete.** Next: whatever Gabby picks; candidates are in "Remaining (next phases)" in the
archive section below and in `docs/arch-parity.md`. Open item for 5c: live-test lid closed with a power
adapter + external display (see "Part 5c" below).

## Part 1 — done

- `AppIndex` (Shell/Launcher): own apps first (SkyRose.app from `Bundle.main`, even though it is
  LSUIElement, and SkyRose Settings next to it or via Launch Services), then the roots
  (/Applications, ~/Applications, /System/Applications(+Utilities), /Applications/Utilities,
  /System/Library/CoreServices/Applications) **3 sub-folder levels deep** (never inside a bundle,
  no symlinked dirs), Finder pinned, then Spotlight hits. First copy of a bundle id wins.
  `AppIndex.isIndexable(path:)` drops Spotlight hits inside another bundle, in hidden folders
  (Trash, .build), caches/containers/Application Support/Developer/DerivedData, /Volumes (DMGs),
  /private, /usr, /opt and /System/Library (except CoreServices/Applications and Finder).
- `AppIndexWatcher`: live `NSMetadataQuery` (`kMDItemContentTypeTree == 'com.apple.application-bundle'`)
  + FSEvents on the roots (works with Spotlight off); every change rescans once, debounced 1 s.
- Launching the SkyRose entry opens SkyRose Settings (SkyRose is this process and has no window);
  `>settings` now opens SkyRose Settings (was a "not built yet" toast).
- Bug fix: closing the launcher/session menu calls `ShellHost.shellKeyDrawerClosed(launched:)`;
  the WM ignores macOS focusing a **parked** window for `focusGuardInterval` (0.5 s) afterwards,
  so the re-activated previous app no longer drags the display to its workspace. Launching an app
  from the launcher clears the guard (that app is followed).
- Live: launcher on the built-in (empty ws1), typed "skyrose" via `CGEvent.postToPid` to SkyRose
  only: SkyRose, SkyRose Settings, TestWindows listed (`/tmp/cwm/phase5/launcher-skyrose.png`);
  after closing, the built-in stayed on ws1. The ws 3 → 4 jump itself is unit-tested
  (`testClosingAKeyDrawerDoesNotFollowTheReactivatedApp`); reproducing it live needs a parked
  window on the built-in while Gabby's kitty holds focus on the DELL, skipped.

Decisions: DMG apps (/Volumes) are not listed; Bundle's info cache means an app renamed in place
shows its new name after a WM restart.

## Part 2 — done

- `WallpaperLibrary.scan`: the folder and sub-folders 3 levels deep, hidden files, packages,
  symlinked dirs and non-media (.md notes) skipped; `ScanResult.groups` (`""` = top level,
  then "Live", "Live/Anime", "Static" by name) + flattened `urls`. Videos: .mp4/.mov/.m4v.
- `LiveWallpaper.swift`: `LiveWallpaperStill` (AVAssetImageGenerator first frame → JPEG in
  `Application Support/SkyRose/live-stills/<key>.jpg`, cached by path/mtime/size);
  `LiveWallpaperPolicy` (pause on battery, Low Power Mode, every window covered, screens
  asleep / session inactive); `LiveWallpaperRecord` (`live-wallpaper.json`, resumed at shell
  start only while macOS still shows our still); `LiveWallpaperController` (one muted
  `AVQueuePlayer` + `AVPlayerLooper`, one borderless window per screen at desktop level + 1,
  i.e. under the Finder's icons, all Spaces, click-through; rebuilt on screen changes).
- `setWallpaper(video)`: still → desktop picture on every display (lock screen, Mission Control,
  colour extraction all read it) → video loops above. Picking a picture stops it and forgets the
  record; `shell kill` stops it but keeps the record. `wallpaper get` returns the video.
- Picker: group chips (All / Live / Static with counts) + play badge on video thumbs (first
  frame). Settings › Appearance › Wallpaper: one grid per group, badge, "Choose…" accepts movies.
- Test-only: `SKYROSE_LIVE_WALLPAPER_ON_BATTERY=1` (env at launch) ignores the battery rule.
- Live (Gabby's `Live/Sky - Aurora at dawn.mp4`, on battery): paused on the first frame
  ("paused (on battery)" in the log) and the still was the desktop picture on both displays;
  with the override: "playing … on 2 display(s)", two crops 2 s apart differ, WM CPU 1.6 %;
  a WM restart resumed it. Restored `~/Pictures/arch-mac-blue.png` with its original options
  (scaling 3, clipping, fill colour) afterwards; record cleared, no live windows left.
  Shots: `/tmp/cwm/phase5/live-battery.png`, `picker.png`. Not live-tested: the "covered" pause
  (needs a window covering a whole display; unit-tested in the policy).

Decisions: no config key for "play on battery" (the brief says pause); the first occlusion
report can log one "paused (covered by windows)" before the windows are on screen.

## Part 3 — SIP-off mode (done)

Verified first (2026-11-05): `csrutil status` = Custom Configuration with Filesystem, Debugging
and NVRAM protections disabled; `nvram boot-args` = `-arm64e_preview_abi`; macOS 27.2 (26B123), arm64.

- `Packaging/sa/`: `trampoline.s`, `loader.c` (`skyrose-sa-loader`, no arguments, sudo, invoking
  user's Dock only), `payload.c` (`SkyRoseSA.dylib`). `scripts/build-sa.sh` (arm64e), called by
  build.sh into `SkyRose.app/Contents/Resources/sa/` (ad-hoc signed before the bundle seal).
  Protocol and safety: docs/ENHANCED_MODE.md › How it works.
- Swift: `CaelestiaPlatform/Enhanced/ScriptingAddition.swift` (`SAClient`, `SAProtocol`),
  `CaelestiaWMKit/EnhancedMode.swift` (`EnhancedMode`, `EnhancedWindowAnimator`), hooks in the
  layout pass (instant switch hide/restore, `layoutApplied`), the slide gate, the close action,
  `shutdown()` (reset), daemon wiring (animator swap on `onChange`), `query state` mode.
- `[sipOff]` config: enabled=false, animations, opacity, shadows, instantWorkspaces, pinOnTop.
- `SIPOffReadiness` (Core): parses csrutil + boot-args. CLI `skyrose sa status | load-command |
  reset`; `skyrose wm panic` also sends `reset` + `stop` straight to the SA socket.
- Settings › SIP-off mode (`SIPOffPage`): warning, status, sudo line + Copy, switch locked until
  the showcase's "I understand the risks" (`@AppStorage sipOffShowcaseSeen`), per-feature
  switches, how to turn SIP back on. `SIPOffShowcase`: live side-by-side demos (animations,
  opacity/shadows, instant workspaces, pinning) + risks. `--sip-off-showcase` opens it.
- SIP reminder flag: `EnhancedMode.probe()` calls `RestoreManifest.recordModeUsed(.sipOff)` the
  first time the SA answers.
- Tested without the Dock: payload loaded into a throwaway arm64e host process with its own
  window (`SKYROSE_SA_SOCKET` override): hello listed all 5 capabilities on macOS 27.2; info
  read the window server transform convention translate(-x,-y); `visual` drew the 400×332
  window at 200×166 at (700,360) with alpha 0.9 (`/tmp/cwm/phase5/sa-visual.png`); alpha/level
  went back when the client disconnected; freeze/thaw ok. Settings page + showcase shots:
  `/tmp/cwm/phase5/settings-sipoff.png`, `showcase.png`.
- **Next (after Gabby loads the SA):** `skyrose sa status`; `skyrose config set sipOff.enabled
  true` with `sipOff.opacity false` (opacity would touch Gabby's kitty); TestWindows only (float
  rule): pop-in, move, close, pin on top, alpha via the socket; `skyrose wm panic` → everything
  restored; then flip the macOS-limit rows in arch-parity.md that work, commit "part 3b".

### Part 3b — loader debugging (macOS 26 / Darwin 27)

- Live symptom: `sudo skyrose-sa-loader` printed nothing and exited. Added a `-v` trace, unbuffered
  output, always-on crash handlers and distinct exit codes to `Packaging/sa/loader.c`.
- Verbose trace showed every step succeed through `thread_convert_thread_state`, then exit 137.
  Kernel log: `EXC_GUARD type=0x1 (GUARD_TYPE_MACH_PORT) … THREAD_SET_STATE on mach port … signal 9`.
  So **`thread_set_state` on a thread's mach port is killed by a Mach-port guard on macOS 26** —
  not a ptrauth fault (SIGKILL is why the handler stayed silent). Confirmed by Frida issue #3757
  (same guard on 26.4; `tss_should_crash=0` is ignored on 26.x). SIP/boot-args were fine
  (Debugging Restrictions off, `-arm64e_preview_abi` set), so readiness was never the problem.
- **Fix (mirrors yabai's 14.4+/15+ path):** on macOS ≥ 14.4 don't call `thread_set_state`; throw
  the conversion thread away (`thread_terminate`) and start the real one atomically with
  `thread_create_running(task, ARM_THREAD_STATE64, converted_state, …)`. Older macOS keeps the
  classic `set_state` + `resume`. Our ptrauth signing (IA key, ctx 0) and convert direction
  (`FROM_SELF`) already matched yabai. Gated by `macos_at_least()` (`kern.osproductversion`).
- Also reverted (via Gabby) `sipOff.enabled` in his config.toml — my live Settings test had left
  the toggle on after the showcase unlocked it; inert with no SA loaded, now back to the default.
- Gabby's run (2026-11-06): every step ok, "thread_create_running ok", exit 0, Dock pid 664.

### Part 3b — live test (done)

- `skyrose sa status`: loaded (v1: alpha, shadow, level, transform, space); `query state` mode enhanced;
  `sipOff-mode-used` flag written.
- Raw socket on Gabby's idle kitty "~" (0x314): alpha 0.4, shadow off, half-size transform, level 3,
  all read back; all undone on disconnect.
- WM path (TestWindows on empty ws2 + kitty on ws1): open pop + fade, retile spring, WM close shrink+fade,
  instant workspace switch, pin on top, opacity on/off (0.95 on kitty too), shadows off/on. Numbers in
  arch-parity.md › SIP-off mode live test. Files: `/tmp/cwm/phase5/3b/`.
- **Bug found + fixed:** pinning starts a float-move animation, and `layoutApplied` skipped windows the
  animator covered, so the level (and shadow) was never sent. Now only alpha waits for the animation
  (`testPinDuringAnAnimationRaisesAtOnceButAlphaWaits`). Live after the fix: level 3, stays above a
  focused tile; unpin → level 0.
- `skyrose wm panic`: every change undone, socket closed, WM quit. TestWindows quit, no leftovers;
  WM started again (standard mode, since the helper's socket is closed). Config left as found
  (`sipOff.enabled = true`, opacity false).
- To use SIP-off mode again after a panic or a reboot: run the loader again (`stop` resets the payload's
  running flag, so a second load restarts it).

Decisions: blur and rounding of other apps stay limits (no SkyLight call for them); a rebuild while the
Dock has the dylib loaded was harmless (Dock kept running, helper kept answering).

## Part 4 — Material Symbols (done)

- `ShellIcon` (Shell/Theme/ShellTheme.swift): `fromSF` maps every SF name the shell uses to a
  Material Symbols Rounded name + fill; `glyph(_:)` resolves SF or Material names (dotted unknown
  names stay SF only, e.g. `apple.logo`; plain unknown names are Material); `materialFont(size:
  weight:fill:)` builds the variable font with FILL / wght / opsz / GRAD axes (cached);
  `materialScale` 1.25 so a Material glyph matches the SF size it replaces.
- `MaterialIcon` view (Shell/Support/MaterialIcon.swift): ligature text when the family is
  registered (FontStore, already done at WM start once `skyrose fonts download` ran), else the SF
  Symbol. Every `Image(systemName:)` in the shell (47 sites) now goes through it; brightness slider
  uses `brightness_high`, the session moon `bedtime` (filled).
- Tests: SF names in the map exist, every Material name's SF fallback exists, resolver cases,
  weight axis, and every Material name is a single ligature glyph in the pinned font (skipped
  where the font is not downloaded).
- Live: dashboard (tabs, weather, chips, gauges) and sidebar (empty notifications, keep awake,
  sliders, quick toggles) render Material: `/tmp/cwm/phase5/icons/dashboard.png`, `sidebar.png`.

Decisions: no config switch (Material whenever the font is present, SF otherwise); Settings
(SkyRoseSettingsKit) keeps SF Symbols (macOS settings look); `apple.logo` stays SF.

## Part 5a — screenshot tool (done)

- Core `Capture/Capture.swift`: `CaptureMode` (region, freeze, window, full), `CaptureGeometry`
  (drag rect, click tolerance 4 pt, global → display-local → pixels, window under the pointer from
  the window list, macOS-style file names "Screenshot 2026-11-06 at 09.05.07.png" + " (2)",
  opt-in ⇧⌘3/4/5 binds written with whichever logical modifier is ⌘ in the preset).
- `[capture]` config: folder `~/Pictures/Screenshots`, saveToFolder, copyToClipboard, thumbnail,
  overrideSystemShortcuts = **false** (WMDaemon appends the binds at keymap load / reload / when the
  key flips; macOS's own shortcuts are never touched by default).
- Shell `Capture/ScreenshotController.swift`: ScreenCaptureKit (`SCScreenshotManager`), picker
  panels at screen-saver level on every display (dim + hole, size label, hover highlights the
  window under the pointer; drag = region, click = window, click on the desktop = that display,
  Esc / right click = cancel, pressing the bind again cancels). Freeze captures every display
  first and crops the still. Window capture without shadow. Full = display under the pointer.
  PNG to the folder + PNG/TIFF on the clipboard; success toast with a thumbnail
  (`Toast.imagePath`). Binds: existing `capture.region` / `capture.full` / `capture.freeze`
  (Print → ⌥L⌘⇧4 / F13 etc.). CLI: `skyrose screenshot region|freeze|window|full` (returns at once).
- Live (capture.folder → /tmp, clipboard off, then both reset): full 2940×1912; region drag
  400×220 pt → 800×440 px; window (TestWindow 1408×862) → 2816×1724 without shadow; freeze drag
  → 800×400 of the still; Esc closes the picker; toast with thumbnail
  (`/tmp/cwm/phase5/shots-toast.png`, `window-shot.png`, `freeze-shot.png`).

Decisions: full = the display under the pointer (grim joins all outputs; stitching mixed scales is
not worth it); no swappy-style editor (Preview is one double-click away); the toast is
click-through like every toast, so no "open" action on it; if macOS's own ⇧⌘3/4/5 still fire with
the override on, turn them off in System Settings › Keyboard › Shortcuts › Screenshots
(documented in LIMITATIONS.md). Seen once, not reproduced: right after a WM restart + `ws focus 2`
the display was back on ws1 before the first picker (picker/drag/Esc on ws2 kept ws2 three times).

## Part 5b — keep-awake timers (done)

- Core `Power/KeepAwakeTimer.swift`: parse "30m" / "1h" / "1h30m" / "90" (minutes) / "45s" /
  "forever" (1 s … 7 days), presets ∞ / 15 min / 1 h / 2 h / 5 h, "1 h 05 min left" text, status
  line, `isChosen` (a chip lights only for exactly its length; a CLI `on 1m` lights none).
- `KeepAwakeService.set(on:duration:)` + `until` / `duration` / `remaining`; a one-shot Timer
  (RunLoop common mode) releases the `PreventUserIdleDisplaySleep` assertion "SkyRose keep awake".
  Turning it on again replaces the timer.
- `ShellState.keepAwakeUntil` + `keepAwakeDuration`; sidebar card: countdown status (TimelineView,
  20 s) + chip row. The switch only forwards real flips (re-sending the current value would have
  turned a timed keep-awake unlimited).
- IPC `keepawake {state: on|off|status, seconds?}` → `{enabled, until?, status}`; CLI
  `skyrose keepawake on [30m|1h|forever] | off | status` (aliases keep-awake, caffeinate), help + Schema.md.
- Live: `on 1m` → assertion present (checked with a read-only `IOPMCopyAssertionsByProcess` script,
  no pmset), released on time with the sidebar open and `swift test` running; 10 s / 15 s timers with
  the sidebar closed / open / opened after start all ended on time; bad duration / verb → exit 3 +
  help. Shots: `/tmp/cwm/phase5/keepawake-1m-card.png` (no chip lit), `keepawake-1h-card.png` (1 h lit).
- Seen once, not reproduced (4 later runs fine): the first 1 min run was still on, unlimited, after
  it should have ended. Only the sidebar switch can do that, so its setter is now guarded. If it
  comes back, log the caller in `KeepAwakeService.set`.
- Not live-clicked: the chips themselves (the same `set(on:duration:)` path as the CLI). The switch
  looks grey while on because the sidebar panel is never key (macOS inactive look; it was like that before).

## Part 5c — Clamshell (done)

No sudo, no pmset, no power-setting changes. macOS runs lid-closed only on a power adapter AND with an
external display (native clamshell); SkyRose reports that and does not override it (LIMITATIONS.md
"Lid closed").
- Core `Power/Clamshell.swift`: `ClamshellFacts` (hasLid, lidClosed, closingCausesSleep?, onAC,
  externalDisplays) → `ClamshellMode` (no-lid, open-will-sleep, open-will-stay-awake, closed-running);
  the kernel's `AppleClamshellCausesSleep` wins when published; summary line names what is missing;
  `holdsKeepAwake` only while closed-running and opted in.
- `[clamshell] keepAwake = false` (Config + config.default.toml).
- Services `Power/ClamshellMonitor.swift`: reads IOPMrootDomain `AppleClamshellState` /
  `AppleClamshellCausesSleep`, `IOPSGetProvidingPowerSourceType`, online non-built-in displays;
  refreshes on root-domain interest messages, IOPS notifications and screen-parameter changes (no
  polling). Own assertion "SkyRose clamshell keep awake" (PreventUserIdleDisplaySleep) while
  closed-running with the option on.
- Shell: `ShellState.clamshell`; sidebar keep-awake card shows the summary line (laptop_mac icon) on
  Macs with a lid. IPC/CLI `skyrose clamshell [status]` (alias `lid`) → `{hasLid, lidClosed, onAC,
  externalDisplays, mode, summary, closingCausesSleep?, keepAwake, holdingKeepAwake}`.
- WM (`WorkspaceState`): `removeDisplay` remembers each surviving workspace's home display and what
  it showed (`displayHomes`, `homeActive`, Optional so old session.json decodes); `ensureDisplay` of a
  returning display moves them back and shows the old one; a display that was showing one falls back
  to its lowest own workspace or a new one; a workspace closed while away loses its home. Works across
  a WM restart with the lid closed (`restored` → snapshot → open). `DisplayReturnTests` (7).
- Live (battery, no external display): `skyrose clamshell` → open-will-sleep, closingCausesSleep true,
  matches read-only `ioreg -r -n IOPMrootDomain`; `clamshell on` → exit 3 + help; sidebar shot
  `/tmp/cwm/phase5/clamshell-sidebar.png`. **Not live-tested**: lid closed with power + display
  (closed-running, the assertion, workspaces returning on open); needs a dock.

## Tests

After part 1: 970 tests, 0 failures (`/usr/bin/swift test`).
After part 2: 976 tests, 0 failures.
After part 3a: 987 tests, 0 failures.
After 3a-fix (loader): 987 tests, 0 failures.
After part 3b: 988 tests, 0 failures.
After part 4: 993 tests, 0 failures.
After part 5a: 1002 tests, 0 failures.
After part 5b: 1011 tests, 0 failures.
After part 5c: 1024 tests, 0 failures.

---

# Previous phase (archive)

## Phase: terminal, fonts, liquid animations + bug fixes (started 2026-11-05)

Resume here after a context reset. Read `docs/parity-progress.md` and `docs/arch-parity.md` first.
Order: 1 bugs → 2 liquid animations → 3 terminal → 4 fonts. Commit on main after each part
(not pushed).

## Status

| Part | State | Commit |
|---|---|---|
| 1. Bugs (SIP reminder, weather, temperatures, edge drags) | done, live-tested | see `git log` ("Part 1") |
| 2. Liquid animations | done, live-tested | see `git log` ("Part 2") |
| 3. Terminal | done, live-checked (Settings page, sync no-op) | see `git log` ("Part 3") |
| 4. Fonts | done, live-tested (dashboard in Rubik) | see `git log` ("Part 4") |

## Part 1 — done

- **SIP reminder**: `SIPReminderDecision.shouldShow(sipOffModeUsed:status:)` (Core/Backup/SIPStatus.swift).
  Shown only if the `sipOff-mode-used` flag file (or the manifest entry) exists **and** `csrutil
  status` is not fully enabled. A corrupt manifest no longer forces it. `skyrose uninstall` decides
  before removing anything and opens Settings `--sip-reminder`. Nothing in the app sets the flag
  yet (Enhanced mode / the SA loader is not built); `RestoreManifest.recordModeUsed(.sipOff)` is the hook.
- **Weather**: `[weather]` config (city, latitude, longitude, useLocation=false, fahrenheit,
  refreshMinutes=30). Open-Meteo client in `CaelestiaServices/Weather/OpenMeteo.swift` (pure
  parsing, fixtures in `Tests/fixtures/openmeteo`). `WeatherController` (Shell) fills
  `ShellState.weather` / `weatherStatus`. Dashboard Overview card + new Weather tab. Settings ›
  Bar and Shell › Weather: debounced city search. CoreLocation via `LocationService`, entitlement
  `com.apple.security.personal-information.location` added to SkyRose.entitlements.
  Live: Oslo test showed 5 °C "Mainly clear", 12 h + 7 days; config restored afterwards (no city set).
- **Temperatures**: `HIDTemperatureReader` (dlsym'd IOHIDEventSystemClient… like Stats) +
  `TemperatureSummary` classifier. M4 Air live: CPU 30 °C avg / 32 °C hottest, battery 25 °C,
  SSD 30 °C; GPU hidden (M4 exposes no named GPU sensor). "degrees need root" removed.
- **Edge drags**: `EdgeDrag` (Shell/Support) + passive global monitors (mouse down/drag/up,
  trackpad scroll phases). Frame stays click-through. Live: 108 pt drag on the upper right band
  opened the sidebar; 28 pt did nothing. Session-zone drag only unit-tested (a synthetic drag
  could release over a session button).

Decisions: lat/lon are stored with 2 decimals by ConfigFileEditor (≈1 km, fine for weather).

## Part 2 — done

- `CaelestiaCore/Motion/LiquidMotion.swift`: every spring from (damping ratio, settling time).
  Windows: pop ζ 0.58 from 80 %, move ζ 0.72, both 300 ms; close unchanged. Workspaces: Arch
  snappy Bézier 320 ms. `FrameSampler` returns exactly 1 at its end time (FP fix).
- Shell: `Support/LiquidDrawer.swift` (`liquidBody` / `liquidContent`) on every drawer
  (sidebar without neck, launcher, dashboard, session, OSD, wallpaper, popouts, utilities with
  a corner neck). `ShellTheme.drawerSpring(depth:)`, `neckSpring`, `contentFadeIn`,
  `panelFadeInSeconds` (50 ms), `overshootRoom(depth:)` + `DisplayLayout.withRoom` on every
  drawer panel frame; Utilities got an explicit `bodyHeight` so its GeometryReader layout is
  unchanged. Bar: `ShellTween.animate(to:spring:)` (velocity kept on retarget),
  `ShellTheme.barRevealSpring`, frame band swell (`frameInsets(swell:)`, cap 1.12),
  `BarMotion.contentOffset`. Toasts: asymmetric scale/slide/fade transitions.
- Live (built-in, ws 3 empty, TestWindows only): see the table at the end of
  `docs/arch-parity.md`. Clips + contact sheets in `/tmp/cwm/liquid/` (`before_*`, `after_*`,
  `NOTES.md`). Not live-tested: bar reveal (warped pointers do not trigger hover), toasts (would
  write to Gabby's notification history), OSD (needs a volume key), popouts, wallpaper.

Decisions: no anisotropic window squash (unsafe to compose with the cover's scale animation);
workspace slide uses the Arch Bézier despite its front-loading because the brief names it;
overshoot is a constant ~16 pt so small and large drawers bounce alike.

Found, not fixed (pre-existing, not motion): closing a key drawer (launcher/session) on an empty
workspace re-activates the previous app and the WM follows it to its workspace (seen ws 3 → 4).

## Part 3 — done

- `CaelestiaCore/Scheme/KittyProfile.swift`: `KittyProfile` renders `~/.config/kitty/skyrose.conf`
  (Gabby's Arch kitty.conf mapped to macOS: blur 32, titlebar-only, ⌥ as Alt; colours from
  `include skyrose-theme.conf`). `KittySetup` installs (one `include skyrose.conf` line appended to
  kitty.conf, original copied + journalled as `kittyConfig`), uninstalls (restores the file
  byte-for-byte; deletes a kitty.conf it created), refuses to overwrite files it did not write,
  writes through a symlinked kitty.conf, and `syncTheme` rewrites colours only when kitty includes us.
- WM: `KittyLiveSync` on every scheme change and at start; `SIGUSR1` to running kittys only when
  the theme file changed.
- Terminals: `TerminalChoice.presets` = kitty (default), Rex (`com.superlogical.rex`), Terminal,
  iTerm2, Ghostty, WezTerm; Other = bundle id or command. ⌥T on a missing app opens macOS Terminal.
- Settings › Terminal: preset list with install state, Shortcut card (records `app.terminal`
  like Keybinds), kitty setup card (Set up / Remove, notes), Try it.
- CLI: `skyrose kitty status | install | uninstall [--json]`.
- Live: Settings page screenshot `/tmp/cwm/phase/settings-terminal.png`; WM restart left
  `~/.config/kitty` untouched (Gabby's kitty.conf does not include the profile). The profile was
  **not** installed into Gabby's kitty.conf (it would restyle the terminal running this session):
  `skyrose kitty install` or Settings › Terminal › Set up does it when wanted.

Decisions: no new config key; the include line is the opt-in. Terminal/iTerm2/Ghostty/WezTerm
open or come forward (no new-window scripting); only kitty opens a new window each time. Kitty
install offer in onboarding is left to the installer phase (brief).

## Part 4 — done

- `CaelestiaCore/Fonts/FontPack.swift`: Rubik, Inter, CaskaydiaCove NF, JetBrainsMono NF,
  Material Symbols Rounded; URLs pinned to tags/commits, SHA-256 + size per file, licence file per
  family (OFL 1.1 ×4, Apache 2.0). See `docs/FONTS.md`.
- `CaelestiaPlatform/FontStore.swift`: verified download into `Application Support/SkyRose/Fonts`,
  process-only registration (WM at start + on config reload, Settings at start), opt-in copy
  into `~/Library/Fonts` with `installed.json` + journal, uninstall of exactly those files.
- `ShellTheme.fontsChanged()` / `fontGeneration`: newly registered fonts re-render every surface.
- Config: `appearance.fontMono` is now the v3 family "CaskaydiaCove Nerd Font" (the v2 "NF" name
  is a fallback, plus "JetBrainsMono NF" which is what this Mac has); `apps.kittyFont` /
  `apps.kittyFontSize` feed `skyrose.conf`.
- Settings: Appearance › Fonts card (download with progress, install for other apps, remove);
  Terminal › kitty setup › Font picker (re-renders the profile and reloads kitty if in use).
- CLI: `skyrose fonts status | download | install | uninstall [--json]`.
- Live: `skyrose fonts download` (into SkyRose's folder only; nothing in ~/Library/Fonts) +
  `skyrose config reload` switched the running dashboard from SF Pro to Rubik:
  `/tmp/cwm/phase/fonts-compare.png` (left before, right after). JetBrainsMono Nerd Font was
  already installed on this Mac (Gabby's own copy), so kitty's font resolves today.

Decisions: fetch instead of committing ~32 MB of binaries; registration is per process so nothing
is installed without the explicit button; icons stay SF Symbols for now.

## Remaining (next phases)

- Installer phase: onboarding offers kitty (not installed by SkyRose) and the font download.
- Material Symbols for the shell's icons.
- Closing a key drawer on an empty workspace follows the re-activated app to its workspace.
- Not live-tested this phase: bar spring reveal, toasts, OSD, popouts, wallpaper drawer; the
  kitty profile against a real kitty (Gabby's kitty.conf was deliberately not changed).

## Tests

After part 1: 928 tests, 0 failures (`/usr/bin/swift test`).
After part 2: 942 tests, 0 failures.
After part 3: 954 tests, 0 failures.
After part 4: 964 tests, 0 failures.
