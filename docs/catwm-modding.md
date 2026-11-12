# Modding CatWM for SkyRose (read this before touching CatWM)

SkyRose's default window manager is CatWM by Per William Krogstad-Østensen (@noxaur,
https://github.com/noxaur/CatWM), used with permission. SkyRose runs a modded CatWM: Per's `main` plus
a short stack of SkyRose commits. The old SkyRose WM stays as an option ("SkyRose WM, WIP, not recommended").

## Hard rules

- Never push to noxaur/CatWM, never open PRs, issues or tags there. The clone's push URL is
  `DISABLED-do-not-push-to-CatWM`; keep it that way. Mods are committed locally on branch `skyrose`.
- Never force-push anything.
- Gabby has given permission to change CatWM freely (2026-11-12). Keep each mod a separate, small,
  self-contained commit so it can be replayed on a new upstream version.

## Where things are

- CatWM clone: `~/Projects/CatWM`, branch `skyrose` = `origin/main` + the mods listed below.
- `SKYROSE.md` in the CatWM branch lists the mods from CatWM's side (what each one changes and why).
- SkyRose links `CatWMKit` (path dependency `../CatWM` while the mods are local only). Release builds
  need the mods reachable from a public URL: a fork under Gabby's account (ask Gabby before creating it).
- SkyRose never imports CatWMKit outside `Sources/SkyRoseCatWM/`. The shell talks to the WM through the
  same interface for both engines.

## Updating to a new CatWM version

1. `cd ~/Projects/CatWM && git fetch origin` (fetch only; push stays disabled).
2. `git switch skyrose && git rebase origin/main`. Conflicts: keep upstream's new structure and re-apply
   the mod's intent; the mod list below says what each mod must achieve.
3. `swift build` and `swift test` in CatWM, then `/usr/bin/swift test` in SkyRose.
4. Live-check every bind in `docs/catwm-migration.md` with TestWindows.
5. Update the mod list below and `SKYROSE.md` if a mod changed or became unnecessary (upstream may adopt it).

## The mods (keep in sync with SKYROSE.md in the CatWM branch)

| # | Mod | Why SkyRose needs it | State |
|---|---|---|---|
| M1 | Parked workspaces: workspaces on the current Desktop, hidden ones parked in a corner | SkyRose/Hyprland workspaces must not be macOS Desktops | in progress |
| M2 | Per-window commands (`window: <id>` on window commands) | app rules, CLI, panic act on a given window | planned |
| M3 | Move hook: planned `(window, from, to)` before AX writes, host-driven animation | SkyRose's glide animations and borders | planned |
| M4 | Dwindle layout + `togglesplit`, `swapsplit`, `pseudo`, `pin`, resize by delta | Hyprland behaviour and binds | planned |
| M5 | Special (scratchpad) workspace | Hyprland `togglespecialworkspace` | planned |
