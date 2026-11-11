# Window manager migration to CatWMKit

Status (Nov 11, 2026): **blocked**, nothing migrated. The old SkyRose WM is untouched. See
`docs/catwm-requests.md`: CatWMKit's public API can't leave SkyRose's parked workspace windows alone.

Each SkyRose WM action, the CatWM command it would map to, and whether it was verified live.
"none" means SkyRose keeps its own implementation or CatWM needs a change (request number in brackets).

| SkyRose action / CLI | CatWM command | Verified live |
|---|---|---|
| `workspace.focus` / `ws focus <n>` | `workspace <n>` (macOS Desktops only) [1] | no |
| `workspace.next` / `.prev` | `workspace +1` / `-1` [1] | no |
| `workspace.move` / `ws move <n>` | `movetoworkspace <n>` [1] | no |
| `workspace.moveSilent` / `ws move <n> --silent` | `movetoworkspacesilent <n>` [1] | no |
| `workspace.focusGroup`, `.moveGroup`, `.nextGroup`, `.prevGroup` | none (SkyRose groups of 10) [1] | no |
| `workspace.moveToNext` / `.moveToPrev` | `movetoworkspace +1` / `-1` [1] | no |
| `special.toggle`, `workspace.moveToSpecial`, `.moveOutOfSpecial` / `ws toggle-special` | none [5] | no |
| `window.focus <dir>` / `window focus` | `movefocus <dir>` | no |
| `window.swap <dir>` / `window move` | `swapwindow <dir>` | no |
| `window.cycleNext` / `.cyclePrev` | `cyclenext next` / `prev` | no |
| `window.resize <axis> <delta>` | `splitratio` (main pane only) [5] | no |
| `window.drag`, `window.resizeDrag` (mouse) | `input.mouse` (swap / resize) | no |
| `window.toggleFloat` / `window float` | `togglefloating` [2] | no |
| `window.fullscreen` | `nativefullscreen` | no |
| `window.maximize` | `fullscreen` (CatWM fullscreen fills the screen inside the tiling) | no |
| `window.close` / `window close` | `killactive` | no |
| `window.center` / `window center` | none (SkyRose, floating only) [5] | no |
| `window.pin` / `window pin` | none (SkyRose, floating only) [5] | no |
| `window.pip` | none (SkyRose, floating only) | no |
| `window.pseudo` / `window pseudo` | none [5] | no |
| `layout.toggleSplit` / `window togglesplit` | none [4] | no |
| `layout.swapSplit` / `window swapsplit` | `layoutmsg swapsides` (master layouts only) [4] | no |
| `window.normalize` | `retile` | no |
| `group.toggle` | `moveintogroup <dir>` (needs `windows.tabGroups`) | no |
| `group.moveOut` | `moveoutofgroup` | no |
| `group.next` / `.prev` | `changegroupactive next` / `prev` | no |
| `group.lock` | none [5] | no |
| `wm.panic` / `skyrose wm panic` | `engine.stop()` puts parked windows back; SkyRose's own restore stays | no |
| `skyrose rules`, rules.toml, `[appRules]` | `floating.listedAppsFloat` covers float rules only; workspace rules need [1], [2] | no |
