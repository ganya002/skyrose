# SkyRose Part 10: Caelestia-exact OSD, media player, and a sidebar that actually controls the Mac (release v0.5.0)

Send after Part 9 (v0.4.0) is released. Read docs/phase-progress.md first.
Reference screenshots from Gabby's real Arch Caelestia: docs/caelestia-reference/part10/
- osd-volume-brightness.png: the volume/brightness OSD
- media-player.png: the dashboard Media tab
- wifi-popout.png: the bar's Wi-Fi popout
Also use the rest of docs/caelestia-reference and the Caelestia shell source on GitHub (caelestia-dots/shell, QML) for exact sizes, radii, spacing, fonts and animation curves. Match 1:1. Colours always come from the live SkyRose scheme (the screenshots are a light scheme; dark must look just as right).

## Hard rules (same as always)
- No sudo by you. Never close Gabby's running apps. Never force-push or move an existing tag.
- No disk/EFI/bootloader/LUKS/NVRAM/SIP changes. No curl|sh.
- WM tests with TestWindows; `skyrose wm panic` is the escape hatch. You have permission for live tests on this Mac (rebuild, restart SkyRose, record the screen and inspect the recordings) as long as you don't close Gabby's apps.
- Journal every system change; uninstall.sh undoes it; fixture-HOME tests.
- Never store Wi-Fi passwords yourself: hand them to macOS (the system keychain via CoreWLAN) and don't log them.
- Commit locally per part, push main plus the tag only when everything is built, tested, and verified live. Nothing half-done: no stubs, no display-only controls. If macOS truly blocks something, say exactly why and what you shipped instead.

## 10a: Volume and brightness OSD, Caelestia layout
- Exactly like osd-volume-brightness.png: a pill that slides out from the right screen edge, attached to the bar's border shape (the same concave "melt" corners where it joins the border, not a floating box), two tall vertical sliders stacked (volume with a speaker icon in the knob, brightness with a sun icon), the filled part in the scheme's primary colour, and a rounded track.
- Shows on volume/brightness keys and on hovering the right edge. You can drag the sliders directly, and scroll works on them. It hides after the Caelestia timeout with the Caelestia slide animation, with no end-of-animation flash (see 9e).
- Mute shows the muted icon; the keyboard-backlight and mic OSD use the same style if SkyRose has them.
- Replaces the macOS volume/brightness HUD while SkyRose runs (suppress the system OSD the most reliable SIP-on way; if it can't be fully suppressed, say so).

## 10b: Media player, Caelestia layout
Exactly like media-player.png, in the dashboard's Media tab:
- Left: round album art with a radial, beat-reactive bar visualiser ring around it (bars drawn from the real audio spectrum, not a timer), and the art rotating slowly while playing.
- Centre: title, album, artist (or label) lines, prev / play-pause / next with the round filled play-pause button, a seekable progress bar with a draggable knob and elapsed/total time, and below it a row with the "open in app" source pill (app icon + name, e.g. Spotify; click to bring that app forward), a player-switch button when several players are active, and the remove/close button.
- Right: the bongo cat (from 9h) slapping to the beat.
- Lyrics (from 9h) appear in this tab in the Caelestia style. Works with any Now Playing source (Spotify, Apple Music, YouTube/YouTube Music in a browser).

## 10c: Wi-Fi that actually works
Bar popout like wifi-popout.png on hover (connected network, strength, frequency), plus a full Wi-Fi panel on click:
- Toggle Wi-Fi on/off, scan and list nearby networks (signal bars, lock icon, known vs new), connect to an open network, and connect to a secured network with an in-panel password field (show/hide toggle, Enter to connect, clear wrong-password error). Forget a network, and show "Connecting…" / connected / failed states live.
- Use CoreWLAN (CWWiFiClient / CWInterface.associate(to:password:)). Scanning SSIDs needs Location Services permission on modern macOS: add it to onboarding and the permissions pages with the same live detection and deep link as the others.
- Credentials go to the macOS keychain the way System Settings does, never into SkyRose files or logs.
- Live-test: scan, then connect and disconnect to Gabby's current known network without breaking his connection (reconnect right away if you disconnect). Don't join unknown networks during tests.

## 10d: Bluetooth that actually works
Bar popout plus a panel: Bluetooth on/off, paired devices with battery levels where available, connect/disconnect on click, "Pair new device" scan with pairing (including PIN/confirm prompts), and remove/forget. Use IOBluetooth (and CoreBluetooth only where needed). Add Bluetooth permission to onboarding. Live-test connect/disconnect only with a device Gabby already paired; don't unpair anything of his.

## 10e: The sidebar replaces the macOS menu bar's extras
If the menu bar is turned off (9f), nothing important can be lost. The SkyRose sidebar/bar must cover what Control Center and menu extras do:
- Wi-Fi (10c), Bluetooth (10d), sound output/input device picker and volume, display brightness, battery % and charging with Low Power Mode toggle, Focus/Do Not Disturb, AirDrop visibility if reachable, Night Shift, keyboard input source, clock and calendar, and a now-playing entry.
- Third-party menu bar apps (Discord, Spotify, etc.): show their status items in a SkyRose tray if possible (research the reliable SIP-on way; if it's impossible without SIP off, give a keybind that briefly reveals the real menu bar instead, and say so in the UI).
- Each control works for real. Nothing is display-only.

## 10f: Release v0.5.0
Build, `/usr/bin/swift test` with 0 failures, live verification with screen recordings for 10a/10b (look at the frames yourself and compare them side by side with the reference screenshots), sign, publish release v0.5.0 like the previous ones, and check `skyrose update` from 0.4.0. Update CHANGELOG and docs (PERMISSIONS.md gets Location + Bluetooth).
Report: commits, test counts, the live-test results for Wi-Fi/Bluetooth, side-by-side comparisons, release URL, and what was NOT verified.
