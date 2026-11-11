# Troubleshooting

Run `skyrose doctor` first: it prints macOS version, permissions, SIP status (read-only),
config/keymap parse results, keybind conflicts and whether the WM answers on its socket.

## "Hotkeys stopped working"

1. **Secure Input is on in another app.** The OSD says "Hotkeys paused: <app> has Secure
   Keyboard Entry". Terminal → *Secure Keyboard Entry* in its menu turns it on; password
   fields in browsers hold it only while focused; some password managers keep it. Switch away
   from / close that app. `skyrose doctor` shows the owning app.
2. **Input Monitoring was revoked** (System Settings → Privacy & Security → Input Monitoring).
   The event tap cannot be created without it.
3. **Permissions lost after a rebuild.** Ad-hoc signed builds are a new app every time. Run
   `scripts/sign-setup.sh` once, then `scripts/build.sh`; remove the stale SkyRose WM entries
   in Accessibility / Input Monitoring and add the new one.
4. **The event tap was disabled by the system** (it happens when the callback is slow). The
   watchdog re-enables it within 2 s; the log (`Console.app`, subsystem `com.skyrose.mac`,
   category `input`) shows `tap re-enabled`.
5. **A macOS shortcut wins.** `skyrose keys check` lists clashes (Mission Control ⌃↑,
   Spaces ⌃←/→, Spotlight ⌘Space …) with a fix for each.

## "Windows are gone / off-screen"

- Press the panic chord **⌃⌥⌘⇧Esc**: tiling stops and every window is brought back on screen.
- If the WM is not running: the parked-windows journal is replayed on the next launch of SkyRose.app (open it again), or
  restart your Mac (parked windows are only moved off-screen, never closed). The planned
  `scripts/uninstall.sh --windows-only` does not exist yet.
- The journal is `~/Library/Application Support/SkyRose/parked-windows.json`.

## Restarting SkyRose

`skyrose restart` quits SkyRose (every window is put back first), waits until it has exited, and
starts the same SkyRose.app the CLI belongs to (dist/ or ~/Applications). If SkyRose is not running
it just starts it. Also: Settings › About › Restart, the session menu's last button, or `>restart`
in the launcher. The SIP-off helper lives in the Dock, so it stays loaded across restarts.
`skyrose shell restart` only rebuilds the shell UI. If SkyRose does not quit within 20 s, run
`skyrose wm panic`, then `skyrose restart`.

SkyRose is always started by path, never by bundle id: Launch Services also lists copies in other
accounts (e.g. an installer test under /Users/testuser) and could start one of those instead.

## "The bar is missing"

- `bar.persistent = false` in your config (Gabby's Arch default): the bar slides in when the
  pointer touches the left edge. Set `persistent = true` for an always-visible bar.
- On a display that was just plugged in, the bar is created within 500 ms; if it is not,
  `skyrose shell restart`.

## "Black or empty panels"

Should never happen (release blocker R1). Please report with `skyrose doctor --json` output
and a screenshot; as a workaround `skyrose shell restart`.

## "Windows keep flashing / re-layout loops"

The WM converges in ≤ 3 layout passes and ignores its own move/resize echoes. If an app refuses
its tile size (minimum size larger than the slot), it is clipped to its minimum and centred in
the slot instead of fighting. If you see continuous movement, run with
`SKYROSE_DEBUG_LAYOUT=1` and send the log.

## "Option characters don't work"

Only the **left** Option key is Super. Type æ ø å « » @ £ $ { } [ ] | \ with the **right**
Option key. `skyrose keys check` lists every ⌥L+key chord and the character it hides.

## "kitty didn't pick up the theme"

The WM writes `~/.config/kitty/skyrose-theme.conf` and sends SIGUSR1 to running kitty
processes. Your `kitty.conf` must `include skyrose-theme.conf` (a guided kitty setup step is not
built yet; add the line by hand). Pre-rename installs used `caelestia-theme.conf`.

## Logs

`~/Library/Logs/SkyRose/` and the unified log: `log stream --predicate 'subsystem ==
"com.skyrose.mac"'`. Window titles are redacted unless `[logging] includeTitles = true`.
