# Surface parity, Phase 9.5 A1 (2026-11-11)

Each SkyRose surface was captured on the MacBook Air (1470×956 pt) and set next to its reference at
the same scale (reference = `docs/caelestia-reference/shell/*` at 5120×1440 or the 2560×720 jpgs in
`~/caelestia-ref/full-2026-11-05/04-caelestia/`). Exact values come from `caelestia-dots/shell` at
`fd630ff`. The capture's .mp4 clips are now H.264 (re-exported Nov 11), so timing is measured frame
by frame with AVFoundation (scratchpad `probe`/`frame` tools: per-frame luma of a strip, single frames).
Colours differ by design: the scheme comes from each wallpaper.

| Surface | Reference | Status | Remaining diffs |
|---|---|---|---|
| Dashboard tabs | `shell/dashboard_opened.jpg`, `Tabs.qml` | fixed | none major |
| Dashboard cards | same, `dash/*.qml` | fixed | user card keeps an initial (no face picker); location moved to a tooltip |
| Media card | `dash/Media.qml` | fixed | none major |
| Launcher | `shell/launcher_opened.jpg`, `AppItem.qml` | fixed | none major |
| Sidebar | `shell/1-sidebar.jpg`, `NotifDock.qml` | fixed | a collapsed group shows two lines, upstream one; extra macOS rows (timers, clamshell, sliders) stay |
| Utilities | `04-caelestia/utilities_opened.jpg` | fixed | Screen recorder card added (status + timer, Fullscreen/Stop, newest 3 recordings with Finder/Trash). Upstream also has Region and with-sound modes behind a menu and a collapsible list: our recorder only does the full main display, so no menu (no display-only controls) |
| Bar | `04-caelestia/bar_hover_*.jpg` | fixed | the window title was invisible (clipped); now shows |
| Toasts + notification popups | `04-caelestia/notification_popup.mp4`, `notification_visible.jpg`, `Notification.qml` | fixed | one drawer out of the top-right frame corner on the liquid surface (Gabby: toasts too, upstream keeps toasts as a bottom-right card). Measured: 430 wide, padding 15/5, card 410×61 r20, icon 42; open 300 ms (edge arrives at ~125 ms, wobble settles by ~300 ms) = ours at speed 1. No expand chevron / swipe (click-through) |
| Session | `shell/1-session.jpg` | matches | the GIF is a moon on macOS (Phase 8 decision) |
| OSD | `04-caelestia/osd_opened.jpg` | deferred | rebuilt in Part 10a against `part10/osd-volume-brightness.png` |
| Bar popouts | none usable: every `bar_hover_*.jpg` is the same frame with the bar hidden (the capture warped the cursor only); upstream `bar/popouts/*.qml` | blocked on reference | the only popout capture is `part10/wifi-popout.png`; audio/network/bluetooth popouts are rebuilt in Phase B (10b–10d) against it and the QML |
| Settings | upstream `modules/nexus` (Caelestia's settings app; never captured on the Arch box) | compared from source | same structure (nav pane + pages + grouped rows on surfaceContainer). Not ported: Nexus's "Search settings" field in the nav pane and the icon next to each page title. When Settings is not frontmost it looks see-through: that is `sipOff.opacity` (inactive-window alpha, WM), not the Settings fill |

## Drawer timing, re-measured on the H.264 clips (2026-11-11)

Method: per-frame mean luma of a strip at each drawer's final edge and a box at its origin edge
(scratchpad `probe`); visible time = first motion to last change. SkyRose recorded the same way
(`screencapture -v`, Gabby's speed 1.5, times ×1.5 to compare at speed 1). Tokens were scaled by
reference ÷ SkyRose where they differed by over 15 %, then re-recorded.

| Drawer | Reference open / close (ms) | SkyRose before | SkyRose after | Token (base ms) |
|---|---|---|---|---|
| Dashboard | ~350 / ~183 | ~426 / ~125 | ~400 / ~200 | 650 → 525, 162.5 → 237.5 |
| Launcher | ~333 / ~167 | ~400 / ~125 | 225–400 (list content makes the strip noisy) / ~175 | 475 → 400, 162.5 → 212.5 |
| Sidebar | ~245 / ~115 | ~276 / ~125 | unchanged | 287.5 / 162.5 |
| Utilities | ~350–380 | matches | unchanged | 437.5 / 150 |
| Session | ~150 / ~133 (edge; the origin box also catches the screen dim) | ~126 / ~126 (origin, same caveat) | unchanged | 225 / 212.5 |
| OSD | ~175 / ~60 | ~390 / ~75 | ~175 | new `osd` 225 / 187.5 (was the generic 500) |
| Notifications | ~300 | ~300 | | 375 / 187.5 |

Before stills (this session, not in git: personal screen content): `/tmp/sr-parity/{idle,dash,launcher,sidebar,session,osd,utilities}.png`.
After: `/tmp/sr-parity/{dash3,sidebar2,bar2,toast2,popup,util-ready,util-rec,util-final}.png` and the clips `/tmp/sr-parity/{after-dashboard,popup}.mov`.

# Arch parity: progress (2026-11-05)

Phase brief: make SkyRose match Gabby's Arch Hyprland + Caelestia setup
(`~/caelestia-ref/full-2026-11-05/`, 5120x1440 @1x). The full audit table is in
`docs/arch-parity.md`. **Re-read this file first after a context compaction.**

## Gabby's picks

- Border colour fade **480 ms**, like Arch. This is the one exception to the
  350 ms cap, and `AnimationGuardTests` guards it.
- New window **follows the cursor** (Hyprland `force_split 0`). A cursor outside
  the focused tile goes to the right/bottom.
- Cursor (2026-11-05): ship every cursor that can be restored and **skip the wait
  cursor**, and say so in Settings.
- WM restart: windows must stay on their workspace and side.

## Done (committed on main, not pushed)

| Commit | What | Live-tested |
|---|---|---|
| `29ead98` | Hyprland dwindle geometry, gapsOutSingle 20, longer-side split, preserve_split, pseudo, togglesplit/swapsplit, float centring, min tile, opacity 0.95, bar 60, border fade 480 ms, popin 0.8, group bar outside the ring | yes (Air, ws4) |
| `f468d85` | Settings: radius 15 / inset sidebar; live WM status; single WM instance; socket rebind | yes |
| `215b557` | Hover reveals (dashboard top band, utilities corner, OSD right edge, 100 ms dwell), standalone utilities drawer, session dim | yes |
| `99b5928` | Red button quits the app (opt-in, exceptions, Finder default) | yes, see below |
| `c782feb` | WM restart keeps every window on its workspace and side (`session.json`) | yes, three restarts |
| `d0b135d` | Appearance › Cursor: Bibata Modern Classic, session-only, wait cursor never touched; `skyrose cursor …` | yes |
| (this commit) | TestWindows no longer exempt from close-quit (it stands in for any app); Corner calibration pill fix; cursor hint text; build.sh no longer needs the untracked `Resources/`; docs | yes |

Tests: **903 pass, 0 failures** (`/usr/bin/swift test`).

### Live results

- **Close-quit** (TestWindows only, float rule, built-in display):
  - With 2 windows, the red button closed only that window and the app kept running.
  - On the last window, the red button quit the app.
  - With the option off, the app kept running after its last window closed.
  - Afterwards the rule and config were reverted to `auto` and `false`.
- **Restart**:
  - The first restart onto the new binary used a snapshot seeded from the live
    state, because the old binary could not write one.
  - The next two restarts used the WM's own snapshot.
  - Each time, `restoredFromSession: 3`: Firefox ws1; Grok left and kitty right
    on the DELL ws2. Frames were identical.
- **Cursor**:
  - Apply: ArrowS/IBeamS 24×24 at hotspots 5.16,1.59 and 12,12, all 29
    `com.apple.cursor.N`, Move/Copy/Alias.
  - Reset through Settings, through `cursor set default` and on WM quit: the
    registry matched the pre-apply snapshot exactly.
  - Relaunch re-applied. Running apps switch at the next pointer shape change.
  - Visual crops are in `/tmp/cwm/parity/after/cursor-*.png`.
  - Left on **macOS** (not applied) for Gabby to choose.

## Remaining / still different (see arch-parity.md)

- Limits (macOS):
  - Other apps' window blur and rounding (even with SIP off).
  - Other apps' opacity, shadow on/off and real always-on-top for pin: SIP-off mode only
    (live-tested 2026-11-06, see arch-parity.md › SIP-off mode live test).
  - The top edge also reveals an auto-hidden macOS menu bar.
- Decisions:
  - Bar/drawers overlay and do not push tiles.
  - Move/open springs about 300 ms, not riko's about 600–700 ms.
  - Drawer and bar timings are a little faster.
- Not done:
  - Drawer drags from the right edge (our frame is click-through).
  - Dashboard Weather tab (no weather service).
- Cursor: the wait cursor stays macOS's. It is still Bibata's in this session
  because of the 2026-11-05 experiment; logging out fixes it.

## Side effects to report

- `ws focus 4` once hit the focused DELL. The full-screen shots that caught
  Firefox were deleted, and the DELL was restored to ws2.
- Before the session snapshot existed, WM restarts swapped kitty/Grok on the DELL
  and moved windows to ws1. This is fixed now.
- `git stash -u` (used to test one commit alone) deleted the empty untracked
  `Resources/` folder that build.sh copied from. The folder was recreated, and
  build.sh no longer requires it.
- Gabby opened and closed an extra kitty window during testing, not the WM.
