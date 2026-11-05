# Phase: terminal, fonts, liquid animations + bug fixes (started 2026-11-05)

Resume here after a context reset. Read `docs/parity-progress.md` and `docs/arch-parity.md` first.
Order: 1 bugs → 2 liquid animations → 3 terminal → 4 fonts. Commit on main after each part
(not pushed).

## Status

| Part | State | Commit |
|---|---|---|
| 1. Bugs (SIP reminder, weather, temperatures, edge drags) | done, live-tested | see `git log` ("Part 1") |
| 2. Liquid animations | done, live-tested | see `git log` ("Part 2") |
| 3. Terminal | not started | |
| 4. Fonts | not started | |

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

## Remaining

- Parts 3–4 (see the brief).

## Tests

After part 1: 928 tests, 0 failures (`/usr/bin/swift test`).
After part 2: 942 tests, 0 failures.
