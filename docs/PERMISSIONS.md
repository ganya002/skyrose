# Permissions (TCC)

SkyRose never grants itself anything (no `tccutil`, no profiles). You grant each
permission in **System Settings → Privacy & Security**, and you can revoke it there at any time.
The first-run **onboarding** (Permissions step; re-run it from SkyRose Settings → General or with
`skyrose onboarding`) and **SkyRose Settings → Permissions** show the live status of each one and
open the exact System Settings pane. If a permission is lost later, the WM reopens only that
permission step. For testing, `--simulate-missing accessibility,inputMonitoring` (or the env var
`SKYROSE_SIMULATE_MISSING`) pretends those permissions are missing.

macOS answers permission checks per app, so Settings cannot check SkyRose's grants itself. It
asks the running WM (`permissions.status`). When the WM is not running, or too busy to answer
in time, Settings starts `SkyRose.app --permissions-probe <file>` through Launch Services every
2 s. That instance only writes SkyRose's status and exits; it never starts the window manager.
So the status stays live either way.

> **Re-grant needed after the rename.** SkyRose.app has a new bundle id (`com.skyrose.mac`), so
> macOS treats it as a new app: grant Accessibility, Input Monitoring and Screen Recording once
> again. The old CaelestiaWM entries can be removed from the lists.

| Permission | Required? | Why we need it | What breaks without it | How to revoke |
|---|---|---|---|---|
| **Accessibility** | required | read window frames, move/resize windows, raise/focus, close; synthesise the ⌃⌘Q lock keystroke and the "type latest clipboard item" keystrokes | nothing tiles; the WM shows a single notice and waits | Privacy & Security → Accessibility → untick SkyRose WM |
| **Input Monitoring** | required | the global event tap that hears the hotkeys, the ⌥L tap, ⌥L+drag and ⌥L+scroll | no hotkeys, no mouse binds (the bar and IPC still work) | Privacy & Security → Input Monitoring |
| **Screen Recording** | optional | workspace-slide snapshots, screenshots, the screen recorder, the colour picker | workspace switches cross-fade instead of sliding; capture tools are disabled and say why | Privacy & Security → Screen & System Audio Recording |
| **Automation** (per app) | optional | *System Events*: log out / restart / shut down from the session menu. *Spotify* / *Music*: the media card when MediaRemote is unavailable | the session buttons fall back to the loginwindow Apple events and the media card shows "No media" | Privacy & Security → Automation |
| **Location** | optional | Wi-Fi network names in the bar and the Wi-Fi panel (macOS 14+ hides SSIDs without it) and local weather | the bar says "Connected"; weather uses the city from Settings | Privacy & Security → Location Services |
| **Bluetooth** | optional | the Bluetooth panel: paired devices, battery, connect/disconnect, pairing | the panel can't list or connect devices | Privacy & Security → Bluetooth |
| **Microphone** | optional | "record with sound" | recordings have no microphone track | Privacy & Security → Microphone |

## Why the grants survive rebuilds

macOS keys a grant on the app's code signature. Ad-hoc signatures change on every build, so
each rebuild would be a "new app" and you would have to remove and re-add it. `scripts/
sign-setup.sh` creates a local certificate ("SkyRose Local Signing"; an existing "Caelestia Local Signing" certificate is kept and used) in your login keychain
and `scripts/build.sh` signs every build with it, keeping the same bundle identifiers.

To delete the certificate: `scripts/sign-setup.sh --remove` (or Keychain Access → login →
My Certificates). If a Developer ID is available, `scripts/build.sh --identity "Developer ID
Application: …"` uses it instead.

## Secure Event Input

When another app turns on Secure Event Input (password fields, Terminal "Secure Keyboard
Entry", some password managers), macOS hides keystrokes from every event tap. Hotkeys pause
until that app releases it; the OSD says which app holds it (see TROUBLESHOOTING.md).

## SIP-off boot daemon (optional)

Without it, the SIP-off helper has to be loaded by hand after every restart. The daemon does that
for you. It is off until you install it yourself:

```sh
sudo /path/to/SkyRose.app/Contents/Resources/sa/install-sa-daemon.sh
```

Add `--dry-run` to see every step first; that needs no sudo. Settings › SIP-off mode has Copy
buttons for this command and for the matching `uninstall-sa-daemon.sh`.

- **What it installs.** `/Library/LaunchDaemons/com.skyrose.sa-loader.plist` (root:wheel 644) and
  `/Library/Application Support/SkyRose/` with the loader, the helper and two scripts (root:wheel
  755). launchd only ever runs that root-owned copy, never a file in your account. The installer
  refuses to continue if those folders can be written by anyone but root.
- **When it runs.** At boot as root. It waits for your Dock, loads the helper, and loads it again if
  the Dock restarts. If SIP-off mode is off in Settings it exits at once. It reads your config with
  your own rights, and that file only decides whether it runs.
- **Risk.** A root daemon that injects code into the Dock lowers the Mac's security further on a
  machine that already has SIP partly off. Install it only if you accept that.
- **After an update.** Run the install command again. `skyrose sa status` says when the copy is old.
- **`skyrose wm panic`** stops the helper for this session only; the next boot loads it again.
  `skyrose sa reload` prints the sudo line that loads it sooner.

## What we never do

- no `tccutil reset` / no automatic granting,
- no LaunchDaemons, no root, no SIP/NVRAM/boot-args changes (Enhanced mode is documented for
  you to do by hand and is never required),
- no changes to system files under `/System` or `/Library`.
