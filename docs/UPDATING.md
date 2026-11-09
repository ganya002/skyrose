# Updating

SkyRose checks GitHub for a newer release. It never installs one by itself, and it never
downgrades.

## Check

- **Settings › About** shows the version you are running. **Check** looks at the latest release.
  **Install** appears only when a newer one exists, and nothing is downloaded until you press it.
- **Check automatically once a day** is off. Turn it on and About mentions a newer release the next
  time you open it that day. It still does not install.
- In Terminal: `skyrose update` or `skyrose update --check` only reports.
  `skyrose update --yes` downloads and installs.

## What an install does

The command downloads `SkyRose-<version>-arm64.zip` and the `.sha256` file next to it, checks the
hash, and only then runs that release's `install.sh --update`.

Update mode:

- replaces `~/Applications/SkyRose.app` and `~/Applications/SkyRose Settings.app`
- keeps `~/.config/skyrose`, the restore journal, and your wallpapers
- does not add the `~/.local/bin/skyrose` symlink
- quits SkyRose only for the copy, then opens again whichever of the two apps was running

If the checksum does not match, the release list cannot be read, or there is no network, SkyRose
says so and leaves the current install in place. The zip is not opened.

This build is signed on the build machine, not with an Apple Developer ID, and it is not notarized.
The same note is in the installer.

## Installing the first time

That is [the README](../README.md): download `install.sh`, check `install.sh.sha256`, read it, then
`sh install.sh`. Updating an existing copy does not need that dance if `skyrose update --yes` can
reach GitHub.
