import Foundation

// `caelestia` — command-line client for Caelestia for Mac (spec 4.8). Replaces `hyprctl` and the
// Linux `caelestia` CLI: every verb either talks to the WM over the IPC socket or runs locally
// (keys check/list, doctor, uninstall, shell -d).
//
// Exit codes: 0 ok, 1 command failed, 2 WM not running, 3 usage error.

let app = CLIApp(arguments: Array(CommandLine.arguments.dropFirst()))
exit(app.run())
