# Keybinds

Generated from `Sources/CaelestiaCore/Resources/keymap.default.toml` by `gen-keybind-docs`; do not edit by hand.
Every bind of the Hyprland setup (`Tests/fixtures/binds.json`, 153 entries) is listed with its Mac equivalent.

## Notation

- **Linux**: the original Hyprland chord. `SUPER_L` alone is a Super tap; `mouse_up` / `mouse_down` are scroll steps; `mouse:272` / `mouse:273` are left / right drag.
- **Mac**: the physical chord under the shipped modifier preset (**Option is Super**: SUPER = ⌥L, ALT = ⌘L, CTRL = ⌃, SHIFT = ⇧). Only the LEFT Option / Command keys are window-manager modifiers; the right ones keep typing characters and ⌘ shortcuts. Keys are bound by position: `-` / `=` are the two keys right of `0` (`+` and `´` on the Norwegian layout) and `\` is the key next to Return.
- **Keymap**: how the chord is written in `keymap.toml` (Linux modifier names, Mac key names). Edit `~/.config/skyrose/keymap.toml` to change a bind; the window manager reloads it within 200 ms.
- **Flags**: `release` fires on key-up, `repeat` auto-repeats while held, `locked` also works on the lock screen (media / volume / brightness), `mouse` is a drag bind.
- `window.resize` deltas are **percent of the window's current size**, not pixels.

## Shell

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `SUPER + SUPER_L` | `⌥L tap` | `launcher.toggle` | release | toggle the launcher (Super tapped alone, nothing else pressed) | `SUPER` | `launcher.tap` |
| `SUPER + Space` | `⌥L Space` | `launcher.toggle` |  | toggle the launcher | `SUPER + Space` | `launcher.toggle` |
| `CTRL + ALT + Delete` | `⌃ ⌘L ⌫` / `⌃ ⌘L ⌦` | `session.toggle` |  | session menu (lock, sleep, log out, restart, shut down); Delete is fn+⌫ on a MacBook | `CTRL + ALT + Backspace` / `CTRL + ALT + Delete` | `session.menu` |
| `SUPER + N` | `⌥L N` | `sidebar.toggle` |  | sidebar (notifications and utilities) | `SUPER + N` | `sidebar.toggle` |
| `CTRL + ALT + C` | `⌃ ⌘L C` | `notifs.clear` | locked | clear all notifications | `CTRL + ALT + C` | `notifs.clear` |
| `SUPER + K` | `⌥L K` | `panels.showAll` |  | show all panels (and the keybind cheat sheet) | `SUPER + K` | `panels.showAll` |
| `SUPER + L` | `⌥L L` | `lock` |  | lock the screen | `SUPER + L` | `lock` |
| `SUPER + ALT + L` | `⌥L ⌘L L` | `shell.restoreLock` |  | restore lock: restart the shell, then lock | `SUPER + ALT + L` | `shell.restoreLock` |
| `SUPER + CTRL + SHIFT + R` | `⌃ ⌥L ⇧ R` | `shell.kill` | release | kill the shell | `SUPER + CTRL + SHIFT + R` | `shell.kill` |
| `SUPER + CTRL + ALT + R` | `⌃ ⌥L ⌘L R` | `shell.restart` | release | restart the shell | `SUPER + CTRL + ALT + R` | `shell.restart` |

## Workspaces

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `SUPER + 1` | `⌥L 1` | `workspace.focus(index=1)` |  | focus workspace 1 | `SUPER + 1` | `ws.focus.1` |
| `SUPER + 2` | `⌥L 2` | `workspace.focus(index=2)` |  | focus workspace 2 | `SUPER + 2` | `ws.focus.2` |
| `SUPER + 3` | `⌥L 3` | `workspace.focus(index=3)` |  | focus workspace 3 | `SUPER + 3` | `ws.focus.3` |
| `SUPER + 4` | `⌥L 4` | `workspace.focus(index=4)` |  | focus workspace 4 | `SUPER + 4` | `ws.focus.4` |
| `SUPER + 5` | `⌥L 5` | `workspace.focus(index=5)` |  | focus workspace 5 | `SUPER + 5` | `ws.focus.5` |
| `SUPER + 6` | `⌥L 6` | `workspace.focus(index=6)` |  | focus workspace 6 | `SUPER + 6` | `ws.focus.6` |
| `SUPER + 7` | `⌥L 7` | `workspace.focus(index=7)` |  | focus workspace 7 | `SUPER + 7` | `ws.focus.7` |
| `SUPER + 8` | `⌥L 8` | `workspace.focus(index=8)` |  | focus workspace 8 | `SUPER + 8` | `ws.focus.8` |
| `SUPER + 9` | `⌥L 9` | `workspace.focus(index=9)` |  | focus workspace 9 | `SUPER + 9` | `ws.focus.9` |
| `SUPER + 0` | `⌥L 0` | `workspace.focus(index=10)` |  | focus workspace 10 | `SUPER + 0` | `ws.focus.10` |
| `SUPER + ALT + 1` | `⌥L ⌘L 1` | `workspace.move(index=1)` |  | move window to workspace 1 and follow | `SUPER + ALT + 1` | `ws.move.1` |
| `SUPER + ALT + 2` | `⌥L ⌘L 2` | `workspace.move(index=2)` |  | move window to workspace 2 and follow | `SUPER + ALT + 2` | `ws.move.2` |
| `SUPER + ALT + 3` | `⌥L ⌘L 3` | `workspace.move(index=3)` |  | move window to workspace 3 and follow | `SUPER + ALT + 3` | `ws.move.3` |
| `SUPER + ALT + 4` | `⌥L ⌘L 4` | `workspace.move(index=4)` |  | move window to workspace 4 and follow | `SUPER + ALT + 4` | `ws.move.4` |
| `SUPER + ALT + 5` | `⌥L ⌘L 5` | `workspace.move(index=5)` |  | move window to workspace 5 and follow | `SUPER + ALT + 5` | `ws.move.5` |
| `SUPER + ALT + 6` | `⌥L ⌘L 6` | `workspace.move(index=6)` |  | move window to workspace 6 and follow | `SUPER + ALT + 6` | `ws.move.6` |
| `SUPER + ALT + 7` | `⌥L ⌘L 7` | `workspace.move(index=7)` |  | move window to workspace 7 and follow | `SUPER + ALT + 7` | `ws.move.7` |
| `SUPER + ALT + 8` | `⌥L ⌘L 8` | `workspace.move(index=8)` |  | move window to workspace 8 and follow | `SUPER + ALT + 8` | `ws.move.8` |
| `SUPER + ALT + 9` | `⌥L ⌘L 9` | `workspace.move(index=9)` |  | move window to workspace 9 and follow | `SUPER + ALT + 9` | `ws.move.9` |
| `SUPER + ALT + 0` | `⌥L ⌘L 0` | `workspace.move(index=10)` |  | move window to workspace 10 and follow | `SUPER + ALT + 0` | `ws.move.10` |
| `SUPER + CTRL + 1` | `⌃ ⌥L 1` | `workspace.focusGroup(group=1)` |  | focus workspace group 1 (workspaces 1–10) | `SUPER + CTRL + 1` | `ws.focusGroup.1` |
| `SUPER + CTRL + 2` | `⌃ ⌥L 2` | `workspace.focusGroup(group=2)` |  | focus workspace group 2 (workspaces 11–20) | `SUPER + CTRL + 2` | `ws.focusGroup.2` |
| `SUPER + CTRL + 3` | `⌃ ⌥L 3` | `workspace.focusGroup(group=3)` |  | focus workspace group 3 (workspaces 21–30) | `SUPER + CTRL + 3` | `ws.focusGroup.3` |
| `SUPER + CTRL + 4` | `⌃ ⌥L 4` | `workspace.focusGroup(group=4)` |  | focus workspace group 4 (workspaces 31–40) | `SUPER + CTRL + 4` | `ws.focusGroup.4` |
| `SUPER + CTRL + 5` | `⌃ ⌥L 5` | `workspace.focusGroup(group=5)` |  | focus workspace group 5 (workspaces 41–50) | `SUPER + CTRL + 5` | `ws.focusGroup.5` |
| `SUPER + CTRL + 6` | `⌃ ⌥L 6` | `workspace.focusGroup(group=6)` |  | focus workspace group 6 (workspaces 51–60) | `SUPER + CTRL + 6` | `ws.focusGroup.6` |
| `SUPER + CTRL + 7` | `⌃ ⌥L 7` | `workspace.focusGroup(group=7)` |  | focus workspace group 7 (workspaces 61–70) | `SUPER + CTRL + 7` | `ws.focusGroup.7` |
| `SUPER + CTRL + 8` | `⌃ ⌥L 8` | `workspace.focusGroup(group=8)` |  | focus workspace group 8 (workspaces 71–80) | `SUPER + CTRL + 8` | `ws.focusGroup.8` |
| `SUPER + CTRL + 9` | `⌃ ⌥L 9` | `workspace.focusGroup(group=9)` |  | focus workspace group 9 (workspaces 81–90) | `SUPER + CTRL + 9` | `ws.focusGroup.9` |
| `SUPER + CTRL + 0` | `⌃ ⌥L 0` | `workspace.focusGroup(group=10)` |  | focus workspace group 10 (workspaces 91–100) | `SUPER + CTRL + 0` | `ws.focusGroup.10` |
| `SUPER + CTRL + ALT + 1` | `⌃ ⌥L ⌘L 1` | `workspace.moveGroup(group=1)` |  | move window to workspace group 1 and follow | `SUPER + CTRL + ALT + 1` | `ws.moveGroup.1` |
| `SUPER + CTRL + ALT + 2` | `⌃ ⌥L ⌘L 2` | `workspace.moveGroup(group=2)` |  | move window to workspace group 2 and follow | `SUPER + CTRL + ALT + 2` | `ws.moveGroup.2` |
| `SUPER + CTRL + ALT + 3` | `⌃ ⌥L ⌘L 3` | `workspace.moveGroup(group=3)` |  | move window to workspace group 3 and follow | `SUPER + CTRL + ALT + 3` | `ws.moveGroup.3` |
| `SUPER + CTRL + ALT + 4` | `⌃ ⌥L ⌘L 4` | `workspace.moveGroup(group=4)` |  | move window to workspace group 4 and follow | `SUPER + CTRL + ALT + 4` | `ws.moveGroup.4` |
| `SUPER + CTRL + ALT + 5` | `⌃ ⌥L ⌘L 5` | `workspace.moveGroup(group=5)` |  | move window to workspace group 5 and follow | `SUPER + CTRL + ALT + 5` | `ws.moveGroup.5` |
| `SUPER + CTRL + ALT + 6` | `⌃ ⌥L ⌘L 6` | `workspace.moveGroup(group=6)` |  | move window to workspace group 6 and follow | `SUPER + CTRL + ALT + 6` | `ws.moveGroup.6` |
| `SUPER + CTRL + ALT + 7` | `⌃ ⌥L ⌘L 7` | `workspace.moveGroup(group=7)` |  | move window to workspace group 7 and follow | `SUPER + CTRL + ALT + 7` | `ws.moveGroup.7` |
| `SUPER + CTRL + ALT + 8` | `⌃ ⌥L ⌘L 8` | `workspace.moveGroup(group=8)` |  | move window to workspace group 8 and follow | `SUPER + CTRL + ALT + 8` | `ws.moveGroup.8` |
| `SUPER + CTRL + ALT + 9` | `⌃ ⌥L ⌘L 9` | `workspace.moveGroup(group=9)` |  | move window to workspace group 9 and follow | `SUPER + CTRL + ALT + 9` | `ws.moveGroup.9` |
| `SUPER + CTRL + ALT + 0` | `⌃ ⌥L ⌘L 0` | `workspace.moveGroup(group=10)` |  | move window to workspace group 10 and follow | `SUPER + CTRL + ALT + 0` | `ws.moveGroup.10` |
| `SUPER + SHIFT + 1` | `⌥L ⇧ 1` | `workspace.moveSilent(index=1)` |  | move window to workspace 1 silently | `SUPER + SHIFT + 1` | `ws.moveSilent.1` |
| `SUPER + SHIFT + 2` | `⌥L ⇧ 2` | `workspace.moveSilent(index=2)` |  | move window to workspace 2 silently | `SUPER + SHIFT + 2` | `ws.moveSilent.2` |
| `SUPER + SHIFT + 3` | `⌥L ⇧ 3` | `workspace.moveSilent(index=3)` |  | move window to workspace 3 silently | `SUPER + SHIFT + 3` | `ws.moveSilent.3` |
| `SUPER + SHIFT + 4` | `⌥L ⇧ 4` | `workspace.moveSilent(index=4)` |  | move window to workspace 4 silently | `SUPER + SHIFT + 4` | `ws.moveSilent.4` |
| `SUPER + SHIFT + 5` | `⌥L ⇧ 5` | `workspace.moveSilent(index=5)` |  | move window to workspace 5 silently | `SUPER + SHIFT + 5` | `ws.moveSilent.5` |
| `SUPER + SHIFT + 6` | `⌥L ⇧ 6` | `workspace.moveSilent(index=6)` |  | move window to workspace 6 silently | `SUPER + SHIFT + 6` | `ws.moveSilent.6` |
| `SUPER + SHIFT + 7` | `⌥L ⇧ 7` | `workspace.moveSilent(index=7)` |  | move window to workspace 7 silently | `SUPER + SHIFT + 7` | `ws.moveSilent.7` |
| `SUPER + SHIFT + 8` | `⌥L ⇧ 8` | `workspace.moveSilent(index=8)` |  | move window to workspace 8 silently | `SUPER + SHIFT + 8` | `ws.moveSilent.8` |
| `SUPER + SHIFT + 9` | `⌥L ⇧ 9` | `workspace.moveSilent(index=9)` |  | move window to workspace 9 silently | `SUPER + SHIFT + 9` | `ws.moveSilent.9` |
| `SUPER + SHIFT + 0` | `⌥L ⇧ 0` | `workspace.moveSilent(index=10)` |  | move window to workspace 10 silently | `SUPER + SHIFT + 0` | `ws.moveSilent.10` |
| `SUPER + CTRL + Right` / `SUPER + Page_Down` | `⌃ ⌥L →` / `⌥L ⇟` | `workspace.next` | repeat | next workspace (Page Down is fn+↓ on a MacBook) | `SUPER + CTRL + Right` / `SUPER + PageDown` | `ws.next` |
| `SUPER + mouse_down` | `⌥L Scroll Down` | `workspace.next` |  | next workspace (scroll down) | `SUPER + mouse_down` | `ws.next.scroll` |
| `SUPER + CTRL + Left` / `SUPER + Page_Up` | `⌃ ⌥L ←` / `⌥L ⇞` | `workspace.prev` | repeat | previous workspace (Page Up is fn+↑ on a MacBook) | `SUPER + CTRL + Left` / `SUPER + PageUp` | `ws.prev` |
| `SUPER + mouse_up` | `⌥L Scroll Up` | `workspace.prev` |  | previous workspace (scroll up) | `SUPER + mouse_up` | `ws.prev.scroll` |
| `SUPER + CTRL + mouse_down` | `⌃ ⌥L Scroll Down` | `workspace.nextGroup` |  | next workspace group (+10) | `SUPER + CTRL + mouse_down` | `ws.nextGroup.scroll` |
| `SUPER + CTRL + mouse_up` | `⌃ ⌥L Scroll Up` | `workspace.prevGroup` |  | previous workspace group (−10) | `SUPER + CTRL + mouse_up` | `ws.prevGroup.scroll` |
| `SUPER + ALT + Page_Down` / `SUPER + CTRL + SHIFT + Right` | `⌥L ⌘L ⇟` / `⌃ ⌥L ⇧ →` | `workspace.moveToNext` | repeat | move window to the next workspace | `SUPER + ALT + PageDown` / `SUPER + CTRL + SHIFT + Right` | `ws.moveToNext` |
| `SUPER + ALT + mouse_down` | `⌥L ⌘L Scroll Down` | `workspace.moveToNext` |  | move window to the next workspace (scroll down) | `SUPER + ALT + mouse_down` | `ws.moveToNext.scroll` |
| `SUPER + ALT + Page_Up` / `SUPER + CTRL + SHIFT + Left` | `⌥L ⌘L ⇞` / `⌃ ⌥L ⇧ ←` | `workspace.moveToPrev` | repeat | move window to the previous workspace | `SUPER + ALT + PageUp` / `SUPER + CTRL + SHIFT + Left` | `ws.moveToPrev` |
| `SUPER + ALT + mouse_up` | `⌥L ⌘L Scroll Up` | `workspace.moveToPrev` |  | move window to the previous workspace (scroll up) | `SUPER + ALT + mouse_up` | `ws.moveToPrev.scroll` |
| `SUPER + ALT + S` / `SUPER + CTRL + SHIFT + Up` | `⌥L ⌘L S` / `⌃ ⌥L ⇧ ↑` | `workspace.moveToSpecial(name=special)` |  | move window to the special workspace | `SUPER + ALT + S` / `SUPER + CTRL + SHIFT + Up` | `ws.moveToSpecial` |
| `SUPER + CTRL + SHIFT + Down` | `⌃ ⌥L ⇧ ↓` | `workspace.moveOutOfSpecial` |  | move window out of the special workspace (to the current one) | `SUPER + CTRL + SHIFT + Down` | `ws.moveOutOfSpecial` |

## Window cycling and groups

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `ALT + TAB` | `⌥L ⇥` | `window.cycleNext` | repeat | cycle to the next window | `SUPER + Tab` | `window.cycleNext` |
| `ALT + SHIFT + TAB` | `⌥L ⇧ ⇥` | `window.cyclePrev` | repeat | cycle to the previous window | `SUPER + SHIFT + Tab` | `window.cyclePrev` |
| `CTRL + ALT + TAB` | `⌃ ⌥L ⇥` | `group.next` | repeat | next window in the group (tab) | `CTRL + SUPER + Tab` | `group.next` |
| `CTRL + ALT + SHIFT + TAB` | `⌃ ⌥L ⇧ ⇥` | `group.prev` | repeat | previous window in the group | `CTRL + SUPER + SHIFT + Tab` | `group.prev` |
| `SUPER + Comma` | `⌥L ,` | `group.toggle` |  | toggle group (tabbed) for the active window | `SUPER + Comma` | `group.toggle` |
| `SUPER + U` | `⌥L U` | `group.moveOut` |  | move window out of its group | `SUPER + U` | `group.moveOut` |
| `SUPER + SHIFT + Comma` | `⌥L ⇧ ,` | `group.lock` |  | lock the active group | `SUPER + SHIFT + Comma` | `group.lock` |

## Focus / move / resize

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `SUPER + Left` | `⌥L ←` | `window.focus(direction=left)` |  | focus window to the left | `SUPER + Left` | `window.focus.left` |
| `SUPER + Right` | `⌥L →` | `window.focus(direction=right)` |  | focus window to the right | `SUPER + Right` | `window.focus.right` |
| `SUPER + Up` | `⌥L ↑` | `window.focus(direction=up)` |  | focus window above | `SUPER + Up` | `window.focus.up` |
| `SUPER + Down` | `⌥L ↓` | `window.focus(direction=down)` |  | focus window below | `SUPER + Down` | `window.focus.down` |
| `SUPER + SHIFT + Left` | `⌥L ⇧ ←` | `window.swap(direction=left)` |  | move (swap) window to the left | `SUPER + SHIFT + Left` | `window.swap.left` |
| `SUPER + SHIFT + Right` | `⌥L ⇧ →` | `window.swap(direction=right)` |  | move (swap) window to the right | `SUPER + SHIFT + Right` | `window.swap.right` |
| `SUPER + SHIFT + Up` | `⌥L ⇧ ↑` | `window.swap(direction=up)` |  | move (swap) window up | `SUPER + SHIFT + Up` | `window.swap.up` |
| `SUPER + SHIFT + Down` | `⌥L ⇧ ↓` | `window.swap(direction=down)` |  | move (swap) window down | `SUPER + SHIFT + Down` | `window.swap.down` |
| `SUPER + Minus` / `SUPER + ALT + Left` | `⌥L -` / `⌥L ⌘L ←` | `window.resize(axis=width, delta=-10)` | repeat | width −10% of the current size | `SUPER + Minus` / `SUPER + ALT + Left` | `window.resize.narrower` |
| `SUPER + Equal` / `SUPER + ALT + Right` | `⌥L =` / `⌥L ⌘L →` | `window.resize(axis=width, delta=10)` | repeat | width +10% of the current size | `SUPER + Equal` / `SUPER + ALT + Right` | `window.resize.wider` |
| `SUPER + SHIFT + Minus` / `SUPER + ALT + Up` | `⌥L ⇧ -` / `⌥L ⌘L ↑` | `window.resize(axis=height, delta=-10)` | repeat | height −10% of the current size | `SUPER + SHIFT + Minus` / `SUPER + ALT + Up` | `window.resize.shorter` |
| `SUPER + SHIFT + Equal` / `SUPER + ALT + Down` | `⌥L ⇧ =` / `⌥L ⌘L ↓` | `window.resize(axis=height, delta=10)` | repeat | height +10% of the current size | `SUPER + SHIFT + Equal` / `SUPER + ALT + Down` | `window.resize.taller` |
| `SUPER + Z` / `SUPER + mouse:272` | `⌥L Z` / `⌥L Left Click` | `window.drag` | mouse | drag window (hold Z, or left-drag anywhere) | `SUPER + Z` / `SUPER + mouse:272` | `window.drag` |
| `SUPER + X` / `SUPER + mouse:273` | `⌥L X` / `⌥L Right Click` | `window.resizeDrag` | mouse | resize window (hold X, or right-drag / two-finger-click drag) | `SUPER + X` / `SUPER + mouse:273` | `window.resizeDrag` |
| `SUPER + CTRL + Backslash` | `⌃ ⌥L \` | `window.center` |  | center floating window (Backslash is the key next to Return: ' on the Norwegian layout) | `SUPER + CTRL + Backslash` | `window.center` |
| `SUPER + CTRL + ALT + Backslash` | `⌃ ⌥L ⌘L \` | `window.normalize` |  | normalize: float, resize to 55% × 70% of the screen, center | `SUPER + CTRL + ALT + Backslash` | `window.normalize` |
| `SUPER + ALT + Backslash` | `⌥L ⌘L \` | `window.pip` |  | picture-in-picture: float, move to the PiP corner, pin | `SUPER + ALT + Backslash` | `window.pip` |
| `SUPER + P` | `⌥L P` | `window.pin` |  | pin window (show on all workspaces) | `SUPER + P` | `window.pin` |
| `SUPER + F` | `⌥L F` | `window.fullscreen` |  | fullscreen (covers bar and gaps) | `SUPER + F` | `window.fullscreen` |
| `SUPER + ALT + F` | `⌥L ⌘L F` | `window.maximize` |  | maximize (fills the work area, keeps gaps and bar) | `SUPER + ALT + F` | `window.maximize` |
| `SUPER + ALT + Space` | `⌥L ⌘L Space` | `window.toggleFloat` |  | toggle floating | `SUPER + ALT + Space` | `window.toggleFloat` |
| `SUPER + Q` | `⌥L Q` | `window.close` |  | close window | `SUPER + Q` | `window.close` |

## Special workspaces

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `SUPER + S` | `⌥L S` | `special.toggle(name=special)` |  | toggle the special workspace (closes whichever special workspace is open) | `SUPER + S` | `special.toggle` |
| `CTRL + SHIFT + Escape` | `⌃ ⇧ ⎋` | `special.toggle(name=sysmon)` |  | system monitor (btop in kitty) | `CTRL + SHIFT + Escape` | `special.sysmon` |
| `SUPER + M` | `⌥L M` | `special.toggle(name=music)` |  | music (Spotify, else Apple Music) | `SUPER + M` | `special.music` |
| `SUPER + D` | `⌥L D` | `special.toggle(name=communication)` |  | communication (Discord, else Messages) | `SUPER + D` | `special.communication` |
| `SUPER + R` | `⌥L R` | `special.toggle(name=todo)` |  | to-do (Todoist, else Reminders) | `SUPER + R` | `special.todo` |

## Apps

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `SUPER + T` | `⌥L T` | `app.terminal` |  | terminal (Settings › Terminal; kitty by default) | `SUPER + T` | `app.terminal` |
| `SUPER + W` | `⌥L W` | `app.browser` |  | browser (Firefox) | `SUPER + W` | `app.browser` |
| `SUPER + C` | `⌥L C` | `app.editor` |  | editor (VSCodium) | `SUPER + C` | `app.editor` |
| `SUPER + E` | `⌥L E` | `app.files` |  | file manager (Finder) | `SUPER + E` | `app.files` |
| `CTRL + ALT + V` | `⌃ ⌘L V` | `app.audioSettings` |  | audio settings (Sound settings pane) | `CTRL + ALT + V` | `app.audioSettings` |

## Capture

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `Print` | `⌥L ⇧ ⌘L 4` / `F13` | `capture.region` |  | region screenshot (macOS ⇧⌘4 with Super held; SUPER + SHIFT + 4 is taken by ws.moveSilent.4) | `SUPER + ALT + SHIFT + 4` / `F13` | `capture.region` |
| `SHIFT + Print` | `⌥L ⇧ ⌘L 3` / `⇧ F13` | `capture.full` | locked | full-screen screenshot (macOS ⇧⌘3 with Super held; SUPER + SHIFT + 3 is taken by ws.moveSilent.3) | `SUPER + ALT + SHIFT + 3` / `SHIFT + F13` | `capture.full` |
| `SUPER + SHIFT + S` | `⌥L ⇧ S` | `capture.freeze` |  | region screenshot on a frozen screen | `SUPER + SHIFT + S` | `capture.freeze` |
| `CTRL + ALT + R` | `⌃ ⌘L R` | `record.screen` |  | record the screen | `CTRL + ALT + R` | `record.screen` |
| `SUPER + ALT + R` | `⌥L ⌘L R` | `record.sound` |  | record the screen with sound | `SUPER + ALT + R` | `record.sound` |
| `SUPER + ALT + SHIFT + R` | `⌥L ⇧ ⌘L R` | `record.region` |  | record a region | `SUPER + ALT + SHIFT + R` | `record.region` |
| `SUPER + SHIFT + C` | `⌥L ⇧ C` | `picker.color` |  | color picker (copies the hex value) | `SUPER + SHIFT + C` | `picker.color` |

## Media / volume / brightness

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `XF86MonBrightnessUp` | `Brightness Up` | `brightness.up` | locked | brightness up, with OSD (F2) | `BrightnessUp` | `brightness.up` |
| `XF86MonBrightnessDown` | `Brightness Down` | `brightness.down` | locked | brightness down, with OSD (F1) | `BrightnessDown` | `brightness.down` |
| `SUPER + CTRL + Space` / `XF86AudioPlay` / `XF86AudioPause` | `⌃ ⌥L Space` / `Play` / `Pause` | `media.playPause` | locked | media play / pause (F8) | `CTRL + SUPER + Space` / `Play` / `Pause` | `media.playPause` |
| `SUPER + CTRL + Equal` / `XF86AudioNext` | `⌃ ⌥L =` / `Next` | `media.next` | locked | media next (F9) | `CTRL + SUPER + Equal` / `Next` | `media.next` |
| `SUPER + CTRL + Minus` / `XF86AudioPrev` | `⌃ ⌥L -` / `Previous` | `media.prev` | locked | media previous (F7) | `CTRL + SUPER + Minus` / `Previous` | `media.prev` |
| `SUPER + CTRL + Backspace` / `XF86AudioStop` | `⌃ ⌥L ⌫` / `Stop` | `media.stop` | locked | media stop | `CTRL + SUPER + Backspace` / `Stop` | `media.stop` |
| `SUPER + SHIFT + M` / `XF86AudioMute` | `⌥L ⇧ M` / `Mute` | `audio.toggleMute` | locked | toggle output mute (F10) | `SUPER + SHIFT + M` / `Mute` | `audio.toggleMute` |
| `XF86AudioMicMute` | `⌃ ⌥L ⇧ M` | `audio.toggleMicMute` | locked | toggle microphone mute (no mic key on most Macs) | `SUPER + CTRL + SHIFT + M` | `audio.toggleMicMute` |
| `XF86AudioRaiseVolume` | `Volume Up` | `audio.volumeUp` | locked, repeat | volume +10% (max 100%, unmutes), with OSD (F12) | `VolumeUp` | `audio.volumeUp` |
| `XF86AudioLowerVolume` | `Volume Down` | `audio.volumeDown` | locked, repeat | volume −10% (unmutes), with OSD (F11) | `VolumeDown` | `audio.volumeDown` |
| `Caps_Lock` | `⇪` | `osd.lockKey(key=caps)` | locked, release | Caps Lock OSD (the key itself is passed through: Hyprland non_consuming + ignore_mods) | `CapsLock` | `osd.capsLock` |
| `Num_Lock` | `⌧` | `osd.lockKey(key=num)` | locked, release | Num Lock OSD (Clear on an external keypad; passed through like Caps Lock) | `KeypadClear` | `osd.numLock` |

## Session / utilities

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| `SUPER + SHIFT + L` | `⌥L ⇧ L` | `system.sleep` | locked | sleep (pmset sleepnow) | `SUPER + SHIFT + L` | `system.sleep` |
|  | `⌥L ⇧ B` | `menuBar.peek` |  | show Apple's menu bar for 5 seconds | `SUPER + SHIFT + B` | `menuBar.peek` |
| `SUPER + V` | `⌥L V` | `clipboard.open` |  | clipboard history picker | `SUPER + V` | `clipboard.open` |
| `SUPER + ALT + V` | `⌥L ⌘L V` | `clipboard.delete` |  | delete from the clipboard history | `SUPER + ALT + V` | `clipboard.delete` |
| `CTRL + ALT + SHIFT + V` | `⌃ ⇧ ⌘L V` | `clipboard.typeLatest` | locked | type the latest clipboard item after 0.5 s (for fields that block paste) | `CTRL + ALT + SHIFT + V` | `clipboard.typeLatest` |
| `SUPER + Period` | `⌥L .` | `emoji.open` |  | emoji picker | `SUPER + Period` | `emoji.open` |
| `SUPER + ALT + F12` | `⌥L ⌘L F12` | `notify.test` |  | send a test notification | `SUPER + ALT + F12` | `notify.test` |

## Safety

| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |
|---|---|---|---|---|---|---|
| — | `⌃ ⌥L ⇧ ⌘L ⎋` | `wm.panic` |  | fixed; cannot be removed | `CTRL + SUPER + ALT + SHIFT + Escape` | `wm.panic` |

## Modifier presets

Pick one in Settings; each preset is just a different `[modifiers]` table in `keymap.toml`. The binds above stay the same, only the physical keys change.

| Preset | SUPER | ALT | Summary |
|---|---|---|---|
| A. Option is Super (default) | ⌥L | ⌘L | Left Option acts as the Linux Super key and Left Command as Alt. The right-hand keys keep their normal meaning, so Option characters (æ ø å @ £ $ { } [ ] \| \ …) still type with Right Option and Right Command stays a normal ⌘. |
| B. Caps Lock is Hyper | ⇪ | ⌥L | Caps Lock becomes the Super key through a user-level hidutil remap (Caps Lock → F18, which the window manager treats as a modifier). Left Option is Alt. Both Option keys type characters as usual. |
| C. Command is Super | ⌘L | ⌥L | Left Command is Super and Left Option is Alt, like other Mac window managers. Right Command stays a normal ⌘ for app shortcuts. |
| D. Custom | — | — | Pick any physical key for each Linux modifier in keymap.toml ([modifiers]). |

**Option is Super**

- A tap of Left Option alone opens the launcher.
- Left Command shortcuts such as ⌘L+Tab are not taken over by default (see "Take over ⌘Tab").

**Caps Lock is Hyper**

- Reversible and needs no root; the mapping is re-applied at login because hidutil resets on reboot.
- Caps Lock itself is no longer available; use Shift for capitals.
- A tap of Caps Lock alone opens the launcher.

**Command is Super**

- Binds on ⌘L+Q/W/T/C/V/X/Z/S/F/,/. shadow those app shortcuts while the window manager runs; the conflict checker lists every one of them.
- ⌘L+Space clashes with Spotlight and ⌘L+Tab with the app switcher unless those are changed.

**Custom**

- Available keys: lopt (⌥L), ropt (⌥R), opt (⌥), lcmd (⌘L), rcmd (⌘R), cmd (⌘), lctrl (⌃L), rctrl (⌃R), ctrl (⌃), lshift (⇧L), rshift (⇧R), shift (⇧), capslock (⇪), fn (fn).
- Side-specific keys (lopt, lcmd, …) leave the other side free for typing.

Preset B remaps Caps Lock to F18 with a user-level `hidutil` mapping (reversible, no root, re-applied at login):

```
hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'
```

Undo it with `hidutil property --set '{"UserKeyMapping":[]}'`.

## Trackpad gestures

Gestures are **off** by default (`[gestures]` in `keymap.toml`): macOS uses 3- and 4-finger swipes for Spaces and Mission Control, so turn those off in System Settings › Trackpad first.

| Gesture | Action |
|---|---|
| 4-finger swipe left / right | previous / next workspace |
| 3-finger swipe up | open the special workspace |
| 3-finger swipe down | toggle the special workspace closed |
| 4-finger swipe down | sleep |

## Safety

`CTRL + SUPER + ALT + SHIFT + Escape` (physically ⌃⌥⌘⇧Esc) is the panic chord: it stops tiling and brings every window back on screen. It cannot be removed; the parser restores it if the keymap lacks it.
