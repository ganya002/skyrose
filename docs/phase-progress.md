# Phase S: SkyStore (worktree ../skyrose-store, branch phase-skystore, started 2026-11-11)

Spec: `docs/PHASE-PROMPT-MASTER.md` › PHASE S. Store only, no addons. User doc `docs/SKYSTORE.md`,
threat model `docs/skystore-security.md`. Local index scaffold: `~/Projects/skystore-index` (no remote).

| Item | State | Commits |
|---|---|---|
| S1 engine: manifest, policy, permissions, signed index, install/update/rollback, revocation, panic, creator, CLI | done, 31 tests | d9c0a22 |
| S2 Store drawer UI (shell, bottom blob like the launcher) + Settings › SkyStore + `>store` | done, 7 model tests; not seen live (no launching here) | fb734d8 |
| S3 docs (SKYSTORE.md, skystore-security.md) + index scaffold `~/Projects/skystore-index` (local commit 577901d, no remote) | done; e2e in a scratch home: tool-signed index verifies, install/disable/tamper OK | e7fffbf |
| S5 Gabby's maintainer key built in; signed `serial` + anti-replay (index-serial); index tool raises serial (skystore-index e973cbd, not pushed); decisions in SKYSTORE.md (drawer + Settings fallback, builtins as first-party addons next, wallpaper stays) | done, 1279 tests 0 failures | (this commit) |
| S6 clamshell + colour picker as first-party `feature` addons | done 2026-11-13: `BuiltinFeature`, seeded installed once, Categories › Built in (also offline), CLI install/uninstall/enable/disable. The colour picker did not exist (bind, no handler): built on NSColorSampler. Live: Clamshell off refuses `clamshell on`; picker loupe seen, Escape leaves the clipboard. No `ShellFeature` protocol yet (not needed for two) | 2a7725c |
| App addon kind | merged into main 2026-11-13 without its version commit | e291519, f02a575 |
| S4 live recording of the Store | done at merge: `~/Pictures/Screenshots/skyrose-store-1794410118.mov` + `.png`, opened and closed with `skyrose store`; Featured tab shows "The index is empty" (no trusted index yet) | (merge) |

Notes: no addons are made (spec). `StoreSource.trustedKeys` is empty until Gabby makes the key, so every
index is refused until then (the Store says so). E2E without touching the real home: run the CLI with
`CFFIXED_USER_HOME=<scratch> HOME=<scratch>` (HOME alone is not honoured). Never run `wm panic` for a test:
it also neutralises the live scripting addition.

# Master prompt run (started 2026-11-11)

Spec: `docs/PHASE-PROMPT-MASTER.md` (overrides older prompts). Phase A on branch `phase-9.5`.
Resume here: read this table, then the newest section below.

| Item | State | Commits |
|---|---|---|
| 0. Commit prompts | done | 9ae3c6b |
| A1 polish | surfaces fixed + recorder card, top-right notification drawer, drawer timings re-measured on H.264 clips; bar popouts have no capture (Phase B), Settings: no search field yet. See `docs/parity-progress.md` | aeaea90, 9d9b77c, 0250478, 7fff8aa, d5160a9, edda590, 8341436 |
| A1 bongo + lyrics with a real song | closed by Gabby 2026-11-11 (no Spotify on this Mac: counted as checked; a live beat/lyrics run never happened) | |
| A1 boot daemon sudo install | done 2026-11-11: Gabby installed it, rebooted; after boot `sa status` loaded with no password, log: loaded SkyRoseSA.dylib into the Dock (pid 717); all files root:wheel, not user-writable | |
| A2 helper card | done: Gabby loaded it from the card (recorded, `sa status` loaded); boot-daemon toggle untested | d873f84, bc3e828 |
| A3 Teams flicker | done: Gabby checked Teams behind OneNote live, no flicker (no recording) | bc3e828 |
| A4 restart | done: CLI, Settings › About, session menu, `>restart`; no keybind (Gabby: CLI/Settings/launcher are enough). Stray copy = separate `testuser` account, now never launched (start by path) | (this commit) |
| A5 v0.4.1 | done: merged to main e4c0dee, tag v0.4.1, release with zip, install.sh, uninstall.sh and .sha256 files. 0.4.0 CLI reports the update; sandboxed `update --yes` installs 0.4.1. A part10 reference image had the Wi-Fi name filled out before the first push (unpushed history rewritten, hashes above updated). | e4c0dee |
| W. CatWMKit swap | superseded by "CatWM default WM" below (was blocked, waiting for Per, 2026-11-11). Branch `phase-w` (pushed, docs only): `docs/catwm-requests.md`, `docs/catwm-migration.md`. Old WM untouched. | b32f0fb |
| S merge | merged into main 18119e5; 1282 tests, 0 failures; Store recorded live | 18119e5 |
| B 10a OSD | done: Caelestia column layout, handle with % while moving, scroll, 2 s hide; seen live (`~/Pictures/Screenshots/skyrose-osd-1794410476*.png/.mov`). Drag and scroll not tried live (no pointer synthesis). Also fixed a clamshell IPC crash (585f21c) | 1de22b7 |
| B 10b media | done 2a291d3; seen live 2026-11-12 with a throwaway Now Playing test app (no Gabby players touched): ring reacts to the beat, art turns, transport, seek bar, source pill, cat. Compared side by side with media-player.png | 2a291d3 |
| B 10c Wi-Fi | done b8fdfcb: hover summary + click panel, scan/join/leave/forget, `skyrose wifi`. Live: scan (6.4 s), leave + rejoin of the current network once. Not verified: the networksetup rejoin fallback for a known network without a password, wrong-password message, forget | b8fdfcb |
| B 10d Bluetooth | done 08cbe84, 083e73a: power, paired list with battery, connect/disconnect, pair (PIN/confirm), forget, `skyrose bluetooth`. Live: power off/on; connect to the only paired device (headphones, switched off) failed with a clear message; nearby scan ends without the inquiry crash. Not verified: pairing, forget | 083e73a |
| B 10e Controls | done 0fcb331: Controls button and panel. Live: panel renders, Night Shift on/off (restored off). Menu bar apps: on macOS 27 every item lives in MenuBarAgent; a test status item of our own was not reachable by AX, so the panel says so and offers menuBar.peek. Low Power Mode (admin prompt) and AirDrop not tried live | 0fcb331 |
| B bugsweep | done a229f9c: review of phase-b-net, 10 findings fixed (Wi-Fi forget off the main thread, CLI join state kept on hover, key focus only for password/PIN, optional permissions never reopen onboarding, one CLLocationManager + when-in-use, BT connect leak, BT forget result, battery read throttle, menu extra matched by title). Escape on the CatWM panel fixed 52bd84c and seen live | a229f9c |
| B 10f v0.5.0 | main 36799ad pushed, tag v0.5.0 pushed. 2026-11-13: rebuilt from the tag (install.sh hash unchanged, 17b4fb…); `gh release create` blocked again by auto mode, Gabby publishes. 1313 tests, 0 failures. Zip + install.sh + uninstall.sh + .sha256 in dist/release-0.5.0 (signed Caelestia Local Signing). 0.4.0 `update --check` (local release JSON) reports v0.5.0; sandboxed install of the zip gives 0.5.0. NOT DONE: `gh release create` was blocked by the auto-mode permission check; Gabby publishes it (command in the report) | 36799ad |
| CatWM default WM | **done**, merged to main cd464e1 (2026-11-12). CatWM pinned to the fork `ganya002/CatWM` branch `skyrose` (258a705; Per's main never pushed). Mods M1–M9 in `docs/catwm-modding.md`. Live-checked with TestWindows: borders, gaps, dwindle binds, float/pseudo/fullscreen, special, groups, handoff across restart, panic restore, 60 fps slides on the Air. Settings › CatWM incl. Motion (curve, speed, bounce). Escape on the panel fixed in 52bd84c. | cd464e1 |

| C site | live on here.now: https://ground-pocket-866h.here.now/ (anonymous: expires unless claimed with the claim URL in archify-site/.herenow/state.json). `scripts/publish-herenow.sh` republishes | archify-site e2fd89b |
| Leftovers 2026-11-13 | drawer close on an empty ws no longer follows the app (4/4 under CatWM, seen only with the old engine); Settings search (b019af7); CLI shell commands reported failure (9f05489). Not done live: boot-daemon toggle, Wi-Fi forget / wrong password, BT pairing / forget, Low Power Mode, AirDrop (need Gabby, admin prompts or other devices) | |
| Live tests 2026-11-13 | Gabby at the Mac, all passed: media tab with a real song in Firefox (source pill, bongo cat, lyrics; long lines truncated, fixed 28102d4 to wrap); AirDrop tile opens AirDrop; Low Power Mode on/off (asked for a password on every switch: b343a99 adds `pmset -a lowpowermode 0\|1` to the scoped sudoers rule, one last prompt installs it; rule install not yet seen on this Mac); SIP-off toggle off/on without a password, `killall Dock` and the boot daemon reloads the helper; Bluetooth connect, forget, pair (WH-1000XM6); Wi-Fi wrong password, forget, rejoin | 28102d4, b343a99 |
| v0.6.0 | version bump, tag; release files built in the scratchpad; publish blocked like 0.5.0 | (this commit) |

Next: publish the v0.5.0 and v0.6.0 releases (Gabby), claim the here.now site, then third-party code addons (out of process).

Notes for a fresh session:
- Tests: `/usr/bin/swift test` runs 9 XCTest bundles, 1226 tests; only the last bundle's summary is at the
  tail, so sum the `*.xctest' passed` blocks.
- The capture's .mp4 files are HEVC 4:4:4: AVFoundation cannot decode them (-12906); use the jpg frames.
- Restart for testing: `dist/SkyRose.app/Contents/MacOS/skyrose restart`.
- Caelestia source: clone `caelestia-dots/shell` into the scratchpad (fd630ff was used).

# Phase 9.5: fixes + Caelestia polish (started 2026-11-10)

Spec: `docs/PHASE-PROMPT-9.5-fixes-polish.md`. Branch `phase-9.5`, one commit per part, not pushed.

| Part | State | Commit |
|---|---|---|
| 1. Real Bongo Cat | done, sprite seen live; beats need a song | "Phase 9.5 part 1" |
| 2. Hover focus | done, live with TestWindows | "Phase 9.5 part 2" |
| 3. Lyrics | partial: built, states checked, not seen with a song | "Phase 9.5 part 3" |
| 4. 1:1 polish | partial: motion done, side-by-side not complete | "Phase 9.5 part 4" |
| 5. SIP-off daemon | built, dry runs pass, never run with sudo | "Phase 9.5 part 5" |

References read: `docs/caelestia-reference` (the prompt says part10 has 66 images, it has 3), the capture README and brief,
`caelestia-dots/shell` at fd630ffe. Clone it into a scratch folder; it is not in the repo.

## Part 5 — SIP-off boot daemon

Scripts live in `Packaging/sa/` and ship in `Contents/Resources/sa/`. `test-sa-daemon.sh` covers the
daemon's decisions, config parsing and both dry runs. The real install has not been run: it needs
Gabby's sudo. The pause file `/tmp/skyrose-sa-paused-<uid>` keeps a panic to this session.

## Part 4 — 1:1 polish

Already in place from Phase 6 and left alone: one SDF surface for the border and drawers, the jelly
(stiffness 200, damping 16, 35 % cap), per-panel deformAmount, and a display link that pauses at rest.

New here: each drawer opens and closes on its measured time (`CaelestiaTokens.DrawerMs`). Dashboard
tabs have their own heights and the blob morphs between them on the spatial curve with a crossfade.
The open sidebar pushes the session menu and the OSD left, and the OSD no longer hides for it.
Content stays with the attached edge during a morph. The media tab's details are centred like the reference.

Recording: `~/Pictures/Screenshots/skyrose-1794313186.mov`. Dashboard close measured about 150 ms.
Still open: the surface-by-surface side-by-side against every reference image was not finished.
No before clip was recorded for this part.

## Part 3 — lyrics after Caelestia's LyricList

The media tab now has Caelestia's right column: a Lyrics header over the list. The current line is
primary and full size with a glow; other lines are outline, scaled to 74 %, and dimmer with distance.
Rows are laid out at full size and only scaled, so nothing changes height when the line advances.
A spring scrolls the list so the current line stays centred; a 10 % mask fades both edges. A click
on a line seeks, and the lyric clock moves at once. Loading and "No lyrics found" match upstream.

Checked by offscreen renders of first, middle, last, empty and loading. Not checked with a real
song: no player was running, so the scroll spring and seek have not been recorded.

## Part 2 — hover focus follows the real stack

Cause: `hoverTarget` picked by placement kind and largest id and ignored z-order. Hex's invisible
near-full-screen windows (layers 25–27) were also in the placements.

Now `CGWindowSnapshot.hit` walks CGWindowList front to back and answers window, blocked or nothing.
Menus, popovers, Dock, Spotlight and system UI block, as do SkyRose panels and the border strip.
Very large overlays above layer 0 are looked through. The stack is read again right before focus.
Hover holds during a mouse button, a warp, a retile, and 0.3 s after a keyboard focus.

Live test: one tiled and two offset floating TestWindows, 13 of 13 hover checks picked the topmost
window, including a flick across a window that must not take focus. Stack order did not change.
Recording: `~/Pictures/Screenshots/skyrose-1794312643.mov`, checked on a sheet at 2.5 fps plus a
focus poll every ~50 ms. No before clip was recorded for this part.

## Part 1 — the real Bongo Cat

`assets/bongocat.gif` is 20 frames but only two poses, ten of each. `Resources/BongoCat` holds those two at 4x (800×504,
edges redrawn so they stay clean), each with and without the red motion ticks. A detected beat shows the slap with ticks
and swaps paw. 90 ms later the ticks go and the pose holds. Paused or nothing playing: the last pose, no ticks.
Upstream only has the cat on the dashboard card, under the controls. The media tab copy follows `part10/media-player.png`.

# Phase 9: focus, easy setup, tiling (started 2026-11-09)

Spec: `docs/PHASE-PROMPT-9-focus-easy-setup.md`. Commit locally after each part. Push `main` and tag `v0.4.0` only at 9k. Do not move tags `v0.2.0` or `v0.3.0`.

Order for this run: 9i, 9j, then 9a–9h, then 9k.

| Part | State | Commit |
|---|---|---|
| 9i. Rock-solid tiling | done | "Phase 9 part 9i" |
| 9j. Smooth live resize | redone, recorded | speed fix, then Glide restored as the default |
| 9j2. Window borders | done, corners checked live | per-window SkyLight radii, even stroke |
| 9a. Cursor follows focus | done, live | keyboard focus warps to the window centre |
| 9b. Focus follows mouse | done, live | hover focuses after the delay and does not raise |
| 9c. Easy setup | done | one tour, Use recommended, doctor --fix, one Install button |
| 9d. SIP-off assistant | done | steps for this Mac, copy and QR, no automation |
| 9e. End-of-animation flash | done, recorded | hide stays at alpha 0 until ordered out |
| 9f. Menu bar off | done | Shown, Auto-hide, Off; peek on Super+Shift+B |
| 9g. Clipboard history | done | Super+V, images, concealed items skipped |
| 9h. Bongo cat + lyrics | done | beats from output audio, LRCLIB cache |
| 9k. Release v0.4.0 | done | tag v0.4.0 |

## Part 9i — rock-solid tiling (done)

A normal window stays tiled. It floats only when the user floated it, or a float rule matches
(rules, dialogs, sheets, panels, utility windows, fixed-size windows). The WM no longer floats a
window because its minimum does not fit or because the app keeps moving it.

- Minimums still steal room from the other side of a split (stored ratios are unchanged, so the
  room comes back when the window closes). The frame is never grown past its slot, so neighbours
  do not overlap. If the other split direction fits, that direction is used for the pass. If
  nothing fits side by side, the workspace stacks: one window fills the area, the rest are parked.
  A window bigger than the screen stays tiled to the full area.
- A new window that would break `minTileWidth` / `minTileHeight` joins the focused leaf as a tab
  instead of floating.
- An app that moves its own tiled window is put back twice, then left alone until the reconcile
  pass (1 s, or wake / Space change / a window that shows up with no event). The pass is
  idempotent. Native fullscreen exit and a window that AX announces late are picked up there.
- User float/tile is stored in `~/Library/Application Support/SkyRose/user-float.json`, keyed by
  bundle id + subrole + title, and wins over rules until the user toggles it back. The session
  snapshot still restores the same window id within a boot.
- `query state` carries `tilingNotes`. `skyrose doctor` prints them.

Harness stress (not the live WM): 55 windows spawned and 30 closed, workspace switch in the
middle, two displays, an empty display list then the screens back, and a sleep event. Wide
minimums (900 pt) flipped the split and both stayed on screen with no overlap. 2000×2000
minimums stacked. A drifted window came back on wake; a second reconcile wrote nothing. A window
inserted with no event, and one that left native fullscreen, were tiled. A dialog still floated.
User float survived a new process and a daemon restart. `/usr/bin/swift test`: 1115 tests, 0 failures.

Not verified on this Mac: no TestWindows were opened, the running WM was not restarted, and
nothing was applied to Gabby's windows, Dock, cursor, wallpaper or desktop picture.

## Part 9j — smooth live resize (speed fix)

Glide (`animations.windows = "snapshot"`) is the default again. Live stays available. Gabby's
config already sets snapshot. A size change is still the real window under the cover, on the
same fixed ease-out, so the still is not scaled.

The 2 pt-per-tick cap (in the display-link slew and again in the per-app frame writer) made a
resize take seconds, because the time grew with the distance. That cap is gone.

Keyboard and tiling moves use `animations.windowDurationMs` (default 150, 0 snaps) on Hyprland's
default ease-out. `speed` and `globalMultiplier` scale it; 0 stays 0. The clock does not grow
with distance. Size is written once, at the final size, and only the origin eases after that:
a size step bigger than about 2 pt is what makes the window server scale the old buffer, and
walking that 2 pt at a time was the multi-second resize. A mouse-edge drag is the cursor frame
itself. A newer frame replaces one the app has not applied yet, so a slow app jumps to the
cursor instead of catching up through the points it missed. Each finished move is logged as
`live anim #<id> <ms>ms ease|snap <from> -> <to> budget <ms>ms`. A resize drag logs
`live drag #<id> 1:1`.

Gabby's config has `animations.speed = 1.5`, so the budget on this Mac is 100 ms (150 / 1.5).
Live, workspace 2, two kitty windows, TestWindows floating (her float rule). Lid closed,
Clamshell on, SleepDisabled 1 the whole time.

- Opening the second kitty: `live anim #9681 104ms ease 1357x861 -> 682x881 budget 100ms`.
- Maximize to full width (675 pt wider): `live anim #9691 64ms ease 682x881 -> 1357x861 budget 100ms`.
  Recording `docs/bugs/resize-maximize-9j.mov` (32 frames, 1.23 s, ~26 fps). The half-width
  layout is frame 18 and the full-width sharp fastfetch is frame 20. One frame in between is
  the old buffer at the new size; the next frame is sharp. No fade, blur filter, or grey.
- Swap of the two equal tiles (695 pt, size unchanged): both `104ms ease 682x881 -> 682x881
  budget 100ms`. `docs/bugs/resize-swap-9j.mov`.
- Option-right drag of the split, cursor from x=730 to x=460 (−270 pt) in 20 steps of 25 ms.
  The left tile's width went 682 → 416 (the 13 pt gap stayed). Samples every ~50 ms moved
  26–27 pt, which is two cursor steps. The edge stopped when the cursor stopped. No trailing.
  `docs/bugs/resize-drag-9j.mov`.

The panel is 60 Hz (kitty's fastfetch still says 60 Hz). The recorder asked for up to 120.

## Part 9j2 — borders that follow each window

`SLSWindowIteratorGetCornerRadii` is in this Mac's SkyLight and works with SIP on. It returns four
doubles per window. On 10 Nov every normal window asked (Firefox, T3 Code, Grok Bot, kitty, Finder,
Safari, TestWindows, Teams, Hex) reported 16 pt on all four corners. SkyRose's own border panels and
the menu bar report 0, so they stay square. The value is cached per window and size. If the symbol
is missing, the border falls back to `windowRounding`.

The outline is a shape stroke, not `CALayer.borderWidth`. The layer border was solid at the corner
and about half as strong along the straight edge, which read as the right side fading out. The
stroke's inner edge sits on the window and its centreline radius is the window radius plus half the
border width, so the curve stays concentric. A square window (radius 0) stays square.

Live corners, border pink and continuous through the turn, no gap of wallpaper at the curve:
Firefox, kitty, Safari, Finder, TestWindows. Shots in `/tmp/b-tl.png`, `/tmp/b-tr.png`,
`/tmp/corner-kitty-tl.png`, `/tmp/corner-kitty-tr.png`, `/tmp/corner-safari-br.png`,
`/tmp/corner-finder-tl.png`, `/tmp/corner-finder-tr.png`, `/tmp/corner-test-wide.png`.
Radius fitter tests: 5 passed. Not checked on an external display (none is attached).

## Part 9a — cursor follows focus (done)

Keyboard, workspace, close and launcher focus move the pointer to the newly focused window.
`cursorFollowsFocus` defaults on. `cursorWarpMode` is `center` (the middle) or `last` (the last
point inside that window). A click, a held button, a drag, a window that is not on a visible
display, or a pointer that is already inside the window does not warp. The warp disconnects the
hardware mouse (`CGAssociateMouseAndMouseCursorPosition`), moves, then reconnects, and ignores
focus changes from that synthetic move for 80 ms.

Live: Firefox centred at 413,494 and a kitty centred at 1108,494. `window focus left` logged
`cursor warp #233 412,494`. `window focus right` logged `cursor warp #835 1107,494`. The pointer
read back on those windows. Tests: `CursorWarpTests` (5), `CursorFollowsFocusTests` (4).

## Part 9b — focus follows mouse (done)

Hovering a tiled or floating window focuses it after `focusFollowsMouseDelayMs` (default 100,
range 0…5000). Moving inside the same window does not restart the wait. `raiseOnHover` defaults
off: the window is focused and left where it is in the stack. macOS raises a window when it
becomes focused, so the windows that were already in front are raised back, front-most last.
A drag, a held button, a warp, a password field, an open menu, a visible sheet, the menu bar,
a SkyRose drawer or popout, Spotlight, the launcher, or a fullscreen window on another Space
does not take focus. Fully transparent windows (Hex's invisible system dialogs cover this
screen at alpha 0) are not the window under the pointer. The pointer is already inside the
window, so cursor-follows-focus does not warp it.

Settings › Windows has the toggle, a 0–500 ms delay slider, raise-on-hover, and a two-tile demo.

Live, delay 100 ms (Gabby's config does not override it). Cursor posted to a point, then left there:

- T3 Code at 200,500 (centre is about 760,494): `hover focus #89 raise false`. Cursor still 200,500.
- TestWindow 1 at 760,494: `hover focus #1156 raise false`.
- After TestWindow 1 was in front, hovering TestWindow 0 at 200,150 (its centre is 410,304):
  `hover focus #1155 raise false`. Focus became 0x483. Stack stayed TestWindow 1 then
  TestWindow 0. `raiseCalls` stayed 6. Cursor still 200,150.
- Back to T3 at 1200,700: `hover focus #89 raise false`. Cursor still 1200,700.

Tests: `HoverFocusTests` (4), `CursorFollowsFocusTests` (7, including the delay, no warp, no
raise, and looking through a fully transparent window). The lid was closed for the stack check.
Clamshell stayed on and SleepDisabled stayed 1. TestWindows were opened for the check and then
closed. Gabby's other apps were not closed.

## Part 9c — one setup flow (done)

First run is five steps: mode, permissions, one recommended setup, kitty and fonts, done. A progress
bar shows which step this is. Every step can be skipped. Settings › General opens the same tour
again. A lost permission still opens only that step, and closes itself once the grant is back.
On a full first run, the permission step moves on by itself once the needed grants are in.
Screen Recording, which macOS applies on the next launch, restarts SkyRose for you.

The recommended step is one **Use recommended** button: hide the Dock (it keeps running), hide
the menu bar automatically, set the Bibata cursor, copy a starter wallpaper and set it when
SkyRose has never set one, and put screen corners back on automatic. Nothing is written until
that click. The uninstaller can put the journaled changes back.

`skyrose doctor --fix` writes a missing config, hides the Dock or menu bar again when SkyRose
had done that and it came back, puts the cursor setting back to Bibata when it is empty, and
removes a leftover socket when the WM is not running. A broken config file is left in place and
explained. Permissions are explained too: SkyRose cannot tick those boxes.

The installer window is one Install button. Command line and "open when finished" are under
Advanced. A stopped install says what happened in plain words and offers **Fix it**, which runs
the installer again.

Tests: `SetupFlowTests` (5), `OnboardingTests` (7). The button was not clicked on this Mac, and
`doctor --fix` was not run against Gabby's config, Dock, cursor or wallpaper.

## Part 9d — SIP-off assistant (done)

Settings › SIP-off mode walks through only the steps this Mac needs. Apple Silicon gets the
`nvram` boot argument. Intel does not. Each command has a Copy button, and a QR code holds
those commands so they can be read on a phone while the Mac is in Recovery. The red box says
this lowers security, that school Macs often forbid it, and that SkyRose works with SIP fully
on. After a reboot the existing status rows update by themselves. SkyRose does not open
Recovery, does not run `csrutil`, and does not change NVRAM.

Tests: `SIPAssistantTests` (3). Nothing on this Mac's SIP or boot arguments was changed.

## Part 9f — menu bar Shown, Auto-hide, or Off (done)

Settings › Appearance has the three choices. Shown leaves the bar up. Auto-hide uses
`_HIHideMenuBar`, so it returns when the pointer touches the top edge. Off does that and tells
the layout not to reserve the bar. The notch is still reserved. The previous value is journaled,
and uninstall puts it back. The choice is stored in Application Support, which uninstall removes.

With SIP on, macOS can still show the bar at the top edge. The page says so. Super+Shift+B, and
a button on that page, show the bar for 5 seconds so menus stay reachable. Nothing was changed
on this Mac: the control was not used, and the mode file was not written.

Tests: menu-bar plan and the mode file round trip, and a display with Off drops the bar inset
while a notched screen keeps its 32 pt notch.

## Part 9g — clipboard history (done)

Super+V opens a local history. Return pastes into the app that was focused (the panel does not
take activation, then types ⌘V). Shift+Return copies only. Delete, and Super+Alt+V, remove the
selected row. Pause and Clear are on the panel. Images are stored as PNG thumbnails in the list.

Items marked `org.nspasteboard.ConcealedType` or `TransientType` are never stored, so password
managers are skipped. History lives in `~/Library/Application Support/SkyRose/clipboard`.
Uninstall removes Application Support, and with it the history. The default cap is 50 entries
and 32 MB of images.

Tests: `ClipboardHistoryTests` (4): order, repeats, concealed and transient, pause, eviction,
and deleting an image removes its file. The picker was not opened on this Mac.

## Part 9h — bongo cat and lyrics (done)

The media tab shows a small cat. While the dashboard is open and something is playing, SkyRose
listens to the system output with ScreenCaptureKit and the cat's paws come down on the beats.
Closing the dashboard stops that listener. Nothing is playing: the cat sits still. Settings ›
Bar and Shell can turn the cat off.

Lyrics come from LRCLIB using the artist, title, album and duration. Synced lines are used when
they exist, otherwise the plain lyric is one line. The result is cached in
`~/Library/Application Support/SkyRose/lyrics`, which uninstall removes with the rest of
Application Support. The current line is highlighted and the list scrolls to it. Clicking a
line seeks Spotify or Music. Settings can turn lyrics off. A miss says "No lyrics found".

Tests: `LyricsTests` (5). LRC times, the line for a clock time, LRCLIB's synced-then-plain
choice, the cache file, and three clicks in a silent buffer. Not tried live: no track was
playing, and LRCLIB was not contacted from this Mac.

## Part 9k — release v0.4.0 (done)

Release: https://github.com/ganya002/skyrose/releases/tag/v0.4.0
Tag `v0.4.0` is new. Tags `v0.2.0` (`1bf9a30`) and `v0.3.0` (`e65f99b`) were not moved.
`/usr/bin/swift test`: 1172 tests, 0 failures. Apps built with `scripts/build.sh` and signed with
"Caelestia Local Signing". The zip is `SkyRose-0.4.0-arm64.zip` (SkyRose.app, SkyRose Settings.app,
install.sh, uninstall.sh) plus detached `.sha256` files. `docs/caelestia-reference` is not in the zip.

A 0.3.0 `skyrose update --check` against a local copy of that zip reported v0.4.0. `skyrose update --yes`
with `HOME` pointed at a temporary folder and `SKYROSE_INSTALL_SANDBOX=1` installed 0.4.0 there.
The running window manager was left in place.

Not done on this Mac: the new apps were not copied over `~/Applications`. The recommended-setup
button, `doctor --fix`, the menu-bar control, and the clipboard picker were not used. No track was
playing, so the cat and LRCLIB were not tried live. No Dock, cursor, wallpaper, or SIP change.

## Part 9e — no flash at the end of a shell animation

Closing a drawer reset its layer to full opacity and the rest pose, then ordered the panel out.
That committed a full frame of the open drawer before the window server dropped it. The same
restore, if it landed during the next open, snapped the new animation to full size for a frame.
`ShellPanel.orderOutSettled` now orders the panel out while alpha and the content layer are still
0, and puts the rest pose back on the next turn only if the panel is still hidden. A show cancels
that restore. Opening a liquid drawer applies the off-screen opacity before the panel is ordered in.

Regression: `ShellPanelFadeTests` (3). Live recordings, no frame of the surface back at full size
after it had left:

- launcher `~/Pictures/Screenshots/skyrose-1794299268.mov`
- volume popout `~/Pictures/Screenshots/skyrose-1794299270.mov` (frame 40 open, frame 82 gone)
- dashboard `~/Pictures/Screenshots/skyrose-1794299272.mov` (frame 19 open; the close does not jump back)
- session menu `~/Pictures/Screenshots/skyrose-1794299274.mov` (frame 30 open, frame 70 gone)

# Phase 8: shipped defaults + updater (started 2026-11-09)

Spec: `docs/PHASE-PROMPT-8-defaults-update.md`. Commit on `main` after each part, `git push origin main`. Do not move tag `v0.2.0`.

| Part | State | Commit |
|---|---|---|
| 8a. Bibata cursor bundled, on by default | done | "Phase 8 part 8a" |
| 8b. Dock removed (not unloaded) | done | "Phase 8 part 8b" |
| 8c. Starter wallpapers | done, none bundled (licensing) | "Phase 8 part 8c" |
| 8d. Updater | done | "Phase 8 part 8d" |
| 8e. Corner calibration | done | "Phase 8 part 8e" |
| 8f. Release v0.3.0 | done | tag v0.3.0 on e65f99b |

## Part 8a — Bibata cursor (done)

Bibata Modern Classic (GPL-3.0, ful1e5) is copied into the Platform resource bundle
(`Cursors/`, with `GPL-3.0.txt` and `CREDITS.txt`; also `THIRD_PARTY.md`). `CursorCapeLibrary`
finds that folder first, then Application Support, then Mousecape. New configs default
`appearance.cursor` to `Bibata-Modern-Classic`. The WM already re-applies it on wake, session
activate and every 15 s, and clears it on quit. Settings still offers macOS, and says the wait
cursor cannot be restored until logout. Gabby's config already names this cape, so the default
change does not rewrite it. Not verified: a fresh login on this Mac.

## Part 8b — Dock removed, not unloaded (done)

`DockRemoval` journals `autohide`, `autohide-delay`, `autohide-time-modifier` and `tilesize`
(including absent), then sets autohide, a 1000 s delay, a 0 time modifier and a 16 pt tile size,
and restarts the Dock with `killall Dock`. It does not unload the Dock's launch agent.
`skyrose dock show|hide|status`, Settings › Appearance, and an Apply button on the onboarding
tweaks step. Nothing was applied on this Mac. The uninstaller already rewrites those defaults and
restarts the Dock; a fixture-HOME test covers the four keys.

What the Dock did that SkyRose covers: opening apps (launcher), running apps (workspace pills).
Not covered: Dock stacks, recent items, and the Downloads folder.

## Part 8c — starter wallpapers (done, none bundled)

The copier journals each copied file by SHA-256 and skips an existing name or a duplicate hash.
Uninstall trashes only those paths. No picture is in the bundle: seven wallhaven pages were fan art
without a redistribution license, the API then returned 429, and the Eris Greyrat files were
excluded. The list is in `Sources/CaelestiaCore/Resources/Wallpapers/CREDITS.md`. Nothing was copied
into `~/Pictures/Wallpapers` and no desktop picture was changed.

## Part 8d — updater (done)

`skyrose update` reads the latest GitHub release and compares it to the installed version.
`--check` (and a bare `update`, which does not pass `--yes`) only reports. `--yes` downloads the
zip and its `.sha256`, checks the hash, and runs that release's `install.sh --update`, which
replaces the two apps and relaunches whichever of them was running. A bad checksum, an unreadable
release list, or no network keeps the current install and does not downgrade. Settings › About
shows the version, Check, and Install once a newer release is known. "Check automatically once a
day" is off; the daily check only writes a note. Nothing was installed over the copy on this Mac.

## Part 8e — corner calibration (done)

Onboarding has a skippable Corners step. Settings › Appearance has a per-display slider and a
"this screen has square corners" switch (off returns to Auto). `skyrose corners calibrate` opens
the same fullscreen outline as `frame calibrate`: all four corners, a slider or the arrow keys,
0 for a square pair, saved under `[displays."<uuid>"]` and drawn live without restarting the WM.
A notched built-in panel (safe area, or a gap between the auxiliary top areas) starts at 10 pt on
top and square on the bottom. External screens start square. Not checked on the real displays.

## Part 8f — release v0.3.0 (done)

Release: https://github.com/ganya002/skyrose/releases/tag/v0.3.0
Tag `v0.3.0` points at `e65f99b`. Tag `v0.2.0` still points at `1bf9a30` (the tag object is
`c1ea513`; it was not moved). Apps were built with `scripts/build.sh` and signed with
"Caelestia Local Signing". The zip is `SkyRose-0.3.0-arm64.zip` (SkyRose.app, SkyRose Settings.app,
install.sh, uninstall.sh) plus detached `.sha256` files. `docs/caelestia-reference` is not in the zip.
`/usr/bin/swift test`: 1106 tests, 0 failures.

Not verified on this Mac, on purpose: the new apps were not copied over `~/Applications`, so the
running WM stayed 0.2.0. No Dock change, no cursor change, no wallpaper copy, no desktop picture
change, no updater install, and no live corner calibration (TestWindows was not opened for it).
Uninstaller and installer checks stayed on `--dry-run` and a temporary HOME.

# Phase 7: first ship, installer and uninstaller (started 2026-11-06)

Spec: `docs/PHASE-PROMPT-7-ship.md`. Commit on `main` after each part, `git push origin main`.

| Part | State | Commit |
|---|---|---|
| 7a. Launcher black flash | done, live-tested on the built-in | "Phase 7 part 7a" |
| 7b. Uninstaller | done | "Phase 7 part 7b" |
| 7c. Release installer + GUIs | done | "Phase 7 part 7c" |
| 7d. GitHub Release v0.2.0 | done | tag v0.2.0 on 1bf9a30 |

## Part 7a — launcher black flash (done)

Gabby's still (`docs/bugs/launcher-black-flash.png`) shows two 1 px dark vertical lines ~30 pt
left and right of the launcher and a frame above it. Two causes, both fixed:

- **Shader culling box (the lines and the rectangle).** `blob.frag` skips each rect outside a box
  at half + 1.5 k (k = 20, so 30 pt out) by setting its distance to 1e10. `fwidth()` across that
  jump is ~1e10, so `smoothstep(-fw, fw, d)` painted ~50 % fill along the box edges whenever the
  box fell inside a 2×2 pixel quad, which happens on most frames while a drawer slides. Fix:
  `fw = clamp(fwidth(d), 0.5/scale, 4/scale)` (also for the display-corner mask). Regression test
  `LiquidSurfaceTests.testNothingIsDrawnOutsideTheBlobWhileADrawerAnimates` renders the launcher
  blob on the GPU at slid / squashed / fractional positions (fill and blur mask) and asserts zero
  alpha beyond the blob + shadow reach. It failed before the fix (a = 45 at d = 49 pt) and passes after.
- **First open after a launch (rows beside the body).** The drawer panel is made at `.zero` and
  resized in the same update as the launcher's model changes, so the `bodySize` animations carried
  the content from its zero-width layout (the panel's left edge) to the centre while the blob was
  already centred. That showed as dark rows sliding in ~100 pt left of / above the body.
  `ShellPanel.setFrame` now lays the SwiftUI content out right away whenever the size changes.
- Also fixed: `ShellPanel.fadeOut` now ends on a timer if AppKit never calls the animation
  completion back (the session dim stayed ordered in at alpha 0; the unit test
  `testSessionDimsTheScreenAndClearsOnClose` had been failing on `main`).
- Live (built-in, a floated TestWindow as a bright backdrop, 60 fps clips): before, the first
  open slid the rows in beside the body (`docs/bugs/launcher-open-before.png`). After:
  `launcher-first-open-after.png`, `launcher-open-state-after.png` and `launcher-close-after.png`
  show only the blob: no outline, no rectangle, content inside the body (these captures are local
  and not committed, because they show the terminal). Debugging also ruled out the content's
  sublayerTransform: its pivot and jelly match the blob, and dx stays 0 on screen.
- Tests: 1066 passed, 0 failed (`/usr/bin/swift test`).

## Part 7b — uninstaller (done)

`scripts/uninstall.sh` is the engine `skyrose uninstall` runs, and `scripts/build.sh` copies it into
`SkyRose.app/Contents/Resources/scripts/uninstall.sh`. Settings › Backup & uninstall opens the same
script in the SkyRose-styled window (`--progress`). `--yes` keeps fonts, `~/.config/skyrose` and the
signing certificate unless a `--remove-*` flag says otherwise.

Five bugs in the first draft are fixed, each with a fixture-HOME test (the real account is refused;
nothing here ran the uninstaller against Gabriel's Mac):

- A failed `defaults` / hotkey / wallpaper / file restore keeps `~/Library/Application Support/SkyRose`
  (the manifest stays) and the script exits non-zero.
- If the WM is still running after `wm quit`, the script stops. Settings, apps and data are left as they are.
- Every `BackupValue` type is written back (bool, int, double, string, date, data, array, dictionary),
  and a `symbolichotkeys` entry restores or removes only that shortcut number inside `AppleSymbolicHotKeys`.
- Wallpaper restore uses the recorded display id. Two displays showing the same SkyRose picture get
  their own originals; a display that no longer shows it is left alone.
- After `::sip` the script waits for `ack` on stdin (the window sends it when the reminder is dismissed).
  Terminal uses `open -W` on a Settings instance that quits when the reminder is dismissed. Nothing is
  trashed before that, and a missing acknowledgement exits non-zero.

Tests: 1087 passed, 0 failed (`/usr/bin/swift test`). Uninstaller checks were `--dry-run` and fixture
HOME only.

## Part 7c — release installer (done)

`scripts/install-release.sh` is the user bootstrap (published as `install.sh`). It checks Apple
Silicon and macOS 14, downloads the pinned GitHub release zip, checks SHA-256 before it strips
quarantine, copies the two apps to `~/Applications`, and says plainly that the build is not
notarized. The CLI symlink is off unless you pass `--cli` or answer yes. `--dry-run` changes
nothing. `scripts/install.sh` (from source) gained `--dry-run` too.

A terminal run without `--yes` opens SkyRose Settings from the checked download
(`--installer --payload`). That window uses the same chrome as the uninstaller. Its progress bar
follows the script's `::stage` lines. First-run onboarding still asks for permissions, and now has
skippable kitty and font steps.

The zip hash is read from `SkyRose-<version>-arm64.zip.sha256` on the release (or
`SKYROSE_RELEASE_SHA256` in tests). Part 7d publishes that file. Tests used a local zip and a
temporary HOME only. Full `/usr/bin/swift test`: 0 failures (1087 from 7b, plus 5 installer tests
and 1 stage-map test).

## Part 7d — GitHub Release (done)

Release: https://github.com/ganya002/skyrose/releases/tag/v0.2.0
Tag `v0.2.0` points at `1bf9a30` (not moved after that). Apps were built with
`scripts/build.sh` and signed with "Caelestia Local Signing". The zip is
`SkyRose-0.2.0-arm64.zip` (SkyRose.app, SkyRose Settings.app, install.sh, uninstall.sh).
Detached checksums are on the release. `docs/caelestia-reference` is not in the zip.
`uninstall.sh` is also inside `SkyRose.app/Contents/Resources/scripts/`.

Not done, on purpose: Homebrew cask, Apple notarization.

# Phase 6: Caelestia 1:1 visual polish (started 2026-11-06)

Resume here after a context reset. Spec: `docs/caelestia-reference/PHASE-PROMPT.md` and
`docs/caelestia-reference/docs/caelestia-research.md`. Public repo: https://github.com/ganya002/skyrose
(created 2026-11-06; push `main` after every part, never force-push).

| Part | State | Commit |
|---|---|---|
| 6a. Blob overlay (one SDF surface) | done, live-tested on the built-in | "Phase 6 part 6a" |
| 6b. Panel motion tokens | done, live-checked (launcher, dashboard clips) | "Phase 6 part 6b" |
| 6c. Left-bar dock popouts | done, live-tested on the built-in (hover, morph, trail) | "Phase 6 part 6c" |
| 6d. Wallpaper carousel | done, live-tested on the built-in (preview, revert, commit) | "Phase 6 part 6d" |

## Part 6a — blob overlay (done)

- `CaelestiaCore/Motion/Blob.swift`: pure port of Caelestia's Blobs plugin (@ bcbb5d5):
  `BlobRect` / `BlobFrame` / `BlobScene`, `BlobSDF` (CPU line-by-line port of `blob.frag`: circular
  smin, smaxSharpA frame edge, border compression, border sinks, `effectiveRadii` = corner fill) and
  `Jelly` (`BlobRect::updatePhysics`: stretch along velocity, cap 35 %, spring k 200 / c 16, implicit
  damping, rest snapping). `CaelestiaTokens.swift`: M3 Expressive curves + durations, per-panel
  `deformAmount`.
- `CaelestiaShell/Blob/BlobShader.swift`: the MSL port (compiled at runtime), plus display corner
  radii, a 15 pt shadow and a mask mode. `LiquidSurface.swift`: one per display, it is the frame
  window's content (replaces the frame `FrostedView`): Metal fill layer + behind-window blur masked by a
  second CAMetalLayer rendered from the same SDF. It draws the band, the notch dips and every open
  drawer's background as ONE group, and its display link is the drawers' clock: offsetScale 0↔1 on
  expressiveDefaultSpatial (500 ms × 0.8), slide out through the edge, jelly, and the same
  slide/squash/fade applied to the drawer's content panel (`DrawerContentView.sublayerTransform` /
  opacity). Renders only while something moves.
- Drawer views: `DrawerBackground` replaces `FrostedShape + liquidBody` (launcher, dashboard, session,
  OSD, sidebar, utilities, popout, wallpaper); on the surface it draws nothing and reports the body rect
  (fillets excluded) through `\.blobReporter`. `liquidBody` / `liquidContent` are no-ops on the surface.
  The old frosted path stays as the fallback (no Metal, or `SKYROSE_LIQUID=0`).
- Controller: `makeTheme` sets `theme.liquidSurface`; `makeDrawerPanel` wraps the host in a
  `DrawerContentView` and sets edge + deformAmount (`blobStyle`); `present` → `surface.open`;
  `dismiss` / `dismissAfter` / `hideOSD` → `retract` → `surface.close` (orders out when hidden).
  Session dim moved under the frame (it would dim the session's own background otherwise).
- **Bug fixed on the way:** AppKit constrained the full-display frame window below the menu-bar/notch
  strip (32 pt) on the built-in while drawers were laid out from the unconstrained layout, so every
  drawer sat 32 pt off its band. `ShellPanel.constrainFrameRect` now returns the rect unchanged; the
  frame reaches the top again and dips around the notch as designed.
- Live (built-in, kitty behind): dashboard, launcher, session, OSD, sidebar, utilities, audio popout all
  grow out of the band with concave fillets; the notch dip is part of the surface; utilities + OSD fuse
  into one shape. Dashboard open ≈ 400 ms with a small overshoot, close ≈ 100 ms. Shots in the session
  scratchpad (`live/d2.png`, `l2.png`, `s2.png`, `sb3.png`, `u4.png`, `m1.png`).

Still separate from the surface: toasts (own frosted pill, as upstream: not a PanelBg) and the bar's
content
(the bar band itself is the frame's left edge). Jelly amounts are upstream's (dashboard 0.1 → ≈ 4 %
stretch at full speed): subtle by design.

## Part 6b — panel motion tokens (done)

- Drawers (launcher, dashboard, session, OSD, sidebar, utilities, popouts, wallpaper): offsetScale on
  expressiveDefaultSpatial, 500 ms × 0.8 = 400 ms both ways (Caelestia Wrapper Behavior); content fades
  1 − offsetScale with the slide; open size changes morph on the same curve (`LiquidSurface.bodyChanged`).
  Interruptible: a reopen/close mid-flight starts from the current offsetScale.
- `ShellTheme`: `small` = expressiveDefaultEffects (colour/opacity, 160 ms), new `spatial` =
  expressiveDefaultSpatial (size/position, 400 ms), `fastSpatial` = token (280 ms), `token(_:)` /
  `tokenSeconds(_:)`. Size-like animations moved to `spatial`: launcher rows + scroll, dashboard tab
  height, sidebar group expand, OSD slider fill, gauges/arcs, toast list.
- Bar reveal (liquid surface): expressiveDefaultSpatial 400 ms both ways (was spring in /
  emphasizedAccel out); the swing past 1 swells the band (cap unchanged), past 0 is clamped.
- Toasts: scale 0.7 → 1 (Caelestia), list on the spatial token. Session scrim: slowEffects in /
  defaultEffects out.
- Reduce Motion: drawers slide in 120 ms on `standard` with no jelly; every token falls back to the
  120 ms ease (`ShellTheme.token`); the bar reveal uses `standard`.
- WM window animations (popin 80 %, workspace slide) untouched.
- Live: launcher open ≈ 70 ms to the band, overshoot settles by ≈ 400 ms, close < 100 ms
  (reference: open ≈ 380 / close ≈ 130 measured to rest); dashboard likewise. Not live-tested:
  bar reveal (warped pointers do not trigger hover; no IPC), toasts (would write the notification history).

## Part 6c — left-bar dock popouts (done)

- Workspace pills (Caelestia Workspace.qml): shape per workspace (active: dot, occupied: small
  square, empty: faint dot) followed by up to 5 app icons of its windows (`WorkspacePill.apps`,
  filled by `ShellBridge.pills(… bundleID:)` from the WM's window handles). The column grows with them.
- Active trail (ActiveIndicator.qml, `activeTrail`): one primary capsule behind the active workspace
  whose top and bottom move separately; the edge in the direction of travel leads on
  expressiveDefaultSpatial (500 × 0.8 = 400 ms), the other trails 1.5× (600 ms), so it stretches and
  catches up. Contents of the active workspace turn onPrimary. Reduce Motion: 120 ms, no trail.
- Hover popouts: hovering the active-window column or a status icon (audio, network, Bluetooth,
  battery) opens its popout; moving to another item morphs the one popout to it (the blob tweens
  body size + position on the spatial token and the content panel rides the drawn body,
  `LiquidSurface.applyContent` now offsets against the morph target); content cross-fades
  (`.id(kind)` + opacity). Leaving the bar and the popout closes it (120 ms pointer check);
  click-opened popouts stay until clicked away; hover does not open popouts over the launcher,
  dashboard, session or wallpaper drawers.
- Hover is hit-tested in the controller's global pointer monitor against item frames the bar
  reports (`BarModel.itemFrames`): SwiftUI `.onHover` never fires in the non-activating bar panel
  while another app is active (live finding).
- New active-window popout (400 pt): app icon, title, app name and a ScreenCaptureKit still of the
  focused window (only when Screen Recording is already granted; no prompt from a hover).
  Popout widths follow Caelestia: active window 400, audio / network 320, Bluetooth 300, battery 250.
- An IPC / keybind popout on an auto-hidden bar now reveals and holds the bar (a popout always grows
  out of it); closing re-checks the pointer so the bar hides again. `shell drawers toggle
  popout.activewindow` (names are case-insensitive).
- Right sidebar unchanged.
- Live (built-in, kitty on ws1): hover audio → popout; up to the window column → morph to the
  preview popout (≈ 400 ms, jelly settles); leave → close + bar hides. Trail clip ws1 → ws4 → ws1:
  leading edge arrives first both directions. Shots: scratchpad `live6c/hover3.png`,
  `live6c/sheet.png` (morph), `live6c/trailsheet.png`.
- Note: during this run macOS showed "SkyRose would like to record this computer's screen and audio"
  although `permissions status` reports Screen Recording granted (left for Gabby; nothing clicked).

## Part 6d — wallpaper carousel (done)

- `>wallpaper` (the command autocompletes to `>wallpaper `, Caelestia `autocomplete`) turns the
  launcher into the carousel (Caelestia ContentList "wallpapers" state + WallpaperList PathView):
  the app list fades out (defaultEffects), the body morphs to max(600 × 1.2, slots × 254) ×
  200 on the spatial token, the carousel fades in. Text after the command fuzzy-filters by file name
  and starts on the best match; with no search the carousel starts on the desktop's wallpaper.
- Carousel: circular path; slots = what fits in screen − 4 × rounding − 2 × bar, at most 9, odd
  (2 → 1); centre item scale 1 with an elevation shadow, the others on the path 0.8, items
  leaving the path shrink to 0, new ones pop in from 0.5 (scale spatial, opacity effects). Items are
  280 × 158 thumbnails (640 px, disk-cached) with the file name; live wallpapers show a play badge.
  Up / Down / Tab / ←/→ / scroll / click a neighbour move it; Enter or a click on the centre picks.
- Live preview: every centred item cross-fades the desktop over 600 ms through `WallpaperPreview`
  (desktop-level image windows above the live-wallpaper video, below icons and windows, all
  Spaces, click-through). Nothing is written until a pick: Escape / click outside / closing the
  launcher fades back to the real desktop picture; a pick sets it underneath and the overlay
  leaves 0.8 s later (2 s for a live wallpaper, whose video window starts below it).
- The wallpaper drawer and `>random` now change wallpapers through the same 600 ms cross-fade
  (`transitionWallpaper`); IPC `wallpaper set` stays immediate. Reduce Motion: 200 ms fade.
- Live (built-in, 3 slots): typing → morph, preview cross-fades behind kitty, → → moves + previews,
  Escape reverts (measured fade ≈ 0.55–0.6 s, `wallpaper get` unchanged), `>wallpaper peaks` +
  Enter set "Landscapes - Minimal peaks" and removed the overlay windows. Gabby's wallpaper
  (`~/Pictures/arch-mac-blue.png`) was restored afterwards on both displays.
  Shots: scratchpad `live6d/carousel.png`, `live6d/moved.png`, `live6d/reverted_s.png`, `live6d/morph2.png`.
- Short of 1:1: the dynamic colour scheme is not previewed while scrolling (it follows the pick);
  one transition (crossfade), not Caelestia's 29 shaders.

## Tests (phase 6)

After part 6a: 1045 tests, 0 failures (`/usr/bin/swift test`).
After part 6b: 1048 tests, 0 failures.
After part 6c: 1055 tests, 0 failures.
After part 6d: 1065 tests, 0 failures.

---

# Previous phase: launcher + wallpapers, SIP-off mode, Material icons / screenshots / Clamshell

(started 2026-11-05)

Resume here after a context reset. Read `docs/parity-progress.md` and `docs/arch-parity.md` first.
Strict order (Gabby is low on usage): 1 quick fixes → 2 wallpapers → 3 SIP-off mode → 4 Material
Symbols → 5 screenshots, keep-awake, Clamshell. Commit on main after each part (not pushed).

## Status

| Part | State | Commit |
|---|---|---|
| 1. Launcher index + empty-workspace jump | done, live-checked | see `git log` ("Phase 5 part 1") |
| 2. Wallpaper subfolders + live wallpapers | done, live-tested | see `git log` ("Phase 5 part 2") |
| 3. SIP-off mode | done, live-tested in the Dock (3b) | "Phase 5 part 3a", "3a-fix", "3b" |
| 4. Material Symbols | done, live-checked (dashboard + sidebar) | "Phase 5 part 4" |
| 5. Screenshots, keep-awake, Clamshell | 5a screenshots done, live-tested; 5b keep-awake timers done, live-tested; 5c Clamshell done; 5c-fix: lid closed on battery / built-in only via `pmset disablesleep` (on/off/timer/panic live-tested; closed lid tested by Gabby) | "Phase 5 part 5a", "5b", "5c", "5c-fix" |

**Phase 5 is complete.** Next: whatever Gabby picks; candidates are in "Remaining (next phases)" in the
archive section below and in `docs/arch-parity.md`. Open item for 5c: Gabby's own lid-close test (Clamshell
on, battery, built-in display only; see "Part 5c-fix" below).

## Part 1 — done

- `AppIndex` (Shell/Launcher): own apps first (SkyRose.app from `Bundle.main`, even though it is
  LSUIElement, and SkyRose Settings next to it or via Launch Services), then the roots
  (/Applications, ~/Applications, /System/Applications(+Utilities), /Applications/Utilities,
  /System/Library/CoreServices/Applications) **3 sub-folder levels deep** (never inside a bundle,
  no symlinked dirs), Finder pinned, then Spotlight hits. First copy of a bundle id wins.
  `AppIndex.isIndexable(path:)` drops Spotlight hits inside another bundle, in hidden folders
  (Trash, .build), caches/containers/Application Support/Developer/DerivedData, /Volumes (DMGs),
  /private, /usr, /opt and /System/Library (except CoreServices/Applications and Finder).
- `AppIndexWatcher`: live `NSMetadataQuery` (`kMDItemContentTypeTree == 'com.apple.application-bundle'`)
  + FSEvents on the roots (works with Spotlight off); every change rescans once, debounced 1 s.
- Launching the SkyRose entry opens SkyRose Settings (SkyRose is this process and has no window);
  `>settings` now opens SkyRose Settings (was a "not built yet" toast).
- Bug fix: closing the launcher/session menu calls `ShellHost.shellKeyDrawerClosed(launched:)`;
  the WM ignores macOS focusing a **parked** window for `focusGuardInterval` (0.5 s) afterwards,
  so the re-activated previous app no longer drags the display to its workspace. Launching an app
  from the launcher clears the guard (that app is followed).
- Live: launcher on the built-in (empty ws1), typed "skyrose" via `CGEvent.postToPid` to SkyRose
  only: SkyRose, SkyRose Settings, TestWindows listed (`/tmp/cwm/phase5/launcher-skyrose.png`);
  after closing, the built-in stayed on ws1. The ws 3 → 4 jump itself is unit-tested
  (`testClosingAKeyDrawerDoesNotFollowTheReactivatedApp`); reproducing it live needs a parked
  window on the built-in while Gabby's kitty holds focus on the DELL, skipped.

Decisions: DMG apps (/Volumes) are not listed; Bundle's info cache means an app renamed in place
shows its new name after a WM restart.

## Part 2 — done

- `WallpaperLibrary.scan`: the folder and sub-folders 3 levels deep, hidden files, packages,
  symlinked dirs and non-media (.md notes) skipped; `ScanResult.groups` (`""` = top level,
  then "Live", "Live/Anime", "Static" by name) + flattened `urls`. Videos: .mp4/.mov/.m4v.
- `LiveWallpaper.swift`: `LiveWallpaperStill` (AVAssetImageGenerator first frame → JPEG in
  `Application Support/SkyRose/live-stills/<key>.jpg`, cached by path/mtime/size);
  `LiveWallpaperPolicy` (pause on battery, Low Power Mode, every window covered, screens
  asleep / session inactive); `LiveWallpaperRecord` (`live-wallpaper.json`, resumed at shell
  start only while macOS still shows our still); `LiveWallpaperController` (one muted
  `AVQueuePlayer` + `AVPlayerLooper`, one borderless window per screen at desktop level + 1,
  i.e. under the Finder's icons, all Spaces, click-through; rebuilt on screen changes).
- `setWallpaper(video)`: still → desktop picture on every display (lock screen, Mission Control,
  colour extraction all read it) → video loops above. Picking a picture stops it and forgets the
  record; `shell kill` stops it but keeps the record. `wallpaper get` returns the video.
- Picker: group chips (All / Live / Static with counts) + play badge on video thumbs (first
  frame). Settings › Appearance › Wallpaper: one grid per group, badge, "Choose…" accepts movies.
- Test-only: `SKYROSE_LIVE_WALLPAPER_ON_BATTERY=1` (env at launch) ignores the battery rule.
- Live (Gabby's `Live/Sky - Aurora at dawn.mp4`, on battery): paused on the first frame
  ("paused (on battery)" in the log) and the still was the desktop picture on both displays;
  with the override: "playing … on 2 display(s)", two crops 2 s apart differ, WM CPU 1.6 %;
  a WM restart resumed it. Restored `~/Pictures/arch-mac-blue.png` with its original options
  (scaling 3, clipping, fill colour) afterwards; record cleared, no live windows left.
  Shots: `/tmp/cwm/phase5/live-battery.png`, `picker.png`. Not live-tested: the "covered" pause
  (needs a window covering a whole display; unit-tested in the policy).

Decisions: no config key for "play on battery" (the brief says pause); the first occlusion
report can log one "paused (covered by windows)" before the windows are on screen.

## Part 3 — SIP-off mode (done)

Verified first (2026-11-05): `csrutil status` = Custom Configuration with Filesystem, Debugging
and NVRAM protections disabled; `nvram boot-args` = `-arm64e_preview_abi`; macOS 27.2 (26B123), arm64.

- `Packaging/sa/`: `trampoline.s`, `loader.c` (`skyrose-sa-loader`, no arguments, sudo, invoking
  user's Dock only), `payload.c` (`SkyRoseSA.dylib`). `scripts/build-sa.sh` (arm64e), called by
  build.sh into `SkyRose.app/Contents/Resources/sa/` (ad-hoc signed before the bundle seal).
  Protocol and safety: docs/ENHANCED_MODE.md › How it works.
- Swift: `CaelestiaPlatform/Enhanced/ScriptingAddition.swift` (`SAClient`, `SAProtocol`),
  `CaelestiaWMKit/EnhancedMode.swift` (`EnhancedMode`, `EnhancedWindowAnimator`), hooks in the
  layout pass (instant switch hide/restore, `layoutApplied`), the slide gate, the close action,
  `shutdown()` (reset), daemon wiring (animator swap on `onChange`), `query state` mode.
- `[sipOff]` config: enabled=false, animations, opacity, shadows, instantWorkspaces, pinOnTop.
- `SIPOffReadiness` (Core): parses csrutil + boot-args. CLI `skyrose sa status | load-command |
  reset`; `skyrose wm panic` also sends `reset` + `stop` straight to the SA socket.
- Settings › SIP-off mode (`SIPOffPage`): warning, status, sudo line + Copy, switch locked until
  the showcase's "I understand the risks" (`@AppStorage sipOffShowcaseSeen`), per-feature
  switches, how to turn SIP back on. `SIPOffShowcase`: live side-by-side demos (animations,
  opacity/shadows, instant workspaces, pinning) + risks. `--sip-off-showcase` opens it.
- SIP reminder flag: `EnhancedMode.probe()` calls `RestoreManifest.recordModeUsed(.sipOff)` the
  first time the SA answers.
- Tested without the Dock: payload loaded into a throwaway arm64e host process with its own
  window (`SKYROSE_SA_SOCKET` override): hello listed all 5 capabilities on macOS 27.2; info
  read the window server transform convention translate(-x,-y); `visual` drew the 400×332
  window at 200×166 at (700,360) with alpha 0.9 (`/tmp/cwm/phase5/sa-visual.png`); alpha/level
  went back when the client disconnected; freeze/thaw ok. Settings page + showcase shots:
  `/tmp/cwm/phase5/settings-sipoff.png`, `showcase.png`.
- **Next (after Gabby loads the SA):** `skyrose sa status`; `skyrose config set sipOff.enabled
  true` with `sipOff.opacity false` (opacity would touch Gabby's kitty); TestWindows only (float
  rule): pop-in, move, close, pin on top, alpha via the socket; `skyrose wm panic` → everything
  restored; then flip the macOS-limit rows in arch-parity.md that work, commit "part 3b".

### Part 3b — loader debugging (macOS 26 / Darwin 27)

- Live symptom: `sudo skyrose-sa-loader` printed nothing and exited. Added a `-v` trace, unbuffered
  output, always-on crash handlers and distinct exit codes to `Packaging/sa/loader.c`.
- Verbose trace showed every step succeed through `thread_convert_thread_state`, then exit 137.
  Kernel log: `EXC_GUARD type=0x1 (GUARD_TYPE_MACH_PORT) … THREAD_SET_STATE on mach port … signal 9`.
  So **`thread_set_state` on a thread's mach port is killed by a Mach-port guard on macOS 26** —
  not a ptrauth fault (SIGKILL is why the handler stayed silent). Confirmed by Frida issue #3757
  (same guard on 26.4; `tss_should_crash=0` is ignored on 26.x). SIP/boot-args were fine
  (Debugging Restrictions off, `-arm64e_preview_abi` set), so readiness was never the problem.
- **Fix (mirrors yabai's 14.4+/15+ path):** on macOS ≥ 14.4 don't call `thread_set_state`; throw
  the conversion thread away (`thread_terminate`) and start the real one atomically with
  `thread_create_running(task, ARM_THREAD_STATE64, converted_state, …)`. Older macOS keeps the
  classic `set_state` + `resume`. Our ptrauth signing (IA key, ctx 0) and convert direction
  (`FROM_SELF`) already matched yabai. Gated by `macos_at_least()` (`kern.osproductversion`).
- Also reverted (via Gabby) `sipOff.enabled` in his config.toml — my live Settings test had left
  the toggle on after the showcase unlocked it; inert with no SA loaded, now back to the default.
- Gabby's run (2026-11-06): every step ok, "thread_create_running ok", exit 0, Dock pid 664.

### Part 3b — live test (done)

- `skyrose sa status`: loaded (v1: alpha, shadow, level, transform, space); `query state` mode enhanced;
  `sipOff-mode-used` flag written.
- Raw socket on Gabby's idle kitty "~" (0x314): alpha 0.4, shadow off, half-size transform, level 3,
  all read back; all undone on disconnect.
- WM path (TestWindows on empty ws2 + kitty on ws1): open pop + fade, retile spring, WM close shrink+fade,
  instant workspace switch, pin on top, opacity on/off (0.95 on kitty too), shadows off/on. Numbers in
  arch-parity.md › SIP-off mode live test. Files: `/tmp/cwm/phase5/3b/`.
- **Bug found + fixed:** pinning starts a float-move animation, and `layoutApplied` skipped windows the
  animator covered, so the level (and shadow) was never sent. Now only alpha waits for the animation
  (`testPinDuringAnAnimationRaisesAtOnceButAlphaWaits`). Live after the fix: level 3, stays above a
  focused tile; unpin → level 0.
- `skyrose wm panic`: every change undone, socket closed, WM quit. TestWindows quit, no leftovers;
  WM started again (standard mode, since the helper's socket is closed). Config left as found
  (`sipOff.enabled = true`, opacity false).
- To use SIP-off mode again after a panic or a reboot: run the loader again (`stop` resets the payload's
  running flag, so a second load restarts it).

Decisions: blur and rounding of other apps stay limits (no SkyLight call for them); a rebuild while the
Dock has the dylib loaded was harmless (Dock kept running, helper kept answering).

## Part 4 — Material Symbols (done)

- `ShellIcon` (Shell/Theme/ShellTheme.swift): `fromSF` maps every SF name the shell uses to a
  Material Symbols Rounded name + fill; `glyph(_:)` resolves SF or Material names (dotted unknown
  names stay SF only, e.g. `apple.logo`; plain unknown names are Material); `materialFont(size:
  weight:fill:)` builds the variable font with FILL / wght / opsz / GRAD axes (cached);
  `materialScale` 1.25 so a Material glyph matches the SF size it replaces.
- `MaterialIcon` view (Shell/Support/MaterialIcon.swift): ligature text when the family is
  registered (FontStore, already done at WM start once `skyrose fonts download` ran), else the SF
  Symbol. Every `Image(systemName:)` in the shell (47 sites) now goes through it; brightness slider
  uses `brightness_high`, the session moon `bedtime` (filled).
- Tests: SF names in the map exist, every Material name's SF fallback exists, resolver cases,
  weight axis, and every Material name is a single ligature glyph in the pinned font (skipped
  where the font is not downloaded).
- Live: dashboard (tabs, weather, chips, gauges) and sidebar (empty notifications, keep awake,
  sliders, quick toggles) render Material: `/tmp/cwm/phase5/icons/dashboard.png`, `sidebar.png`.

Decisions: no config switch (Material whenever the font is present, SF otherwise); Settings
(SkyRoseSettingsKit) keeps SF Symbols (macOS settings look); `apple.logo` stays SF.

## Part 5a — screenshot tool (done)

- Core `Capture/Capture.swift`: `CaptureMode` (region, freeze, window, full), `CaptureGeometry`
  (drag rect, click tolerance 4 pt, global → display-local → pixels, window under the pointer from
  the window list, macOS-style file names "Screenshot 2026-11-06 at 09.05.07.png" + " (2)",
  opt-in ⇧⌘3/4/5 binds written with whichever logical modifier is ⌘ in the preset).
- `[capture]` config: folder `~/Pictures/Screenshots`, saveToFolder, copyToClipboard, thumbnail,
  overrideSystemShortcuts = **false** (WMDaemon appends the binds at keymap load / reload / when the
  key flips; macOS's own shortcuts are never touched by default).
- Shell `Capture/ScreenshotController.swift`: ScreenCaptureKit (`SCScreenshotManager`), picker
  panels at screen-saver level on every display (dim + hole, size label, hover highlights the
  window under the pointer; drag = region, click = window, click on the desktop = that display,
  Esc / right click = cancel, pressing the bind again cancels). Freeze captures every display
  first and crops the still. Window capture without shadow. Full = display under the pointer.
  PNG to the folder + PNG/TIFF on the clipboard; success toast with a thumbnail
  (`Toast.imagePath`). Binds: existing `capture.region` / `capture.full` / `capture.freeze`
  (Print → ⌥L⌘⇧4 / F13 etc.). CLI: `skyrose screenshot region|freeze|window|full` (returns at once).
- Live (capture.folder → /tmp, clipboard off, then both reset): full 2940×1912; region drag
  400×220 pt → 800×440 px; window (TestWindow 1408×862) → 2816×1724 without shadow; freeze drag
  → 800×400 of the still; Esc closes the picker; toast with thumbnail
  (`/tmp/cwm/phase5/shots-toast.png`, `window-shot.png`, `freeze-shot.png`).

Decisions: full = the display under the pointer (grim joins all outputs; stitching mixed scales is
not worth it); no swappy-style editor (Preview is one double-click away); the toast is
click-through like every toast, so no "open" action on it; if macOS's own ⇧⌘3/4/5 still fire with
the override on, turn them off in System Settings › Keyboard › Shortcuts › Screenshots
(documented in LIMITATIONS.md). Seen once, not reproduced: right after a WM restart + `ws focus 2`
the display was back on ws1 before the first picker (picker/drag/Esc on ws2 kept ws2 three times).

## Part 5b — keep-awake timers (done)

- Core `Power/KeepAwakeTimer.swift`: parse "30m" / "1h" / "1h30m" / "90" (minutes) / "45s" /
  "forever" (1 s … 7 days), presets ∞ / 15 min / 1 h / 2 h / 5 h, "1 h 05 min left" text, status
  line, `isChosen` (a chip lights only for exactly its length; a CLI `on 1m` lights none).
- `KeepAwakeService.set(on:duration:)` + `until` / `duration` / `remaining`; a one-shot Timer
  (RunLoop common mode) releases the `PreventUserIdleDisplaySleep` assertion "SkyRose keep awake".
  Turning it on again replaces the timer.
- `ShellState.keepAwakeUntil` + `keepAwakeDuration`; sidebar card: countdown status (TimelineView,
  20 s) + chip row. The switch only forwards real flips (re-sending the current value would have
  turned a timed keep-awake unlimited).
- IPC `keepawake {state: on|off|status, seconds?}` → `{enabled, until?, status}`; CLI
  `skyrose keepawake on [30m|1h|forever] | off | status` (aliases keep-awake, caffeinate), help + Schema.md.
- Live: `on 1m` → assertion present (checked with a read-only `IOPMCopyAssertionsByProcess` script,
  no pmset), released on time with the sidebar open and `swift test` running; 10 s / 15 s timers with
  the sidebar closed / open / opened after start all ended on time; bad duration / verb → exit 3 +
  help. Shots: `/tmp/cwm/phase5/keepawake-1m-card.png` (no chip lit), `keepawake-1h-card.png` (1 h lit).
- Seen once, not reproduced (4 later runs fine): the first 1 min run was still on, unlimited, after
  it should have ended. Only the sidebar switch can do that, so its setter is now guarded. If it
  comes back, log the caller in `KeepAwakeService.set`.
- Not live-clicked: the chips themselves (the same `set(on:duration:)` path as the CLI). The switch
  looks grey while on because the sidebar panel is never key (macOS inactive look; it was like that before).

## Part 5c — Clamshell (done)

(Superseded by 5c-fix below: the "adapter + external display only" limit was wrong; SkyRose now uses
`pmset disablesleep` through a scoped sudo -n helper.) Original 5c: macOS runs lid-closed natively only
on a power adapter AND with an external display; SkyRose reported that.
- Core `Power/Clamshell.swift`: `ClamshellFacts` (hasLid, lidClosed, closingCausesSleep?, onAC,
  externalDisplays) → `ClamshellMode` (no-lid, open-will-sleep, open-will-stay-awake, closed-running);
  the kernel's `AppleClamshellCausesSleep` wins when published; summary line names what is missing;
  `holdsKeepAwake` only while closed-running and opted in.
- `[clamshell] keepAwake = false` (Config + config.default.toml).
- Services `Power/ClamshellMonitor.swift`: reads IOPMrootDomain `AppleClamshellState` /
  `AppleClamshellCausesSleep`, `IOPSGetProvidingPowerSourceType`, online non-built-in displays;
  refreshes on root-domain interest messages, IOPS notifications and screen-parameter changes (no
  polling). Own assertion "SkyRose clamshell keep awake" (PreventUserIdleDisplaySleep) while
  closed-running with the option on.
- Shell: `ShellState.clamshell`; sidebar keep-awake card shows the summary line (laptop_mac icon) on
  Macs with a lid. IPC/CLI `skyrose clamshell [status]` (alias `lid`) → `{hasLid, lidClosed, onAC,
  externalDisplays, mode, summary, closingCausesSleep?, keepAwake, holdingKeepAwake}`.
- WM (`WorkspaceState`): `removeDisplay` remembers each surviving workspace's home display and what
  it showed (`displayHomes`, `homeActive`, Optional so old session.json decodes); `ensureDisplay` of a
  returning display moves them back and shows the old one; a display that was showing one falls back
  to its lowest own workspace or a new one; a workspace closed while away loses its home. Works across
  a WM restart with the lid closed (`restored` → snapshot → open). `DisplayReturnTests` (7).
- Live (battery, no external display): `skyrose clamshell` → open-will-sleep, closingCausesSleep true,
  matches read-only `ioreg -r -n IOPMrootDomain`; `clamshell on` → exit 3 + help; sidebar shot
  `/tmp/cwm/phase5/clamshell-sidebar.png`. **Not live-tested**: lid closed with power + display
  (closed-running, the assertion, workspaces returning on open); needs a dock.

## Part 5c-fix — Clamshell on battery / built-in only (done)

5c called "power adapter AND external display" a hard limit; that is only macOS without a helper.
Ported Clamshell Toggle's `Power.swift` (github.com/ganya002/clamshell-toggle) into SkyRose (no
second menu-bar app, no updater, LaunchAgent or installer).
- Core `Clamshell.swift`: `ClamshellFacts.sleepDisabled` wins over `AppleClamshellCausesSleep`
  (the kernel keeps that `Yes` with SleepDisabled 1, seen live); `ClamshellVia` native /
  sleep-disabled; `LidSleepStatus` (clamshellOn, keepAwakeOn, helper unknown/ready/missing);
  new summary lines; `LidSleep` (pmset -g parsing, `sudo -n pmset disablesleep 0|1` arguments, the
  two-command sudoers rule, `installCommand(user:)` for `/etc/sudoers.d/skyrose`).
- Services `Power/LidSleepControl.swift`: `PmsetSleepSwitch` (pmset -g / sudo -n on a serial queue,
  never interactive) + `LidSleepControl`: SleepDisabled 1 while Clamshell or a keep-awake is on, no
  sudo call when already there, 0 when both are off; quit and next-start-after-crash restore only
  what SkyRose set (marker `sleep-disabled-by-skyrose`), panic restores always. Start probes the
  helper by re-applying the current value (as Clamshell Toggle's installer does).
- `ClamshellMonitor` reads `SleepDisabled` from IOPMrootDomain. Shell: `ShellState.lidSleep`,
  keep-awake `onChange` → `setKeepAwake`, sidebar Clamshell chip next to the lid line.
  WM: `onPanic` hook (chord + IPC), `WMDaemon.terminate` → `releaseForQuit`.
- IPC/CLI `skyrose clamshell [status|on|off|helper]` adds `enabled, keepAwakeActive, sleepDisabled,
  sleepDisabledBySkyRose, helper, via?, helperCommand?, helperError?`. Schema.md, help, LIMITATIONS
  ("Lid closed"), UNINSTALL (restore sleep, remove the rule, heat/battery), SHELL.md, README.
- Helper: **already present**: `/etc/sudoers.d/clamshell` (Clamshell Toggle's) makes `sudo -n` work;
  status `helper ready` at WM start. The missing-helper path is unit-tested only.
- Live (Clamshell Toggle quit by Gabby first; AC + DELL attached): `clamshell on` → pmset
  SleepDisabled 1, `via sleep-disabled`; `off` → 0; `keepawake on 15s` → 1, back to 0 at ~15 s;
  `clamshell on` + `wm panic` → 0, no marker; WM restart → helper ready, layout from session.json.
  Sidebar shots `/tmp/cwm/phase5/clamshell-fix-on.png` / `-off.png`. Left at SleepDisabled 0.
- **Not tested by Claude**: closing the lid. Gabby: `skyrose clamshell on`, unplug power and the
  DELL, close the lid, check it stays awake (e.g. music keeps playing / ssh in), open the lid,
  `skyrose clamshell off`, `pmset -g | grep SleepDisabled` → 0.

## Tests

After part 1: 970 tests, 0 failures (`/usr/bin/swift test`).
After part 2: 976 tests, 0 failures.
After part 3a: 987 tests, 0 failures.
After 3a-fix (loader): 987 tests, 0 failures.
After part 3b: 988 tests, 0 failures.
After part 4: 993 tests, 0 failures.
After part 5a: 1002 tests, 0 failures.
After part 5b: 1011 tests, 0 failures.
After part 5c: 1024 tests, 0 failures.
After part 5c-fix: 1031 tests, 0 failures.

---

# Previous phase (archive)

## Phase: terminal, fonts, liquid animations + bug fixes (started 2026-11-05)

Resume here after a context reset. Read `docs/parity-progress.md` and `docs/arch-parity.md` first.
Order: 1 bugs → 2 liquid animations → 3 terminal → 4 fonts. Commit on main after each part
(not pushed).

## Status

| Part | State | Commit |
|---|---|---|
| 1. Bugs (SIP reminder, weather, temperatures, edge drags) | done, live-tested | see `git log` ("Part 1") |
| 2. Liquid animations | done, live-tested | see `git log` ("Part 2") |
| 3. Terminal | done, live-checked (Settings page, sync no-op) | see `git log` ("Part 3") |
| 4. Fonts | done, live-tested (dashboard in Rubik) | see `git log` ("Part 4") |

## Part 1 — done

- **SIP reminder**: `SIPReminderDecision.shouldShow(sipOffModeUsed:status:)` (Core/Backup/SIPStatus.swift).
  Shown only if the `sipOff-mode-used` flag file (or the manifest entry) exists **and** `csrutil
  status` is not fully enabled. A corrupt manifest no longer forces it. `skyrose uninstall` decides
  before removing anything and opens Settings `--sip-reminder`. Nothing in the app sets the flag
  yet (Enhanced mode / the SA loader is not built); `RestoreManifest.recordModeUsed(.sipOff)` is the hook.
- **Weather**: `[weather]` config (city, latitude, longitude, useLocation=false, fahrenheit,
  refreshMinutes=30). Open-Meteo client in `CaelestiaServices/Weather/OpenMeteo.swift` (pure
  parsing, fixtures in `Tests/fixtures/openmeteo`). `WeatherController` (Shell) fills
  `ShellState.weather` / `weatherStatus`. Dashboard Overview card + new Weather tab. Settings ›
  Bar and Shell › Weather: debounced city search. CoreLocation via `LocationService`, entitlement
  `com.apple.security.personal-information.location` added to SkyRose.entitlements.
  Live: Oslo test showed 5 °C "Mainly clear", 12 h + 7 days; config restored afterwards (no city set).
- **Temperatures**: `HIDTemperatureReader` (dlsym'd IOHIDEventSystemClient… like Stats) +
  `TemperatureSummary` classifier. M4 Air live: CPU 30 °C avg / 32 °C hottest, battery 25 °C,
  SSD 30 °C; GPU hidden (M4 exposes no named GPU sensor). "degrees need root" removed.
- **Edge drags**: `EdgeDrag` (Shell/Support) + passive global monitors (mouse down/drag/up,
  trackpad scroll phases). Frame stays click-through. Live: 108 pt drag on the upper right band
  opened the sidebar; 28 pt did nothing. Session-zone drag only unit-tested (a synthetic drag
  could release over a session button).

Decisions: lat/lon are stored with 2 decimals by ConfigFileEditor (≈1 km, fine for weather).

## Part 2 — done

- `CaelestiaCore/Motion/LiquidMotion.swift`: every spring from (damping ratio, settling time).
  Windows: pop ζ 0.58 from 80 %, move ζ 0.72, both 300 ms; close unchanged. Workspaces: Arch
  snappy Bézier 320 ms. `FrameSampler` returns exactly 1 at its end time (FP fix).
- Shell: `Support/LiquidDrawer.swift` (`liquidBody` / `liquidContent`) on every drawer
  (sidebar without neck, launcher, dashboard, session, OSD, wallpaper, popouts, utilities with
  a corner neck). `ShellTheme.drawerSpring(depth:)`, `neckSpring`, `contentFadeIn`,
  `panelFadeInSeconds` (50 ms), `overshootRoom(depth:)` + `DisplayLayout.withRoom` on every
  drawer panel frame; Utilities got an explicit `bodyHeight` so its GeometryReader layout is
  unchanged. Bar: `ShellTween.animate(to:spring:)` (velocity kept on retarget),
  `ShellTheme.barRevealSpring`, frame band swell (`frameInsets(swell:)`, cap 1.12),
  `BarMotion.contentOffset`. Toasts: asymmetric scale/slide/fade transitions.
- Live (built-in, ws 3 empty, TestWindows only): see the table at the end of
  `docs/arch-parity.md`. Clips + contact sheets in `/tmp/cwm/liquid/` (`before_*`, `after_*`,
  `NOTES.md`). Not live-tested: bar reveal (warped pointers do not trigger hover), toasts (would
  write to Gabby's notification history), OSD (needs a volume key), popouts, wallpaper.

Decisions: no anisotropic window squash (unsafe to compose with the cover's scale animation);
workspace slide uses the Arch Bézier despite its front-loading because the brief names it;
overshoot is a constant ~16 pt so small and large drawers bounce alike.

Found, not fixed (pre-existing, not motion): closing a key drawer (launcher/session) on an empty
workspace re-activates the previous app and the WM follows it to its workspace (seen ws 3 → 4).

## Part 3 — done

- `CaelestiaCore/Scheme/KittyProfile.swift`: `KittyProfile` renders `~/.config/kitty/skyrose.conf`
  (Gabby's Arch kitty.conf mapped to macOS: blur 32, titlebar-only, ⌥ as Alt; colours from
  `include skyrose-theme.conf`). `KittySetup` installs (one `include skyrose.conf` line appended to
  kitty.conf, original copied + journalled as `kittyConfig`), uninstalls (restores the file
  byte-for-byte; deletes a kitty.conf it created), refuses to overwrite files it did not write,
  writes through a symlinked kitty.conf, and `syncTheme` rewrites colours only when kitty includes us.
- WM: `KittyLiveSync` on every scheme change and at start; `SIGUSR1` to running kittys only when
  the theme file changed.
- Terminals: `TerminalChoice.presets` = kitty (default), Rex (`com.superlogical.rex`), Terminal,
  iTerm2, Ghostty, WezTerm; Other = bundle id or command. ⌥T on a missing app opens macOS Terminal.
- Settings › Terminal: preset list with install state, Shortcut card (records `app.terminal`
  like Keybinds), kitty setup card (Set up / Remove, notes), Try it.
- CLI: `skyrose kitty status | install | uninstall [--json]`.
- Live: Settings page screenshot `/tmp/cwm/phase/settings-terminal.png`; WM restart left
  `~/.config/kitty` untouched (Gabby's kitty.conf does not include the profile). The profile was
  **not** installed into Gabby's kitty.conf (it would restyle the terminal running this session):
  `skyrose kitty install` or Settings › Terminal › Set up does it when wanted.

Decisions: no new config key; the include line is the opt-in. Terminal/iTerm2/Ghostty/WezTerm
open or come forward (no new-window scripting); only kitty opens a new window each time. Kitty
install offer in onboarding is left to the installer phase (brief).

## Part 4 — done

- `CaelestiaCore/Fonts/FontPack.swift`: Rubik, Inter, CaskaydiaCove NF, JetBrainsMono NF,
  Material Symbols Rounded; URLs pinned to tags/commits, SHA-256 + size per file, licence file per
  family (OFL 1.1 ×4, Apache 2.0). See `docs/FONTS.md`.
- `CaelestiaPlatform/FontStore.swift`: verified download into `Application Support/SkyRose/Fonts`,
  process-only registration (WM at start + on config reload, Settings at start), opt-in copy
  into `~/Library/Fonts` with `installed.json` + journal, uninstall of exactly those files.
- `ShellTheme.fontsChanged()` / `fontGeneration`: newly registered fonts re-render every surface.
- Config: `appearance.fontMono` is now the v3 family "CaskaydiaCove Nerd Font" (the v2 "NF" name
  is a fallback, plus "JetBrainsMono NF" which is what this Mac has); `apps.kittyFont` /
  `apps.kittyFontSize` feed `skyrose.conf`.
- Settings: Appearance › Fonts card (download with progress, install for other apps, remove);
  Terminal › kitty setup › Font picker (re-renders the profile and reloads kitty if in use).
- CLI: `skyrose fonts status | download | install | uninstall [--json]`.
- Live: `skyrose fonts download` (into SkyRose's folder only; nothing in ~/Library/Fonts) +
  `skyrose config reload` switched the running dashboard from SF Pro to Rubik:
  `/tmp/cwm/phase/fonts-compare.png` (left before, right after). JetBrainsMono Nerd Font was
  already installed on this Mac (Gabby's own copy), so kitty's font resolves today.

Decisions: fetch instead of committing ~32 MB of binaries; registration is per process so nothing
is installed without the explicit button; icons stay SF Symbols for now.

## Remaining (next phases)

- Installer phase: onboarding offers kitty (not installed by SkyRose) and the font download.
- Material Symbols for the shell's icons.
- Closing a key drawer on an empty workspace follows the re-activated app to its workspace.
- Not live-tested this phase: bar spring reveal, toasts, OSD, popouts, wallpaper drawer; the
  kitty profile against a real kitty (Gabby's kitty.conf was deliberately not changed).

## Tests

After part 1: 928 tests, 0 failures (`/usr/bin/swift test`).
After part 2: 942 tests, 0 failures.
After part 3: 954 tests, 0 failures.
After part 4: 964 tests, 0 failures.
