# SkyRose

*(formerly "Caelestia for Mac"; the window manager is **SkyRose WM**)*

*Official website here: **https://ground-pocket-866h.here.now/***

A native macOS (Apple Silicon, macOS 14+) port of Gabby's Arch Linux desktop: **Hyprland**
dwindle tiling + the **Caelestia** shell, so her muscle memory carries over — same keybinds
(Super = left Option), gaps, 1 px periwinkle borders, 15 px corners, the left bar, launcher,
dashboard, sidebar, session menu, OSDs and the springy animation feel.

Swift + AppKit/SwiftUI only. No Electron, no web views, no root, no SIP changes (Enhanced mode is
optional and documented, never required).

> **School laptop note:** Standard mode changes nothing at system level without asking you
> first, and everything it does change is recorded and meant to be reversible. Check your school's
> IT rules before enabling Enhanced mode (it lowers SIP).

## Components

| Component | What it is |
|---|---|
| `SkyRose.app` | agent app (no Dock icon, executable `SkyRoseWM`, bundle id `com.skyrose.mac`): the window manager, the shell (bar, panels, OSDs, frame, launcher) and the IPC server |
| `skyrose` | CLI inside the app bundle (`SkyRose.app/Contents/MacOS/skyrose`, optionally linked to `~/.local/bin/skyrose`): `hyprctl` + Linux `caelestia` in one. `caelestia` still works as a deprecated alias for one release and prints a notice |
| `SkyRose Settings.app` | settings app (`com.skyrose.mac.settings`) and first-run onboarding; changes apply live |
| `TestWindows.app` | harness for the Riko regression suite |
| CaelestiaSA | Phase 10 — not in this build (Enhanced mode) |

## Settings, onboarding and WM-only mode

**SkyRose Settings** has pages General, Appearance, Windows, Window rules, Keybinds, Bar and
Shell, Terminal, Permissions and About. Changes go through the config API (`config.set` over IPC)
and apply live; when SkyRose is not running, Settings writes `~/.config/skyrose/config.toml`
directly. You can still edit the TOML files by hand (hot reload).

**Onboarding** runs on first launch (re-run it from Settings > General or with `skyrose onboarding`):
mode, permissions (Accessibility, Input Monitoring, Screen Recording, with live status and a button
that opens the exact System Settings pane; the step moves on when they are granted), one
**Use recommended** button (hide the Dock, auto-hide the menu bar, Bibata, a starter wallpaper,
automatic corners; only on click, undoable, recorded in the restore manifest), then optional kitty
and fonts, then a cheat sheet. If a permission is lost later, only that step is shown again.
Focus behaviour is in [docs/FOCUS.md](docs/FOCUS.md). Settings › SIP-off mode walks through
Enhanced mode and does not change SIP itself.

**Modes.** `[general] mode = "full"` is the whole desktop. `mode = "wm"` is WM-only: tiling, keybinds
and borders, with no bar, shell or frame. In full mode `[shell]` has an `enabled` switch and
per-module toggles (launcher, dashboard, sidebar, session, osd, notifications, wallpaperPicker);
the bar has `bar.show*` module toggles; `wm.bordersEnabled` turns borders off and
`animations.reduceMotion` swaps animations for short cross-fades.

**Terminal.** ⌥L+T opens the terminal picked in Settings › Terminal: kitty (default), Rex,
Terminal, iTerm2, Ghostty, WezTerm or any bundle id / command; a missing app falls back to macOS
Terminal. Settings › Terminal › kitty setup (or `skyrose kitty install`) adds one include line to
`kitty.conf` for Gabby's Arch kitty settings and colours that follow the SkyRose scheme live.
SkyRose never installs kitty itself.

**Fonts.** Settings › Appearance › Fonts (or `skyrose fonts download`) fetches the Arch fonts
(Rubik, Inter, CaskaydiaCove and JetBrainsMono Nerd Fonts, Material Symbols; OFL / Apache, pinned
and checksummed, see docs/FONTS.md) for SkyRose's own use; "Install for kitty and other apps"
copies them into ~/Library/Fonts.

**Not in this build:** a module store. Install and uninstall are in the sections below.

## Upgrading from Caelestia for Mac

On the first SkyRose start the old data is migrated once, automatically (also available as
`skyrose migrate`; skipped while the old CaelestiaWM is still running): `~/.config/caelestia-mac`
to `~/.config/skyrose`, `~/Library/Application Support/CaelestiaMac` to `.../SkyRose` (`backup.json`
is now `restore-manifest.json`). Env vars `CAELESTIA_*` are now `SKYROSE_*`. The old scheme names
`caelestia-*` are still accepted (new names: `skyrose-default`, `skyrose-dynamic`,
`skyrose-dynamic-dark`). The bundle id changed, so **grant the permissions once more** to
SkyRose.app. A signing certificate named "Caelestia Local Signing" is kept and used; new setups
create "SkyRose Local Signing".

## Quick start

From a release, without Xcode (the hash is the `SkyRose-<version>-arm64.zip.sha256` file next to the zip):

```sh
curl -fsSLO https://github.com/ganya002/skyrose/releases/download/v0.7.0/install.sh
curl -fsSLO https://github.com/ganya002/skyrose/releases/download/v0.7.0/install.sh.sha256
shasum -a 256 -c install.sh.sha256
less install.sh
sh install.sh --dry-run
sh install.sh
```

That build is signed on the build machine, not with an Apple Developer ID, and it is not notarized.
`sh install.sh` opens the SkyRose installer window. Add `--yes` to stay in the terminal.
There is no Homebrew cask. A copy that is already installed can look for a newer release with
`skyrose update` (see [docs/UPDATING.md](docs/UPDATING.md)); installing one always takes a click or
`--yes`.

From a git checkout (needs Xcode):

```sh
git clone https://github.com/ganya002/skyrose.git && cd skyrose
scripts/sign-setup.sh      # once: local signing cert so permissions survive rebuilds
scripts/install.sh         # builds, copies to ~/Applications, opens the onboarding
```

Then grant **Accessibility**, **Input Monitoring** and **Screen Recording** when the onboarding
asks (see [docs/PERMISSIONS.md](docs/PERMISSIONS.md)). Press **⌥L** (tap) for the launcher,
**⌥L+1…0** for workspaces, **⌥L+T** for your terminal (kitty by default), **⌥L+Q** to close. Full
table: [docs/KEYBINDS.md](docs/KEYBINDS.md).
Panic chord (always on): **⌃⌥⌘⇧Esc** stops tiling and brings every window back on screen.

## Standard vs Enhanced

| Feature | Standard (SIP on) | Enhanced (SIP partly off) |
|---|---|---|
| Dwindle tiling, gaps, splits | yes | yes |
| Workspaces 1–10 (+ groups to 50) + special | yes (virtual, off-screen parking) | yes (virtual, or native Spaces option) |
| Instant workspace switch | ~fast; AX moves 5–30 ms per window | instant (SkyLight batch) |
| Window borders | overlay windows | overlay or SA-drawn |
| Rounded 15 px window corners | overlay stroke + optional corner caps (can't clip other apps) | no (macOS draws its own ≈10 pt corners; Tahoe ≈16 pt) |
| Window opacity 0.95 | no | yes |
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
- the release install is download, check SHA-256, read the script, then `sh install.sh`
  (a pipe can run it, but that skips the read and is not the path above); the zip is pinned to a release;
- no `sudo` in Standard mode, never passwordless sudo;
- every `defaults` key, hidutil mapping, wallpaper, kitty config, login item or font we change is
  recorded first in `~/Library/Application Support/SkyRose/restore-manifest.json` for the
  uninstaller to restore (`skyrose uninstall`, or Settings › Backup & uninstall);
- no stored secrets; logs redact window titles by default;
- crash-safe: parked windows are journaled before they are moved and restored on relaunch.

## Uninstall

`skyrose uninstall` or Settings › Backup & uninstall. See [docs/UNINSTALL.md](docs/UNINSTALL.md).

## Building and testing

```sh
scripts/build.sh                 # release build + signed bundles in dist/
xcrun swift test                 # unit tests (Core, Layout, IPC, Platform, Services, Overlay)
scripts/test-integration.sh      # Riko regression suite (needs permissions; spawns TestWindows.app)
```

Always use the Xcode toolchain (`xcrun swift`), not a swift.org toolchain.

## Docs

[DESIGN](docs/DESIGN.md) · [SHELL](docs/SHELL.md) · [KEYBINDS](docs/KEYBINDS.md) ·
[LIMITATIONS](docs/LIMITATIONS.md) · [PERMISSIONS](docs/PERMISSIONS.md) ·
[ENHANCED_MODE](docs/ENHANCED_MODE.md) · [UNINSTALL](docs/UNINSTALL.md) ·
[TROUBLESHOOTING](docs/TROUBLESHOOTING.md) · [IPC schema](Sources/CaelestiaIPC/Schema.md)

## Credits and license

Window management powered by CatWM by Per William Krogstad-Østensen (@noxaur), https://github.com/noxaur/CatWM, used with permission.
SkyRose runs CatWM (Apache-2.0) with a few SkyRose changes on the `skyrose` branch of
https://github.com/ganya002/CatWM; see [docs/catwm-modding.md](docs/catwm-modding.md).

SkyRose (formerly "Caelestia for Mac") is re-created from scratch in Swift; the look and
behaviour follow [Caelestia](https://github.com/caelestia-dots/shell) (GPL-3.0) and
[Hyprland](https://hyprland.org). Ideas from [AeroSpace](https://github.com/nikitabobko/AeroSpace)
(off-screen workspace parking), [yabai](https://github.com/koekeishiya/yabai) (scripting-addition
design), [JankyBorders](https://github.com/FelixKratz/JankyBorders) (border overlays),
[Mousecape](https://github.com/alexzielenski/Mousecape) and
[Bibata](https://github.com/ful1e5/Bibata_Cursor) (cursor). No code was copied from any of them.
Material Symbols (Apache-2.0). TOMLKit (MIT).
Bongo Cat sprite from Caelestia (caelestia-dots/shell, GPL-3.0); original Bongo Cat by StrayRogue & DitzyFlama.

This project is licensed under **GPL-3.0** (see LICENSE): the shell layouts, the bongo-cat idea
and the panel designs follow Caelestia closely enough that keeping the same license is the
honest choice.
