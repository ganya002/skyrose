import AppKit

/// Where SkyRose.app is. Never by bundle id alone: Launch Services also knows copies in other
/// accounts' homes (an installer test left /Users/testuser/Applications/SkyRose.app), and
/// `open -b com.skyrose.mac` started that one instead of the user's own.
public enum SkyRoseApp {
    public static let bundleID = "com.skyrose.mac"

    /// The SkyRose.app that contains `executable` (the CLI, the WM) or sits next to its app
    /// (Settings), else ~/Applications, /Applications, else Launch Services' pick — skipping any
    /// copy in another user's home.
    public static func locate(near executable: URL? = Bundle.main.executableURL) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [URL] = []
        if let exe = executable?.resolvingSymlinksInPath() {
            // …/X.app/Contents/MacOS/exe
            let app = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            candidates += [app, app.deletingLastPathComponent().appendingPathComponent("SkyRose.app")]
        }
        candidates += [URL(fileURLWithPath: home + "/Applications/SkyRose.app"), URL(fileURLWithPath: "/Applications/SkyRose.app")]
        if let ls = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { candidates.append(ls) }
        return candidates.first { !inOtherHome($0.path, home: home) && Bundle(url: $0)?.bundleIdentifier == bundleID }
    }

    /// `/Users/<someone else>/…`: that account's copy, with its own files and permissions.
    static func inOtherHome(_ path: String, home: String) -> Bool {
        path.hasPrefix("/Users/") && !(path + "/").hasPrefix(home + "/")
    }
}
