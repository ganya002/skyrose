# Limitations (honest list)

Things macOS does not allow, or that this build does not do yet. Nothing here is faked: when a
feature cannot work, the UI says so and the closest substitute is used.

## Imposed by macOS (Standard mode, SIP on)

| Arch feature | On the Mac | Why |
|---|---|---|
| Window opacity 0.94 + blur behind other apps' windows | **Not possible.** Our own panels (bar, drawers, OSDs) get the full glass look; third-party windows stay opaque. kitty gets its glass from its own `background_opacity` / `background_blur`. | Only the window server (or a scripting addition in the Dock, Enhanced mode) can change another app's window alpha. |
| 15 px rounded window corners | Border overlay is drawn at 15 px; the real window keeps the macOS corner (≈10 pt on Sonoma/Sequoia, ≈16 pt on Tahoe). Optional corner caps hide the difference. | Other apps' windows cannot be clipped. |
| Smooth open/move animations of real windows ("popin 80 %", spring moves) | The **border overlay** pops in / springs; the real window snaps to its final frame. Optional "animated tiling" sends ≤ 60 Hz interpolated frames for ≤ 200 ms (off by default: many apps lag). | Each AX frame change is a synchronous IPC round trip into the target app. |
| Special-workspace slide of real windows | The special workspace fades/slides a snapshot (needs Screen Recording), then the real windows appear in place. | Same as above. |
| Always-on-top for other apps' windows | **Not possible** in Standard mode. "Pin" is honoured by the WM (the window is kept visible on every workspace) but a floating window of another app can still cover it. | Window level is per-process. |
| Focus without raise | **Not possible**; focusing raises. | AX focus always raises. |
| Instant workspace switch | Each window move is an AX call (5–30 ms). Six windows switch in well under 120 ms; 20 windows take longer. | — |
| Hiding the stock volume/brightness HUD | **Both HUDs show** when you use the F-row keys: ours (Caelestia style) and Apple's. Our hotkey chords (⌥L⇧M etc.) show only ours. | Suppressing Apple's HUD needs private API. |
| Tray for other apps' menu-bar extras | The bar shows **our** items only, plus a button that reveals the stock menu bar. | macOS has no public API to host other apps' status items. |
| Reading other apps' notifications | The sidebar shows notifications from **Caelestia components and `caelestia notify`** only. | No public API; scraping the Notification Center database is not acceptable. |
| Lock screen | ⌥L+L triggers the **real macOS lock screen** (⌃⌘Q). No custom lock screen. | A custom lock screen cannot secure the session. |
| Hotkeys while another app holds Secure Event Input | Hotkeys pause; the OSD names the app. | macOS rule for every event tap. |
| Cursor theme (Bibata) | Exported as a Mousecape `.cape` (Phase 9) and applied by Mousecape, not by us. Zero-install fallback: the Accessibility pointer size/colour settings. | No public cursor-theme API. |
| Trackpad gestures (3/4-finger) | Opt-in, public `NSEvent` gesture API only; macOS owns 3/4-finger swipes until you turn them off in Trackpad settings. | — |
| Now playing (media card) | Spotify and Music via AppleScript (asks for Automation once each). Other players: controls only through media keys. | MediaRemote is restricted to Apple-entitled processes on macOS 15.4+. |
| Wi-Fi network name | Needs the Location permission on macOS 14+; otherwise the bar shows "Connected". | Apple policy. |
| Display brightness value | Built-in Apple Silicon panels expose no public read API; the OSD tracks the F1/F2 steps. External displays with DDC are not controlled. | — |
| Temperature in the Performance tab | Hidden. | SMC reads need root/private API. |
| Shell tray, part 1 | Other apps' menu extras are not shown; the bar's tray button only reveals the menu bar. | Same as the Tray row above. |
| Stock HUD with the native OSD | Apple's volume/brightness HUD also shows next to ours. | No public way to hide it. |
| Bar hover with synthetic pointer moves | `CGWarpMouseCursorPosition` does not trigger the bar's hover reveal; real mouse movement does. | Warps post no mouse-moved event. |
| Quick toggles | Wi-Fi, Do-not-disturb (Caelestia toasts only) and Keep awake switch. **Bluetooth and macOS dark mode are read-only** and open System Settings; macOS Focus cannot be switched. | No public API; private hacks or silent system changes are not used. |
| Notification history | In memory, our own toasts and `caelestia notify` only. | See the notifications row above. |
| Dashboard temperatures | Only the thermal pressure level; degrees hidden. | SMC needs root. |
| Dashboard weather | Placeholder card; no Weather tab. | No weather service yet. |
| Dynamic colours | Follow the wallpaper macOS reports for the main display (or the one picked here); dynamic/aerial wallpapers fall back to the static scheme. | No public colour feed. |
| Fonts and icons | Rubik / Inter / CaskaydiaCove / Material Symbols are not installed or bundled yet; the shell uses SF Pro and SF Symbols. The `fontSans` chain uses Rubik/Inter once installed. | Material Symbols bundling is TODO (spec 7.1). |
| Session menu mascot | A drawn moon glyph placeholder; no character art is shipped. | — |
| Brightness slider | Hidden when the display reports no brightness (it was unavailable on the test setup). | See the brightness row above. |
| `middle_click_paste`, `hotspot_padding`, XWayland rules, env.lua | Not applicable on macOS. | — |

## Not built in this version (planned phases)

| Phase | Item | Status |
|---|---|---|
| P6 | (shell parts 1 and 2 are built: see SHELL.md; the rest below is not) Weather tab, screen recorder card; screenshot/colour-picker UI; clipboard/emoji pickers | services exist (`CaelestiaServices`) for some; the UIs are not wired yet |
| P7 | Wallpaper-driven dynamic colour (Material "tonal spot") | static themes only (Caelestia Dynamic dark snapshot, Caelestia Default, Catppuccin Mocha, Noctalia); accent override is an approximation |
| P8 | Caelestia Settings app | not built; everything is editable in `~/.config/caelestia-mac/*.toml` with hot reload, and `caelestia keys check` / `caelestia doctor` cover the checks |
| P9 | kitty config installer, fonts installer, xcursor2cape | kitty theme file is written from the scheme; the installer/cursor tool are not built |
| P10 | Enhanced mode scripting addition | not built; documented in ENHANCED_MODE.md, capability probe reports Standard |
| P11 | Fresh-Mac install→uninstall QA pass | not performed |

See the end-of-build report in README.md for what was verified.
