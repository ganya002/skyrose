# Phase: terminal, fonts, liquid animations + bug fixes (started 2026-11-05)

Resume here after a context reset. Read `docs/parity-progress.md` and `docs/arch-parity.md` first.
Order: 1 bugs → 2 liquid animations → 3 terminal → 4 fonts. Commit on main after each part
(not pushed).

## Status

| Part | State | Commit |
|---|---|---|
| 1. Bugs (SIP reminder, weather, temperatures, edge drags) | done, live-tested | see `git log` ("Part 1") |
| 2. Liquid animations | not started | |
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

## Remaining

- Part 2–4 (see the brief). Clips for part 2 go to `/tmp/cwm/liquid/`.

## Tests

After part 1: 928 tests, 0 failures (`/usr/bin/swift test`).
