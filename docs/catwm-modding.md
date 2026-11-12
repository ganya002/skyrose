# Modding CatWM for SkyRose (read this before touching CatWM)

SkyRose's default window manager is CatWM by Per William Krogstad-Østensen (@noxaur,
https://github.com/noxaur/CatWM), used with permission. SkyRose runs a modded CatWM: Per's `main` plus
a short stack of SkyRose commits. The old SkyRose WM stays as an option ("SkyRose WM, WIP, not recommended").

## Hard rules

- Never push to noxaur/CatWM, never open PRs, issues or tags there. The clone's push URL is
  `DISABLED-do-not-push-to-CatWM`; keep it that way. Mods live on branch `skyrose`, pushed only to
  Gabby's fork (remote `fork`, https://github.com/ganya002/CatWM).
- Never force-push anything.
- Gabby has given permission to change CatWM freely (2026-11-12). Keep each mod a separate, small,
  self-contained commit so it can be replayed on a new upstream version.

## Where things are

- CatWM clone: `~/Projects/CatWM`, branch `skyrose` = `origin/main` + the mods listed below.
- `SKYROSE.md` in the CatWM branch lists the mods from CatWM's side (what each one changes and why).
- Fork: https://github.com/ganya002/CatWM (created by Gabby 2026-11-12). Push with `git push fork skyrose`
  only. SkyRose links `CatWMKit` by path `../CatWM` during development and by the fork URL for releases.
- SkyRose never imports CatWMKit outside `Sources/SkyRoseCatWM/`. The shell talks to the WM through the
  same interface for both engines.

## Updating to a new CatWM version

1. `cd ~/Projects/CatWM && git fetch origin` (fetch only; push stays disabled).
2. `git switch skyrose && git merge origin/main` (merge, not rebase: the branch is pushed to the fork and
   force-push is banned). Conflicts: keep upstream's new structure and re-apply the mod's intent; the mod
   list below says what each mod must achieve.
3. `swift build` and `swift test` in CatWM, then `/usr/bin/swift test` in SkyRose.
4. Live-check every bind in `docs/catwm-migration.md` with TestWindows.
5. Update the mod list below and `SKYROSE.md` if a mod changed or became unnecessary (upstream may adopt it).
6. `git push fork skyrose`.

## The mods (keep in sync with SKYROSE.md in the CatWM branch)

| # | Mod | Why SkyRose needs it | State |
|---|---|---|---|
| M1 | Parked workspaces: workspaces on the current Desktop, hidden ones parked in a corner | SkyRose/Hyprland workspaces must not be macOS Desktops | done: CatWM d586da8, `ParkedWorkspacesTests`, 914 CatWM tests pass |
| M2 | Per-window commands (optional `window` id on window commands) | app rules, CLI, panic act on a given window | done: CatWM 82c8d86, `WindowTargetTests`, 916 CatWM tests pass |
| M3 | `CatWMEngine.onWindowFrames` (in-flight frames per animation frame) + snapshot glide in embedded mode | borders follow windows; Hyprland glide via CatWM's own Bézier/duration/snapshot settings, no host-driven animation | done: CatWM 0e81281, `WindowFramesHookTests`, engine test, 918 CatWM tests pass |
| M4 | Dwindle layout + `togglesplit`, `swapsplit`, `pseudo`, `pin`, resize by delta | Hyprland behaviour and binds | planned |
| M5 | Special (scratchpad) workspace | Hyprland `togglespecialworkspace` | planned |

## CatWM checks (learned the hard way)

- Use `/usr/bin/swift` (the swiftly 6.1.2 toolchain on PATH fails on the manifest).
- `Tools/check-style.sh` bans comments in CatWM sources and tests: put the why in `SKYROSE.md`.
- After an option change, regenerate without installing or restarting the user's CatWM:
  `/usr/bin/swift build -c debug --product CatWM && .build/debug/CatWM --write-schema && .build/debug/CatWM --write-config-docs && python3 Tools/generate-clients.py`, then delete `Tools/__pycache__`.
- Fake-backend tests: `Tests/Fakes/FakeBackend.swift`, `fake.makeManager { $0.parkedWorkspaces = true }`, `await fake.settle(manager)`.
