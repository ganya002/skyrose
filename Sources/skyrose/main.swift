import CaelestiaIPC
import Foundation

// `skyrose` — command-line client for SkyRose (spec 4.8). Replaces `hyprctl` and the Linux
// `caelestia` CLI: every verb either talks to the WM over the IPC socket or runs locally
// (keys check/list, doctor, migrate, uninstall, shell -d).
//
// `caelestia` (a symlink in the app bundle) is a deprecated alias for one release: it works the
// same and prints a one-line notice on stderr.
//
// Exit codes: 0 ok, 1 command failed, 2 WM not running, 3 usage error.

if CLIAlias.isDeprecatedName(CommandLine.arguments.first ?? "") {
    FileHandle.standardError.write(Data((CLIAlias.deprecationNotice + "\n").utf8))
}
let app = CLIApp(arguments: Array(CommandLine.arguments.dropFirst()))
exit(app.run())
