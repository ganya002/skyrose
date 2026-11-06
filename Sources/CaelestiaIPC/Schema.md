# SkyRose — IPC schema (protocol version 2)

Transport: Unix domain stream socket at `~/Library/Application Support/SkyRose/ipc.sock`
(mode `0600`, owner only). One JSON object per line, UTF-8, terminated by `\n`. A line may be at
most 1 MiB. A connection may carry any number of requests; responses come back in request order
and carry the request's `id`.

## Request

```json
{"id": 1, "command": "ws.focus", "args": {"index": 3}}
```

| field     | type   | notes                                                      |
|-----------|--------|------------------------------------------------------------|
| `id`      | int    | optional (defaults to 0); echoed back                      |
| `command` | string | an `IPCCommand` raw value (see the catalog below)          |
| `args`    | object | optional; argument names/types are per command            |

Unknown commands and missing required arguments are rejected by the server with `ok: false`
before the WM handler runs (`IPCServer(validatesRequests:)`).

## Response

```json
{"id": 1, "ok": true, "result": null, "protocolVersion": 2}
{"id": 1, "ok": false, "error": "No workspace 42", "protocolVersion": 2}
```

`result` is omitted when there is nothing to return; `error` is present only when `ok` is false.
Clients compare `protocolVersion` with their own `CaelestiaVersion.protocolVersion` (2 since SkyRose 0.2.0) and refuse to
talk to a mismatched WM (`IPCError.protocolMismatch`).

## Handshake

`{"command": "hello"}` is answered by the server itself (no WM code involved):

```json
{"id": 0, "ok": true, "result": {"version": "0.2.0", "protocolVersion": 2, "pid": 4242}, "protocolVersion": 2}
```

The server uses the same probe on start-up: a left-over socket file that does not answer `hello`
is unlinked and replaced; one that answers makes `start()` fail with `alreadyRunning`.

## Command catalog

### Window manager (replaces `hyprctl dispatch`)

| command             | args                                   | result |
|---------------------|----------------------------------------|--------|
| `ws.focus`          | `index: int`                           | null   |
| `ws.move`           | `index: int`, `silent?: bool`          | null   |
| `ws.toggleSpecial`  | `name?: string` (default `special`)    | null   |
| `window.focus`      | `direction: left\|right\|up\|down`     | null   |
| `window.move`       | `direction: left\|right\|up\|down`     | null   |
| `window.float`      |                                        | null   |
| `window.fullscreen` |                                        | null   |
| `window.maximize`   |                                        | null   |
| `window.pin`        |                                        | null   |
| `window.close`      |                                        | null   |
| `window.center`     |                                        | null   |
| `action`            | `action: string` (ActionKind), `args?: object` | null |
| `config.reload`     |                                        | `{warnings: [string]}` |
| `config.get`        | `path?: string` (`table.key`, e.g. `wm.gapsIn`; whole config when omitted) | value or object, as written in config.toml with defaults filled in |
| `config.set`        | `path: string`, `value: bool\|number\|string` (a string starting with `[` or `{` is parsed as a TOML literal) | `{warnings: [string]}` |
| `config.reset`      | `path: string`                         | `{warnings: [string]}` |
| `rules.reload`      |                                        | `{warnings: [string]}` |
| `keys.list`         |                                        | array of BindQueryEntry |
| `keys.pause`        | `seconds?: number` (default 10, max 15; 0 ends the pause) | `{paused: bool}` |
| `wm.panic`          |                                        | null   |
| `wm.restoreAll`     |                                        | null   |
| `wm.quit`           |                                        | null   |
| `permissions.status`|                                        | PermissionsStatusEntry |
| `permissions.request`| `kind: accessibility\|inputMonitoring\|screenRecording`, `open?: bool` (default true) | `{granted: bool}` |
| `doctor`            |                                        | object (free-form WM diagnostics) |

### Queries (replaces `hyprctl -j`)

| command            | result                         |
|--------------------|--------------------------------|
| `query.windows`    | array of `WindowQueryEntry`    |
| `query.workspaces` | array of `WorkspaceQueryEntry` |
| `query.monitors`   | array of `MonitorQueryEntry`   |
| `query.binds`      | array of `BindQueryEntry`      |
| `query.state`      | `StateQueryEntry`              |
| `query.overlays`   | array of `OverlayQueryEntry` (`{target, overlay, at, size, alpha, active, vanishing, group}`: one per border window; Riko R2) |

`debug.overlay` (`on?: bool`, toggles when omitted) shows/hides the debug overlay and returns `{on: bool}`.

### Shell conveniences and utilities

| command              | args                                               | result |
|----------------------|----------------------------------------------------|--------|
| `shell.launcher`, `shell.dashboard`, `shell.sidebar`, `shell.session`, `shell.showall`, `shell.clear-notifs` | | null |
| `shell.kill`, `shell.restart` |                                           | null   |
| `screenshot`         | `mode?: region\|freeze\|window\|full`              | `{mode, folder}` (result: toast) |
| `keepawake`          | `state: on\|off\|status, seconds?`                  | `{enabled, until?, status}` |
| `clamshell`          | `state?: on\|off\|status\|helper`                  | `{hasLid, lidClosed, onAC, externalDisplays, mode, via?, summary, enabled, keepAwakeActive, sleepDisabled, sleepDisabledBySkyRose, helper, helperCommand?, helperError?, closingCausesSleep?, keepAwake, holdingKeepAwake}` |
| `record`             | `sound?: bool`, `region?: bool`                    | `{recording: bool, path?}` |
| `clipboard`          | `delete?: bool`                                    | null   |
| `emoji`              |                                                    | null   |
| `scheme.set`         | `name: string`                                     | null   |
| `wallpaper.random`   |                                                    | `{path}` |
| `notify`             | `title: string`, `body?`, `app?`, `icon?`          | `{id}` |
| `frame.calibrate`    | `display?: string` (id or name)                    | `{display, radius}` |

### Shell targets (Linux `ipc-commands.txt`, 1:1)

Every Linux function `target.fn(params)` is `shell.<target>.<fn>` with the same parameter names;
all parameters are strings. Return types map `void → null`, `string → string`, `real → number`,
`bool → bool`.

| target          | functions                                                                 |
|-----------------|---------------------------------------------------------------------------|
| `toaster`       | `error`, `warn`, `info`, `success` `(title, message, icon)`               |
| `brightness`    | `set(value)`, `get()`, `getFor(query)`, `setFor(query, value)`            |
| `wallpaper`     | `set(path)`, `get()`, `list()`                                            |
| `nexus`         | `open()`                                                                  |
| `lock`          | `isLocked()`, `lock()`, `unlock()`                                        |
| `notifs`        | `toggleDnd()`, `isDndEnabled()`, `clear()`, `disableDnd()`, `enableDnd()` |
| `picker`        | `openFreezeClip()`, `openClip()`, `open()`, `openFreeze()`                |
| `gameMode`      | `toggle()`, `enable()`, `isEnabled()`, `disable()`                        |
| `drawers`       | `toggle(drawer)`, `isOpen(drawer)`, `list()`                              |
| `idleInhibitor` | `toggle()`, `enable()`, `isEnabled()`, `disable()`                        |
| `mpris`         | `next()`, `stop()`, `getActive(prop)`, `play()`, `pause()`, `playPause()`, `previous()`, `list()` |
| `audio`         | `cycleOutput()`                                                           |
| `hypr`          | `listSpecialWorkspaces()`, `cycleSpecialWorkspace(direction)`, `refreshDevices()` |

### Config API (protocol 2)

`config.set` edits `config.toml` in place (comments and ordering are kept), validates the result and
rolls the file back if it does not parse or validate, then applies the change live. `config.reset`
removes the key so the default applies again. `config.get` returns what is written in the file with
defaults filled in. SkyRose Settings uses these three; when SkyRose is not running it edits
`config.toml` directly instead. Example:

```json
{"id": 2, "command": "config.set", "args": {"path": "general.mode", "value": "wm"}}
```

`keys.pause` makes every key pass through to the focused app for a few seconds so Settings can
record a new chord; it ends by itself. `permissions.request` triggers the macOS prompt from the WM
process (so SkyRose, not the CLI, appears in the System Settings list) and opens the pane.

### Changes in protocol 2

Version 2 adds `config.get`, `config.set`, `config.reset`, `keys.pause` and `permissions.request`.
A CLI or WM still speaking version 1 is rejected with `protocolMismatch`. The old `caelestia` CLI
name is a deprecated alias of `skyrose` and speaks the same protocol.

## Golden JSON shapes

### `WindowQueryEntry` (`query.windows`, compatible with `hyprctl clients -j` / `clients.json`)

```json
{
  "address": "0x1a2b",            // "0x" + hex CGWindowID
  "at": [21, 21],                 // top-left in global CG points
  "size": [2533, 1398],           // points
  "workspace": {"id": 1, "name": "1"},
  "floating": false,
  "pinned": false,
  "fullscreen": 0,                // 0 none, 1 maximized, 2 fullscreen
  "class": "net.kovidgoyal.kitty",// bundle id
  "title": "~",
  "pid": 3296,
  "focusHistoryID": 0,            // 0 = most recently focused
  "monitor": "37D8832A-2D66-02CA-B9F7-8F30A301B230", // MonitorQueryEntry.id
  "mapped": true, "hidden": false,                       // optional
  "initialClass": "...", "initialTitle": "...",          // optional
  "appName": "kitty", "role": "AXWindow", "subrole": "AXStandardWindow", "minimized": false // Mac extras, optional
}
```

### `MonitorQueryEntry` (`query.monitors`, compatible with `monitors.json`)

```json
{
  "name": "Built-in Retina Display",
  "id": "37D8832A-2D66-02CA-B9F7-8F30A301B230",  // stable display UUID (hyprctl: int index; both decode)
  "width": 1470, "height": 956,                   // points
  "x": 0, "y": 0,
  "scale": 2,
  "reserved": [10, 42, 10, 10],                   // [left, top, right, bottom]
  "activeWorkspace": {"id": 1, "name": "1"},
  "specialWorkspace": {"name": ""},               // empty when none is open
  "focused": true,
  "description": "...", "refreshRate": 120,       // optional
  "displayID": 1, "primary": true, "builtin": true // Mac extras, optional
}
```

### `WorkspaceQueryEntry` (`query.workspaces`, compatible with `hyprctl workspaces -j`)

```json
{
  "id": 1, "name": "1",
  "monitor": "Built-in Retina Display", "monitorID": "37D8...",
  "windows": 2, "hasfullscreen": false,
  "lastwindow": "0x1a2b", "lastwindowtitle": "~",
  "group": 1, "active": true                      // Mac extras, optional
}
```

### `BindQueryEntry` (`query.binds`, `keys.list`)

```json
{
  "id": "workspace.focus.1", "keys": ["SUPER + 1"], "mac": ["⌥L + 1"],
  "action": "workspace.focus", "args": {"index": 1},
  "locked": false, "mouse": false, "release": false, "repeat": false,
  "description": "focus workspace 1", "enabled": true, "linux": "bind = SUPER, 1, workspace, 1"
}
```

### `StateQueryEntry` (`query.state`)

```json
{
  "mode": "standard", "version": "0.2.0", "pid": 4242, "uptimeSeconds": 120.5,
  "focusedWindow": "0x1a2b", "focusedWorkspace": {"id": 1, "name": "1"}, "focusedMonitor": "37D8...",
  "windowCount": 6, "workspaceCount": 3, "monitorCount": 1, "gameMode": false,
  "counters": {"layoutPasses": 12, "axSetFrame": 40}
}
```

### `PermissionsStatusEntry` (`permissions.status`)

```json
{"accessibility": true, "inputMonitoring": false, "screenRecording": true,
 "automation": {"com.apple.systemevents": true}, "mode": "standard", "enhancedLoaded": false}
```

## Errors seen by clients (`IPCError`)

| case               | meaning                                              | CLI exit |
|--------------------|------------------------------------------------------|----------|
| `notRunning`       | no socket, or nothing accepting (`ECONNREFUSED`)     | 2        |
| `timeout`          | connected but no answer within the timeout           | 1        |
| `protocolMismatch` | WM and CLI protocol versions differ                  | 1        |
| `remote`           | `ok: false` with the WM's message (from `call`)      | 1        |
| `malformedResponse`, `lineTooLong`, `socketError` | transport problems     | 1        |
