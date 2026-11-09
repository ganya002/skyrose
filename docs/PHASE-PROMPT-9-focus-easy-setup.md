# SkyRose Part 9: cursor/focus behaviour + make setup dead easy (release v0.4.0)

Send only after Part 8 (docs/PHASE-PROMPT-8-defaults-update.md) is released as v0.3.0. Read docs/phase-progress.md, docs/ENHANCED_MODE.md, docs/PERMISSIONS.md and the onboarding code first.

## Hard rules (same as always)
- No sudo by you. Never close Gabby's running apps. Never force-push or move an existing tag.
- Never touch disks, EFI, the bootloader, LUKS or NVRAM yourself. SIP can only be changed by the user in Recovery; SkyRose may guide, never automate it. No curl|sh.
- Test WM behaviour only with TestWindows; `skyrose wm panic` is the escape hatch.
- Journal every system change before making it; uninstall.sh must undo it (fixture-HOME tests).
- Don't apply anything to Gabby's real setup until it's tested and you're 99% sure it can't break.
- Commit locally after each part (small, clear commits). Push only at the end (see 9k). Report what you did and what you did NOT verify.

## 9a: Cursor follows focus (Hyprland-style)
When focus changes by keyboard (focus left/right/up/down, workspace switch, launcher opening an app, window close moving focus, cycling), warp the pointer to the newly focused window.
- Hyprland reference: `cursor:no_warps = false` / `misc:cursor_warp`-style behaviour. Warp to the window centre by default; option for "last position inside that window" (remember per window).
- Do NOT warp when focus changed because the mouse moved or clicked (no feedback loop with focus-follows-mouse), during drags/resizes, while a mouse button is held, or when the target is on a display the user can't see.
- Use CGWarpMouseCursorPosition + CGAssociateMouseAndMouseCursorPosition correctly so there is no stuck/lag frame; suppress the synthetic move so it doesn't count as hover focus.
- Config: `cursorFollowsFocus = true` (default on), `cursorWarpMode = "center" | "last"`; Settings toggle; keybind-free.

## 9b: Focus follows mouse, done properly
`focusFollowsMouse` and `focusFollowsMouseDelayMs` already exist in config.default.toml. Check it actually works across every case and fix what doesn't:
- Hovering a tiled or floating window focuses it after the delay, without raising floating windows above others unless `raiseOnHover = true` (new option, default false, like Hyprland follow_mouse = 1).
- Never steal focus from: open menus, popovers, Spotlight/launcher, SkyRose drawers, the system menu bar, a drag in progress, a sheet/dialog, password fields, or fullscreen apps in another Space.
- Works with the cursor theme (8a) and corner calibration (8e) in place; no flicker on the bar.
- Settings: toggle + delay slider (0–500 ms) on the same page as 9a, with a short live demo using two TestWindows-style preview tiles.
- Tests: focus-state machine unit tests for both features (hover → focus, keyboard focus → warp, no loop, suppression cases).

## 9c: Make setup as easy as possible
Goal: a normal user goes from download to a working SkyRose with the fewest clicks and zero Terminal knowledge. Audit the whole first-run path and cut friction. At least:
- Onboarding becomes one guided flow with a progress bar: mode → permissions → recommended tweaks (Dock removal, menu bar, Bibata, wallpapers, corners) with one "Use recommended" button → kitty/fonts (skippable) → done. Every step can be skipped and revisited from Settings.
- Permissions: detect each one live (Accessibility, Screen Recording, Input Monitoring if used), open the exact System Settings pane with the right deep link, show an animated "drag SkyRose here / flip this switch" hint, and move on automatically the moment it's granted. No "restart the app" step if it can be avoided; if macOS really needs a relaunch, do it for the user.
- A `skyrose doctor --fix` that repairs everything it safely can (stale permissions after an update, missing config, wrong cursor, Dock back) and explains the rest in plain words.
- Error messages in plain English with a "Fix it" button where possible.
- The installer window: one big Install button; advanced options folded away.

## 9d: SIP-off (Enhanced mode) made simpler, but still honest
SIP can only be turned off by the user in Recovery mode, so SkyRose can't do it for them. Make the walkthrough painless anyway:
- A step-by-step Enhanced mode assistant in Settings: detects Apple Silicon model + macOS version, shows ONLY the steps for that Mac, with big readable screenshots/illustrations of Recovery, a copy button for the exact `csrutil` command(s) the docs require, and a printable/QR-code version so the user can follow along on their phone while the Mac is in Recovery.
- Before it starts: the red risk box (lowers security, may break on macOS updates, often not allowed on school/work Macs; Gabby's own Mac is a school laptop, so SkyRose must work fully without it), plus how to turn SIP back on.
- After reboot: SkyRose detects the new SIP state automatically, installs/loads the scripting addition (`skyrose sa` path, the user runs any needed sudo themselves, shown as one copyable command), and confirms with a green check. Same assistant for turning it back on and cleaning up.
- Never automate Recovery, NVRAM, or boot args. Never bundle anything that disables SIP.

## 9e: Kill the end-of-animation flash
Every animated SkyRose surface flashes for about one frame after its animation finishes: the Dock/left-bar popouts, the volume/brightness OSD, the launcher/app drawer (it flashes once after closing), the dropdown menus, and anything else animated. Find the root cause instead of patching each surface:
- Likely suspects: the window/layer being ordered out or resized one frame after its alpha/scale reaches the end value, a final non-animated layout pass, CATransaction implicit animations snapping back, the model value not set to the presentation value at completion, or the window's backing being re-shown at full opacity before orderOut.
- Fix it once in the shared animation/overlay layer (CaelestiaOverlay / ShellController) so every surface benefits. Order out / hide in the same frame the animation completes, with the final presentation state held (fillMode / model value set before the animation).
- Verify by recording at 60 fps or more (screen recording of TestWindows plus the shell only) and stepping through frames: zero frames of flash on open AND close for every surface listed. Add a regression test where possible (e.g. assert the hide happens in the completion block and the window is never visible with alpha 1 after close).

## 9f: Option to fully turn off Apple's menu bar
- Settings › Appearance: "Apple menu bar: Shown / Auto-hide / Off". Off means it never appears, even when you hover at the top edge (fixes the known "hovering the top edge reveals the auto-hidden menu bar" limit as far as macOS allows).
- Research the most reliable way that works with SIP ON first (e.g. `_HIHideMenuBar` / `AppleMenuBarVisibleInFullscreen` defaults, the per-app presentation options SkyRose can set for apps it manages, the reserved top inset). If a truly-off bar is only possible with the scripting addition (SIP off), say so in the UI and offer the best SIP-on fallback.
- Journal the original values; uninstall and the toggle restore them. Make sure system menus are still reachable some way (SkyRose bar, or a keybind that briefly shows the menu bar) so apps stay usable.

## 9g: Clipboard history on Super+V (Caelestia-style)
- Super+V (Cmd+V must stay paste; "Super" here means SkyRose's main modifier as in keymap.default.toml; pick a combo that doesn't clash and document it) opens a clipboard history picker styled exactly like Caelestia's `caelestia clipboard` (look at docs/caelestia-reference and the Arch screenshots: same drawer shape, fuzzy search field, list rows, colours from the current scheme, the same open/close animation, no flash; see 9e).
- Records text, rich text (as plain preview), file references and IMAGES. Images render as thumbnails in the list with a larger preview on the selected row. Enter pastes into the previously focused app, Shift+Enter copies only, and Super+Alt+V or Delete removes an entry (match Arch: Super+Alt+V deletes).
- Storage in ~/Library/Application Support/SkyRose/clipboard (size cap plus max entries, configurable), never synced anywhere. Skip anything marked concealed/transient (org.nspasteboard.ConcealedType / TransientType, the password manager types) so passwords never get stored. Add a "Clear history" button and a pause toggle.
- Uninstall removes the history. Tests: store/evict, concealed-type skip, image thumbnailing, and the paste-back focus path.

## 9h: Bongo cat + live lyrics in the media drawer (Caelestia parity)
Check how Caelestia does both (docs/caelestia-reference, the Caelestia shell source on GitHub: the dashboard/media module and its beat-reactive visualiser) and match the look and motion 1:1, using the current colour scheme.
- Bongo cat: the little cat in the dashboard/dropdown that slaps its bongos to the beat of whatever's playing. Drive it from real audio (system output via ScreenCaptureKit audio capture or the existing audio visualiser source if SkyRose has one, then beat/onset detection), not a timer. It idles when nothing plays and pauses entirely when the drawer is closed (no CPU when hidden). Use original or properly licensed sprite art (check the license of whatever Caelestia ships; credit it, or draw our own in the same style).
- Lyrics in the media tab: synced, line-by-line lyrics for the current track from any player macOS reports in Now Playing (Spotify, YouTube Music in a browser, Apple Music, etc.). Use a public, free, no-key source like LRCLIB (lrclib.net) for synced LRC, matching on artist, title, album and duration, with a plain-lyrics fallback and a clean "No lyrics found" state. The current line is highlighted and auto-scrolls with a Caelestia-style smooth scroll, and you can click a line to seek if the player supports it. Cache lyrics locally (Application Support/SkyRose/lyrics) and never send anything but the track metadata.
- Settings toggles for both. Tests: LRC parsing and timing, track matching, cache, beat detector on a fixture audio clip.

## 9i: Rock-solid tiling, always (top priority of this phase; do it FIRST)
The WM is janky and sometimes stops tiling. Rule: every normal window is ALWAYS tiled, except windows the USER set to floating and apps matched by a float rule (rules.default.toml / user rules, dialogs, sheets, panels, utility windows). Nothing else may float or escape the layout.
- Audit every path where a window can end up untiled: new windows that appear before AX is ready, windows created hidden or minimized then shown, app relaunch/restart, Spaces/display changes, sleep/wake, fullscreen exit, tab merges, windows that move themselves, apps that ignore the first resize, AX errors or timeouts, the WM daemon restarting. Fix each at the root and add a periodic reconcile pass (cheap, event-driven first, timer fallback) that re-tiles anything that drifted, idempotently.
- Minimum sizes: if an app refuses to shrink (min size), shrink the OTHER tiles to make room, re-balancing the split ratios. If the workspace truly can't fit all minimum sizes, keep tiling anyway with the best fit (e.g. switch that workspace to a stacked/monocle-style group or the next split direction) rather than letting a window float or overlap. Never leave overlapping windows. Log what happened in `skyrose doctor`.
- Respect float state persistently: user-floated windows stay floating across restarts (keyed per app + window identity) until the user toggles them back.
- Stress test with TestWindows: spawn/close 50+ windows fast, windows with large min sizes, multi-display, workspace switching mid-spawn, sleep/wake simulation, daemon restart. Assert no window is ever untiled and nothing overlaps. Add these as automated tests where possible plus a scripted stress run, and report the results.

## 9j: Smooth live resize like Hyprland (no fade, blur, grey or stretch)
Right now resizing a tile fades/blurs/greys the window and stretches it, even for kitty. Fix it:
- Find what causes it (likely a snapshot/screenshot overlay or a scaled layer used as an animation proxy, or animating the frame via a transform). Remove the proxy approach for resizes. The real window content must stay sharp and live the whole time: no opacity change, no blur, no tint, no scaling or stretching of content.
- Animate the actual window frames with a smooth spring (match Hyprland's default bezier/spring and duration from docs/caelestia-reference / the hypr config), batched per frame with CVDisplayLink / CADisplayLink at the display's refresh rate (120 Hz on ProMotion). Coalesce AX setFrame calls so slow apps don't lag the others; if an app can't keep up, let it snap to the final frame rather than showing a stretched image.
- Same for mouse-drag resizes between tiles and keyboard resize binds: neighbours move in real time with the drag.
- Verify with 60/120 fps recordings of kitty plus TestWindows, frame by frame: zero frames that are blurred, faded, greyed, or stretched. Add regression tests for the animation scheduler.

## 9j2: Window borders that actually hug every window
Bugs Gabby saw: (1) some windows have a visible gap between the SkyRose border and the window's rounded corner, because the border uses one fixed radius, and different apps/window styles (macOS 26 toolbar windows, Electron apps like Grok Bot/Discord, kitty, sheets) have different radii. (2) The border looks fully visible on the top-left but fades out toward the right side.
- No fixed radius. Find each window's real corner radius per window, in this order: a private WindowServer/SkyLight query if one exists and works with SIP on (research it; don't guess symbols, verify), else measure it: capture the window alone without its shadow (ScreenCaptureKit, already permitted via Screen Recording), scan the corner alpha mask and fit the radius (sub-pixel, at the display's backing scale). Cache it per app bundle ID + window style/size class and re-measure when the window style changes (toolbar shown/hidden, fullscreen, tab bar).
- Draw the border on that exact rounded rect, aligned to pixel boundaries at the backing scale, so there's zero gap and zero overlap on all four corners. Non-rounded windows get square borders.
- Fix the fade: find why the right/bottom side is dimmer (likely the gradient/angle of an animated border, a mask/shadow clipping one side, the overlay being slightly offset/clipped by the window frame, or alpha premultiplication). The border must be evenly visible on all sides unless a gradient is configured on purpose, and then the gradient must not drop to invisible anywhere.
- Verify with zoomed screenshots of the four corners of: kitty, Finder, Safari, System Settings, an Electron app (Grok Bot or Discord), and TestWindows, on the built-in display and an external one if attached. Add unit tests for the radius fitter on fixture masks.

## 9k: Release v0.4.0 and push
Build, `/usr/bin/swift test` with 0 failures, sign with "Caelestia Local Signing", publish GitHub release v0.4.0 the same way as 0.3.0 (zip + install.sh + uninstall.sh + .sha256, new tag only). Make sure `skyrose update` from 0.3.0 to 0.4.0 works using a local test release first. Update CHANGELOG, docs (KEYBINDS.md, ENHANCED_MODE.md, a new FOCUS.md), and the website prompt's feature list if the site exists by then.
Push to GitHub (main plus the tag) only when EVERY part above is done, built, and tested, with `/usr/bin/swift test` at 0 failures and the stress and recording checks passing. No half-done features, TODO stubs, "works mostly", or skipped edge cases. If something genuinely can't be done on macOS, say exactly why and what you shipped instead.
Report: commits, test counts, stress-test and frame-check results, release URL, and what was NOT verified on the real Mac.
