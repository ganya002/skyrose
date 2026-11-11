# CatWM requests (for Gabby to pass to Per)

SkyRose wants to run CatWMKit as its window manager (Phase W). Read against noxaur/CatWM a6a6cb6
(Nov 11, 2026). Nothing here was sent to the CatWM repo. Linking works: a scratch package that depends on
`.package(url: "https://github.com/noxaur/CatWM", revision: "a6a6cb6…")` resolves only CatWM itself
(target-based resolution skips Sparkle, mackeys-sdk and PermissionFlow) and builds `CatWMKit` in about 26 s.

The licence question is settled: a6a6cb6 adds an Apache-2.0 LICENSE, which GPL-3.0 code can use.

## Blocking: SkyRose can't keep its own workspaces

SkyRose workspaces live on one macOS Desktop. Windows of hidden workspaces are parked in a screen corner
(1 pt left visible, like AeroSpace) and SkyRose's overlay plays the workspace slide. The master prompt
says workspaces must keep that feel, so `windows.desktops` (each workspace a macOS Desktop, switched with
the macOS swipe in embedded mode) is not an option.

With `windows.desktops` off, CatWM tiles every on-screen window of the current Desktop.
`planMove` in `WindowManager+refresh.swift` sees a parked frame (`isParked`) and moves it straight back to
its tile. So CatWM would pull every hidden-workspace window back onto the screen. The public API has no way
to stop this: `Scope` filters by pid only, and one app (kitty, Safari) often has windows on several
SkyRose workspaces.

**Request 1 (needed):** a public way for the host to own workspaces, for example
`engine.setHeld(_ windows: Set<CGWindowID>)` or `engine.exclude(windowIDs:)`: windows in that set are not
tiled, not moved and not focused by CatWM until released. Releasing them lets CatWM place them again.

## Also needed for the parts the master prompt lists

2. **Per-window commands.** Every command acts on the focused window. SkyRose's rules, the `skyrose window`
   CLI and panic act on a given window. Request: an optional `window: <id>` argument on the window commands
   (`togglefloating`, `fullscreen`, `movetoworkspace*`, `swapwindow`, `killactive`, `minimize`).
3. **A placement hook for host animations.** SkyRose draws its own window animations (snapshot glide by
   default) and its borders follow each window. Today the engine writes AX frames itself and only reports
   `layout.changed`. Request: a public event or callback with the planned `(window, from, to)` moves *before*
   they are written, plus a way to ask the engine to place instantly (the host animates), or to let the
   host run the move.
4. **Dwindle.** SkyRose's default is Hyprland dwindle: each new window splits the focused tile along its
   longer side, with `togglesplit`, `swapsplit` and preselect. `bsp` is the closest layout; please confirm
   whether it splits the focused tile or the last one, and whether a split direction can be toggled.
5. **Hyprland dispatchers with no CatWM equivalent:** `resizeactive` by a pixel delta on one axis,
   `pseudo`, `pin`, `centerwindow`, a special (scratchpad) workspace, `lockgroups`. SkyRose can keep its
   own code for the floating-only ones (pin, center, pip) if CatWM leaves floating windows alone; the
   rest need engine support.
