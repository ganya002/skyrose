# Troubleshooting

Run `caelestia doctor` first: it prints macOS version, permissions, SIP status (read-only),
config/keymap parse results, keybind conflicts and whether the WM answers on its socket.

## "Hotkeys stopped working"

1. **Secure Input is on in another app.** The OSD says "Hotkeys paused: <app> has Secure
   Keyboard Entry". Terminal → *Secure Keyboard Entry* in its menu turns it on; password
   fields in browsers hold it only while focused; some password managers keep it. Switch away
   from / close that app. `caelestia doctor` shows the owning app.
2. **Input Monitoring was revoked** (System Settings → Privacy & Security → Input Monitoring).
   The event tap cannot be created without it.
3. **Permissions lost after a rebuild.** Ad-hoc signed builds are a new app every time. Run
   `scripts/sign-setup.sh` once, then `scripts/build.sh`; remove the stale CaelestiaWM entries
   in Accessibility / Input Monitoring and add the new one.
4. **The event tap was disabled by the system** (it happens when the callback is slow). The
   watchdog re-enables it within 2 s; the log (`Console.app`, subsystem `com.caelestia.mac`,
   category `input`) shows `tap re-enabled`.
5. **A macOS shortcut wins.** `caelestia keys check` lists clashes (Mission Control ⌃↑,
   Spaces ⌃←/→, Spotlight ⌘Space …) with a fix for each.

## "Windows are gone / off-screen"

- Press the panic chord **⌃⌥⌘⇧Esc**: tiling stops and every window is brought back on screen.
- If the WM is not running: `caelestia` → `scripts/uninstall.sh --windows-only` replays the
  parked-windows journal through System Events.
- The journal is `~/Library/Application Support/CaelestiaMac/parked-windows.json`.

## "The bar is missing"

- `bar.persistent = false` in your config (Gabby's Arch default): the bar slides in when the
  pointer touches the left edge. Set `persistent = true` for an always-visible bar.
- On a display that was just plugged in, the bar is created within 500 ms; if it is not,
  `caelestia shell restart`.

## "Black or empty panels"

Should never happen (release blocker R1). Please report with `caelestia doctor --json` output
and a screenshot; as a workaround `caelestia shell restart`.

## "Windows keep flashing / re-layout loops"

The WM converges in ≤ 3 layout passes and ignores its own move/resize echoes. If an app refuses
its tile size (minimum size larger than the slot), it is clipped to its minimum and centred in
the slot instead of fighting. If you see continuous movement, run with
`CAELESTIA_DEBUG_LAYOUT=1` and send the log.

## "Option characters don't work"

Only the **left** Option key is Super. Type æ ø å « » @ £ $ { } [ ] | \ with the **right**
Option key. `caelestia keys check` lists every ⌥L+key chord and the character it hides.

## "kitty didn't pick up the theme"

The WM writes `~/.config/kitty/caelestia-theme.conf` and sends SIGUSR1 to running kitty
processes. Your `kitty.conf` must `include caelestia-theme.conf` (the kitty step of the wizard
adds it with a backup).

## Logs

`~/Library/Logs/CaelestiaMac/` and the unified log: `log stream --predicate 'subsystem ==
"com.caelestia.mac"'`. Window titles are redacted unless `[logging] includeTitles = true`.
