import Darwin
import Foundation

/// Where app addons live and how SkyRose starts and stops them. App addons always run as their
/// own process (their own TCC identity: they inherit none of SkyRose's permissions).
///
///     addons/<id>/<version>/      the verified bundle (manifest, source archive)
///     addons/<id>/app/<Name>.app  the built app (stable path across updates)
///     addons/<id>/deps/           pinned downloads the app uses at run time
///     addons/<id>/bin/            command-line helpers
///     addons/<id>/build/          the build folder (removed after a good build)
///     ~/Library/LaunchAgents/<bundleID>.plist   only with `launchAgent` + the `login` permission
public struct AppHost: Sendable {
    public var root: URL
    public var home: URL
    /// false = never call launchctl (tests and isolated `SKYROSE_HOME` runs); plists are still written.
    public var live: Bool

    public init(root: URL, home: URL = Paths.home, live: Bool = Paths.isLiveHome) {
        self.root = root
        self.home = home
        self.live = live
    }

    public func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    public func appURL(_ id: String, _ app: AppEntry) -> URL {
        folder(id).appendingPathComponent("app", isDirectory: true).appendingPathComponent(app.appFolderName, isDirectory: true)
    }
    public func executableURL(_ id: String, _ app: AppEntry) -> URL {
        appURL(id, app).appendingPathComponent("Contents/MacOS/\(app.executable)")
    }
    public func depsURL(_ id: String) -> URL { folder(id).appendingPathComponent("deps", isDirectory: true) }
    public func binURL(_ id: String) -> URL { folder(id).appendingPathComponent("bin", isDirectory: true) }
    public func launchAgentURL(_ app: AppEntry) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(app.bundleID).plist")
    }
    public func logURL(_ id: String) -> URL { home.appendingPathComponent("Library/Logs/SkyRose/addons/\(id).log") }

    /// The manifest of an installed addon's current version.
    public func manifest(_ a: InstalledAddon) -> AddonManifest? {
        let url = folder(a.id).appendingPathComponent(a.version, isDirectory: true).appendingPathComponent(AddonManifest.fileName)
        return (try? Data(contentsOf: url)).flatMap { try? AddonManifest.decode($0) }
    }

    // MARK: Start / stop

    /// Writes the LaunchAgent (when declared and allowed) and loads it, which starts the app.
    public func activate(_ a: InstalledAddon) {
        guard a.enabled, a.setup == InstalledAddon.setupReady, let m = manifest(a), let app = m.entry.app else { return }
        guard app.launchAgent == true, a.permissions.contains("login") else { return }
        let exe = executableURL(a.id, app)
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { return }
        let plist: [String: Any] = [
            "Label": app.bundleID,
            "ProgramArguments": [exe.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": logURL(a.id).path,
            "StandardErrorPath": logURL(a.id).path,
            "EnvironmentVariables": ["SKYROSE_ADDON_ID": a.id, "SKYROSE_ADDON_DIR": folder(a.id).path],
        ]
        let url = launchAgentURL(app)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logURL(a.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: url, options: .atomic)
        guard live else { return }
        _ = AddonBundle.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(app.bundleID)"])
        _ = AddonBundle.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", url.path])
    }

    /// Stops the app and unloads its LaunchAgent. `removeAgent` also deletes the plist so it does
    /// not start at the next login (disable, panic, revoke, uninstall). `wait: false` never blocks
    /// longer than a signal (the panic path).
    public func deactivate(_ a: InstalledAddon, removeAgent: Bool, wait: Bool = true) {
        guard let m = manifest(a), let app = m.entry.app else { return }
        let agent = launchAgentURL(app)
        if live, FileManager.default.fileExists(atPath: agent.path) {
            _ = AddonBundle.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(app.bundleID)"])
        }
        if removeAgent { try? FileManager.default.removeItem(at: agent) }
        stop(a.id, app, wait: wait)
    }

    /// The declared quit command first (when waiting), then SIGTERM, then SIGKILL, for every
    /// process whose executable is inside this addon's `.app`.
    /// Stops the app and anything it started from its addon folder (a pinned runtime in `deps/`,
    /// such as a model server): the declared quit command first, then SIGTERM, then SIGKILL.
    public func stop(_ id: String, _ app: AppEntry, wait: Bool = true) {
        let exe = executableURL(id, app)
        let scope = folder(id)
        if wait, let args = app.stop, FileManager.default.isExecutableFile(atPath: exe.path), !Self.pids(inside: appURL(id, app)).isEmpty {
            _ = Self.run(exe.path, args, timeout: 5)
            for _ in 0..<30 where !Self.pids(inside: scope).isEmpty { usleep(100_000) }
        }
        let pids = Self.pids(inside: scope)
        for p in pids { kill(p, SIGTERM) }
        guard wait, !pids.isEmpty else { return }
        for _ in 0..<20 where !Self.pids(inside: scope).isEmpty { usleep(100_000) }
        for p in Self.pids(inside: scope) { kill(p, SIGKILL) }
    }

    public func isRunning(_ id: String, _ app: AppEntry) -> Bool { !Self.pids(inside: folder(id)).isEmpty }

    /// This user's processes whose executable lives inside `bundle`.
    public static func pids(inside bundle: URL) -> [pid_t] {
        // realpath, not resolvingSymlinksInPath: that one strips /private, proc_pidpath keeps it.
        guard let real = realpath(bundle.path, nil) else { return [] }
        let prefix = String(cString: real) + "/"
        free(real)
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        var list = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size + 16)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &list, Int32(list.count * MemoryLayout<pid_t>.size))
        let n = Int(bytes) / MemoryLayout<pid_t>.size
        var out: [pid_t] = []
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let me = getuid()
        for pid in list.prefix(n) where pid > 0 && pid != getpid() {
            var info = proc_bsdshortinfo()
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdshortinfo>.size)) > 0, info.pbsi_uid == me else { continue }
            guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { continue }
            let path = String(cString: buf)
            if path.hasPrefix(prefix) { out.append(pid) }
        }
        return out
    }

    /// Runs a tool with a timeout; stdout and stderr together.
    @discardableResult
    static func run(_ exe: String, _ args: [String], timeout: TimeInterval, cwd: URL? = nil, env: [String: String]? = nil) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        if let env { p.environment = env }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "\(error)") }
        let deadline = DispatchTime.now() + timeout
        let done = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        DispatchQueue.global().async { box.data = pipe.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: deadline) == .timedOut { p.terminate(); _ = done.wait(timeout: .now() + 2) }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: box.data, as: UTF8.self))
    }
}
