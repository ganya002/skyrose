# SkyRose Phase 9.5 — fixes + big 1:1 Caelestia polish

Repo: ~/Projects/caelestia-mac (v0.4.0 at 83c833e). Do this phase BEFORE docs/PHASE-PROMPT-10-controls.md. Commit after each numbered part and keep docs/phase-progress.md updated, so a fresh session can resume if you hit your usage limit.

## References: use ALL of them
Look at every one before you design anything, and compare against them constantly:
- `docs/caelestia-reference/` in this repo: shell/, hover/, motion/, tiling/, part10/ (66 images), docs/caelestia-research.md (read section 0 first) and PHASE-PROMPT.md.
- `~/caelestia-ref/full-2026-11-05/` on this Mac (~990 files, 78 MB): the full capture from Gabby's real Arch Caelestia setup. Read its README.md (measured values, animation curves, file index) and CLAUDE-BRIEF.md first. 04-caelestia/ has every panel opened, hovered and closed. Each `*_frames/` folder has 10 frames plus contact.jpg and scene.txt with timestamps, so use those for timing. 03-animations/, 05-mouse/ (focus-follows-mouse notes), motion.txt, hypr/ and binds.txt are there too. Read it in place; don't copy it into the repo, it's too big for git.
- The Caelestia source: caelestia-dots/shell on GitHub (GPL-3.0, same as us). Read the QML for exact sizes, radii, colours and timings instead of guessing.

## Part 1 — the real Bongo Cat
The current cat is two grey paw blobs with no cat. Replace it with the real Bongo Cat from docs/caelestia-reference/part10/media-player.png: a white loaf cat with a black outline, pointy ears, a ·ω· face and pink paw beans, on a table edge, with motion ticks when it slaps.
- Take bongocat.gif from caelestia-dots/shell (find it through modules/dashboard/dash/Media.qml) and split it into frames. Drive the frames on detected beats: alternate the paws, stay idle when paused or nothing is playing. Don't just loop the gif.
- Put it in the media tab and the dropdown, sharp at Retina scale.
- Credit it in the README and on the About page: "Bongo Cat sprite from Caelestia (caelestia-dots/shell, GPL-3.0); original Bongo Cat by StrayRogue & DitzyFlama."

## Part 2 — fix hover-to-focus (9b), it's very buggy
Right now it focuses windows BEHIND the window under the pointer. Fix it so it behaves like Hyprland's follow_mouse=1 (see ~/caelestia-ref/full-2026-11-05/README.md "Input" and 05-mouse/):
- Focus only the TOPMOST window actually under the pointer. Use the real on-screen z-order (CGWindowListCopyWindowInfo, front to back, layer 0, on-screen only, skip SkyRose's own and transparent/zero-alpha windows) and hit-test against that, never an AX or tiling-order list.
- Never focus through SkyRose shell panels, the border overlay, menus, popovers, the Dock, Spotlight or other system UI. Pointer over those = no focus change.
- Only real pointer motion triggers it. Programmatic warps from 9a must not cause a hover-focus (no warp → hover → focus loop).
- Keep the delay. Cancel it if the pointer leaves the window before it fires, and re-check the topmost window right before focusing.
- Don't change focus while a mouse button is down (drags), while a keyboard modifier drag/resize runs, during a retile, or for a short while after a keyboard focus change.
- Focusing must not raise or reorder windows in a way that shuffles the stack (match mouse_refocus=1).
- Add tests for the hit-test logic with overlapping and floating windows. Then live-test with overlapping TestWindows and a floating one on top, record it, and check frame by frame that it never picks a window behind.

## Part 3 — lyrics look bad, redo them
Make synced lyrics look like they belong in Caelestia. First check whether the Caelestia source or reference has a lyrics view, and match it if it does. If not, design it in Caelestia's language from the media/dashboard references: same fonts, colour-scheme roles, spacing and radii. Show the current line large and bright and the neighbours dim and smaller, and scroll smoothly with a spring, centred on the current line. Fade the top and bottom edges. Show a clean "no lyrics" state. No clipping, no jumping, and keep it in sync while seeking. Record it with a song playing and compare to the references.

## Part 4 — big 1:1 Caelestia polish
Make the shell feel like Gabby's Arch Caelestia. That setup's motion is liquid, and that's the bar.
- **One metaball surface.** The screen border and every drawer (dashboard, launcher, sidebar, utilities, OSD, session, notifications, bar popouts) are drawn by one SDF smooth-min Metal shader in a single full-screen transparent overlay (fillet k = border.smoothing, default 20). Drawers grow out of the border with a concave fillet and merge with their neighbours. Separate NSWindows with corner radii are not acceptable.
- **Velocity jelly.** Each panel stretches along its direction of motion, capped at 35%. Use a semi-implicit underdamped spring with stiffness 200 and damping 16, start it above 5 px/s, and snap to rest below the thresholds in the notes. Apply the same transform to the content, and use the per-panel deformAmount values.
- **Timing.** Match the measured curves and durations in the README and the `*_frames` timestamps: drawers open in 230–520 ms and close faster (~130–170 ms), the shell scale is 0.8, and so on. Panels physically shove each other: the sidebar pushes the session and the OSD. Tabs morph height with overshoot and crossfade. Edge-hover reveals match the hover_*_frames clips.
- **Side-by-side check.** Go through every surface against its reference image: spacing, fonts, radii, colours, icons, hover states, transparency (base .75, layers .35).
- No shader runs while nothing moves (keep power use sane). Everything stays sharp at Retina scale.

## Out of scope
Window tiling and window animations get replaced by CatWM later, so don't touch them, except to fix something outright broken (a crash, a lost window).

## Rules
- No sudo, no installing anything, no system settings changes. Never close Gabby's apps.
- Test only with TestWindows and windows you opened yourself. Run `skyrose wm panic` if anything breaks, and when you're done.
- You may rebuild and restart SkyRose, record the screen, and inspect recordings frame by frame. Record before/after clips for every part.
- Never force-push. Commit each part separately in the repo's commit style. Don't push; Gabby reviews first.
- If something needs Gabby's hands (a permission prompt, a Spotify login), stop and say exactly what to click.

## Report
Per part: Done / Partial / Blocked, with commits and the recordings you checked, plus anything Gabby should test himself. If everything passes, propose v0.4.1 but don't release it.

## Part 5 — load the SIP-off helper automatically at boot
Right now `sudo …/SkyRose.app/Contents/Resources/sa/skyrose-sa-loader` has to be run by hand after every restart (and after `skyrose wm panic`) to remove the menu bar. Make it automatic:
- Ship an opt-in LaunchDaemon (`/Library/LaunchDaemons/com.skyrose.sa-loader.plist`, RunAtLoad, root) that runs the loader at boot and again when the WindowServer/Dock restarts (or retries until the Dock is up). Only run it when SIP-off mode is on in Settings; otherwise exit right away.
- SECURITY: a root daemon must never run a file Gabby's user can write. Install a root-owned copy of the loader (e.g. `/Library/Application Support/SkyRose/skyrose-sa-loader`, root:wheel 755) plus the plist (root:wheel 644), and point the plist at that copy, never at dist/ or ~/Projects. Updating SkyRose re-copies it through the same sudo step.
- Give Gabby ONE script to run himself with sudo (`sudo …/sa/install-sa-daemon.sh`) and a matching uninstall script. You never run sudo yourself. Add both to Settings › SIP-off mode as "Copy command" buttons, and make the main uninstaller remove the daemon too.
- `skyrose wm panic` unloads the helper for this session only; the daemon brings it back on the next boot. Add a `skyrose sa reload` command (or a Settings button that shows the sudo command) for reloading without a reboot.
- Document it in PERMISSIONS.md and the SIP-off page. Test the scripts' logic with a dry-run mode, and tell Gabby exactly what to run to test the real thing.
