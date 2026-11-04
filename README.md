# Caelestia for Mac

A native macOS (Apple Silicon, macOS 14+) port of Gabby's Arch Linux desktop: **Hyprland**
dwindle tiling + the **Caelestia** shell, so her muscle memory carries over — same keybinds
(Super = left Option), gaps, 1 px periwinkle borders, 15 px corners, the left bar, launcher,
dashboard, sidebar, session menu, OSDs and the springy animation feel.

Swift + AppKit/SwiftUI only. No Electron, no web views, no root, no SIP changes (Enhanced mode is
optional and documented, never required).

> **School laptop note:** Standard mode changes nothing at system level without asking you
> first, and everything it does change is journaled and reversible. Check your school's IT rules
> before enabling Enhanced mode (it lowers SIP).

## Components

| Component | What it is |
|---|---|
| `CaelestiaWM.app` | agent app (no Dock icon): the window manager, the shell (bar, panels, OSDs, frame, launcher), the IPC server |
| `caelestia` | CLI inside the app bundle (symlinked to `~/.local/bin` on request): `hyprctl` + Linux `caelestia` in one |
| `TestWindows.app` | harness for the Riko regression suite |
| Caelestia Settings | Phase 8 — not in this build; edit `~/.config/caelestia-mac/*.toml` (hot reload) |
| CaelestiaSA | Phase 10 — not in this build (Enhanced mode) |

## Quick start

```sh
git clone <this repo> caelestia-mac && cd caelestia-mac
scripts/sign-setup.sh      # once: local signing cert so permissions survive rebuilds
scripts/install.sh         # builds, copies to ~/Applications, opens the first-run wizard
```

Then grant **Accessibility** and **Input Monitoring** when asked (see
[docs/PERMISSIONS.md](docs/PERMISSIONS.md)). Press **⌥L** (tap) for the launcher, **⌥L+1…0**
for workspaces, **⌥L+T** for kitty, **⌥L+Q** to close. Full table: [docs/KEYBINDS.md](docs/KEYBINDS.md).
Panic chord (always on): **⌃⌥⌘⇧Esc** stops tiling and brings every window back on screen.

## Standard vs Enhanced

| Feature | Standard (SIP on) | Enhanced (SIP partly off) |
|---|---|---|
| Dwindle tiling, gaps, splits | yes | yes |
| Workspaces 1–10 (+ groups to 50) + special | yes (virtual, off-screen parking) | yes (virtual, or native Spaces option) |
| Instant workspace switch | ~fast; AX moves 5–30 ms per window | instant (SkyLight batch) |
| Window borders | overlay windows | overlay or SA-drawn |
| Rounded 15 px window corners | overlay stroke + optional corner caps (can't clip other apps) | no (macOS draws its own ≈10 pt corners; Tahoe ≈16 pt) |
| Window opacity 0.94 | no | yes |
| Window blur behind | no | partial |
| Open/close/move/drag animations | snapshot stills animate on an overlay, real windows move once underneath (app-initiated closes: neighbours only) | planned: real windows via the SA (`WindowAnimator` hook) |
| Special workspace slide-in | snapshot slide/fade, then snap | real windows slide |
| Pin (all workspaces) | yes (WM keeps it visible) | yes (sticky + level) |
| Always on top | no | yes |
| Hide stock menu bar / Dock | yes (System Settings auto-hide, with backup) | yes |
| Focus without raise | no | yes |
| Fullscreen (true) | our "zoom" fullscreen fills the screen; native fullscreen opt-in per app | same |
| Mouse drag/resize with ⌥L | yes (event tap + AX) | yes, smoother |
| Trackpad gestures | public APIs only, opt-in | + MultitouchSupport |
| Secure input (password fields) | hotkeys pause while another app holds Secure Event Input; OSD explains | same |

Details and the full honest list: [docs/LIMITATIONS.md](docs/LIMITATIONS.md).

## Safety promises

- never destructive: user files go to the Trash, never `rm -rf`; nothing under `/System` or
  `/Library` is touched; no SIP / NVRAM / boot-args / firewall / MDM changes;
- no `curl | sh`, no piped installers; downloads are pinned + SHA-256 checked or Homebrew;
- no `sudo` in Standard mode, never passwordless sudo;
- every `defaults` key, hidutil mapping, wallpaper, kitty config, login item or font we change is
  recorded first in `~/Library/Application Support/CaelestiaMac/backup.json` and restored by the
  uninstaller — even if the app is already gone;
- no stored secrets; logs redact window titles by default;
- crash-safe: parked windows are journaled before they are moved and restored on relaunch.

## Uninstall

`caelestia uninstall` or `scripts/uninstall.sh` — see [docs/UNINSTALL.md](docs/UNINSTALL.md).

## Building and testing

```sh
scripts/build.sh                 # release build + signed bundles in dist/
xcrun swift test                 # unit tests (Core, Layout, IPC, Platform, Services, Overlay)
scripts/test-integration.sh      # Riko regression suite (needs permissions; spawns TestWindows.app)
```

Always use the Xcode toolchain (`xcrun swift`), not a swift.org toolchain.

## Docs

[DESIGN](docs/DESIGN.md) · [ARCH_TO_MAC](docs/ARCH_TO_MAC.md) · [KEYBINDS](docs/KEYBINDS.md) ·
[LIMITATIONS](docs/LIMITATIONS.md) · [PERMISSIONS](docs/PERMISSIONS.md) ·
[ENHANCED_MODE](docs/ENHANCED_MODE.md) · [UNINSTALL](docs/UNINSTALL.md) ·
[CURSOR](docs/CURSOR.md) · [TROUBLESHOOTING](docs/TROUBLESHOOTING.md)

## Credits and license

Re-created from scratch in Swift; the look and behaviour follow
[Caelestia](https://github.com/caelestia-dots/shell) (GPL-3.0) and
[Hyprland](https://hyprland.org). Ideas from [AeroSpace](https://github.com/nikitabobko/AeroSpace)
(off-screen workspace parking), [yabai](https://github.com/koekeishiya/yabai) (scripting-addition
design), [JankyBorders](https://github.com/FelixKratz/JankyBorders) (border overlays),
[Mousecape](https://github.com/alexzielenski/Mousecape) and
[Bibata](https://github.com/ful1e5/Bibata_Cursor) (cursor). No code was copied from any of them.
Material Symbols (Apache-2.0). TOMLKit (MIT).

This project is licensed under **GPL-3.0** (see LICENSE): the shell layouts, the bongo-cat idea
and the panel designs follow Caelestia closely enough that keeping the same license is the
honest choice.
