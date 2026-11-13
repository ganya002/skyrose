# SkyStore

SkyStore is where you browse, install, update and remove optional addons for SkyRose. This
release installs **data addons** (colour schemes and wallpapers) and first-party **app addons**
(whole macOS apps, like Sky, built on your Mac from reviewed source; see [App addons](#app-addons)).
Addons that run code inside SkyRose (widgets, bar modules, keymaps, split-out features) are
designed but not installable yet. See [skystore-security.md](skystore-security.md) for why.

## Using the Store

Open it with `>store` in the launcher, `skyrose store`, `skyrose shell drawers toggle store`, or
Settings › SkyStore › Open. It rises from the bottom of the screen like the launcher, with the
same blob motion and colours.

- **Featured**: what the maintainers picked (or everything, when nothing is featured).
- **Categories**: one shelf per category (Colour scheme, Wallpapers, …).
- **Search**: type in the pill at the bottom. It searches names, authors, summaries and categories.
- **Installed**: every addon, its version and state, with Turn on/off and Uninstall.
- **Updates**: addons with a newer version, one at a time or all at once.
- **Detail page** (click a card): screenshots, description, permissions, version history, and
  the Install / Update / Uninstall button. Esc goes back, then closes.

Install shows a progress bar: checking, downloading, verifying, unpacking, installing. If a step
fails, nothing changes. A failed update leaves the old version installed and working.

Uninstall and any new permissions need a second press. The button changes to "Remove?" or
"Allow N new permissions" first.

Installed schemes appear in Settings › Appearance next to the built-in ones. Their names look like
`dev.someone.rose-pine/rose-pine` (`appearance.theme`). Installed wallpapers appear in the
wallpaper picker as a group called `SkyStore/<name>`.

### Command line

    skyrose store                       open the Store
    skyrose store list [--json]         installed addons and their state
    skyrose store refresh               fetch the index, apply revocations, list updates
    skyrose store install <id> [--yes]  install (--yes allows new permissions without asking)
    skyrose store update [id] [--yes]   update one addon or all of them
    skyrose store setup <id> [--json]   app addons: check the Mac, fetch pinned runtimes, build, start
    skyrose store uninstall <id> [--purge]   --purge also deletes an app's own data
    skyrose store enable|disable <id>

### Safety

- The index is signed. SkyRose only trusts the keys built into it. An index with a bad signature
  is refused and nothing changes.
- Each version in the index lists its bundle's SHA-256. The bundle must match, and every file in
  it must match the SHA-256 in the bundle's own manifest.
- Downloads are HTTPS only. The index is only fetched when you open the Store, or every 6 hours
  while at least one addon is installed (for the kill switch). With no addons, SkyRose never
  contacts the index on its own.
- **No replays**: each index carries a signed `serial`; SkyRose refuses one older than an index it
  already saw, so an old copy cannot hide a revocation.
- **Kill switch**: the maintainers can revoke an addon or a single version in the index. SkyRose
  then switches it off, shows a toast, and it cannot be turned back on.
- **Panic**: `skyrose wm panic` (and the panic chord) switches every addon off, even when the WM
  is hung. Turn them back on one by one with `skyrose store enable <id>` or in Installed.

Files: `~/Library/Application Support/SkyRose/addons/` (`state.json`, `index-serial`, one folder
per addon version).

Where it lives: the Store is a shell drawer (`>store`, `skyrose store`); Settings › SkyStore is
the fallback (Open, Creator mode). Uninstalling or turning off a wallpaper addon that is the
current wallpaper leaves the desktop as it is: the picture stays until you pick another one.

## App addons

Kind `app`: a whole macOS app (Sky is the first). The bundle carries the app's **source** as one
`.tar.gz`, pinned by SHA-256 in the manifest and so by the signed index, plus a declarative build
recipe (`entry.app`). There are no install scripts. SkyRose's own installer does every step and the
Store shows each one on the card's progress bar, with real bytes, speed and time left while
downloading.

1. **Preflight**, before anything is written: Apple Silicon (Intel Macs are refused with a clear
   message), the app's minimum macOS (14 or newer), and enough free disk for the whole install.
2. **Tools**: the Xcode Command Line Tools. If they are missing, Apple's own installer dialog opens
   (`xcode-select --install`) and setup waits for it. SkyRose never runs `sudo`. If Apple's
   installer needs an admin password, it asks for it in its own standard dialog.
3. **Downloads**: only the artefacts the manifest pins (URL + SHA-256 + size), over HTTPS,
   resumable. A wrong checksum stops the install. Archives are checked entry by entry before
   unpacking, and links that leave their folder are refused. Each host must be declared as a
   `network:<host>` permission. No Homebrew, no `curl | sh`.
4. **Build**: `xcrun swift build -c release` for each product, from the source in the bundle.
   Packages with remote dependencies are refused, so everything that is compiled was reviewed.
5. **Bundle**: the `.app` is assembled from the recipe (its Info.plist must name the declared
   bundle id), signed ad hoc, and swapped in. A running copy is stopped first; a failure keeps
   the old app.
6. **Activate**: command-line helpers go to `addons/<id>/bin/`, and with `launchAgent` and the
   `login` permission a per-user LaunchAgent (`~/Library/LaunchAgents/<bundleID>.plist`) starts it.

The installer runs out of process: the Store drawer starts `skyrose store setup <id> --json` and
reads one JSON line per step. `skyrose store install <id>` runs the same setup in the CLI.

Where things go (per user, nothing system-wide):

    ~/Library/Application Support/SkyRose/addons/<id>/<version>/   the verified bundle
    ~/Library/Application Support/SkyRose/addons/<id>/app/<Name>.app
    ~/Library/Application Support/SkyRose/addons/<id>/deps/        pinned runtimes
    ~/Library/Application Support/SkyRose/addons/<id>/bin/         helpers (skyctl)
    ~/Library/Logs/SkyRose/addons/<id>.log                          setup log, app output

Off, panic and revocation stop the app (its declared quit command, then SIGTERM) and remove its
LaunchAgent; on puts the LaunchAgent back. Uninstall does the same and deletes the addon folder.
The app's own data (`entry.app.dataPaths`, e.g. chats and models) stays unless you pass `--purge`.

App permissions are shown before install like any other: `network:<host>`, `microphone`,
`accessibility`, `keychain`, `login`, `notifications`, `windows`. macOS still asks for the
microphone and Accessibility itself, per app; the app inherits none of SkyRose's permissions.
For now only first-party ids (`dev.gabby.*`) may use the kind.

`SKYROSE_HOME=/some/folder skyrose store …` runs the whole flow against a separate home (config,
addons, LaunchAgents and logs under that folder, and nothing is loaded into launchd). Use it to
test an app addon without touching the real install.

    "entry": { "app": {
      "bundleID": "dev.gabby.sky", "appName": "Sky",
      "source": "source.tar.gz", "products": ["Sky", "sky-whisper"],
      "infoPlist": "Packaging/Info.plist",
      "copy": [ { "from": "source:Resources/personality", "to": "Contents/Resources/personality" },
                { "from": "build:sky-whisper", "to": "Contents/MacOS/sky-whisper" } ],
      "requires": ["xcode-clt"],
      "downloads": [ { "id": "llama-cpp", "title": "llama.cpp b12317", "url": "https://github.com/…",
                       "sha256": "…", "size": 16896114, "unpack": "tar.gz", "into": "deps/llama" } ],
      "minMacOS": "14.0", "architectures": ["arm64"], "diskBytes": 900000000,
      "cli": [ { "from": "source:bin/skyctl", "to": "skyctl" } ],
      "stop": ["ctl", "quit"], "launchAgent": true,
      "dataPaths": ["Library/Application Support/Sky"] } }

`into` is `deps/<path>` (kept for the app at run time) or `source/<path>` (placed in the source
tree before the build, for a binary framework). `copy.from` is `source:<path>`, `build:<product>`
or `deps:<path>`; `copy.to` is under `Contents/`.

## Creator mode

Off by default. Turn it on in Settings › SkyStore › Creator mode, or with
`skyrose config set store.creatorMode true`.

    skyrose store new dev.you.my-theme [--kind scheme|wallpaper]
    skyrose store validate [dir]
    skyrose store pack [dir]
    skyrose store submit [dir] --repo you/my-addons [--yes]

1. `new` creates a folder with `manifest.json`. A scheme addon also gets a copy of SkyRose
   Default in `schemes/` to edit. For a wallpaper addon, put images or videos in `wallpapers/`
   and list them in `entry.wallpapers`.
2. Fill in `author` and `summary`. Add screenshots (PNG or JPEG) and list them in `screenshots`.
3. `validate` checks the manifest, the permissions, the files (schemes must parse, wallpapers
   must be jpg/png/heic/webp/mp4/mov/m4v, at most 200 files and 64 MB), and whether a packed
   bundle still matches its `.sha256`.
4. `pack` writes `dist/<id>-<version>.skyaddon` (a zip with the manifest and every file's
   SHA-256) and `dist/<id>-<version>.skyaddon.sha256`.
5. `submit` packs again and prints two steps. With `--yes` it runs both:
   - `gh release create <id>-v<version> …` uploads the bundle to **your** repo with your own `gh`
     login.
   - A GitHub link opens the "new file" page of `ganya002/skystore-index` with
     `submissions/<id>-<version>.json` already filled in. GitHub forks the index for you and
     opens the pull request.

SkyRose never stores a GitHub token. A person reviews every submission. Nothing is published
automatically.

To test against your own index, creator mode also accepts `store.indexURL = "file:///…/index.json"`
and your own public keys in `store.trustedKeys`. Sign it with the index tools (below).

## Formats

### manifest.json (in every bundle)

    {
      "schema": 1,
      "id": "dev.you.rose-pine",            // reverse-DNS, lower case
      "name": "Rose Pine",                  // at most 40 characters
      "author": "You",
      "version": "1.0.0",                   // numeric, 1 to 4 parts
      "minSkyRose": "0.4.0",
      "kind": "scheme",                     // scheme | wallpaper | app (keymap | widget | feature: not yet)
      "summary": "Soho vibes",              // at most 120 characters
      "description": "…",                   // optional
      "licence": "MIT",                     // SPDX id
      "homepage": "https://…",              // optional, https
      "permissions": [],                    // must be empty for data kinds
      "entry": { "schemes": ["schemes/rose-pine.toml"] },   // or { "wallpapers": [...] }
      "icon": "icon.png",                   // optional, in the bundle
      "screenshots": ["screenshots/1.png"],
      "files": { "schemes/rose-pine.toml": "<sha256>", … }  // written by pack
    }

Permissions are written `name` or `name:scope`: `network:<host>`, `files:<path>`, `notifications`,
`media`, `clipboard`, `keybinds`, `windows`, and for apps `microphone`, `accessibility`,
`keychain`, `login`. They are for code addons, and SkyRose refuses any other name.

A kind this SkyRose does not know is skipped, not an error, so a newer index never breaks the
Store. SkyRose 0.4.1 and older do fail on an unknown kind: publish the first `app` entry only
after the SkyRose release that knows the kind is out.

### index.json (+ index.json.sig)

    { "schema": 1, "generated": "…", "addons": [ {
        "id", "name", "author", "summary", "description", "kind", "category",
        "icon": "https://…", "screenshots": ["https://…"], "licence", "homepage",
        "featured": true, "revoked": "reason (kill switch)",
        "versions": [ { "version", "minSkyRose", "url": "https://…/<id>-<v>.skyaddon",
                        "sha256", "size", "permissions": [], "released": "2026-11-11",
                        "notes", "revoked": "reason" } ] } ] }

`index.json.sig` is the base64 Ed25519 signature of the exact bytes of `index.json`.

## Maintainer setup (Gabby)

The index lives in the public repo `ganya002/skystore-index` (local copy `~/Projects/skystore-index`).
Its `README.md` and `REVIEWING.md` cover the review flow. Done on 2026-11-11: repo created and
pushed, signing key made (`~/.skystore/signing.key`, offline, backed up), public key
`gfdvEbFkyU5rns7ZgFsTCxJWx8DVpyuCPpIL9njAtp4=` built into `StoreSource.trustedKeys`.

Publish (use `/usr/bin/swift`: a swiftly toolchain earlier in PATH cannot import CryptoKit for
scripts):

    cd ~/Projects/skystore-index
    /usr/bin/swift tools/skystore.swift build          # raises the signed serial
    /usr/bin/swift tools/skystore.swift sign ~/.skystore/signing.key
    /usr/bin/swift tools/skystore.swift verify gfdvEbFkyU5rns7ZgFsTCxJWx8DVpyuCPpIL9njAtp4=
    git add index.json index.json.sig && git commit -m "Publish index" && git push

Until a signed `index.json.sig` is pushed, SkyRose shows the Store as offline (the .sig is 404).

Key rotation: add the new public key to `trustedKeys` next to the old one, ship a release, sign
with the new key, then remove the old key in a later release. If the key leaks, ship a release
without it at once. Old SkyRose versions keep trusting it until they update.

## Builtin features as first-party addons

Decided 2026-11-11 (Gabby), built 2026-11-13: SkyRose's own optional parts are `feature` addons,
starting with **Clamshell** (`skyrose.clamshell`) and the **Colour picker** (`skyrose.colorpicker`).

- The code is compiled into SkyRose (`BuiltinFeature`). Installing one writes only a state record,
  so nothing is downloaded. Uninstalling it or switching it off turns the feature off.
- Every builtin starts installed the first time a SkyRose that has it runs (`features-seeded.json`
  in the addons folder), so an update changes nothing. An uninstall sticks.
- They are listed under Categories › Built in, also when the index is offline, and under Installed.
  `skyrose store install|uninstall|enable|disable skyrose.clamshell` works too.
- Off: Clamshell lets the Mac sleep with the lid closed again, its sidebar chip goes, and
  `skyrose clamshell on` refuses. The colour picker bind shows a toast that says how to turn it on.
- Panic and revocation use the data-addon path (`disableAll()`, `applyRevocations(_:)`), so a
  panic switches builtins off too.
- Builtin features alone never make SkyRose contact the index in the background.
- Not done: a `ShellFeature` protocol with its own host API. Two features did not need one; it
  comes with the first feature that adds bar items or binds of its own.

- Real third-party code addons run **out of process** (see the security doc). They get the same
  host API over a socket that is limited to their declared permissions.
