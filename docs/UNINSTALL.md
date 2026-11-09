# Uninstall

SkyRose writes down every macOS setting it changes before it changes it
(`~/Library/Application Support/SkyRose/restore-manifest.json`), so the uninstaller can put back
exactly what you had. Everything runs as your normal user: no `sudo`, no password prompt.

## Three ways, one engine

All three run the same script, `uninstall.sh`, which ships inside the app at
`SkyRose.app/Contents/Resources/scripts/uninstall.sh` (and in the repository as
`scripts/uninstall.sh`, which works even after the apps are gone because it reads the manifest
itself).

1. **SkyRose Settings → Backup & uninstall → Uninstall…** confirms on the page, then opens the
   uninstaller window: *Confirm → Restore settings → Remove profile bits → Trash the apps →
   Report*, with an overall 0–100 % bar driven by the script's own progress lines. **Preview**
   runs the same window with `--dry-run` (nothing changes). From Terminal:
   `open -a "SkyRose Settings" --args --uninstaller [--dry-run]`.
2. **`skyrose uninstall`** in Terminal. It shows the plan and asks before it starts.
   `skyrose uninstall --dry-run` only prints what it would do.
3. **`sh uninstall.sh`** from the release zip or the repository.

Options (the same for 2 and 3, and the toggles on the Confirm screen):

| Option | Effect |
| --- | --- |
| `--dry-run` | Print every step and command, change nothing |
| `--yes` | No questions: keeps your config, your fonts and the certificate |
| `--remove-config` | Also move `~/.config/skyrose` to the Trash |
| `--remove-fonts` | Also remove the fonts SkyRose copied into `~/Library/Fonts` |
| `--remove-cert` | Also delete the local code-signing certificate |
| `--no-color` | Plain output |
| `--progress` | Machine-readable `::stage` / `::done` / `::skip` / `::left` / `::fail` / `::sip` lines (the window uses it). After `::sip` it waits for a line `ack` on stdin before anything is trashed |

Running it twice is harmless: the second run finds nothing left and says so.

## What happens, in order

1. **Windows.** Stops the WM, which brings every window back first. If the WM is still running after
   that, the uninstaller stops: nothing else is changed, and you run it again once the WM has quit.
   If the WM is not running, the parked-windows journal is replayed through System Events so no
   window stays off-screen.
2. **Cursors.** Puts the macOS cursors back if Appearance › Cursor was used (`skyrose cursor
   reset`). They are session-only anyway: logging out also restores them.
3. **macOS settings.** Every manifest entry, newest first, goes back to its original value, or the
   key is deleted if it did not exist before. That covers every recorded type: bools, numbers,
   strings, dates, data, arrays and dictionaries, plus a `symbolichotkeys` entry (one shortcut
   number inside `AppleSymbolicHotKeys`, leaving the others alone — this is how a screenshot
   shortcut SkyRose took over is put back). The `hidutil` key remap (Caps Lock → F18, preset B)
   is put back too. Each wallpaper is restored only on the display id that was recorded, and only
   while that display still shows the picture SkyRose set last; another display showing the same
   file keeps its own original. Then the Dock is restarted. If any of these writes fail, Application
   Support is kept (the manifest is still there) and the script exits non-zero.
4. **Lid-closed sleep.** Only if SkyRose turned it off (the `sleep-disabled-by-skyrose` marker):
   `sudo -n pmset disablesleep 0` if that works without a password, otherwise the report tells you
   to run `sudo pmset disablesleep 0` yourself. `/etc/sudoers.d/skyrose` is mentioned only if it
   exists; Clamshell Toggle's `/etc/sudoers.d/clamshell` is never touched.
5. **Login item.** `com.skyrose.mac` is unloaded and its launch agent goes to the Trash.
6. **Profile bits.** The SkyRose kitty profile is removed (`skyrose kitty uninstall`: the one
   `include skyrose.conf` line and SkyRose's own files; your `kitty.conf` is otherwise untouched).
   Fonts and `~/.config/skyrose` are kept unless you asked for them to go.
7. **SIP reminder.** Only if SkyRose's SIP-off mode was used (`sipOff-mode-used`, also in the
   manifest) **and** `csrutil status` does not say SIP is fully on. It is decided before anything
   is removed. The window shows the guarded reminder (on screen for at least 5 s) and the engine
   waits until you dismiss it before the apps or SkyRose's data go to the Trash. Terminal opens
   it with `SkyRose Settings --sip-reminder` and waits until that window quits (it quits when you
   dismiss the reminder). If the reminder cannot be shown, or is not acknowledged, the apps and
   Application Support stay and the script exits non-zero. The report lists the steps.
8. **Apps.** `~/Applications/SkyRose.app`, `SkyRose Settings.app` and the old `CaelestiaWM.app` go
   to the Trash. `TestWindows.app` goes only if SkyRose's installer put it there (it is listed in
   `install-record.txt`). The `~/.local/bin/skyrose` and `caelestia` links go only if they point
   into SkyRose. The "SkyRose Local Signing" / "Caelestia Local Signing" certificate is kept by
   default.
9. **SkyRose's own data.** `~/Library/Logs/SkyRose` and `~/Library/Caches/com.skyrose.mac` go to
   the Trash. `~/Library/Application Support/SkyRose` goes too, unless a restore failed: then it
   stays, so the manifest is not thrown away while a setting is still unrestored, and the script
   exits non-zero.

Everything is moved to the Trash, never deleted, so you can take it back until you empty it.
The report at the end lists what was done, what was not needed, and anything left for you.

## Backups

Settings → Backup & uninstall also saves a copy of the restore list and a `.zip` of
`~/.config/skyrose` wherever you choose.

## Afterwards

The Mac looks and behaves like stock macOS. Permissions you granted stay listed in System
Settings › Privacy & Security until you remove them (macOS keeps them per app); they do nothing
once the app is gone.
