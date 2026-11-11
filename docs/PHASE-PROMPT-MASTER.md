# SkyRose MASTER PROMPT: finish 9.5, then Part 10, then the site

Repo: ~/Projects/caelestia-mac. This file is the single source of truth and overrides older prompts where they conflict. Work top to bottom. Commit after every numbered item, keep docs/phase-progress.md updated so a fresh session (or a different agent) can resume exactly where you stopped if you hit a usage limit.

## State when this was written (Nov 11, 2026)
- `main` is at d817223 (Phase 9 + 9f menu-bar removal), 14 commits ahead of origin, NOT pushed. The last release is v0.4.0.
- Branch `phase-9.5` has bdbc13b (bongo), f54cc2c (hover focus), f9c838d (lyrics), 72ef28b (polish), 3fdc2e6 (boot daemon). The full test suite passes there.
- Your own 9.5 report said: Part 2 is done. Parts 1, 3 and 4 have gaps (beat-driving and lyrics scroll/seek untested with a real song, side-by-side vs references unfinished, no before clips). Part 5 passed its dry-runs, but the real sudo install has never run.
- Untracked files: docs/PHASE-PROMPT-9.5-fixes-polish.md, docs/PHASE-PROMPT-10-controls.md, docs/caelestia-reference/part10/ and this file. Commit them first.

## References: use ALL of them, every phase
- `docs/caelestia-reference/` (70 files: shell/, hover/, motion/, tiling/, docs/caelestia-research.md (read section 0 first), PHASE-PROMPT.md, README.txt). `part10/` has exactly 3 images: osd-volume-brightness.png, media-player.png, wifi-popout.png. (The old prompt said 66; that was wrong.)
- `~/caelestia-ref/full-2026-11-05/` (~1129 files, 78 MB): Gabby's real Arch Caelestia capture. Read README.md and CLAUDE-BRIEF.md first. Use 04-caelestia/ `*_frames/` (10 frames + contact.jpg + scene.txt timestamps), 03-animations/, 05-mouse/, motion.txt, hypr/ and binds.txt. Read it in place and never copy it into git. It now also has the 29 original screen recordings (.mp4) for every shell panel in 04-caelestia/ and for 05-mouse/focus_follows_mouse. Use them for exact timing and easing: step through them frame by frame (ffmpeg is NOT to be installed; use AVFoundation/AVAssetImageGenerator or QuickTime), not only the 10 sampled frames. The tiling/window-animation clips were left out on purpose (WM is out of scope).
- The Caelestia source: caelestia-dots/shell on GitHub (QML, GPL-3.0 like us). Take exact sizes, radii, colours and timings from it instead of guessing.
- Before you call any visual "done", put a SkyRose screenshot next to its reference and write down what still differs.

## Hard rules (all phases)
- No sudo by you, ever. Gabby runs sudo himself; give him the exact command and wait.
- No installing packages, no system-settings changes, no disk/EFI/bootloader/LUKS/NVRAM/SIP changes, no curl|sh.
- Never close Gabby's apps. Test only with TestWindows and windows you opened yourself. Before EVERY window command, check that the target really is your TestWindow. (In 9.5 a float/move hit Gabby's kitty because the workspace had switched; that must not happen again.)
- `skyrose wm panic` if anything breaks, and when you finish a phase. After the panic, start SkyRose again (`open dist/SkyRose.app`) so Gabby isn't left without it, and tell him the helper needs reloading.
- You may rebuild and restart SkyRose, record the screen and inspect recordings frame by frame. Record before AND after clips for visual work.
- **DO NOT TOUCH THE WINDOW MANAGER.** Window tiling, layouts, window move/resize and window animations are being replaced by Gabby's own modded build of his friend's CatWM (credit the friend when it lands). Don't refactor, retune or "improve" any of it. The only exception is a crash or a lost window: fix the minimum and say so. Keep the shell (bar, drawers, dashboard, OSD, launcher, sidebar, notifications, settings) cleanly separated from the WM code, behind a clear interface, so the WM can be swapped without touching the shell. Hover-to-focus is focus logic, not tiling, so it's in scope, but keep it in its own module.
- Never store secrets. Don't log passwords. Never force-push, never move an existing tag.
- Nothing half-done: no stubs, no display-only controls. If macOS truly blocks something, say why and what you shipped instead.
- If something needs Gabby's hands (a password prompt, Spotify playing, a permission dialog), stop and tell him exactly what to do.

## Git: push after EVERY phase (new rule, replaces "don't push")
At the end of each phase (A, B, C below), once the build is green, the tests pass with 0 failures and the live checks are done:
1. Run a secret scan on the diff being pushed (no tokens, keys, .env, passwords, private screenshots with personal content).
2. Merge the phase branch into `main` with a normal merge (no rebase of pushed history, no force-push).
3. `git push origin main`, plus the release tag if that phase releases one.
4. Report the pushed commit hash.
If a phase fails its checks, push the branch instead (`git push origin phase-…`), not main, and say why.

---

## PHASE A: finish 9.5 (branch phase-9.5), release v0.4.1

### A1: Close the gaps from your own 9.5 report
- Bongo Cat: verify the beat driving with a real song. Gabby will start Spotify when you ask him. The paws should alternate on beats and the cat should go idle when paused. Make sure it's sharp at Retina scale. Credits stay in the README and the About page.
- Lyrics: record a real song. Check that it scrolls centred on the current line, that clicking a line seeks, that it stays in sync while seeking, and the no-lyrics state. Compare to Caelestia's LyricList.
- Big 1:1 Caelestia polish (the visual overhaul; this is the big one, don't skim it). Go through EVERY surface against its reference: bar, dashboard (all tabs), launcher, sidebar, utilities, OSD, session, notifications, bar popouts, settings. Check spacing, fonts, radii, colours, icons, hover states, transparency (base .75, layers .35), the one metaball SDF surface (smoothing 20), velocity jelly (35% cap, stiffness 200, damping 16, per-panel deformAmount), and drawer timings (open 230–520 ms, close ~130–170 ms, shell scale 0.8, matched to the `*_frames` timestamps). Also check that panels shove each other and tabs morph with overshoot, and that the edge-hover reveals match hover_*_frames. Write a table in docs/parity-progress.md (surface, reference file, status, remaining diffs) and fix until nothing major is left. Record before/after clips.
- Boot daemon (Part 5): view the Settings card and check the dry-run again. Gabby will run the real sudo install and reboot test, so tell him the exact commands and then verify `skyrose sa status` with him.

### A2: Zero-skill, beautiful way to load the SIP-off helper (no Terminal)
- A Caelestia-styled card that animates in (spring slide + fade, matching our drawer timings) whenever sipOff.enabled is true but the helper isn't loaded: after launch, after `skyrose wm panic`, and from Settings. It has a big friendly title ("Finish hiding the menu bar"), one plain-English line, one primary "Enable" button and a quiet "Not now".
- "Enable" triggers the standard macOS admin password prompt (AuthorizationServices or `do shell script … with administrator privileges`). Never build our own password field, and never store, log or cache the password.
- Only run the exact root-owned or bundled loader path, quoted and validated. Never run anything user-writable as root (same rule as Part 5).
- The card animates through its states: waiting for the password, then loading (spinner), then success (checkmark, the bar slides away, the card dismisses itself), or failure with a human-readable reason and Retry. Cancelling the password prompt closes things quietly.
- Add a fallback link, "Do it in Terminal instead", that opens Terminal with the command prefilled plus a big Copy button.
- In the same card, offer the boot daemon as an opt-in, off by default: "Do this automatically every restart", with a one-line note that it runs as root at boot.
- Write tests for the state machine. Record the whole flow with a real password prompt; Gabby types the password himself, so pause and tell him when.

### A3: Fix the Teams/Electron flicker (hover focus)
With OneNote frontmost and Microsoft Teams open behind it, moving the mouse inside OneNote makes Teams flicker in front for a few ms, several times. Hover-to-focus must never pick or raise a window that's occluded at the cursor point.
- Reproduce it with two TestWindows that fully overlap, plus a real Electron app only if one is already open. Don't open or close Gabby's apps.
- Log every focus/raise decision with the window under the cursor, the CGWindowList z-order and the reason.
- Suspects: a stale z-order cache; Teams/Electron's invisible or helper windows (layer != 0, alpha 0, tiny or offscreen bounds) counted as hit targets; the focus re-check racing; OneNote's child windows breaking the hit-test.
- Fix the root cause and add a regression test. Record 30 s of mouse movement over the front window and check frame by frame that there's zero flicker.

### A4: Easy way to restart SkyRose
Today a restart needs `skyrose wm panic` plus `open dist/SkyRose.app`, and `shell restart` only restarts the shell UI. Add:
- `skyrose restart`: cleanly stops and relaunches the whole app from wherever it's installed (~/Applications or dist), keeps state and reloads the helper if the daemon/sa is set up. Add `--help` text and an entry in docs.
- A "Restart SkyRose" button in Settings, an entry in the session menu, and a launcher action (">restart").
- A default keybind if one is free (check `skyrose keys check`; suggest Super+Ctrl+Shift+R or similar, and don't steal an existing bind). Document it in KEYBINDS.md.
- If SkyRose has crashed or isn't running, `skyrose restart` just starts it.
- Make sure only ONE SkyRose runs. (On Nov 11 an old copy at /Users/testuser/Applications/SkyRose.app was running instead of dist; probably an installer-test leftover. Find out why it was launched and stop that from happening, e.g. a login item or LaunchAgent pointing at a test HOME.)

### A5: Release v0.4.1
Build, `/usr/bin/swift test` with 0 failures, run the live checks, update CHANGELOG and the docs, then merge, push (see Git rules) and publish release v0.4.1 like the previous ones. Check `skyrose update` from 0.4.0.

---

## PHASE B: Part 10 controls, release v0.5.0
Do everything in `docs/PHASE-PROMPT-10-controls.md` (10a OSD pill, 10b media player, 10c Wi-Fi, 10d Bluetooth, 10e sidebar replaces the menu-bar extras, 10f release v0.5.0), with these overrides:
- The bongo cat and lyrics from Phase A are reused in the media player. Don't rebuild them.
- Push main + the v0.5.0 tag at the end per the Git rules.
- The WM rule above still applies.
- Start this phase in a fresh session if the context is getting full; phase-progress.md must be enough to resume.

---

## PHASE C: the SkyRose site
Do everything in `~/Projects/archify-site/PHASE-PROMPT.md` (including its Nov 9 addendum), with these overrides:
- `version` = the latest real GitHub Release (expected 0.5.0). Read the release, don't guess.
- Document the new things too: the zero-skill helper card (A2), the boot daemon (opt-in, root at boot, how to uninstall), `skyrose restart` (A4), and the Part 10 controls.
- Note that window management will move to CatWM. Don't advertise SkyRose's current tiling as a long-term feature.
- Still never use `docs/caelestia-reference/` images on the site (private Arch content).
- Push after the phase per the Git rules (the site goes to its own public repo, as that prompt says).

---

## Report (after each phase, before starting the next)
For each item: Done / Partial / Blocked, commits, the pushed hash, test counts, the recordings you checked (paths), side-by-side notes, what Gabby must do himself (exact commands), and what was NOT verified. Then continue with the next phase unless something needs Gabby.
