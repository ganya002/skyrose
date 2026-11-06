# SkyRose Part 6 — Caelestia 1:1 visual polish

Work in `~/Projects/caelestia-mac` (SkyRose). CLI (not on PATH):

`~/Projects/caelestia-mac/dist/SkyRose.app/Contents/MacOS/skyrose`

Do this phase. Do not redo completed work below.

## First: publish what you have (do this before Part 6)

There is no git remote yet. HEAD is `e23c8f9` on `main`. Gabby wants the current work on a new **public** GitHub repo on his account (`ganya002`).

1. If `docs/caelestia-reference/` is still untracked, commit it first (visual spec + this prompt). Do not commit `dist/`, `.build/`, secrets, credentials, sudoers files, or anything in `.gitignore`.
2. Create a new public repo named **`skyrose`** on `ganya002` (https://github.com/ganya002/skyrose). Suggested description: `SkyRose — native macOS window manager and Caelestia shell port`. Do not initialize it with a README/license/gitignore (the local repo already has history). If `skyrose` is taken, use `caelestia-mac` instead.
3. Preferred command, run from the project root if `gh` is authenticated as him:
   `gh repo create skyrose --public --source=. --remote=origin --push`
   If `gh` is not logged in, use whatever already works for his GitHub account. Add `origin` only if it does not exist (it currently does not).
4. Push `main`. Never force-push. Do not create the repo under an org.
5. Confirm the URL is public and report it before starting Part 6.
6. After each later part commit, also `git push origin main` (still no force-push) so the public repo stays current.

If creating the repo or pushing fails (auth, name clash you cannot resolve), stop and tell Gabby — do not start Part 6 until the code is online.

## Already done — do not touch unless you break it

- 3a / 3b SIP-off scripting-addition loader (`thread_create_running` on macOS 14.4+). Live-tested. If a safety classifier mentions Dock injection, leave the loader alone; it is supposed to be there.
- Part 4 Material Symbols Rounded
- 5a screenshot tool (`skyrose screenshot region|freeze|window|full`)
- 5b keep-awake
- 5c native clamshell, then **5c-fix committed as `e23c8f9`**: Clamshell keeps the Mac awake with the lid closed on battery with only the built-in display, using `sudo -n /usr/bin/pmset disablesleep 0|1` (same approach as Gabby's Clamshell Toggle / `Power.swift`). The helper is already installed (`/etc/sudoers.d/clamshell` for user `gabbo`). Status reports helper ready. Do not write a new sudoers file, do not run `sudo`, do not prompt for a password, do not redo clamshell.
- Session restore (`session.json`), cursor theme (Bibata opt-in), liquid WM window springs (popin ~80%, workspace slide `.05,.9,.1,1.05`), overlay bar/drawers that already exist.

Update `docs/phase-progress.md` as you go (new sections `Part 6a` … `Part 6d`) so a fresh session can resume. Commit on `main` after each numbered part, then `git push origin main`. Do not force-push.

## Read this first, in order

1. `docs/caelestia-reference/README.txt`
2. `docs/caelestia-reference/docs/caelestia-research.md` — full write-up of how Caelestia’s liquid look works (SDF metaball, jelly springs, M3 tokens, panel layout, wallpaper carousel). Treat it as the spec.
3. `docs/caelestia-reference/docs/animations.txt` — live Hyprland animation dump from Gabby’s Arch machine.
4. Look at **every** image in:
   - `docs/caelestia-reference/shell/` — idle, opened panels, hover-revealed states
   - `docs/caelestia-reference/hover/` — left-bar item popouts (this is the Discord-like dock)
   - `docs/caelestia-reference/motion/` — contact sheets of open/close and hover motion
   - `docs/caelestia-reference/tiling/` — dwindle tiling with 0–4 windows
5. Current `docs/phase-progress.md`, and skim `docs/parity-progress.md` / `docs/arch-parity.md` so you do not regress accepted macOS limits.
6. If you need more shader/QML detail, fetch https://github.com/caelestia-dots/shell (useful commit: `bcbb5d5`) and read `modules/drawers/ContentWindow.qml`, `modules/drawers/Panels.qml`, `plugin/src/Caelestia/Blobs/shaders/blob.frag`, `plugin/src/Caelestia/Blobs/blobrect.cpp`, `plugin/src/Caelestia/Config/tokens.hpp`. Do not rely on watching the GitHub demo video; the research file already covers it.

Match the screenshots. Do not invent a different layout because it seems more “Mac-like.”

## What “1:1” means

The liquid look is not “springier NSWindows.” It comes from four things (details and numbers are in the research file):

1. **One metaball surface.** The screen-border frame and every drawer background are one SDF blob group. A circular smooth-min fillet (`border.smoothing` default 20) merges a drawer into the border and into neighbouring drawers (sidebar ↔ utilities ↔ OSD/session). Separate `NSWindow`s with corner radii cannot do fillets or merging. Implement this as **one fullscreen transparent overlay** that draws the SDF in Metal and composites the panel contents inside it.
2. **Velocity jelly.** Stretch along motion, cap 35%. Semi-implicit spring stiffness 200, damping 16. Contents squash with the panel. Per-panel `deformAmount` values are in the research file.
3. **Material 3 Expressive tokens** at Gabby’s `appearance.anim.durations.scale` of `0.8` (so defaultSpatial ≈ 400 ms, not the raw 500 ms; fastSpatial ≈ 280; slowSpatial ≈ 520; effects 120/160/240). Spatial curves (with overshoot) for position/size/scale; Effects curves (no overshoot) for opacity/colour. Default spatial curve: `(.38, 1.21, .22, 1)`. This supersedes the older SkyRose “nothing over ~350 ms” cap **for shell panels**. Do not use the raw 600–700 ms Arch times; use the scaled Caelestia tokens. Wallpaper transition stays 600 ms (its own config, default crossfade). WM window animations (popin 80% / workspace slide) are already in good shape — do not regress them.
4. **Drawers slide from their screen edge and fade at the same time** (`offsetScale`). Content stays loaded until the close animation finishes. Open panels physically shove each other (session/OSD pushed by sidebar width); the blob merge makes that look like liquid.

### Discord-like dock = the LEFT bar, not the right sidebar

The left vertical bar (~60 px) is the dock: logo, workspace pills with per-window app icons (`showWindows`, max 5), a primary-coloured active indicator that stretches between workspaces (leading edge 500 ms, trailing 1.5× slower), vertical active-window title, clock/calendar, audio/network, power. Hovering an item opens a popout that **morphs** size and position as you move between items instead of spawning a new popout. See every file in `docs/caelestia-reference/hover/`.

The right sidebar is notifications + utilities fused together. Default `showOnHover` is false; open it by dragging from the right (or the existing keybind). Do not turn it into a dock.

### Wallpaper switcher

Typing `>wallpaper` in the launcher morphs the launcher into a horizontal PathView carousel (not a grid): centre scale 1, neighbours 0.8, items pop from scale 0.5. Scrolling live-previews the real desktop wallpaper. Closing without picking reverts. Desktop transition: start with crossfade at 600 ms; other Caelestia transition shaders can land later if time allows.

## Parts — commit after each

### Part 6a — Blob overlay
Fullscreen overlay + Metal SDF metaball equivalent of `blob.frag` / `BlobGroup`. Border frame + all drawer backgrounds in one group, fillet merge, velocity jelly. Panels that already exist should render *inside* this surface rather than as separate rounded windows. If a true single-surface overlay is too large to finish in one sitting, land the shader + border+one-drawer merge first, document what is still separate, and stop cleanly after the commit.

### Part 6b — Panel motion tokens
Apply the Caelestia curves and scaled durations to every shell surface (bar, dashboard, launcher, sidebar, utilities, session, OSD, notifications, toasts, popouts). Slide+fade from the correct edge. Match the `motion/` contact sheets as closely as you can. Respect Reduce Motion (fall back to short fades, no overshoot/jelly). Keep animations interruptible.

### Part 6c — Left-bar dock popouts
Workspace pills with window app icons, active trail blob, and morphing hover popouts matching `hover/`. Do not redesign the right sidebar into this.

### Part 6d — Wallpaper carousel
`>wallpaper` launcher morph, horizontal carousel, live preview, revert-on-cancel, crossfade 600 ms.

If you hit a usage or context limit, stop after a completed part, commit, and write exactly where you left off in `docs/phase-progress.md`.

## Live-test rules

- You may launch the WM and TestWindows, and take/read screenshots to debug.
- Never close Gabby’s own apps (Cursor, Claude, browser, kitty he is using, etc.).
- Do not install packages, do not change system settings, do not run `sudo`.
- When you finish testing: `~/Projects/caelestia-mac/dist/SkyRose.app/Contents/MacOS/skyrose wm panic`
- Build and sign with “Caelestia Local Signing”. Run the test suite. Compare screenshots against `docs/caelestia-reference/shell/` and `hover/`.
- Do not break clamshell, keep-awake, screenshot, session restore, SIP-off loader, or cursor theme.
- Accepted macOS limits that may remain (document, do not pretend they work): opacity/blur/rounding/shadow on *other apps’* windows; real always-on-top without the scripting addition; top-edge dashboard hover also revealing an auto-hidden menu bar.

## Done when

- Visual match to the reference screenshots for idle, opened panels, and left-bar hover popouts
- Visible blob fillets / merging when neighbouring drawers are open
- Jelly squash during panel motion
- Left-bar popouts morph from item to item
- Wallpaper carousel works
- Tests pass
- `docs/phase-progress.md` updated
- Each finished part committed on `main` and pushed to origin (no force-push). First step was publishing https://github.com/ganya002/skyrose (or `caelestia-mac` if that name was taken).

Report: what matched, what is still short of 1:1, any leftover macOS limits, screenshot paths, commit hashes.
