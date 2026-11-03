# Permissions (TCC)

Caelestia for Mac never grants itself anything (no `tccutil`, no profiles). You grant each
permission in **System Settings → Privacy & Security**, and you can revoke it there at any time.
The first-run wizard and **Caelestia Settings → Welcome / Status** show the live status of each
one with an "Open System Settings" button.

| Permission | Required? | Why we need it | What breaks without it | How to revoke |
|---|---|---|---|---|
| **Accessibility** | required | read window frames, move/resize windows, raise/focus, close; synthesise the ⌃⌘Q lock keystroke and the "type latest clipboard item" keystrokes | nothing tiles; the WM shows a single notice and waits | Privacy & Security → Accessibility → untick CaelestiaWM |
| **Input Monitoring** | required | the global event tap that hears the hotkeys, the ⌥L tap, ⌥L+drag and ⌥L+scroll | no hotkeys, no mouse binds (the bar and IPC still work) | Privacy & Security → Input Monitoring |
| **Screen Recording** | optional | workspace-slide snapshots, screenshots, the screen recorder, the colour picker | workspace switches cross-fade instead of sliding; capture tools are disabled and say why | Privacy & Security → Screen & System Audio Recording |
| **Automation** (per app) | optional | *System Events*: log out / restart / shut down from the session menu. *Spotify* / *Music*: the media card when MediaRemote is unavailable | the session buttons fall back to the loginwindow Apple events and the media card shows "No media" | Privacy & Security → Automation |
| **Location** | optional | Wi-Fi network name in the bar (macOS 14+ requires it for the SSID) and local weather | the bar says "Connected"; weather uses the city from Settings | Privacy & Security → Location Services |
| **Microphone** | optional | "record with sound" | recordings have no microphone track | Privacy & Security → Microphone |

## Why the grants survive rebuilds

macOS keys a grant on the app's code signature. Ad-hoc signatures change on every build, so
each rebuild would be a "new app" and you would have to remove and re-add it. `scripts/
sign-setup.sh` creates a local certificate ("Caelestia Local Signing") in your login keychain
and `scripts/build.sh` signs every build with it, keeping the same bundle identifiers.

To delete the certificate: `scripts/sign-setup.sh --remove` (or Keychain Access → login →
My Certificates). If a Developer ID is available, `scripts/build.sh --identity "Developer ID
Application: …"` uses it instead.

## Secure Event Input

When another app turns on Secure Event Input (password fields, Terminal "Secure Keyboard
Entry", some password managers), macOS hides keystrokes from every event tap. Hotkeys pause
until that app releases it; the OSD says which app holds it (see TROUBLESHOOTING.md).

## What we never do

- no `tccutil reset` / no automatic granting,
- no LaunchDaemons, no root, no SIP/NVRAM/boot-args changes (Enhanced mode is documented for
  you to do by hand and is never required),
- no changes to system files under `/System` or `/Library`.
