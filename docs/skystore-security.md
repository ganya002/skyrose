# SkyStore threat model

SkyStore lets other people's work onto the Mac of everyone who runs SkyRose. SkyRose has
Accessibility, Input Monitoring and Screen Recording permissions, and sometimes a scripting
addition inside the Dock, so anything that runs inside it can do what SkyRose can do. This file
lists what we defend against and how.

## Assets

- The user's files, keystrokes, screen and windows (everything SkyRose's TCC permissions reach).
- The SkyRose process itself (IPC socket, config, the SIP-off helper).
- The trust in the index: one signing key decides what every SkyRose installs.

## Attackers

1. **Network attacker** (café Wi-Fi, a compromised CDN or proxy): changes downloads in transit.
2. **Malicious or careless creator**: submits a harmful or broken addon.
3. **Compromised GitHub account or repo** (the index repo, or a creator's repo).
4. **Local malware** already running as the user.
5. **A good addon that turns bad** in a later version.

## Decisions

### Data-only addons first

This release installs two kinds only. SkyRose reads their files and never runs them:

| Kind | Files | Read by |
|---|---|---|
| `scheme` | `.toml` (SkyRose) or `.json` (Caelestia) colour schemes | `SchemeLoader` (strict parser, colours only) |
| `wallpaper` | jpg, png, heic, webp, mp4, mov, m4v | ImageIO / AVFoundation, like any wallpaper |

Planned data kinds (also never executed): layouts, cursor themes, font packs, sound packs.
They need their own strict loaders first.

App addons (`app`) are the one code kind installable now; see "App addons" below.

The following need code inside SkyRose, so they wait for the addon host:

- **keymap**: a bind can `exec` any shell command, so a keymap is code.
- **widget / bar module**: logic and data sources. Installable since 2026-11-13: they run under
  the out-of-process host below, not inside SkyRose.
- **feature**: builtins split out later (clamshell, colour picker, keep-awake). These enable code
  compiled into SkyRose and download none (see SKYSTORE.md).
- A QML-like declarative widget format counts as code too, unless the format has no
  expressions, no network and no commands.

`AddonPolicy.current` decides this. A data kind cannot ask for any permission, and a code kind
is refused at install, in `validate` and in `new`.

### Code addons: out of process, only what they declare

Built for `widget` (2026-11-13, `WidgetHost`, `WidgetSandbox`): one script per widget, the
socketpair is its stdin/stdout, the broker allows `notifications` and `media`. Network is refused
for widgets until the host-pinning proxy below exists. Tests run a real script under the profile
and check it cannot read the home folder or write outside its data folder.

- Each code addon runs as **its own process**, never inside SkyRose. It is started by SkyRose
  under `sandbox-exec` with a profile built from its manifest:
  - deny by default;
  - read its own folder;
  - write only `addons/<id>/data`;
  - network only with `network:<host>` (pinned to that host through a SkyRose-side proxy,
    since a sandbox profile cannot filter by host name);
  - no Apple Events, no other app's files, no access to SkyRose's IPC socket.
- The addon talks to SkyRose only over its own socketpair. SkyRose's broker accepts only the
  calls its permissions allow: `notifications`, then post a toast; `media`, then read or control
  what is playing; `windows`, then read titles. Every other call is refused and logged. The
  addon never gets the main IPC socket, which can move windows and run actions.
- TCC permissions are per app. The addon process is not SkyRose, so it inherits none of
  Accessibility, Input Monitoring or Screen Recording.
- Panic, disable and revocation kill the process.
- An exception is allowed only for `feature` addons, which are SkyRose's own code and are
  enabled, not downloaded.

### App addons: reviewed source, built locally, run as their own app

An app addon is a whole macOS app (Sky). It cannot run under the planned `sandbox-exec` profile:
it needs Metal, the microphone, Accessibility and its own Keychain items. So it gets different
guarantees, and for now only first-party ids (`AddonPolicy.appIDPrefixes`, `dev.gabby.`) may use
the kind.

- **What runs is what was reviewed.** The bundle carries the full source as one archive whose
  SHA-256 is in the manifest, and the manifest's files are covered by the bundle hash in the
  signed index. The reviewer reads that source. There is no install script: the build recipe is
  data (`entry.app`), and SkyRose's installer does every step itself.
- **Pinned downloads only.** Runtimes come from the manifest's `downloads`: HTTPS URL, SHA-256 and
  size, each host declared as `network:<host>`. A wrong hash or an oversized body stops the install.
  Redirects must stay on HTTPS. Archive entries are checked before unpacking (no absolute paths,
  no `..`), and a symbolic link that leaves its folder is refused.
- **No remote package dependencies.** `swift package dump-package` must list none, and the build
  runs with `--disable-automatic-resolution`, so SwiftPM cannot fetch code at build time. SwiftPM
  evaluates `Package.swift` in its own sandbox.
- **Out of process.** Setup runs in `skyrose store setup` (a child of the Store drawer, or the CLI),
  never in the WM. The app runs as its own process with its own bundle id. macOS TCC grants are
  per app, so it inherits none of SkyRose's Accessibility, Input Monitoring or Screen Recording.
  macOS asks the user itself for the microphone or Accessibility.
- **No admin rights.** Everything goes under the user's Library. The only system-level step is
  Apple's own Command Line Tools installer, started with `xcode-select --install`; it shows
  Apple's dialog and asks for a password itself when it needs one. SkyRose never runs `sudo`.
- **Preflight before writing.** Architecture (Apple Silicon only), macOS version and free disk are
  checked before any download or build.
- **Stop paths.** Off, panic and revocation stop the app (declared quit command, then SIGTERM,
  then SIGKILL for processes whose executable is inside the addon's folder, so a runtime it started from `deps/` stops too) and delete its
  LaunchAgent. The panic path only sends signals, so it never blocks.
- **Permissions are declared, not enforced.** An app is not sandboxed, so `network:<host>` and the
  rest are a promise checked in review and shown to the user, not a fence. This is the main
  difference from data addons, and why the kind is first-party only.
- **Updates** follow the normal path: a new bundle (new source hash), new permissions need
  approval, and a failed build keeps the previous app.

What is not covered: a malicious first-party source would run with the user's rights, as any app
the user installs does. The defences are review, the signature, the pinned hashes and the kill
switch.

### Integrity: signature, then checksums

- `index.json` is signed with Ed25519 (`index.json.sig`). SkyRose has the public key(s) built
  in (`StoreSource.trustedKeys`). An index with no valid signature is refused, so nothing is
  installed, updated or revoked from it. This defends against attackers 1 and 3: a stolen
  GitHub login cannot sign. The key is kept offline, not in CI.
- Each version names its bundle URL **and SHA-256**. Since the index is signed, the hash is
  trusted, and a changed bundle is refused (`checksumMismatch`). Bundles are release assets of
  the index repo: the maintainer mirrors the reviewed asset, so a creator cannot swap it later.
- Inside the bundle, `manifest.json` lists every file's SHA-256. Any extra file, missing file,
  wrong hash, symbolic link, or entry with `..` or an absolute path is refused. `zipinfo` checks
  entry names **before** unzipping, so nothing lands outside the staging folder.
- The bundle's manifest must agree with the index: same id, version, kind and the same
  permissions. Otherwise the bundle is refused (`mismatch`).
- HTTPS only. `file://` is allowed only in creator mode, for a local test index. Extra trusted
  keys (`store.trustedKeys`) also count only in creator mode. Anyone who can write config.toml
  can already run code as the user (shell rc files, LaunchAgents), so this adds no real risk,
  but it is still off by default.
- Bundles are capped at 64 MB and 200 files.

### Install, update, rollback

- Each install unpacks and verifies in `addons/.staging-*`. It moves into
  `addons/<id>/<version>/` only when everything checks out. The old version is deleted only
  after the new `state.json` is written. A failure at any step leaves the old version, its files
  and its state as they were.
- `state.json` is written atomically, under an `flock` shared by the CLI and the WM.

### Permissions

- Each version declares its permissions. On install the user sees them all. On update,
  `PermissionDiff` compares them with the ones granted, and any **new** permission needs
  approval: a second press in the Store, or a prompt or `--yes` on the CLI. Declining keeps the
  installed version. Dropped permissions are shown and need no approval.
- Data kinds have no permissions, so today's addons never prompt. The prompt path is tested
  with a test-only policy.

### Kill switch and panic

- The index can revoke a whole addon (`revoked` on the entry) or one version. SkyRose then sets
  it to `revoked`, shows a toast, and refuses to turn it back on or reinstall that version.
  Revocations are checked when the Store opens and every 6 hours while any addon is installed.
  This is the answer to attacker 5.
- `skyrose wm panic` disables every addon in the CLI process too, so it works when the WM hangs.
  The WM's own panic (the chord, or IPC) does the same in `onPanic`. Turning them back on is a
  deliberate step, one addon at a time.

### Review

No auto-publish. A submission is a pull request that adds `submissions/<id>-<version>.json`.
The maintainer then:

1. downloads the creator's asset and checks its SHA-256;
2. unpacks it and runs `skyrose store validate` on it;
3. looks at every file;
4. mirrors the asset to an `ganya002/skystore-index` release;
5. writes `addons/<id>.json`, then runs `build` and `sign`.

See `REVIEWING.md` in the index repo.

### Privacy

- With no addons installed, SkyRose never contacts the index on its own. The Store fetches only
  when it is open.
- Requests send `User-Agent: SkyRose/<version>` and nothing else. No account, no analytics.
- Icons and screenshots load from HTTPS URLs in the signed index (the index repo).

## What is not covered

- **Image and video decoders**: a crafted wallpaper could exploit ImageIO or AVFoundation, as
  any image from the web could. Mitigations: human review, the size limit, and HTTPS from a
  known repo. Decoding in a separate process would help and is a later step.
- **Local malware** (attacker 4) can edit `addons/`, `state.json` or config.toml directly. It
  already runs as the user, so SkyStore does not try to defend against it.
- **A stolen signing key** lets an attacker sign anything until a release removes that key.
  Keep the key offline, and rotate it as SKYSTORE.md describes.
- **Rollback attacks** (replaying an older signed index to hide a revocation) are refused: every
  `build` raises the signed `serial`, SkyRose keeps the highest serial it has seen in
  `addons/index-serial` and refuses any lower one (`StoreError.staleIndex`). A first install that
  only ever sees a replayed index is not protected; HTTPS from GitHub covers that case. Creator
  mode's local test index keeps its own counter (`index-serial-creator`).
