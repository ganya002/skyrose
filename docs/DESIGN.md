# Caelestia for Mac — design decisions

Every non-obvious decision, with its reason. The spec (`docs/SPEC.txt`) said "ask nothing;
decide and write it down", so this file is the record. Section numbers refer to the spec.

## D1. Repository location and the earlier AeroSpace staging

`~/caelestia-mac` already contained a Phase-1 attempt that *staged an AeroSpace configuration*
(no native WM). This spec asks for a native WM, so the new code lives in a fresh repo
(`~/Projects/caelestia-mac`, where the other projects live) and the earlier tree is left exactly
as it was. Its reference dumps (`hyprland-binds.json`, `caelestia-shell.json`, `scheme.json`,
`bordersrc`, `hyprland-options`) were copied into `Tests/fixtures/` and later superseded by
the full export in `Tests/fixtures/ref/` (section 14 attachments). Gabby's screenshots are kept
on disk for visual reference but are git-ignored (they contain her chat history).

## D2. Toolchain

`swift` on this Mac resolves to a swift.org toolchain (swiftly 6.1.2) that cannot compile
against the Xcode 27.2 SDK. All scripts therefore pin `$(xcode-select -p)/Toolchains/
XcodeDefault.xctoolchain/usr/bin` (Swift 6.4.2). Deployment target is macOS 14 as required;
the package builds with any Xcode ≥ 16.

## D3. One process for WM + shell (0.3, 9)

`CaelestiaWM.app` hosts the tiler **and** the shell panels. Reasons:

- one event tap, one set of AX observers, one TCC grant each for Accessibility / Input
  Monitoring / Screen Recording instead of two apps to approve;
- the bar and drawers need the live layout state (focused window, workspace occupancy) at
  display-refresh rate; an IPC hop per frame is avoidable overhead on a 16 GB laptop;
- startup to working tiling < 2 s is easier with one launch.

The downside the spec names (a shell crash takes tiling down) is mitigated by the crash
journal + launchd `KeepAlive` (D9) and by isolating every shell panel behind `do/catch` and
window-level error containment; a panel failure disables that panel, not the process. If the
shell ever needs to be split, it already talks to the WM only through `WMFacade`, the same
surface the IPC server uses.

## D4. SwiftPM first, XcodeGen second (9)

The build is `swift build` + `scripts/build.sh`, which assembles the `.app` bundles (Info.plist,
SwiftPM resource bundles, LaunchAgent plist) and signs them. `Packaging/project.yml` is provided
for XcodeGen when someone wants Xcode's debugger, but it is not needed to ship. One build path
to maintain.

## D5. Language modes

Pure modules (`CaelestiaCore`, `CaelestiaLayout`, `CaelestiaIPC`) build in Swift 6 language
mode with strict concurrency — they are value-typed and have no global mutable state.
AppKit/ApplicationServices modules build in Swift 5 mode with `StrictConcurrency` as an
upcoming feature, because the C callbacks of AXObserver / CGEventTap and many AppKit APIs are
not annotated well enough to be worth fighting in a first release.

## D6. Dependencies

- **TOMLKit 0.6.0** (MIT) for TOML parse/serialise. Vetted, widely used, pure Swift + toml++.
- No other third-party code. Material color utilities are re-implemented in Swift (P7) from
  the published algorithm; yabai/AeroSpace/JankyBorders are *inspirations* (MIT), not copied.

## D7. Keymap is the single source of truth (3.2)

`Sources/CaelestiaCore/Resources/keymap.default.toml` carries every one of the 153 Hyprland
binds with its original chord in `linux = …`; `BindsCoverageTests` fails if any
`(modmask, key)` pair of the live dump `Tests/fixtures/binds.json` is missing.
`NoHardcodedBindsTests` scans the sources and fails on any chord literal outside the keymap
module; the only allowed exception is the panic chord (10.10), marked with
`// caelestia:allow-hardcoded-chord`.

Chords are matched by **key code**, never by character (3.4 note on the Norwegian layout).
The cheat sheet shows the characters of the *current* layout through `UCKeyTranslate`.

Resize binds are **percent**: the original `fn.resize_active_window(-10, 0)` resizes by −10 %
of the window's current size (relative), not by 10 px. The keymap documents this and the WM
converts percent to points from the current placement.

## D8. Modifier mapping (3.1)

Preset A (default) maps SUPER→⌥L, ALT→⌘L. Sides are told apart with the device-dependent
`NX_DEVICE*KEYMASK` bits. Right Option and Right Command are never WM modifiers, so Norwegian
Option characters typed with ⌥R keep working. When an event carries a family flag but no side
bit (some remote-desktop/virtual keyboards) the side is treated as *left* (configurable) so
hotkeys still work there.

⌘Tab is not stolen by default (`takeOverCmdTab = false`); ALT+Tab from Linux lands on ⌥L+Tab.

## D9. Crash safety (4.4, 10.10)

Before a window is parked off-screen its original frame is appended to
`~/Library/Application Support/CaelestiaMac/parked-windows.json` (atomic write). On every
launch the journal is replayed *first*, before the tiler starts. The LaunchAgent plist
(`Packaging/com.caelestia.mac.wm.plist`, registered with `SMAppService.agent`) has
`KeepAlive.SuccessfulExit = false`, so a crash relaunches the WM and a clean quit does not.
`scripts/uninstall.sh` replays the same journal through System Events when the app is gone.
The panic chord ⌃⌥⌘⇧Esc is hard-matched in the event tap as well as present in the keymap.

## D10. Standard-mode window geometry (4.3)

Hyprland stores the window size *excluding* the border. We keep the same numbers: the AX frame
is the Hyprland `at`/`size`, and the border is an overlay window drawn 1 px outside it. The
golden dump (two windows on 5120×1440 with 10 px reserved per edge → (21,21,2533×1398) and
(2566,21,2533×1398)) is a unit test in `CaelestiaLayoutTests`, plus 1/3/4-window cases and the
MacBook Air / Pro sizes.

Node boxes partition the usable area; a leaf is inset by `gapsOut` on sides touching the usable
area edge and `gapsIn` elsewhere, then by `borderSize`. With exactly one tiled window (or one
maximized window) `gapsOutSingle` (20) replaces `gapsOut` — the two Hyprland workspace rules
`w[tv1]s[false]` / `f[1]s[false]`.

## D11. Coordinates (4.6)

One converter (`CoordinateConverter`) flips between AppKit (bottom-left, y up) and CG/AX
(top-left, y down) using only the primary display's height. Everything inside the WM is
CG/AX space; AppKit windows are converted at the edge. Unit-tested with displays left of,
right of, above and below the primary one.

## D12. Private API inventory (9, "each private API use is listed")

| Symbol | Where | Why | Fallback |
|---|---|---|---|
| `_AXUIElementGetWindow` | `CShims` (weak-linked) | map an AX window to its `CGWindowID` so overlays, CGWindowList reconciliation and the journal can address it; used by AeroSpace, yabai, Rectangle; needs no SIP change | if the symbol is missing the window is matched by PID + frame + title through `CGWindowListCopyWindowInfo` (slower, still works) |
| `kCGSSessionSecureInputPID` (IORegistry property read) | `SecureInput` | name the app holding Secure Event Input in the OSD | OSD says "another app" |
| SkyLight / CGS calls | `CaelestiaEnhanced` only, behind a runtime handshake with `CaelestiaSA` | Enhanced mode (opacity, scale, instant moves) | Standard mode behaviour |

Everything else is public API.

## D13. Lock screen (5.8)

`⌥L+L` posts ⌃⌘Q (the public system shortcut) through a CGEvent. The real macOS lock screen
with Touch ID protects the session; we never draw a fake lock screen.

## D14. Sleep / session actions (5.7)

`pmset sleepnow` / `pmset displaysleepnow` need no root. Log out / restart / shut down send the
documented loginwindow Apple events (`kAELogOut`, `kAERestart`, `kAEShutDown`, and their
"show dialog" variants for the confirm step). Never `sudo`.

## D15. Media keys (3.4)

F-row media keys are observed as `NX_SYSDEFINED` events and *passed through* so macOS performs
the actual volume/brightness change; we only add the Caelestia OSD. Suppressing Apple's HUD
needs private API, so both show (listed in LIMITATIONS).

## D16. Window title access

Reading other apps' window titles via AX works with Accessibility alone; CGWindowList titles
additionally need Screen Recording on macOS 14+. We use AX titles and never require Screen
Recording for tiling.
