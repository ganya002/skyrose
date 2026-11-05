# Uninstall

> **Status:** the uninstaller is NOT built yet (planned for a later phase). `scripts/uninstall.sh`,
> the Settings "Backup & uninstall" page and a working `skyrose uninstall` do not exist in this build;
> `skyrose uninstall` only prints the manual steps. What exists today is the groundwork: the
> restore manifest (`restore-manifest.json`, which records every system change SkyRose makes,
> including the Dock / menu bar auto-hide tweaks from onboarding) and the SIP reminder popup
> component (shown for at least 5 s, cannot be dismissed early) that the uninstaller will use.
> The text below describes the intended behaviour.
>
> **SIP reminder rule:** it is shown only when SkyRose's SIP-off (Enhanced) mode was actually used
> (the `sipOff-mode-used` flag file in `~/Library/Application Support/SkyRose`, also recorded in
> the restore manifest) **and** `csrutil status` does not report SIP fully enabled. Never
> otherwise: not for a corrupt manifest, not for a Mac whose SIP was lowered for something else.
> `skyrose uninstall` decides before removing anything and opens it with
> `SkyRose Settings --sip-reminder`.

Three equivalent routes; all run as your normal user, never `sudo`:

1. `skyrose uninstall`
2. `scripts/uninstall.sh` from the repo (works even if the app was already deleted: it reads the
   restore manifest directly)
3. SkyRose Settings → Backup & uninstall → **Uninstall SkyRose** (Settings app is
   not built yet)

What happens, in order, with a printed report at the end:

1. Stops the WM (it unparks every window first). If it is not running, the parked-windows
   journal is replayed through System Events so no window stays off-screen.
2. Puts the macOS cursors back if Appearance › Cursor was used (quitting the WM does it; without
   the WM, `skyrose cursor reset`). Session-only anyway: logging out also restores them.
3. Restores every `defaults` key we changed (menu bar auto-hide, Dock auto-hide/delay,
   "click wallpaper to show desktop"), writing back the exact original value or deleting the key
   if it did not exist — from `~/Library/Application Support/SkyRose/restore-manifest.json`.
4. Removes the Caps Lock → F18 `hidutil` mapping if preset B was used.
5. Removes the login item / launch agent (`com.skyrose.mac`).
6. Restores the previous wallpaper(s) if we changed them.
7. Removes the SkyRose kitty profile if it was set up (`skyrose kitty uninstall`: the one
   `include skyrose.conf` line, `skyrose.conf` and `skyrose-theme.conf`; a `kitty.conf` SkyRose
   created is deleted). A copy of the original `kitty.conf` is kept under
   `~/Library/Application Support/SkyRose/originals/` (journal kind `kittyConfig`).
8. Removes `~/Applications/SkyRose.app`, `~/Applications/SkyRose Settings.app`, `~/Applications/TestWindows.app` and the
   `~/.local/bin/skyrose` (and the deprecated `caelestia`) symlink (moved to the Trash, not deleted).
9. Asks whether to keep the fonts we installed (listed in the install manifest) and whether to
   keep `~/.config/skyrose` (moved to the Trash otherwise).
10. Optionally removes the "SkyRose Local Signing" (or older "Caelestia Local Signing") certificate (`scripts/sign-setup.sh --remove`).

After this the Mac looks and behaves like stock macOS. Permissions you granted in System
Settings remain listed there until you remove the entries (macOS keeps them per app); they are
inert once the app is gone.
