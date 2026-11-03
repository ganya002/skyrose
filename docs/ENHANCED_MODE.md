# Enhanced mode (optional, SIP partly off)

**You do not need this.** Standard mode (SIP fully on, public APIs only) tiles, switches
workspaces, draws borders, the bar and every panel. Enhanced mode only adds what macOS forbids
from outside the window server: real window opacity (0.94), scale/alpha animations of other
apps' windows, instant moves, always-on-top and focus-without-raise.

## What it changes on your Mac

Enhanced mode loads a scripting addition (`CaelestiaSA`) into `Dock.app`, the process that owns
the window-server connection yabai also uses. macOS only allows that when **System Integrity
Protection is partially disabled** and, on Apple Silicon, when the `arm64e_preview_abi` boot
argument is set.

Lowering SIP **reduces the security of the machine**: any process can then inject code into
the Dock. On a school-issued laptop, check the school's IT rules first; many forbid it.
macOS updates can also break the SA until it is rebuilt.

Caelestia for Mac **never** changes SIP, NVRAM or boot arguments itself. The steps below are
done by you, by hand, in Recovery. Everything is reversible.

## Enabling (Apple Silicon)

1. Shut down. Press and hold the power button until "Loading startup options" appears.
2. Choose **Options** → **Continue** → **Utilities** → **Terminal**.
3. Run:
   ```
   csrutil enable --without fs --without debug --without nvram
   ```
   Reboot.
4. In a normal Terminal:
   ```
   sudo nvram boot-args=-arm64e_preview_abi
   ```
   Reboot.
5. In **Caelestia Settings → Enhanced mode** press **Load CaelestiaSA**. Loading needs
   administrator rights **once per boot**; macOS shows its normal authorisation dialog.

### Optional: no password prompt per boot

If you prefer not to type the password at every boot, copy the template
`Resources/sudoers.caelestia-sa.template` by hand to `/etc/sudoers.d/caelestia-sa`
(`sudo visudo -f /etc/sudoers.d/caelestia-sa`). It allows exactly one binary
(the SA loader, by absolute path and SHA-256) and nothing else. The installer never writes
sudoers; the default is the authorisation dialog.

## Reverting

1. Recovery → Terminal → `csrutil enable` (full SIP). Reboot.
2. Normal Terminal → `sudo nvram -d boot-args`. Reboot.
3. Delete `/etc/sudoers.d/caelestia-sa` if you created it.

After this Caelestia falls back to Standard mode automatically; nothing else needs changing.

## How the WM decides which mode it is in

At launch the WM asks the Dock for `CaelestiaSA` through a handshake that returns the SA's
build hash. Only when that hash matches the daemon's own build is the SA used; otherwise a
notice says "SA version mismatch — rebuild" and Standard mode is used. Every feature has a
Standard-mode fallback (see the table in README.md and LIMITATIONS.md).

## Status

The SA itself is Phase 10 and is **not part of this build**; Settings shows the capability
table and these instructions, and the daemon's capability probe reports "Standard".
