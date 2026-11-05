# Phase: launcher + wallpapers, SIP-off mode, then Material icons / screenshots / Clamshell (started 2026-11-05)

Resume here after a context reset. Read `docs/parity-progress.md` and `docs/arch-parity.md` first.
Strict order (Gabby is low on usage): 1 quick fixes → 2 wallpapers → 3 SIP-off mode → 4 Material
Symbols → 5 screenshots, keep-awake, Clamshell. Commit on main after each part (not pushed).

## Status

| Part | State | Commit |
|---|---|---|
| 1. Launcher index + empty-workspace jump | done, live-checked | see `git log` ("Phase 5 part 1") |
| 2. Wallpaper subfolders + live wallpapers | not started | |
| 3. SIP-off mode | not started (verify `csrutil status` + `nvram boot-args` first; no sudo by Claude) | |
| 4. Material Symbols | not started | |
| 5. Screenshots, keep-awake, Clamshell | not started | |

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

## Tests

After part 1: 970 tests, 0 failures (`/usr/bin/swift test`).

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
