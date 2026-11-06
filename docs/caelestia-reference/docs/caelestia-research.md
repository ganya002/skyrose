# Caelestia shell — research for SkyRose 1:1 polish
Sources: github.com/caelestia-dots/shell @ bcbb5d5 (2026-11-03) and Gabby's Arch reference pack (2026-11-05). Screenshots in this folder are from his machine.

## 0. TL;DR: where the "liquid" comes from
1. **One metaball surface, not separate panels.** `modules/drawers/ContentWindow.qml:160-300`: the screen border frame (`BlobInvertedRect`) and every drawer background (`PanelBg` = `BlobRect`) belong to a single `BlobGroup`. One SDF shader draws them (`plugin/src/Caelestia/Blobs/shaders/blob.frag`) and merges them with a circular smooth-min (`smin`, fillet radius k = `border.smoothing`, default 20; BlobGroup default 32). A drawer looks like it grows out of the border with a concave fillet, and it blends into neighbouring drawers (sidebar ↔ utilities ↔ OSD/session).
2. **Velocity-driven jelly deformation.** `plugin/src/Caelestia/Blobs/blobrect.cpp:48-122`: every frame it reads the panel's screen velocity and stretches along the motion direction, capped at 35%. Each matrix component follows a semi-implicit underdamped spring: stiffness 200, damping 16. Physics starts at speed > 5 px/s and snaps to rest when Σ|Δ| < 0.004 and Σ|vel| < 0.05. The same matrix is applied as a transform to the panel's contents, so the content squashes too. Per-panel `deformAmount` (scale = deformAmount·appearance.deformScale(1)/10000): dashboard 0.1, launcher 0.1, session 0.2, sidebar 0.03, OSD 0.25, notifications 0.15 (default), utilities 0.1 if sidebar visible else 0.15, bar popouts 0.05 detached / 0.15 open / 0.1 otherwise.
3. **Material 3 Expressive overshoot curves** on almost everything (spatial ones overshoot >1). See §2.
4. Drawers slide out from their screen edge (anchor margin = −size·offsetScale) and fade (opacity = 1−offsetScale) at the same time. Content is loaded lazily and stays alive until the close animation finishes.

On macOS this is a single full-screen transparent overlay that draws an SDF metaball shape (Metal shader) and moves the panels inside it. Separate NSWindows with corner radii will not produce the fillets or the merging.

## 1. Hyprland (window manager) animations — NOT the shell
From docs/animations.txt (speed unit = 100 ms):
- windowsIn: spring:riko, speed 3.20 → 320 ms, style popin 80%
- windowsMove: spring:riko, speed 3.20
- windowsOut: emphasizedAccel (.3,0,.8,.15), speed 2.40 → 240 ms
- workspaces/In/Out: snappy (.05,.90,.10,1.05), speed 3.20, style slide
- layersIn: emphasizedDecel (.05,.7,.1,1), speed 4.00, slide
- layersOut: emphasizedAccel, speed 3.20, slide
- specialWorkspace: specialWorkSwitch (.05,.7,.1,1), speed 3.20, style slidefadevert 15%
- fade / border / fadeDim: standard (.2,0,0,1), speed 4.80
- fadeLayers: standard, speed 4.00
Window look: gaps_in 5, gaps_out 10, border 1 px, rounding 15, blur 10/3 passes, shadow range 15 power 4, opacity 0.95.

## 2. Shell animation tokens (Quickshell/QML)
`plugin/src/Caelestia/Config/tokens.hpp`
Curves (cubic-bezier control points):
- emphasized: multi-segment M3 emphasized
- emphasizedAccel (.3,0,.8,.15) · emphasizedDecel (.05,.7,.1,1)
- standard (.2,0,0,1) · standardAccel (.3,0,1,1) · standardDecel (0,0,0,1)
- expressiveFastSpatial (.42,1.67,.21,.9): strong overshoot
- expressiveDefaultSpatial (.38,1.21,.22,1): the default for almost everything
- expressiveSlowSpatial (.39,1.29,.35,.98)
- expressiveFastEffects (.31,.94,.34,1) · DefaultEffects (.34,.8,.34,1) · SlowEffects (.34,.88,.34,1)

Durations in ms: small 200, normal 400, large 600, extraLarge 1000, fastSpatial 350, defaultSpatial 500, slowSpatial 650, fastEffects 150, defaultEffects 200, slowEffects 300.
Gabby's config sets `appearance.anim.durations.scale: 0.8`, so defaultSpatial is about 400 ms, fastSpatial 280, slowSpatial 520, effects 120/160/240.

Wrappers: positions, sizes and scale use Spatial curves (with overshoot); opacity and colour use Effects curves (no overshoot).
Measured at scale 0.8: launcher open ≈380 ms / close ≈130 ms; dashboard open ≈520 / close ≈130; sidebar open ≈230 / close ≈130; utilities open ≈350 / close ≈120; session open ≈180 / close ≈170. Closing looks faster because the overshoot curve leaves the screen early and the fade finishes first.

## 3. Drawer/panel mechanics
`modules/drawers/Panels.qml` layout: OSD (right, vertically centred), notifications (top-right), session (right-centre), launcher (bottom-centre), dashboard (top-centre), bar popouts (next to the bar), utilities (bottom-right), toasts (left of the sidebar / above utilities), sidebar (right, between notifications and utilities).
Each Wrapper uses offsetScale 0 when active / 1 when hidden, slides from its edge, fades with opacity 1-offsetScale, and Behavior on offsetScale is DefaultSpatial (500ms × scale, overshoot). Content stays loaded until the close animation ends.
The launcher freezes its implicitHeight while closing so it does not resize mid-close. Session and OSD get pushed left by the sidebar's width. The panels physically shove each other, and the blob merge makes it look like liquid.
Sidebar ↔ utilities corner morph: radii interpolate; when the sidebar is open the two blobs fuse into one column. Panel radius = rounding.extraLarge (28). Frame: border thickness 10, rounding 25. Shadow: MultiEffect blurMax 15.
Bar popouts: moving between hovered bar icons morphs one popout's size and position instead of spawning a new one.

Triggers (defaults):
- bar: showOnHover true when not persistent (Gabby: persistent false), reveal at the left edge, dragThreshold 20
- dashboard: top-centre hover, showOnHover true, dragThreshold 50
- launcher: showOnHover false, drag up from bottom > 50, or keybind
- sidebar: showOnHover false by default, minHoverThreshold 200, dragThreshold 80. Drag in from the right to open.
- session: right edge, dragThreshold 30
- utilities: hover the bottom-right corner
- OSD: hover the right edge (centre)

## 4. Surfaces
- **Bar** (left, ~60 px, vertical): logo at top; workspace pill column with dots; each occupied workspace shows app icons of its windows (showWindows true, maxWindowIcons 5). THIS vertical rail of icons is the Discord-like dock. A primary-coloured active indicator blob stretches between workspaces: leading edge 500 ms, trailing 1.5× slower (activeTrail true). Middle: active window title rotated vertically. Bottom: calendar + clock, audio/network pill, red power button. Hovering each item opens a popout (see hover/): active window preview (400 px), audio (320), network (320), battery (250), tray, kb layout, lock status.
- **Dashboard** (top-centre, ~854 px): tabs Dashboard / Media / Performance / Weather. Weather card, user card, vertical clock, month calendar with a scalloped today shape, CPU/RAM/disk gauges, media card with wavy progress ring and bongocat.gif. Switching tabs morphs the panel height with overshoot and crossfades content.
- **Launcher** (bottom-centre, item 600×57, maxShown 7): app rows, search pill `Type ">" for commands`. Prefixes: `>` actions (`>wallpaper`, `>scheme`, `>variant`), `@` special.
- **Sidebar** (right, 430 px): notifications list + clear-all FAB, utilities fused below it. Not a Discord dock.
- **Utilities** (bottom-right, 430): Keep awake, Screen recorder, quick toggles (wifi, bluetooth, mic, settings, game mode, DND).
- **Session** (right, 80 px buttons), **OSD** (right, sliders 30×150), **Notifications** (top-right, 430), **Toasts** (scale 0.7→1), **Lock**, **Nexus** (settings), screenshot picker, wallpaper + optional visualiser, dim/blur layer.

## 5. Wallpaper switcher
Opened by typing `>wallpaper ` in the launcher. The launcher morphs into a horizontal PathView carousel (not a grid): centre item scale 1, neighbours 0.8, off-path 0; items pop in from scale 0.5. Live preview: scrolling changes the real desktop wallpaper (and dynamic colour scheme). Closing without picking reverts. Desktop transition uses one of 29 shaders; default crossfade, 600 ms (config `background.wallpaperTransition`).

## 6. Folder map
- shell/ — opened panels and hover-revealed states from Gabby's Arch box
- hover/ — left-bar item hover popouts (the Discord-dock feel)
- motion/ — contact sheets of open/close and hover animations
- tiling/ — dwindle tiling with 0–4 windows
- docs/animations.txt — live Hyprland animation dump from his machine
