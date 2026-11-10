# Focus

Two behaviours, both on by default. They do not chase each other.

## Cursor follows focus

A focus change that SkyRose made moves the pointer onto that window. That covers keyboard focus
(left, right, up, down), a workspace switch, the launcher opening an app, and focus moving
because a window closed.

`cursorFollowsFocus` defaults to on. `cursorWarpMode` is `center` (the middle of the window) or
`last` (the last point that was inside that window).

The pointer stays where it is when:

- focus changed because of a click or a hover
- a mouse button is held, or a drag or resize is in progress
- the window is not on a display you can see
- the pointer is already inside the window

The warp disconnects the hardware mouse, moves, then reconnects, and ignores focus changes from
that move for 80 ms.

## Focus follows mouse

Hovering a tiled or floating window focuses it after `focusFollowsMouseDelayMs` (default 100,
from 0 to 5000). Moving inside the same window does not restart the wait. `raiseOnHover`
defaults to off, so a floating window is focused and left where it is in the stack. macOS raises
a window when it becomes focused, so SkyRose puts the windows that were already in front back,
front-most last.

Hover does not take focus during a drag, while a button is held, just after a warp, over a
password field, an open menu, a visible sheet, the menu bar, a SkyRose drawer or popout,
Spotlight, the launcher, or a fullscreen window on another Space. A fully transparent window is
not treated as the window under the pointer.

Settings › Windows has both, including the delay, raise-on-hover, and a two-tile demo.

## Menu bar

Settings › Appearance: Shown, Auto-hide, or Off. Off stops reserving the bar. The notch stays.
With SIP on, the pointer at the top edge can still reveal Apple's bar. ⌥L⇧B
(`menuBar.peek`) shows it for 5 seconds.
