# Fonts

SkyRose uses the fonts of Gabby's Arch desktop (`Tests/fixtures/ref/fonts.txt`, Caelestia's
`appearance.font` defaults). They are **fetched, not committed**: `FontPack`
(`Sources/CaelestiaCore/Fonts/FontPack.swift`) pins each file to an upstream tag or commit and a
SHA-256 sum; a download that does not match is discarded.

| Family | Used for | Files | Licence | Pinned source |
|---|---|---|---|---|
| Rubik | bar, shell and Settings text (`appearance.fontSans`) | `Rubik[wght].ttf` (variable) | SIL OFL 1.1 | google/fonts @ `8b0a1d0` |
| Inter | text fallback | `Inter[opsz,wght].ttf` | SIL OFL 1.1 | google/fonts @ `0b58fb3` |
| CaskaydiaCove Nerd Font | shell numbers/code (`appearance.fontMono`) | Regular, Bold | SIL OFL 1.1 (Cascadia Code by Microsoft; renamed by Nerd Fonts because "Cascadia Code" is a Reserved Font Name) | ryanoasis/nerd-fonts `v3.4.0` |
| JetBrainsMono Nerd Font | kitty (`apps.kittyFont`) | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 | ryanoasis/nerd-fonts `v3.4.0` |
| Material Symbols Rounded | Caelestia's icon font | variable | Apache 2.0 | google/material-design-icons @ `10ecc14` |

All five allow redistribution, so bundling them later (installer phase) is allowed too; each
family's licence text is downloaded next to it.

## How they are used

- **Download** (Settings › Appearance › Fonts, or `skyrose fonts download`; ~32 MB): files go to
  `~/Library/Application Support/SkyRose/Fonts`.
- **SkyRose only**: the WM and Settings register the downloaded files for their own process at
  start (and the WM again on `skyrose config reload`), so the bar, shell and Settings draw in Rubik
  and CaskaydiaCove with nothing installed system-wide.
- **Install for kitty and other apps** (explicit button, or `skyrose fonts install`): copies the
  files into `~/Library/Fonts` (no admin rights). Files already there are not touched; what was
  copied is listed in `Fonts/installed.json` and journalled (`kind: font`).
  `skyrose fonts uninstall` removes exactly those files.
- **kitty**: Settings › Terminal › kitty setup › Font picks JetBrainsMono or CaskaydiaCove for
  `skyrose.conf` (`apps.kittyFont`, `apps.kittyFontSize`).

The shell still draws its icons with SF Symbols: Material Symbols is fetched and licensed, but
the icon views have not been switched to it (see LIMITATIONS).
