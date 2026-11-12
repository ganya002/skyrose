import CryptoKit
import Darwin
import Foundation

/// One line of `skyrose store setup <id> --json`, read by the Store drawer.
public struct AppSetupEvent: Codable, Equatable, Sendable {
    public enum Step: String, Codable, Sendable, CaseIterable {
        case preflight, tools, download, build, bundle, activate, done, failed
    }
    public var step: Step
    public var title: String
    /// Whole setup, 0…1.
    public var fraction: Double
    public var bytes: Int64?
    public var total: Int64?
    public var bytesPerSecond: Double?
    public var eta: Double?

    public init(_ step: Step, _ title: String, fraction: Double, bytes: Int64? = nil, total: Int64? = nil, bytesPerSecond: Double? = nil, eta: Double? = nil) {
        self.step = step; self.title = title; self.fraction = fraction
        self.bytes = bytes; self.total = total; self.bytesPerSecond = bytesPerSecond; self.eta = eta
    }

    public var jsonLine: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? e.encode(self)) ?? Data(), as: UTF8.self)
    }

    /// `12.4 MB of 16.9 MB · 3.1 MB/s · 2 s left`
    public var detail: String? {
        guard let bytes, let total, total > 0 else { return nil }
        var parts = ["\(Self.size(bytes)) of \(Self.size(total))"]
        if let s = bytesPerSecond, s > 0 { parts.append("\(Self.size(Int64(s)))/s") }
        if let eta, eta.isFinite, eta >= 0 { parts.append(eta < 60 ? "\(Int(eta.rounded())) s left" : "\(Int((eta / 60).rounded())) min left") }
        return parts.joined(separator: " · ")
    }

    public static func size(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: b)
    }
}

/// Builds and starts an installed `app` addon (`skyrose store setup <id>`). Runs in the CLI
/// process, never inside the WM: the Store drawer launches it and reads its JSON lines.
///
/// 1. preflight: Apple Silicon, macOS version, free disk (before anything is written)
/// 2. tools: Xcode Command Line Tools (`xcode-select --install`, Apple's own dialog; no sudo)
/// 3. download: each pinned artefact over HTTPS, resumable, SHA-256 checked, unpacked safely
/// 4. build: the source archive from the signed bundle, `xcrun swift build -c release`
///    (no remote package dependencies allowed)
/// 5. bundle: the `.app` from the recipe, ad-hoc signed, swapped in atomically
/// 6. activate: helpers, LaunchAgent (when declared and allowed)
public final class AppInstaller: @unchecked Sendable {
    public enum Failure: Error, Equatable, LocalizedError {
        case unsupported(String), tools(String), download(String), build(String), bundle(String)
        public var errorDescription: String? {
            switch self {
            case .unsupported(let s), .tools(let s), .download(let s), .build(let s), .bundle(let s): return s
            }
        }
    }

    public let store: AddonStore
    public let host: AppHost
    /// Offer Apple's CLT dialog when the tools are missing (false: fail with instructions).
    public var installTools = true
    /// How long to wait for the CLT install to finish.
    public var toolsTimeout: TimeInterval = 45 * 60
    /// Replaced in tests (machine facts).
    public var machine = Machine.current
    let emit: (AppSetupEvent) -> Void
    private var logHandle: FileHandle?

    public struct Machine: Sendable {
        public var arm64: Bool
        public var macOS: OperatingSystemVersion
        public var freeBytes: @Sendable (URL) -> Int64?
        public static var current: Machine {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            let arm = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
            return Machine(arm64: arm, macOS: ProcessInfo.processInfo.operatingSystemVersion) { url in
                var probe = url
                while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
                let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                return v?.volumeAvailableCapacityForImportantUsage ?? v?.volumeAvailableCapacity.map(Int64.init)
            }
        }
    }

    public init(store: AddonStore, host: AppHost? = nil, emit: @escaping (AppSetupEvent) -> Void) {
        self.store = store
        self.host = host ?? AppHost(root: store.root)
        self.emit = emit
    }

    // Weights of the overall bar.
    static let spans: [AppSetupEvent.Step: ClosedRange<Double>] = [
        .preflight: 0...0.02, .tools: 0.02...0.05, .download: 0.05...0.45, .build: 0.45...0.9, .bundle: 0.9...0.97, .activate: 0.97...1,
    ]
    /// The bar never moves back (SwiftPM's task count grows while it plans).
    private var shown = 0.0
    func say(_ step: AppSetupEvent.Step, _ title: String, _ local: Double = 0, bytes: Int64? = nil, total: Int64? = nil, speed: Double? = nil, eta: Double? = nil) {
        let span = Self.spans[step] ?? 0...1
        let f = step == .done ? 1 : max(shown, span.lowerBound + (span.upperBound - span.lowerBound) * min(1, max(0, local)))
        shown = f
        let e = AppSetupEvent(step, title, fraction: f, bytes: bytes, total: total, bytesPerSecond: speed, eta: eta)
        log("[\(step.rawValue)] \(title)\(e.detail.map { " (\($0))" } ?? "")")
        emit(e)
    }

    func log(_ line: String) {
        guard let h = logHandle else { return }
        h.write(Data((ISO8601DateFormatter().string(from: Date()) + " " + line + "\n").utf8))
    }

    /// Sets up `id` (installed, kind `app`). The state says `ready` only when every step passed;
    /// a failure leaves the previous app (if any) in place and records why.
    @discardableResult
    public func setup(_ id: String) throws -> URL {
        guard let a = store.installed(id) else { throw StoreError.notFound(id) }
        guard a.kind == .app, let m = host.manifest(a), let app = m.entry.app else { throw StoreError.notInstallable("\(id) is not an app addon") }
        if a.isRevoked { throw StoreError.revoked(a.status) }
        try? FileManager.default.createDirectory(at: host.logURL(id).deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: host.logURL(id).path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: host.logURL(id))
        defer { try? logHandle?.close(); logHandle = nil }
        try? store.setSetup(id, InstalledAddon.setupPending)
        do {
            let url = try run(a, m, app)
            try store.setSetup(id, InstalledAddon.setupReady)
            if let fresh = store.installed(id) { say(.activate, "Starting \(app.appName)", 0.5); host.activate(fresh) }
            say(.done, "\(app.appName) is ready")
            return url
        } catch {
            let why = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            try? store.setSetup(id, "failed: \(why)")
            log("FAILED: \(why)")
            emit(AppSetupEvent(.failed, why, fraction: 0))
            throw error
        }
    }

    func run(_ a: InstalledAddon, _ m: AddonManifest, _ app: AppEntry) throws -> URL {
        let fm = FileManager.default
        let folder = host.folder(a.id)

        // 1. Preflight: nothing is written before these pass.
        say(.preflight, "Checking this Mac")
        guard machine.arm64 else { throw Failure.unsupported("\(app.appName) needs a Mac with Apple Silicon (M1 or newer). This Mac has an Intel processor.") }
        let os = machine.macOS
        let have = "\(os.majorVersion).\(os.minorVersion)"
        guard Updater.compare(have, app.minMacOS) != .orderedAscending else {
            throw Failure.unsupported("\(app.appName) needs macOS \(app.minMacOS) or newer; this Mac runs \(have).")
        }
        let cached = app.downloads.filter { isCached($0, a.id) }.reduce(Int64(0)) { $0 + $1.size }
        let needed = max(0, app.diskBytes - cached)
        if let free = machine.freeBytes(folder), free < needed {
            throw Failure.unsupported("Not enough free disk: \(app.appName) needs \(AppSetupEvent.size(needed)), \(AppSetupEvent.size(free)) is free.")
        }
        say(.preflight, "This Mac is supported", 1)

        // 2. Toolchain.
        if app.requires.contains("xcode-clt") { try ensureCommandLineTools() }

        // 3. Pinned downloads.
        let totalBytes = max(1, app.downloads.reduce(Int64(0)) { $0 + $1.size })
        var doneBytes: Int64 = 0
        for d in app.downloads {
            try fetch(d, id: a.id, totalBytes: totalBytes, before: doneBytes)
            doneBytes += d.size
        }
        say(.download, app.downloads.isEmpty ? "Nothing to download" : "Downloads verified", 1)

        // 4. Build from the signed source archive.
        let build = folder.appendingPathComponent("build", isDirectory: true)
        let src = build.appendingPathComponent("src", isDirectory: true)
        try? fm.removeItem(at: build)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        let archive = folder.appendingPathComponent(a.version, isDirectory: true).appendingPathComponent(app.source)
        say(.build, "Unpacking the source")
        try Self.untar(archive, into: src)
        for d in app.downloads where d.into.hasPrefix("source/") {
            let dest = src.appendingPathComponent(String(d.into.dropFirst("source/".count)))
            try? fm.removeItem(at: dest)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard AddonBundle.run("/usr/bin/ditto", [cacheURL(d, a.id).path, dest.path]).status == 0 else { throw Failure.build("Could not place \(d.title) in the source tree") }
        }
        let env = buildEnvironment()
        say(.build, "Checking the package")
        let dump = AppHost.run("/usr/bin/xcrun", ["swift", "package", "dump-package"], timeout: 300, cwd: src, env: env)
        guard dump.status == 0, let json = try? JSONSerialization.jsonObject(with: Data(dump.out.utf8.drop { $0 != UInt8(ascii: "{") })) as? [String: Any] else {
            log(dump.out); throw Failure.build("The package manifest could not be read (see \(host.logURL(a.id).path))")
        }
        guard (json["dependencies"] as? [Any] ?? []).isEmpty else { throw Failure.build("The package has remote dependencies; SkyStore builds only self-contained sources.") }
        for (i, product) in app.products.enumerated() {
            try swiftBuild(product, cwd: src, env: env, index: i, of: app.products.count)
        }
        let bin = AppHost.run("/usr/bin/xcrun", ["swift", "build", "-c", "release", "--show-bin-path"], timeout: 120, cwd: src, env: env)
        let binDir = URL(fileURLWithPath: bin.out.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "", isDirectory: true)
        guard bin.status == 0, fm.fileExists(atPath: binDir.appendingPathComponent(app.executable).path) else { throw Failure.build("The build produced no \(app.executable)") }

        // 5. The .app.
        say(.bundle, "Assembling \(app.appFolderName)")
        let appsDir = folder.appendingPathComponent("app", isDirectory: true)
        let staging = appsDir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let bundle = staging.appendingPathComponent(app.appFolderName, isDirectory: true)
        try fm.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: bundle.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        let plistData = try Data(contentsOf: src.appendingPathComponent(app.infoPlist))
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else { throw Failure.bundle("Info.plist is not a dictionary") }
        guard plist["CFBundleIdentifier"] as? String == app.bundleID else { throw Failure.bundle("Info.plist CFBundleIdentifier must be \(app.bundleID)") }
        guard plist["CFBundleExecutable"] as? String == app.executable else { throw Failure.bundle("Info.plist CFBundleExecutable must be \(app.executable)") }
        try plistData.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try fm.copyItem(at: binDir.appendingPathComponent(app.executable), to: bundle.appendingPathComponent("Contents/MacOS/\(app.executable)"))
        for c in app.copy {
            let from: URL
            if c.from.hasPrefix("build:") { from = binDir.appendingPathComponent(String(c.from.dropFirst(6))) }
            else if c.from.hasPrefix("source:") { from = src.appendingPathComponent(String(c.from.dropFirst(7))) }
            else { from = host.depsURL(a.id).appendingPathComponent(String(c.from.dropFirst(5))) }
            guard Self.isInside(from, of: [src, binDir, host.depsURL(a.id)]), fm.fileExists(atPath: from.path) else { throw Failure.bundle("Missing \(c.from)") }
            let to = bundle.appendingPathComponent(c.to)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard AddonBundle.run("/usr/bin/ditto", [from.path, to.path]).status == 0 else { throw Failure.bundle("Could not copy \(c.from)") }
        }
        try Self.refuseEscapingLinks(bundle)
        say(.bundle, "Signing \(app.appFolderName) (ad hoc)", 0.6)
        let sign = AppHost.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", "--timestamp=none", bundle.path], timeout: 300)
        guard sign.status == 0, AppHost.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle.path], timeout: 300).status == 0 else {
            log(sign.out); throw Failure.bundle("Code signing failed")
        }
        // Swap: stop the running copy, move the new one in, drop the old one.
        let dest = host.appURL(a.id, app)
        host.stop(a.id, app)
        let old = appsDir.appendingPathComponent(".old-\(UUID().uuidString)", isDirectory: true)
        if fm.fileExists(atPath: dest.path) { try fm.moveItem(at: dest, to: old) }
        do { try fm.moveItem(at: bundle, to: dest) } catch {
            if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: dest) }
            throw Failure.bundle("Could not install \(dest.path): \(error.localizedDescription)")
        }
        try? fm.removeItem(at: old)
        say(.bundle, "\(app.appFolderName) installed", 1)

        // 6. Helpers.
        let binOut = host.binURL(a.id)
        try? fm.removeItem(at: binOut)
        for c in app.cli ?? [] {
            try fm.createDirectory(at: binOut, withIntermediateDirectories: true)
            let to = binOut.appendingPathComponent(c.to)
            try fm.copyItem(at: src.appendingPathComponent(String(c.from.dropFirst(7))), to: to)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: to.path)
        }
        try? fm.removeItem(at: build)
        return dest
    }

    // MARK: Tools

    func toolsPresent() -> Bool {
        AppHost.run("/usr/bin/xcode-select", ["-p"], timeout: 20).status == 0
            && AppHost.run("/usr/bin/xcrun", ["--find", "swift"], timeout: 60).status == 0
    }

    func ensureCommandLineTools() throws {
        say(.tools, "Looking for the Xcode Command Line Tools")
        if toolsPresent() { say(.tools, "Command Line Tools found", 1); return }
        guard installTools else {
            throw Failure.tools("The Xcode Command Line Tools are missing. Run `xcode-select --install`, finish Apple's installer, then try again.")
        }
        // Apple's own installer dialog; it asks for an admin password itself if it needs one.
        _ = AppHost.run("/usr/bin/xcode-select", ["--install"], timeout: 30)
        let started = Date()
        while Date().timeIntervalSince(started) < toolsTimeout {
            say(.tools, "Waiting for Apple's Command Line Tools installer (finish it in its window)", min(0.95, Date().timeIntervalSince(started) / toolsTimeout))
            sleep(5)
            if toolsPresent() { say(.tools, "Command Line Tools installed", 1); return }
        }
        throw Failure.tools("The Command Line Tools did not finish installing. Run `xcode-select --install`, then try again.")
    }

    // MARK: Downloads

    func cacheURL(_ d: AppEntry.Download, _ id: String) -> URL {
        if d.into.hasPrefix("deps/") { return host.depsURL(id).appendingPathComponent(String(d.into.dropFirst(5))) }
        return host.depsURL(id).appendingPathComponent(".source/\(d.id)", isDirectory: true)
    }

    func stamp(_ d: AppEntry.Download, _ id: String) -> URL {
        host.depsURL(id).appendingPathComponent(".verified/\(d.id)-\(d.sha256)")
    }

    func isCached(_ d: AppEntry.Download, _ id: String) -> Bool {
        FileManager.default.fileExists(atPath: stamp(d, id).path) && FileManager.default.fileExists(atPath: cacheURL(d, id).path)
    }

    func fetch(_ d: AppEntry.Download, id: String, totalBytes: Int64, before: Int64) throws {
        let fm = FileManager.default
        if isCached(d, id) { say(.download, "\(d.title): already verified", Double(before + d.size) / Double(totalBytes)); return }
        guard let url = URL(string: d.url), url.scheme == "https" else { throw StoreError.insecureURL(d.url) }
        let partial = host.depsURL(id).appendingPathComponent(".partial/\(d.sha256)")
        try fm.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        let started = Date()
        let startBytes = (try? fm.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? 0
        try ResumableDownload(url: url, to: partial, expectedSize: d.size).run { got in
            let elapsed = max(0.001, Date().timeIntervalSince(started))
            let speed = Double(got - startBytes) / elapsed
            let eta = speed > 0 ? Double(d.size - got) / speed : nil
            self.say(.download, "Downloading \(d.title)", Double(before + got) / Double(totalBytes), bytes: got, total: d.size, speed: speed, eta: eta)
        }
        say(.download, "Verifying \(d.title) (SHA-256)", Double(before + d.size) / Double(totalBytes))
        let got = try Self.sha256(of: partial)
        guard got == d.sha256 else {
            try? fm.removeItem(at: partial)
            throw StoreError.checksumMismatch(expected: d.sha256, got: got)
        }
        let dest = cacheURL(d, id)
        try? fm.removeItem(at: dest)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch d.unpack {
        case "tar.gz": try fm.createDirectory(at: dest, withIntermediateDirectories: true); try Self.untar(partial, into: dest)
        case "zip": try fm.createDirectory(at: dest, withIntermediateDirectories: true); try Self.unzip(partial, into: dest)
        default: try fm.moveItem(at: partial, to: dest)
        }
        try? fm.removeItem(at: partial)
        try Self.refuseEscapingLinks(dest)
        try fm.createDirectory(at: stamp(d, id).deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: stamp(d, id).path, contents: Data(d.url.utf8))
    }

    static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Archives

    /// Lists entries first: anything absolute or with `..` is refused before extraction.
    static func untar(_ archive: URL, into dir: URL) throws {
        let list = AppHost.run("/usr/bin/tar", ["-tzf", archive.path], timeout: 300)
        guard list.status == 0 else { throw StoreError.unsafeBundle("\(archive.lastPathComponent) is not a tar.gz") }
        for name in list.out.split(separator: "\n").map(String.init) where !isSafeEntry(name) {
            throw StoreError.unsafeBundle("\(archive.lastPathComponent): entry '\(name)' points outside the folder")
        }
        guard AppHost.run("/usr/bin/tar", ["-xzf", archive.path, "-C", dir.path, "--no-same-owner", "--no-same-permissions"], timeout: 600).status == 0 else {
            throw StoreError.unsafeBundle("could not unpack \(archive.lastPathComponent)")
        }
        try refuseEscapingLinks(dir)
    }

    static func unzip(_ archive: URL, into dir: URL) throws {
        let list = AddonBundle.run("/usr/bin/zipinfo", ["-1", archive.path])
        guard list.status == 0 else { throw StoreError.unsafeBundle("\(archive.lastPathComponent) is not a zip") }
        for name in list.out.split(separator: "\n").map(String.init) where !isSafeEntry(name) {
            throw StoreError.unsafeBundle("\(archive.lastPathComponent): entry '\(name)' points outside the folder")
        }
        guard AddonBundle.run("/usr/bin/ditto", ["-x", "-k", "--norsrc", "--noqtn", archive.path, dir.path]).status == 0 else {
            throw StoreError.unsafeBundle("could not unpack \(archive.lastPathComponent)")
        }
        try refuseEscapingLinks(dir)
    }

    static func isSafeEntry(_ raw: String) -> Bool {
        var name = raw
        while name.hasPrefix("./") { name.removeFirst(2) }
        while name.hasSuffix("/") { name.removeLast() }
        if name.isEmpty || name == "." { return true }
        return !name.hasPrefix("/") && !name.split(separator: "/").contains("..")
    }

    /// Symbolic links must be relative and stay inside `dir` (frameworks use relative ones).
    static func refuseEscapingLinks(_ dir: URL) throws {
        let fm = FileManager.default
        let base = dir.resolvingSymlinksInPath().standardizedFileURL.path
        guard let walker = fm.enumerator(atPath: dir.path) else { return }
        for case let rel as String in walker {
            let url = dir.appendingPathComponent(rel)
            guard (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink else { continue }
            let target = (try? fm.destinationOfSymbolicLink(atPath: url.path)) ?? "/"
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            let canonical = URL(fileURLWithPath: parent).appendingPathComponent(target).standardizedFileURL.path
            guard !target.hasPrefix("/"), canonical == base || canonical.hasPrefix(base + "/") else {
                throw StoreError.unsafeBundle("link '\(rel)' points outside its folder")
            }
        }
    }

    static func isInside(_ url: URL, of roots: [URL]) -> Bool {
        let p = url.standardizedFileURL.path
        return roots.contains { p.hasPrefix($0.standardizedFileURL.path + "/") }
    }

    // MARK: Build

    func buildEnvironment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var out = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": env["HOME"] ?? NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        if let t = env["TMPDIR"] { out["TMPDIR"] = t }
        if let d = env["DEVELOPER_DIR"] { out["DEVELOPER_DIR"] = d }
        return out
    }

    func swiftBuild(_ product: String, cwd: URL, env: [String: String], index: Int, of count: Int) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["swift", "build", "-c", "release", "--product", product, "--disable-automatic-resolution"]
        p.currentDirectoryURL = cwd
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        say(.build, "Building \(product) (\(index + 1) of \(count))", Double(index) / Double(count))
        try p.run()
        var buffer = Data()
        var tail: [String] = []
        let h = pipe.fileHandleForReading
        while true {
            let chunk = h.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0a) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                log(line)
                tail.append(line); if tail.count > 12 { tail.removeFirst() }
                if let (n, m) = Self.buildCounter(line), m > 0 {
                    say(.build, "Building \(product) (\(index + 1) of \(count)): step \(n) of \(m)", (Double(index) + Double(n) / Double(m)) / Double(count))
                }
            }
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let why = tail.last { $0.contains("error:") } ?? tail.last ?? "exit \(p.terminationStatus)"
            throw Failure.build("Building \(product) failed: \(why)")
        }
    }

    /// `[12/340] Compiling …` or `[16 / 21] Sky-product` → (12, 340).
    static func buildCounter(_ line: String) -> (Int, Int)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let parts = line[line.index(after: line.startIndex)..<close].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let n = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (n, m)
    }
}

/// A blocking HTTPS download straight to a file with a progress callback, resumed with a Range
/// request when a partial file is already there. Redirects stay on HTTPS.
public final class ResumableDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let url: URL
    let file: URL
    let expectedSize: Int64
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var error: String?
    private var progress: ((Int64) -> Void)?
    private var lastReport = Date.distantPast
    private let done = DispatchSemaphore(value: 0)

    public init(url: URL, to file: URL, expectedSize: Int64) {
        self.url = url; self.file = file; self.expectedSize = expectedSize
    }

    public func run(progress: @escaping (Int64) -> Void) throws {
        self.progress = progress
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
        received = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        if received > expectedSize { try? fm.removeItem(at: file); fm.createFile(atPath: file.path, contents: nil); received = 0 }
        if received == expectedSize { progress(received); return }
        handle = try FileHandle(forWritingTo: file)
        try handle?.seekToEnd()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("SkyRose/\(CaelestiaVersion.string)", forHTTPHeaderField: "User-Agent")
        if received > 0 { request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 6 * 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session.dataTask(with: request).resume()
        done.wait()
        session.finishTasksAndInvalidate()
        try? handle?.close()
        if let error { throw StoreError.download(error) }
        progress(received)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200, received > 0 {
            // The server ignored the Range: start over.
            try? handle?.truncate(atOffset: 0)
            received = 0
        }
        guard status == 200 || status == 206 else { error = "HTTP \(status) from \(url.host ?? "")"; completionHandler(.cancel); return }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handle?.write(data)
        received += Int64(data.count)
        if received > expectedSize { error = "more data than the pinned size"; dataTask.cancel(); return }
        if Date().timeIntervalSince(lastReport) > 0.25 { lastReport = Date(); progress?(received) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        if let e, error == nil { error = e.localizedDescription }
        done.signal()
    }
}
