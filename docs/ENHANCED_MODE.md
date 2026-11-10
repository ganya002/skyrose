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
done by you, by hand, in Recovery. Everything is reversible. Settings › SIP-off mode lists only
the steps for this Mac (Apple Silicon includes the boot argument; Intel does not), with a Copy
button on each command and a QR code of those commands. It does not open Recovery and it does
not run them. After a reboot the status on that page updates by itself.

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
5. Open **SkyRose Settings › SIP-off mode**, press **What changes with SIP off?** and read it to
   the end (**I understand the risks** unlocks the switch), then switch **SIP-off mode** on.
6. Load the scripting addition, once per boot, in Terminal (Settings shows this line with a
   Copy button; `skyrose sa load-command` prints it):
   ```
   sudo /path/to/SkyRose.app/Contents/Resources/sa/skyrose-sa-loader
   ```
   The loader takes no arguments: it only loads `SkyRoseSA.dylib` from its own folder, only
   into the Dock of the user who ran sudo. SkyRose notices within 5 s and switches over.

## Reverting

1. Recovery → Terminal → `csrutil enable` (full SIP). Reboot.
2. Normal Terminal → `sudo nvram -d boot-args`. Reboot.
3. Delete `/etc/sudoers.d/caelestia-sa` if you created it.

After this SkyRose falls back to Standard mode automatically; nothing else needs changing.

## How it works

- `Packaging/sa/loader.c` + `trampoline.s` (arm64e, run as root): `task_for_pid(Dock)`, a
  read-execute page with a 30-instruction trampoline and a read-write data page; the thread
  state is converted to the Dock's pointer-authentication keys (`thread_convert_thread_state`).
  The trampoline calls `pthread_create_from_mach_thread`; that pthread `dlopen`s the payload
  and calls `skyrose_sa_start`. Written for SkyRose from the Mach/dyld APIs; the approach is
  the one yabai made known (yabai is MIT-licensed; none of its code is copied).
- `Packaging/sa/payload.c` (`SkyRoseSA.dylib`, inside the Dock): a Unix socket
  `/tmp/skyrose-sa-<uid>.socket` (0600, peer uid checked) with a line protocol: `hello`,
  `alpha`, `shadow`, `level`, `visual` (window transform so a window is drawn in a given rect),
  `visual-reset`, `freeze`/`thaw` (screen updates, auto-thaw after 250 ms), `space`, `info`,
  `reset`, `stop`. All SkyLight symbols come from `dlsym`; `hello` lists what was found.
- Safety: every change is recorded with its original value and the connection that made it;
  when SkyRose disconnects (quit, crash) its changes are undone. `skyrose wm panic` sends
  `reset` + `stop` itself (works even if the WM hangs). The WM's quit sends `reset` too.
- `EnhancedMode` (WM): probes every 5 s while `sipOff.enabled`; uses the SA only when its
  `hello` matches this build's protocol version; any failed command drops back to the SIP-on
  paths silently. The first successful use writes the `sipOff-mode-used` flag, so the
  uninstaller's SIP reminder appears.
- `EnhancedWindowAnimator`: commits frames at once inside `freeze`/`thaw` with the first
  transform, then springs each real window from its old rect (open: 80 % + fade in, ζ 0.58;
  move: ζ 0.72; the WM's close action: shrink + fade 180 ms, then close). Instant workspaces:
  windows get alpha 0 just before being parked / unparked and their alpha back 60 ms later;
  the slide is skipped. Opacity: `wm.windowOpacity` on non-fullscreen windows. Pinned windows:
  floating window level. Menu bar (`hideMenuBar`, on by default): Apple's menu bar is gone, even
  at the top edge, while the helper answers. `menuBar.peek` (Super+Shift+B) shows it for 5 seconds.
  No macOS setting is written, and quitting SkyRose brings it back. `[sipOff]` switches each feature.

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

Built and tested in this build: `skyrose sa status | load-command | reset`, Settings › SIP-off
mode, the showcase. See docs/phase-progress.md for what was live-tested on this Mac.
