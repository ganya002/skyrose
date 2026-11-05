# Enhanced mode (optional, SIP partly off)

**You do not need this.** Standard mode (SIP fully on, public APIs only) tiles, switches
workspaces, draws borders, the bar and every panel. Enhanced mode only adds what macOS forbids
from outside the window server: real window opacity (0.95), scale/alpha animations of other
apps' windows, instant moves, always-on-top and focus-without-raise.

## What it changes on your Mac

Enhanced mode loads a scripting addition (`CaelestiaSA`) into `Dock.app`, the process that owns
the window-server connection yabai also uses. macOS only allows that when **System Integrity
Protection is partially disabled** and, on Apple Silicon, when the `arm64e_preview_abi` boot
argument is set.

Lowering SIP **reduces the security of the machine**: any process can then inject code into
the Dock. On a school-issued laptop, check the school's IT rules first; many forbid it.
macOS updates can also break the SA until it is rebuilt.

SkyRose **never** changes SIP, NVRAM or boot arguments itself. The steps below are
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
5. In **SkyRose Settings → Enhanced mode** press **Load CaelestiaSA**. Loading needs
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

After this SkyRose falls back to Standard mode automatically; nothing else needs changing.

## How the WM decides which mode it is in

At launch the WM asks the Dock for `CaelestiaSA` through a handshake that returns the SA's
build hash. Only when that hash matches the daemon's own build is the SA used; otherwise a
notice says "SA version mismatch — rebuild" and Standard mode is used. Every feature has a
Standard-mode fallback (see the table in README.md and LIMITATIONS.md).

## Window animation hook

Window animations go through one protocol, `WindowAnimator`
(`Sources/CaelestiaOverlay/WindowAnimation/WindowAnimator.swift`), set as
`WindowManager.windowAnimator`. Per layout pass the WM calls `animate(request, commit:)` *before*
writing any frame. The request lists each change (`.move` from/to, `.open`, `.close`, `.leave`
to a hidden workspace), every visible window after the pass (back to front, active flag, border
on/off) and the display frames. The animator must call `commit` exactly once; `commit` performs
every AX write of the pass. Other hooks: `isCovering(id)` (borders snap while true),
`prepareClose` (the WM's own close action), `beginDrag` / `updateDrag(pointer:dropTarget:)` /
`endDrag` for live drags, `windowsChanged(visible:)`, and `cancel()` (panic, quit, game mode:
must finish at once and leave real windows untouched).

Standard mode uses `SnapshotWindowAnimator` (overlay cover with ScreenCaptureKit stills);
`InstantWindowAnimator` commits at once. An Enhanced-mode animator would: commit at once (real
windows get their final frames), then ask the SA in the Dock to animate each window's transform
and alpha from the old to the new frame with the same `AnimationTable` channels (`windowsMove`,
`windowsIn`, `windowsOut`), return true from `isCovering` while a transform is applied, and drag
the real window's transform in `updateDrag`. No cover, no stills, live content. It is **not
implemented** in this build.

## Status

The SA itself is Phase 10 and is **not part of this build**; Settings shows the capability
table and these instructions, and the daemon's capability probe reports "Standard".
