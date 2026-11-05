# Limitations (honest list)

Things macOS does not allow, or that this build does not do yet. Nothing here is faked: when a
feature cannot work, the UI says so and the closest substitute is used.

## Imposed by macOS (Standard mode, SIP on)

| Arch feature | On the Mac | Why |
|---|---|---|
| Window opacity 0.94 + blur behind other apps' windows | **Not possible.** Our own panels (bar, drawers, OSDs) get the full glass look; third-party windows stay opaque. kitty gets its glass from its own `background_opacity` / `background_blur`. | Only the window server (or a scripting addition in the Dock, Enhanced mode) can change another app's window alpha. |
| 15 px rounded window corners | Border overlay is drawn at 15 px; the real window keeps the macOS corner (≈10 pt on Sonoma/Sequoia, ≈16 pt on Tahoe). Optional corner caps hide the difference. | Other apps' windows cannot be clipped. |
| Smooth open/move animations of real windows ("popin 80 %", spring moves) | **Snapshot animations** (`animations.windows = "snapshot"`, default): a ScreenCaptureKit still of each window springs from the old to the new frame on an overlay cover while the real window gets its final frame once underneath; close shrinks and fades, a dragged tiled window follows the pointer with a drop preview. Stills are never stretched: drawn 1:1, clipped, over their average colour, then cross-faded to a capture at the new size when one arrives (40–400 ms). They are pictures, up to a few seconds old (no live video while the cover is up, ~0.3-0.35 s). **Opens almost never pop in**: only from a still at the final size within one frame, which a brand-new window does not have; it is shown live in its slot instead. | Each AX frame change is a synchronous IPC round trip into the target app; animating real windows needs the window server (Enhanced mode hook, not built). |
| Close animation of windows closed by the app itself (⌘W, red button) | Only the **neighbours** animate into the freed space; the closed window just disappears. Closes through the WM (`window close`, keybind) shrink and fade. | macOS removes the window before the AX "destroyed" notification arrives; drawing its still again afterwards flashed it back for a frame (live finding). |
| Animations on app switch / hide / minimize | None: those passes move windows instantly (also windows found at start). | Stills of reappearing windows are stale or the wrong size; stretched stills for ~1 s were the live finding. |
| Window animations, first pass and fallbacks | The first layout pass after start, a pass whose stills are missing (window never captured, new display/Space), or no Screen Recording permission is an **instant move**. Group bars are not drawn on the cover, and another app's floating-level windows are hidden under the cover for the ~0.3-0.35 s it is up. | Captures take 12–300 ms (p50 18 ms per window, 120 ms per desktop), far longer than a frame, so animations only use stills already cached. |
| Special-workspace slide of real windows | The special workspace fades/slides a snapshot (needs Screen Recording), then the real windows appear in place. | Same as above. |
| Always-on-top for other apps' windows | **Not possible** in Standard mode. "Pin" is honoured by the WM (the window is kept visible on every workspace) but a floating window of another app can still cover it. | Window level is per-process. |
| Focus without raise | **Not possible**; focusing raises. | AX focus always raises. |
| Instant workspace switch | Each window move is an AX call (5–30 ms). Six windows switch in well under 120 ms; 20 windows take longer. | — |
| Stock volume/brightness HUD | Hidden for the F-row keys when SkyRose can do the change itself (CoreAudio volume settable, DisplayServices brightness controllable): the key is swallowed and only our OSD shows. When it cannot (see the next row), the key passes to macOS and only Apple's HUD shows, never our volume OSD. `input.interceptMediaKeys = false` restores pass-through (both HUDs). | Interception needs the event tap (Input Monitoring). |
| Brightness control | Needs **DisplayServices (private API, `dlopen`)**: built-in and Apple displays are controlled; the target is the display under the pointer if controllable, else the built-in. External non-Apple displays (e.g. the DELL U3417W) are not controllable (no DDC): with the pointer there the built-in is adjusted; if no display is controllable the key goes to macOS (Apple HUD only). Volume on outputs without a settable volume (some HDMI/DisplayPort) also goes to macOS (Apple's "not available" HUD). | Private API, see DESIGN D12. |
| Window minimum sizes | AX has **no minimum-size attribute** (probed: Finder, Firefox, T3 Code, kitty, Cursor, Teams expose only `AXSize`). A minimum is learned only after the app refuses a smaller size twice (one extra layout pass). Gaps and borders are counted conservatively, so a window may get a few points more than its minimum (825 for an 800 minimum). Per-app hints are a max over the app's windows. | No public API. |
| Apps that refuse to grow | A fixed or self-sized window stays at its own size in the top-left of its slot (not fought, no overlap); the border ring is drawn around the slot, not the smaller window. | The app owns its window size. |
| New and app-closed windows | A window closed by its app (not by the WM's close action) vanishes at once; only the neighbours animate. A new window can be shown by macOS for a frame at the app's default position before the cover goes up. | macOS acts before the WM hears of it. |
| Workspace slide start | The first frame or two can be dropped while WindowServer is busy un-parking/resizing heavy apps (seen with Firefox + Electron apps). A workspace switch during a running slide finishes that slide at once before the next starts (no retarget across workspaces yet). | WindowServer load; not built. |
| Shell drawer opening | SwiftUI on the main thread drops one frame at the start of opening; the window alpha fade is window-server driven. | Main-thread layout of the first frame. |
| Tray for other apps' menu-bar extras | The bar shows **our** items only, plus a button that reveals the stock menu bar. | macOS has no public API to host other apps' status items. |
| Reading other apps' notifications | The sidebar shows notifications from **SkyRose components and `skyrose notify`** only. | No public API; scraping the Notification Center database is not acceptable. |
| Lock screen | ⌥L+L triggers the **real macOS lock screen** (⌃⌘Q). No custom lock screen. | A custom lock screen cannot secure the session. |
| Hotkeys while another app holds Secure Event Input | Hotkeys pause; the OSD names the app. | macOS rule for every event tap. |
| Cursor theme (Bibata) | Exported as a Mousecape `.cape` (Phase 9) and applied by Mousecape, not by us. Zero-install fallback: the Accessibility pointer size/colour settings. | No public cursor-theme API. |
| Trackpad gestures (3/4-finger) | Opt-in, public `NSEvent` gesture API only; macOS owns 3/4-finger swipes until you turn them off in Trackpad settings. | — |
| Now playing (media card) | Spotify and Music via AppleScript (asks for Automation once each). Other players: controls only through media keys. | MediaRemote is restricted to Apple-entitled processes on macOS 15.4+. |
| Wi-Fi network name | Needs the Location permission on macOS 14+; otherwise the bar shows "Connected". | Apple policy. |
| Temperature in the Performance tab | Hidden. | SMC reads need root/private API. |
| Shell tray, part 1 | Other apps' menu extras are not shown; the bar's tray button only reveals the menu bar. | Same as the Tray row above. |
| Bar hover with synthetic pointer moves | `CGWarpMouseCursorPosition` does not trigger the bar's hover reveal; real mouse movement does. | Warps post no mouse-moved event. |
| Quick toggles | Wi-Fi, Do-not-disturb (SkyRose toasts only) and Keep awake switch. **Bluetooth and macOS dark mode are read-only** and open System Settings; macOS Focus cannot be switched. | No public API; private hacks or silent system changes are not used. |
| Notification history | Our own toasts and `skyrose notify` only; kept in `~/Library/Application Support/SkyRose/notifications.json`. | See the notifications row above. |
| Dashboard temperatures | Only the thermal pressure level; degrees hidden. | SMC needs root. |
| Dashboard weather | Placeholder card; no Weather tab. | No weather service yet. |
| Dynamic colours | Follow the wallpaper macOS reports for the main display (or the one picked here); dynamic/aerial wallpapers fall back to the static scheme. | No public colour feed. |
| Fonts and icons | Rubik / Inter / CaskaydiaCove / Material Symbols are not installed or bundled yet; the shell uses SF Pro and SF Symbols. The `fontSans` chain uses Rubik/Inter once installed. | Material Symbols bundling is TODO (spec 7.1). |
| Session menu mascot | A drawn moon glyph placeholder; no character art is shipped. | — |
| Brightness slider | Hidden when no display is controllable (external non-Apple displays only). | See the brightness row above. |
| `middle_click_paste`, `hotspot_padding`, XWayland rules, env.lua | Not applicable on macOS. | — |

## Not built in this version (planned phases)

| Phase | Item | Status |
|---|---|---|
| P6 | (shell parts 1 and 2 are built: see SHELL.md; the rest below is not) Weather tab, screen recorder card; screenshot/colour-picker UI; clipboard/emoji pickers | services exist (`CaelestiaServices`) for some; the UIs are not wired yet |
| P7 | Wallpaper-driven dynamic colour (Material "tonal spot") | static themes only (SkyRose Dynamic dark snapshot, SkyRose Default, Catppuccin Mocha, Noctalia); accent override is an approximation |
| P8 | SkyRose Settings is built (General, Appearance, Windows, Window rules, Keybinds, Bar and Shell, Terminal, Permissions, About) but not the Enhanced-mode, Backup & uninstall or installer pages | the uninstaller is not built yet; `skyrose keys check` / `skyrose doctor` cover the checks |
| P9 | kitty config installer, fonts installer, xcursor2cape | kitty theme file is written from the scheme; the installer/cursor tool are not built |
| P10 | Enhanced mode scripting addition | not built; documented in ENHANCED_MODE.md, capability probe reports Standard |
| P11 | Fresh-Mac install→uninstall QA pass | not performed |

See the end-of-build report in README.md for what was verified.
