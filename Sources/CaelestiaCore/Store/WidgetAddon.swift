import Foundation

/// A widget addon's script (kind `widget`): `{ "script": "widget.py", "interpreter": "python3" }`.
/// SkyRose runs it as its own process under `sandbox-exec` (``WidgetSandbox``) and talks to it in
/// JSON lines over stdin/stdout (``WidgetMessage``). See docs/skystore-security.md.
public struct WidgetEntry: Codable, Equatable, Sendable {
    /// Bundle path of the script.
    public var script: String
    /// `sh`, `zsh` or `python3`. No binaries: a script can be reviewed in the index repo.
    public var interpreter: String
    public init(script: String, interpreter: String) {
        self.script = script
        self.interpreter = interpreter
    }

    public static let interpreters = ["sh", "zsh", "python3"]

    func issues(files: [String: String]) -> [String] {
        var out: [String] = []
        if !Self.interpreters.contains(interpreter) {
            out.append("entry.widget.interpreter must be one of \(Self.interpreters.joined(separator: ", ")) (got \"\(interpreter)\")")
        }
        if !AddonManifest.isSafePath(script) { out.append("path '\(script)' must be relative, inside the bundle, without '..'") }
        else if files[script] == nil { out.append("entry.widget.script '\(script)' is not in files (run skyrose store pack)") }
        return out
    }
}

/// The `sandbox-exec` profile a widget runs under: deny by default; read the system but not the
/// home folder (only its own addon folder there); write only its `data` folder; run a short list
/// of shell tools and its interpreter; no network, no Apple Events, no other Mach services, so no
/// SkyRose IPC socket either.
public enum WidgetSandbox {
    /// Tools a script may run besides `/bin/*` (no `open`, `osascript`, `curl`).
    public static let tools = ["env", "date", "awk", "sed", "grep", "head", "tail", "cut", "tr", "wc", "sort", "uniq",
                               "printf", "basename", "dirname", "uptime", "pmset", "sw_vers"]

    /// Paths are resolved first: the sandbox matches real paths (`/var` is `/private/var`).
    public static func profile(addonDir: URL, dataDir: URL, home: URL, interpreterDir: URL?) -> String {
        // realpath, not resolvingSymlinksInPath (which turns /private/var back into /var).
        func real(_ u: URL) -> URL { realpath(u.path, nil).map { p in defer { free(p) }; return URL(fileURLWithPath: String(cString: p)) } ?? u }
        let (addonDir, dataDir, home) = (real(addonDir), real(dataDir), real(home))
        let interpreterDir = interpreterDir.map(real)
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let exec = ["(subpath \"/bin\")"] + tools.map { "(literal \(q("/usr/bin/" + $0)))" } + (interpreterDir.map { ["(subpath \(q($0.path)))"] } ?? [])
        return """
        (version 1)
        (deny default)
        (allow process-fork)
        (allow process-exec \(exec.joined(separator: " ")))
        (allow file-read* (subpath "/"))
        (deny file-read* (subpath \(q(home.path))))
        (allow file-read* (subpath \(q(addonDir.path))) (subpath \(q(dataDir.path))))
        (allow file-read-metadata)
        (allow file-write* (subpath \(q(dataDir.path))) (literal "/dev/null"))
        (allow sysctl-read)
        """
    }
}

/// One line between SkyRose and a widget. The widget writes:
///
///     {"set": {"text": "21 °C", "icon": "sunny", "title": "Weather"}}   its card (no permission)
///     {"toast": {"title": "Done", "message": "…"}}                      needs `notifications`
///     {"get": "media"}                                                   needs `media`
///
/// SkyRose writes `{"event": "click"}`, `{"media": {...}}` and `{"error": "…"}`.
public enum WidgetMessage: Equatable, Sendable {
    case set(title: String?, text: String, icon: String?)
    case toast(title: String, message: String)
    case getMedia

    public static let maxLine = 16 * 1024
    public static let maxText = 300

    /// nil for anything that is not a known, well-formed call.
    public static func parse(_ line: String) -> WidgetMessage? {
        guard line.utf8.count <= maxLine, let data = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o.count == 1 else { return nil }
        func clip(_ s: String?) -> String? { s.map { String($0.prefix(maxText)) } }
        if let s = o["set"] as? [String: Any], let text = s["text"] as? String {
            return .set(title: clip(s["title"] as? String), text: clip(text)!, icon: clip(s["icon"] as? String))
        }
        if let t = o["toast"] as? [String: Any], let title = t["title"] as? String {
            return .toast(title: clip(title)!, message: clip(t["message"] as? String) ?? "")
        }
        if o["get"] as? String == "media" { return .getMedia }
        return nil
    }

    /// The permission this call needs (nil: always allowed).
    public var permission: AddonPermission.Name? {
        switch self {
        case .set: return nil
        case .toast: return .notifications
        case .getMedia: return .media
        }
    }

    /// One JSON line for the widget.
    public static func line(_ object: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}\n" }
        return String(decoding: d, as: UTF8.self) + "\n"
    }
}

/// Stopping widget processes from outside the WM (panic in the CLI, uninstall): every process
/// whose command line has the addon's folder in it, which is the sandbox-exec + interpreter + script.
public enum WidgetProcesses {
    public static func kill(addonFolder: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", NSRegularExpression.escapedPattern(for: addonFolder.path + "/")]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
