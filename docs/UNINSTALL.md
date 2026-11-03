# Uninstall

Three equivalent routes; all run as your normal user, never `sudo`:

1. `caelestia uninstall`
2. `scripts/uninstall.sh` from the repo (works even if the app was already deleted: it reads the
   backup journal directly)
3. Caelestia Settings → Backup & uninstall → **Uninstall Caelestia for Mac** (Settings app is
   Phase 8; not in this build)

What happens, in order, with a printed report at the end:

1. Stops the WM (it unparks every window first). If it is not running, the parked-windows
   journal is replayed through System Events so no window stays off-screen.
2. Restores every `defaults` key we changed (menu bar auto-hide, Dock auto-hide/delay,
   "click wallpaper to show desktop"), writing back the exact original value or deleting the key
   if it did not exist — from `~/Library/Application Support/CaelestiaMac/backup.json`.
3. Removes the Caps Lock → F18 `hidutil` mapping if preset B was used.
4. Removes the login item / launch agent (`com.caelestia.mac.wm`).
5. Restores the previous wallpaper(s) if we changed them.
6. Restores your `kitty.conf` from the backup made by the kitty step, if any.
7. Removes `~/Applications/CaelestiaWM.app`, `~/Applications/TestWindows.app` and the
   `~/.local/bin/caelestia` symlink (moved to the Trash, not deleted).
8. Asks whether to keep the fonts we installed (listed in the install manifest) and whether to
   keep `~/.config/caelestia-mac` (moved to the Trash otherwise).
9. Optionally removes the "Caelestia Local Signing" certificate (`scripts/sign-setup.sh --remove`).

After this the Mac looks and behaves like stock macOS. Permissions you granted in System
Settings remain listed there until you remove the entries (macOS keeps them per app); they are
inert once the app is gone.
