import CaelestiaCore
import Foundation

/// One widget's card in the sidebar.
public struct WidgetCard: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var title: String?
    public var text: String = ""
    public var icon: String?
    /// Shown instead of `text` while it is not running ("starting", "stopped: …").
    public var status: String?
}

/// Runs the enabled widget addons, each as its own sandboxed process (docs/skystore-security.md),
/// and brokers their calls: a call is answered only when the widget declared its permission.
/// Follows `state.json` (install, off, panic, revocation from the Store drawer or the CLI).
@MainActor
public final class WidgetHost {
    public var onChange: ([WidgetCard]) -> Void = { _ in }
    public var onToast: (_ widget: String, _ title: String, _ message: String) -> Void = { _, _, _ in }
    public var media: () -> MediaInfo = { MediaInfo() }

    let store: AddonStore
    private var runners: [String: Runner] = [:]
    private var cards: [String: WidgetCard] = [:]
    private var seen: Date??
    private var timer: Timer?
    private static let python: (exe: URL, dir: URL)? = {
        func run(_ exe: String, _ args: [String]) -> (status: Int32, out: String) {
            let p = Process(), out = Pipe()
            p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
            p.standardOutput = out; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return (-1, "") }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        // The /usr/bin/python3 shim runs xcodebuild, which the sandbox refuses: run the real one.
        let r = run("/usr/bin/xcrun", ["-f", "python3"])
        let dev = run("/usr/bin/xcode-select", ["-p"])
        let exe = r.out.trimmingCharacters(in: .whitespacesAndNewlines), dir = dev.out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.status == 0, dev.status == 0, !exe.isEmpty, !dir.isEmpty else { return nil }
        return (URL(fileURLWithPath: exe), URL(fileURLWithPath: dir))
    }()

    public init(store: AddonStore = AddonStore()) { self.store = store }

    public func start() {
        reconcile()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileIfChanged() }
        }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        for r in runners.values { r.stop() }
        runners = [:]; cards = [:]
        publish()
    }

    public func click(_ id: String) { runners[id]?.send(["event": "click"]) }

    private func reconcileIfChanged() {
        let now = store.stateModified
        if seen == nil || seen! != now { reconcile() }
    }

    func reconcile() {
        seen = .some(store.stateModified)
        let wanted = store.enabledWidgets()
        let keys = Set(wanted.map { "\($0.addon.id)@\($0.addon.version)" })
        for (key, r) in runners where !keys.contains(key) {
            r.stop()
            runners[key] = nil
            cards[r.id] = nil
        }
        for w in wanted where runners["\(w.addon.id)@\(w.addon.version)"] == nil {
            var card = WidgetCard(id: w.addon.id, name: w.addon.name, status: "starting")
            let interpreter: (exe: URL, dir: URL?)?
            switch w.widget.interpreter {
            case "sh": interpreter = (URL(fileURLWithPath: "/bin/sh"), nil)
            case "zsh": interpreter = (URL(fileURLWithPath: "/bin/zsh"), nil)
            case "python3": interpreter = Self.python.map { ($0.exe, $0.dir) }
            default: interpreter = nil
            }
            guard let interpreter else {
                card.status = w.widget.interpreter == "python3" ? "needs python3 (the Xcode Command Line Tools)" : "unknown interpreter"
                cards[w.addon.id] = card
                continue
            }
            cards[w.addon.id] = card
            let r = Runner(id: w.addon.id, dir: w.dir, data: w.data, script: w.widget.script, interpreter: interpreter.exe,
                           interpreterDir: interpreter.dir, permissions: Set(w.permissions.map(\.name)))
            r.onLine = { [weak self] line in self?.handle(line, from: r) }
            r.onExit = { [weak self] why in self?.update(r.id) { $0.status = why } }
            runners["\(w.addon.id)@\(w.addon.version)"] = r
            r.start()
        }
        publish()
    }

    private func handle(_ line: String, from r: Runner) {
        guard let msg = WidgetMessage.parse(line) else { r.send(["error": "not a known call"]); return }
        if let need = msg.permission, !r.permissions.contains(need) {
            Log.shell.notice("widget \(r.id, privacy: .public): refused \(need.rawValue, privacy: .public) call (not declared)")
            r.send(["error": "needs the \(need.rawValue) permission"])
            return
        }
        switch msg {
        case .set(let title, let text, let icon):
            update(r.id) { $0.title = title; $0.text = text; $0.icon = icon; $0.status = nil }
        case .toast(let title, let message):
            guard r.allowToast() else { r.send(["error": "toasts are limited to one every 5 s"]); return }
            onToast(cards[r.id]?.name ?? r.id, title, message)
        case .getMedia:
            let m = media()
            r.send(["media": ["available": m.available, "title": m.title, "artist": m.artist, "album": m.album,
                              "playing": m.isPlaying, "player": m.player]])
        }
    }

    private func update(_ id: String, _ edit: (inout WidgetCard) -> Void) {
        guard var c = cards[id] else { return }
        edit(&c)
        guard c != cards[id] else { return }
        cards[id] = c
        publish()
    }

    private func publish() { onChange(cards.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
}

/// One widget process: `sandbox-exec -p <profile> <interpreter> <script>` in the addon folder,
/// HOME = its data folder. Lines out are calls; stderr goes to `data/widget.log` (capped).
/// Restarts after a crash, at most 3 times in 5 minutes.
@MainActor
final class Runner {
    let id: String, dir: URL, data: URL, script: String, interpreter: URL, interpreterDir: URL?
    let permissions: Set<AddonPermission.Name>
    var onLine: (String) -> Void = { _ in }
    var onExit: (String) -> Void = { _ in }
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var stopped = false
    private var crashes: [Date] = []
    private var lastToast: Date?

    init(id: String, dir: URL, data: URL, script: String, interpreter: URL, interpreterDir: URL?, permissions: Set<AddonPermission.Name>) {
        self.id = id; self.dir = dir; self.data = data; self.script = script
        self.interpreter = interpreter; self.interpreterDir = interpreterDir; self.permissions = permissions
    }

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: data, withIntermediateDirectories: true)
        let log = data.appendingPathComponent("widget.log")
        if ((try? fm.attributesOfItem(atPath: log.path))?[.size] as? Int ?? 0) > 256 * 1024 { try? fm.removeItem(at: log) }
        if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        let profile = WidgetSandbox.profile(addonDir: dir, dataDir: data, home: fm.homeDirectoryForCurrentUser, interpreterDir: interpreterDir)
        p.arguments = ["-p", profile, interpreter.path, dir.appendingPathComponent(script).path]
        p.currentDirectoryURL = dir
        p.environment = ["PATH": "/bin:/usr/bin", "HOME": data.path, "LANG": "en_US.UTF-8", "PYTHONDONTWRITEBYTECODE": "1",
                         "SKYROSE_WIDGET": id]
        let out = Pipe(), inn = Pipe()
        p.standardOutput = out
        p.standardInput = inn
        p.standardError = (try? FileHandle(forWritingTo: log)).map { $0.seekToEndOfFile(); return $0 } ?? FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(chunk) } }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.exited(status) } }
        }
        do {
            try p.run()
            process = p
            input = inn.fileHandleForWriting
        } catch {
            onExit("could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        stopped = true
        process?.standardOutput.flatMap { ($0 as? Pipe)?.fileHandleForReading.readabilityHandler = nil }
        if let p = process, p.isRunning {
            p.terminate()
            let pid = p.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        }
        process = nil
    }

    func send(_ object: [String: Any]) {
        guard let input, process?.isRunning == true else { return }
        try? input.write(contentsOf: Data(WidgetMessage.line(object).utf8))
    }

    func allowToast() -> Bool {
        if let t = lastToast, Date().timeIntervalSince(t) < 5 { return false }
        lastToast = Date()
        return true
    }

    private func received(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { onLine(line) }
        }
        // A line longer than the limit is dropped, not buffered forever.
        if buffer.count > WidgetMessage.maxLine { buffer.removeAll() }
    }

    private func exited(_ status: Int32) {
        process = nil
        guard !stopped else { return }
        let now = Date()
        crashes = crashes.filter { now.timeIntervalSince($0) < 300 } + [now]
        if crashes.count > 3 {
            onExit("stopped: it exited \(crashes.count) times (status \(status)); see data/widget.log")
            return
        }
        onExit("restarting (exited with status \(status))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated { if self?.stopped == false { self?.start() } }
        }
    }
}
