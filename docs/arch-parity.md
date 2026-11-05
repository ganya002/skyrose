# Arch parity: SkyRose vs Gabby's Hyprland 0.57 + Caelestia

Source of truth: the capture pack `~/caelestia-ref/full-2026-11-05/` (CLAUDE-BRIEF.md, README.md,
`00-state` dumps, `01-tiling/geometry.txt` + `ops-geometry.txt`, clip frames). The reference
display was 5120×1440 at scale 1, so 1 Arch px = 1 logical px = 1 pt on the Mac: gaps, border,
rounding and panel sizes carry over 1:1 in points (the MacBook panel is 1470×956 pt, so long
captured sizes like the 2533 px tile are only checked as ratios).

Standing decisions that win over Arch (from earlier phases, restated in this phase's brief):

- **Short motion.** Every animation 150–300 ms, nothing over ~350 ms, springy, interruptible. Arch
  curves are mapped into that range; the ~600–700 ms spring settles are not copied.
- **Overlays never retile.** The auto-hidden bar and every drawer overlay the windows; revealing
  them reserves no space (Arch pushes tiles right when the bar opens).
- **Sane minimum tile size** instead of Arch's 27×32 px slivers.
- **No kitty auto-maximize** (a quirk of the capture machine, see the pack's Anomaly section).

Legend for "Action": **fixed** = changed in this phase; **kept** = already matched; **kept
(decision)** = differs on purpose; **limit** = macOS does not allow it (see LIMITATIONS.md);
**upstream** = the pack has no capture, so the value comes from Caelestia/Hyprland source or docs.

## Tiling (dwindle)

| Feature | Arch value | SkyRose before | Action |
|---|---|---|---|
| Split target | the focused tile (`use_active_for_splits`) | focused tile, then nearest to cursor, then last | kept |
| Split axis | longer side of the focused tile: w > h → side by side, else stacked | same (`aspectDirection`) | kept |
| New window side | `force_split = 0`: the half of the focused tile the cursor is in; cursor outside the tile → right/bottom (geometry.txt n3, n5–n13 went left/top because the cursor sat at the left/top of the target) | always right/bottom | **fixed**: cursor half when the cursor is inside the target tile, else right/bottom |
| Split ratio | 0.5 (`default_split_ratio 1.0`) | 0.5 | kept |
| preserve_split | on: a togglesplit sticks | on (stored direction) | kept |
| togglesplit | flips the focused pair (ops01/02: 1258×1398 pair → 2533×693 pair and back) | tree op existed, no action/bind/IPC | **fixed**: `layout.toggleSplit` action, CLI `layout togglesplit` |
| swapsplit | swaps the two sides of the focused pair (ops03) | missing | **fixed**: `layout.swapSplit` |
| smart_resizing | on | on (`resizePercent`) | kept |
| Keyboard resize | ±10 % of window size (SUPER+−/=) | ±10 % | kept |
| move dir | swap with neighbour, else next monitor | same | kept |
| Min tile size | none (tiles down to 27×32 px at 14 windows) | only learned app minimums | **fixed (decision)**: `wm.dwindle.minTileWidth/Height` = 120×80 pt; a split that would go below it splits the largest tile that fits instead; none fits → the window floats centred |
| pseudo | keeps the client's own size centred in its slot, scaled down to fit (ops08: slot 1263×1398 → 1248×1388 centred) | missing | **fixed**: `window.pseudo`; size = last floating size, else the size the window had when it was first tiled; Hyprland's fit-and-centre maths |
| Float toggle | remembered float size centred on the slot's centre (ops10: 1280×1410 centred on a 1263×1398 slot; ops21: 2530×1380) | last float frame, else 60 %×70 % centred on the screen | **fixed**: last float size, else the tile's size, centred on the tile's centre, clamped on-screen |
| Center | `centerwindow` on floats | same | kept |
| Pin | float + pin (shows on every workspace) | same; true always-on-top impossible | kept / limit |
| Maximize | gaps 20 (31,31 5058×1378) | `gapsOutSingle` + border | kept |
| Fullscreen | whole monitor, no border/rounding | whole display, no border | kept |
| Focus follows mouse | on, needs real motion | on, 100 ms delay | kept |
| Focus on close | window under the cursor | same | kept |

## Gaps, frame, borders, rounding, opacity

| Feature | Arch value | SkyRose before | Action |
|---|---|---|---|
| Reserved screen frame | 10 px per edge (caelestia-border-exclusion layers) | `screenFrameInset = 10` | kept |
| gaps_in / gaps_out | 5 / 10 → tiles' client area at x = 21 (10 frame + 10 gap + 1 border) | 5 / 10, border inside the slot | kept (same 21) |
| Dwindle partition | boxes split the area **minus gaps_out**; gaps_in only on interior sides (n3: 1258 \| 1263) | split the full area, gaps_out per edge tile (1263 \| 1258, 5 px off) | **fixed**: Hyprland's formula |
| Single window / maximized | gaps_out 20 (31,31) | `gapsOutSingle = 20` | kept |
| gaps_workspaces | 20 | 20 | kept |
| Border | 1 px, active `primary` @ 0xe6, inactive `onSurfaceVariant` @ 0x11 | same | kept |
| Border colour fade | 480 ms `standard` (.2,0,0,1) | 240 ms | **fixed**: 480 ms (Gabby's pick, the one exception to the 350 ms cap) |
| Rounding | 15, power 2 (circular) | 15 (overlay stroke; real window keeps the macOS corner) | kept / limit |
| Opacity | 0.95 when not fullscreen | 0.94 (Enhanced mode only) | **fixed**: default 0.95 (still Enhanced only) |
| Blur | size 10, 3 passes; off on special workspaces | 10/3 on our own panels; other apps: limit | kept / limit |
| Shadow | 15 px, power 4, `inversePrimary` @ 0x10 | panels only | kept / limit |

## Groups (tab bar)

| Feature | Arch value | SkyRose before | Action |
|---|---|---|---|
| Bar height and gaps | 25 px bar, gaps_in 3 (between tabs), gaps_out 3; content moves down 31 (y 21 → 52) | 25 + 3 = 28 reserved | **fixed**: 31 reserved (3 + 25 + 3) |
| Where the border goes | around the window only; the tab bar sits above it, outside the ring (ops16) | ring around bar + window | **fixed** |
| Tab look | `primary`/`outline` @ 0xd4 (locked: `secondary`), JetBrains Mono NF 15, rounding 5, text `onPrimary`, gradients on, indicator 0 | same colours/font/rounding | kept |
| Multi-tab groups | not captured (into_group failed in the pack) | groupToggle / moveOut / next / prev / lock | **upstream**: Hyprland group docs (new windows join an unlocked group, tabs split the bar width) |

## Workspaces

| Feature | Arch value | SkyRose before | Action |
|---|---|---|---|
| Count | 10 per group (SUPER+1…0), groups via CTRL+SUPER | 10 × 5 groups | kept |
| ±1 | SUPER+scroll, SUPER+PageUp/Down, CTRL+SUPER+←/→ | all bound; bar scroll too | kept |
| ±10 | CTRL+SUPER+scroll | bound | kept |
| Slide | horizontal, 320 ms `snappy` (.05,.9,.1,1.05) | snappy spring ≈ 300 ms | kept (decision: spring, not the front-loaded Bézier) |
| Special workspaces | specialws / sysmon / music / communication / todo on SUPER+S/M/D/R, CTRL+SHIFT+Esc | all five | kept |
| Special animation | vertical slide + fade 15 %, `specialWorkSwitch` (.05,.7,.1,1) 320 ms, no blur | `slidefadevert 15 %` on the snappy spring | kept |
| specialWsCloseAny | on | on | kept |

## Window animations

| Feature | Arch value | SkyRose before | Action |
|---|---|---|---|
| Open | popin 80 %, riko spring, 320 ms nominal (≈600 ms visible) | popin 85 %, snappy spring ≈ 300 ms (opens mostly show live, see LIMITATIONS) | **fixed**: popin 80 %; liquid phase: ζ 0.58 spring, swells to ≈ 102 %, 300 ms |
| Close | `emphasizedAccel` 240 ms + fade | 180 ms | **fixed**: 240 ms (inside the 150–300 range) |
| Move / resize / retile | riko spring 320 ms nominal (≈700 ms) | snappy spring ≈ 300 ms | liquid phase: ζ 0.72 spring (≈ 3.9 % swing), 300 ms |
| Mouse drag/resize | not animated | snapshot follows the pointer, no spring | kept |
| fade / fadeDim | 480 ms `standard` | 200 ms | kept (decision: capped) |
| Float on | ≈220 ms | spring ≈ 300 ms | kept |

## Shell (Caelestia)

| Feature | Arch value | SkyRose before | Action |
|---|---|---|---|
| Scheme | dynamic tonal-spot dark; base .75, layers .35 | same values; `schemeMode` static by default | kept |
| Shell duration scale | 0.8 | 0.8 | kept |
| Bar | left, ~60 px, hidden, reveals at x = 0, hides on leave | left, 48 pt, reveals on the left band | **fixed**: 60 pt |
| Bar reveal pushes tiles | yes | no (overlay) | kept (decision) |
| Bar content | logo, workspace column (dots / pills with app icons), vertical active title, clock HH/MM/am, status pill (audio, network), red power | same modules (logo is the Apple logo; SF Symbols for Material icons) | kept |
| Bar timing | in ≈ 420 ms, out ≈ 420 ms measured (bar_open / bar_close clips) | 400 ms × 0.8 in, 250 ms × 0.8 out | kept (decision) |
| Drawer shape | rounded blobs joined to the frame by concave fillets | `DrawerPath` blobs with fillets | kept |
| Dashboard | top centre; **revealed by hovering the top band over its width**; tabs Dashboard, Media, Performance, Weather | top centre; keybind/IPC only; no Weather tab | **fixed**: top-band hover (Caelestia `inTopPanel`; the notch dip counts as band; 100 ms dwell so crossing to the menu bar does not flash it). On a display whose menu bar auto-hides, the same edge also reveals the macOS menu bar (limit). **fixed (this phase)**: Weather tab + Overview card from Open-Meteo, city picked in Settings |
| Launcher | bottom centre, SUPER tap | same | kept |
| Sidebar | right, SUPER+N; notifications (upstream shows utilities with it) | right; notifications **and** utilities in one panel | kept (matches upstream: sidebar + utilities together) |
| Utilities | bottom right; **revealed by hovering the bottom-right corner**; keep awake, screen recorder, quick toggles | merged into the sidebar | **fixed**: own bottom-right drawer + corner hover (Caelestia `inBottomPanel`) |
| OSD | right edge, vertical sliders; volume keys or **right-edge hover** | volume/brightness keys only | **fixed**: right-edge hover over the OSD's height (Caelestia `inRightPanel`) |
| Session | right edge, 5 round buttons, **dims the screen** | 5 buttons, no dim | **fixed**: screen dim behind the session menu |
| Drawer timing | open 230–520 ms, close 130–170 ms | open 117–283 ms, close 150–167 ms | kept (decision) |
| Toasts / notifications | top-right | top-right | kept |
| Hover leave | panel hides once the pointer leaves the panel (+ rounding) | n/a | **fixed** for the hover-opened drawers (a keybind-opened drawer stays until toggled) |

## Input that the pack could not capture

The capture had no click, scroll or typing injection (no ydotool/wtype). For these, SkyRose follows
Caelestia/Hyprland upstream source and docs:

| Feature | Upstream behaviour | SkyRose |
|---|---|---|
| Bar clicks | workspace pill click focuses it; status icons open popouts; power opens session | same |
| Bar scroll | scroll over workspaces = ±1 workspace | same |
| Launcher typing | fuzzy app search, ↑/↓, Return launches, Esc closes; `>` prefixes for actions | same subset |
| Drawer drags | dragging from the right edge opens the session/sidebar (`Interactions.qml`) | **fixed (this phase)**: drag or two-finger swipe from the right band; session past 30 pt within its height, sidebar past 80 pt elsewhere; the frame stays click-through (passive monitors) |
| Tab groups with 2+ tabs | Hyprland groups docs | see Groups |

## SkyRose-only items in this phase

- **done** Settings: window radius 15 (= WM rounding), blur masked, sidebar an inset panel
  with concentric corners; the WM waits for / refuses a second instance, rebinds a lost
  socket, and the running status is live.
- **done, live-tested** Windows › "Red button quits the app" (opt-in, default off; exceptions,
  Finder by default; Dock apps only; normal quit). TestWindows: with 2 windows only the clicked
  one closed; the last one quit the app; with the option off the app kept running.
- **done, live-tested** A WM restart keeps every window on its workspace and side
  (`session.json`; see docs/parity-progress.md).
- **done, live-tested** Appearance › Cursor: Bibata Modern Classic for the login session, at the
  cape's 24 pt size and hotspots (Arch `cursorSize = 24`; left_ptr hotspot 55,17 of 256 → 5.16,1.59).
  Every cursor except the spinning wait cursor, which macOS cannot restore once replaced, so it
  stays macOS's (said in Settings). Reset, WM quit and `skyrose cursor reset` put back the exact
  originals (registry diff identical). Note: the capture's `hypr/variables.lua` names
  `cursorTheme = "sweet-cursors"`; Bibata is what Gabby asked for and what the Mousecape cape is.

## Questions answered before the big changes

- Border colour fade: **480 ms like Arch** (exception to the 350 ms cap).
- New window side: **follow the cursor** (force_split 0); cursor outside the tile → right/bottom.

## Liquid motion pass (2026-11-05)

Measured from `screencapture -v` clips (60 Hz) in `/tmp/cwm/liquid/` against
`~/caelestia-ref/full-2026-11-05/04-caelestia/*_frames`:

| Motion | Arch | SkyRose before | SkyRose after |
|---|---|---|---|
| Sidebar open | full height at once, grows out in ≈ 190 ms, ≈ 1 % swing | slides, full in ≈ 130 ms, no swing, 180 ms panel fade | grows out of the edge, 96 % at 100 ms, peaks +4.6 % (≈ 18 pt) at 133 ms, settled at 233 ms |
| Launcher open | grows from the bottom band | slides up, full at ≈ 100 ms, ≈ 1 % swing | narrow neck widens while it grows; peaks +3 % (≈ 16 pt) at 183 ms, settled ≈ 300 ms |
| Dashboard open | drops from the top band | slides down, ≈ 1.7 % swing | neck widens, bottom swings ≈ 16 pt past, settled ≈ 220 ms |
| Drawer close | shrinks into the frame | slide + fade 170 ms | shrink + fade, 167–183 ms |
| Window retile | riko spring, ≈ 700 ms | snappy spring, ≈ 1 % | ζ 0.72, visible swing, ≈ 250 ms |
| Window close (WM) | shrink + fade | same | same; neighbour springs to full width by ≈ 317 ms |
| Workspace slide | snappy Bézier 320 ms | snappy spring | snappy Bézier 320 ms (brief) |
