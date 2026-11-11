# Native shell (part 1)

The SkyRose shell (modelled on the upstream Caelestia shell) is drawn natively (SwiftUI + AppKit) inside the WM process, in the
`CaelestiaShell` module. Part 1 is: screen frame, left bar, launcher, session menu,
volume/brightness OSD and toasts. Verified live on a MacBook Air (1470x956) plus an external
3440x1440 display.

Part 2 (below) adds the dashboard, sidebar, bar popouts, wallpaper picker and dynamic colours.
Not built yet: lock-screen cover, screen recorder. See LIMITATIONS.md.

## Screen frame

A click-through panel per display draws a 10 pt band (`wm.screenFrameInset`) around the screen
with an inner corner radius of 25 (window rounding 15 + outer gap 10). The surface is the scheme
colour at transparency base 0.75 over a behind-window blur. The band is even on all four sides.
The Dock area is left alone. Turn it off with `wm.screenFrame = false`.

**Rounded display corners.** Notched MacBook panels round their *top* corners; their bottom
corners are square or close to it (real-hardware photo: a 10 pt frame corner at the bottom
showed a wedge of wallpaper, because a frame corner rounded more than the hardware leaves
uncovered pixels the hardware still shows). The frame's *outer* edge uses
`frame.displayCornerRadius` at the top corners and `frame.displayBottomCornerRadius` at the
bottom ones, only at corners that are real display corners (not where the band meets a shown
Dock or menu bar). Where the outer corner is rounded, the inner corner is concentric with it:
outer radius − band, so the band keeps one width around the corner (a square inner corner once
the radius is no larger than the band, as with the 10 pt default and the 10 pt band). Square
outer corners keep the theme's 25. Apple does not publish the radii, so they are set by eye:
auto (`-1`) top = 10 pt on a built-in panel with a notch, 0 elsewhere; auto bottom = 0 on
built-in panels, else the top value; per display under `[displays."<uuid>"]`.
`skyrose frame calibrate [display]` draws a thin outline along the display edge at the radii
being tried (the pair being tuned bright) and redraws the frame live: ↑/↓ ±0.5 pt, ⇧↑/⇧↓
±0.1 pt, Tab top/bottom corners, ←/→ other display, Return saves every changed value into
config.toml (only those keys are written; comments and other settings stay), Esc cancels. When
the radius matches, the line runs around the corner at an even width; too large and the
wallpaper shows outside it, too small and the hardware corner cuts the line off. Err small: a
radius smaller than the hardware's is hidden by the corner.

**Notch / cutouts.** Each display's cutouts are read from macOS, never from a model list: the
top safe-area strip (`NSScreen.safeAreaInsets.top`) minus `auxiliaryTopLeftArea` and
`auxiliaryTopRightArea`. Whatever is left (one notch today, any number or shape tomorrow; slivers
under 2 pt are ignored) is a cutout. The frame's top band then dips around each cutout with
rounded inner corners (12 pt at the bottom of the dip, 8 pt where it joins the band), instead of a
dark full-width menu-bar strip. Displays without a cutout (externals) get the plain even band.
Windows keep clear of the whole safe-area strip (`query monitors` reserved top = 42 on the
MacBook Air: 32 strip + 10 band; 10 on the external). Drawers that reach the top (dashboard,
sidebar, popouts) start below a cutout only where they overlap it. With the menu bar set to
always show (`_HIHideMenuBar` off), the frame starts below it and there is no dip. Display
changes and hot-plug re-read all of this. Screenshot: `/tmp/cwm/anim/notch-frame.png`.

## Bar (left, 48 pt)

With `bar.persistent = false` (current default in the author's config) the bar is hidden and
slides in when the pointer touches the left band; it hides 0.25 s after the pointer leaves. While
shown it widens the frame's left band and **overlays** the windows: an auto-hidden bar (and every
drawer: sidebar, dashboard, popouts, launcher) never reserves space or retiles, so windows never
move when the pointer reaches an edge (live finding: the reveal used to retile and dwindle flipped
the split, so windows jumped up and down). With `bar.persistent = true` it is always shown and
reserves max(frame, bar width) = 48 pt. Nothing on the top edge moves windows either.

Top to bottom:

- Apple logo: opens the launcher.
- Workspace pills: 5 (`workspacesShown`) of the current group. Active = filled pill, occupied =
  dot, empty = faint dot. Click to focus, scroll to switch.
- Active window: app icon and a vertical title.
- Tray button: macOS has no public API for other apps' menu extras. The button moves the pointer
  to the top edge so the auto-hidden menu bar appears.
- Clock (HH over MM).
- Status icons from `bar.statusIcons`: Caps Lock (only while on), audio, network, Bluetooth,
  keyboard layout, battery.
- Power button: opens the session menu.

## Launcher

Open: tap left Option (`launcher.tap`), or Option+Space, or `skyrose shell launcher`.
A bottom-centre drawer whose corners flare into the frame. Sizes were measured from
`Tests/fixtures/ref/1-launcher.jpg` at 1 px = 1 pt: rows 600x57, pitch 65, 32 pt icons, 20 pt
title, 16 pt subtitle, 15 pt padding, 48 pt search pill, at most 7 visible rows.

- Search: fzf-like fuzzy match over name, file name, keywords and description, ranked by launch
  frequency (counts in `launcher-counts.json` in Application Support).
- Apps scanned: `/Applications`, `~/Applications`, `/System/Applications` (+ Utilities), one
  sub-folder level.
- `>` commands: `lock`, `sleep`, `shutdown`, `reboot`, `restart` (SkyRose itself), `logout` go through the session menu's
  confirm step. `scheme`, `wallpaper`, `variant`, `transparency`, `random`, `settings` only show
  an info toast ("later phase").
- `=` or plain math is a calculator; Enter copies the result.
- Keys: Up/Down, Tab, Ctrl+J / Ctrl+K, Enter, Esc. Clicking outside closes it.

The panel is non-activating: typing never activates SkyRose, and closing leaves focus with the
app you were in.

## Session menu

Open: Ctrl+Option+Backspace (`session.toggle`), the bar's power button, or
`skyrose shell session`. A pill on the right edge: Log out, Shut down, an image slot, Sleep,
Restart, then Restart SkyRose (80 pt buttons, radius 22, spacing 15). The last one is not in
Caelestia: it runs the bundled `skyrose restart`, which quits SkyRose (windows restored) and starts
the same app again.

Every action needs a second press within 3 s (the button turns red with a check). Esc disarms,
then closes. The image slot shows a drawn moon glyph; no character art is shipped.

Routes: `osascript` via System Events for log out / shut down / restart (macOS asks for
Automation permission for System Events on first use), `pmset sleepnow` for sleep, and lock posts
Ctrl+Cmd+Q (the real macOS lock screen). Nothing uses sudo.

## OSD

A right-edge drawer with vertical volume and brightness sliders (draggable). It appears on any
volume, mute or brightness change and hides 1.5 s after the last one unless the pointer is on it.
The brightness slider is hidden when the brightness service reports it unavailable (it was on the
test setup). The system volume/brightness keys still reach macOS, so Apple's own HUD shows too.

## Toasts

Toasts and notification popups (`skyrose notify`) share one drawer that grows down out of the
frame's top-right corner as part of the liquid surface, like Caelestia's notifications module
(Gabby's choice: Caelestia itself shows toasts as a card at the bottom-right). Up to 4 cards,
newest on top, 5 s each; a duplicate refreshes instead of stacking; the drawer closes back into
the frame once the last card expires. Measured on notification_popup.mp4: drawer 430 wide,
padding 15 (left/bottom) and 5 (top/right), cards 410 wide with radius 20, a 42 pt icon circle,
summary · time and a one-line body; open 375 ms × the shell scale (0.8) = 300 ms, as in the
capture. Not ported: the expand chevron and swipe-to-dismiss (the drawer is click-through).

    skyrose shell toaster error|warn|info|success <title> <message> <icon>

## Dashboard (part 2)

Top drawer, 860x560 at full size (scaled uniformly to fit smaller screens, never over the notch
strip). Open: bar clock, `skyrose shell dashboard`, or the `panels.showAll` / `dashboard.toggle`
keybinds; click elsewhere closes it. Tabs Overview / Media / Performance / Weather (`dashboard.defaultTab`).
Data: CPU `host_processor_info`, memory `host_statistics64` (active + wired + compressed), disk
`volumeAvailableCapacityForImportantUsage`, GPU IOAccelerator, network `NetworkThroughputSampler`,
battery IOKit, thermal `ProcessInfo.thermalState`, media Spotify/Music via AppleScript. Sampling
runs at 1 Hz only while open. Temperatures: IOKit HID sensors (CPU die, battery, SSD; GPU only
where the chip names one), no root. Hidden: any sensor that is missing, GPU when not reported,
battery on a desktop Mac.

Weather (`[weather]`, Open-Meteo forecast + geocoding, no API key): Settings › Bar and Shell has
the city search; the Overview card and the Weather tab (now, feels like, humidity, wind,
sunrise/sunset, 12 hours, 7 days) show nothing but a set-up hint until a city is set. Refreshed
every `refreshMinutes` (30) and when the dashboard opens on a stale report. "Use my location"
(CoreLocation, off by default) falls back to the city when denied.

Right-edge drags (Caelestia `Interactions.qml`): press on the right frame band and drag left —
past 30 pt within the session menu's height opens the session menu, past 80 pt elsewhere on the
band opens the sidebar. A two-finger swipe left with the pointer on the band does the same. The
frame stays click-through: the WM only watches the pointer.

## Sidebar and popouts (part 2)

Right drawer: notification history, Keep awake, Screen recorder (full main display to the capture
folder, timer while recording, the newest 3 recordings with Show in Finder / Move to Trash; same
recorder as `record.screen` and `skyrose record`), volume/brightness sliders, quick toggles. Real
toggles: Wi-Fi (CoreWLAN `setPower`), Do-not-disturb (SkyRose toasts only), Keep awake (IOPM
assertion; on a Mac with a lid it also sets `pmset disablesleep 1` while it runs, so it survives
closing the lid), and on laptops a lid line with a **Clamshell** chip (lid closed keeps running on
battery / built-in only; see LIMITATIONS.md "Lid closed"). Bluetooth and dark mode are read-only tiles that open System Settings. Notifications
are kept across restarts in `~/Library/Application Support/SkyRose/notifications.json` (the
app's existing support folder; latest 100, rewritten atomically on every change, "Clear all"
empties it). Bar status icons (audio, network, Bluetooth, battery) open popouts on click;
`shell drawers toggle popout.audio|network|bluetooth|battery` does the same.

## SkyStore

A bottom drawer like the launcher (`>store`, `skyrose store`, Settings › SkyStore): browse,
install, update and remove addons. See [SKYSTORE.md](SKYSTORE.md).

## Wallpaper and dynamic colours (part 2)

`>wallpaper` / `shell drawers toggle wallpaper` open a thumbnail strip of `appearance.wallpaperFolder`.
`appearance.schemeMode = "dynamic"` builds a Material You scheme from the current wallpaper
(`CaelestiaCore/Palette`) and applies it to every surface and the borders; `"static"` (default)
keeps the periwinkle scheme. Extraction failure (grey, unreadable, dynamic wallpaper) falls back to
static. Config reload applies it live.

## IPC

    skyrose shell launcher | session | kill | restart
    skyrose shell dashboard | sidebar | clear-notifs
    skyrose shell drawers toggle <name> | isOpen <name> | list   (launcher, session, osd, dashboard, sidebar, wallpaper, store, popout.<kind>)
    skyrose notify <title> [body] [--app NAME] [--icon ICON]
    skyrose wallpaper set <file> | get | list | random
    skyrose shell toaster.<level> ...
    skyrose shell brightness get | set <0..1 | N% | N%+ | N%->

## Config keys

| Key | Effect |
|---|---|
| `bar.persistent` | always shown and reserved, or hover-reveal (overlays windows) |
| `frame.displayCornerRadius`, `[displays."<uuid>"] displayCornerRadius` | physical top corner radius for the frame's outer edge (-1 = auto) |
| `frame.displayBottomCornerRadius`, `[displays."<uuid>"] displayBottomCornerRadius` | physical bottom corner radius (-1 = auto: 0 on built-in panels, else the top value) |
| `bar.showOnHover` | reveal on pointer contact with the left band |
| `bar.width` | bar width (48 pt) |
| `bar.statusIcons` | which status icons appear, in order |
| `wm.screenFrame`, `wm.screenFrameInset` | frame on/off, band thickness (10 pt) |
| `appearance.transparency*` | surface opacity (base 0.75) |
| `appearance.font*` | font chains (`fontSans` etc.) |
| `animations.shellDurationScale` | speed of shell animations |
| `launcher.tap`, `session.toggle` | keybinds |
| `appearance.schemeMode` | `static` (default) or `dynamic` (wallpaper palette) |
| `appearance.wallpaperFolder` | wallpaper picker folder |
| `dashboard.*` | clock seconds, battery card, default tab |
| `animations.windows` | `snapshot` (default) or `off`: window animations, see DESIGN.md |

## Fonts and icons

Rubik, Inter, CaskaydiaCove and Material Symbols are not installed by this phase. The shell falls
back to SF Pro and SF Symbols (Material names are mapped in `ShellIcon`). If Rubik or Inter is
installed later, the `fontSans` chain picks it up. Bundling Material Symbols is still TODO
(spec 7.1).

## Colours

Calibrated against the reference screenshots: launcher background about #14151a over dark windows
(reference #141821); selected row = secondaryContainer at 60 % (ours rgb 43,47,58, reference
41,43,56); search pill = secondaryContainer at 70 % (46,50,62 vs 42,47,67). AppKit blur materials
add a grey base that Hyprland's blur does not, so the darkest material is used.

## Window borders (changed in the same phase)

Borders no longer spring after a retile. They fade out (70 ms) when their window starts moving,
retiling or being dragged, stay hidden until the frame has been still for 150 ms, jump to the
final frame while invisible, then fade in (140 ms). A live trace showed the border x only ever
held the old or the new value. Off with game mode, Reduce Motion or the animations preset off
(then borders snap with the window). While a window animation draws a window (see DESIGN.md,
"Window animations") its border is part of the animation's tile and the border window snaps
underneath, so nothing trails.

**Clicks.** `NSHostingView.hitTest` returns the hosting view itself for every point (SwiftUI draws
controls without NSViews), so the earlier "pass clicks through where the hit is the hosting view"
rule dropped every click on the bar and drawers. Panels now take every click inside their own
frame (an optional geometric `hitRegion` can exclude parts). Verified with real CGEvent clicks at
the real cursor: audio and Wi-Fi icons open their popouts, the clock opens the dashboard
(`/tmp/cwm/anim/bar-click-*-fixed.png`).

## System settings

None are changed. The test Mac already had the menu bar auto-hidden and the Dock on autohide. The
"Make it look like Arch" wizard (spec 5.11) is not built; any future change must be backed up and
asked first.

## How it is built

- `ShellState` (observable) holds everything the shell draws. `ShellBridge`
  (`Sources/SkyRose WMKit/ShellBridge.swift`) mirrors WM state into it after every layout pass
  and forwards shell keybinds and `shell.*` IPC to `ShellController`. The shell calls back into
  the WM only through `ShellHost` / actions, so it can be driven by fake state in tests.
- `ShellController` owns the panels: `Frame/`, `Bar/`, `Launcher/`, `Session/`, `OSD/`,
  `Toasts/`; `Support/ShellPanel` is the non-activating panel base, `Support/ShellGeometry` the
  drawer shape with concave fillets, `Theme/` the scheme-to-colour mapping.
- Window levels: frame and bar at main menu - 1, drawers at pop-up menu, OSD above that.
- Surfaces are re-asserted (immediately and again after 0.3 s) on display change, wake, Space
  change, screen-parameter change and shell restart. Live: after `skyrose shell restart` the
  frame and bar windows were back on both displays within 400 ms at the right level.
- Tests: `Tests/CaelestiaShellTests/` (app index, launcher, bar and geometry, models) and
  `Tests/SkyRose WMKitTests/ShellIntegrationTests.swift`.
