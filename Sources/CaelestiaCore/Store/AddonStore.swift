import Foundation

/// One installed addon, as kept in `addons/state.json`.
public struct InstalledAddon: Codable, Equatable, Sendable, Identifiable {
    public enum Disabled: Codable, Equatable, Sendable {
        /// Switched off in the Store or `skyrose store disable`.
        case user
        /// `skyrose wm panic` (or the panic chord) turned every addon off.
        case panic
        /// The index revoked it: it stays off and cannot be switched back on.
        case revoked(String)
    }

    public var id: String
    public var name: String
    public var author: String
    public var kind: AddonKind
    public var version: String
    /// What the user allowed (the installed version's permissions).
    public var permissions: [String]
    public var sha256: String
    public var installedAt: Date
    public var disabled: Disabled?
    /// App addons only: `pending` while `skyrose store setup` builds it, `ready`, or `failed: why`.
    public var setup: String?

    public static let setupReady = "ready"
    public static let setupPending = "pending"

    public var enabled: Bool { disabled == nil }
    public var isRevoked: Bool { if case .revoked = disabled { return true } else { return false } }

    public var status: String {
        if kind == .app, disabled == nil, setup != Self.setupReady {
            return setup.map { $0 == Self.setupPending ? "setting up" : "setup \($0)" } ?? "needs setup (skyrose store setup \(id))"
        }
        switch disabled {
        case nil: return "on"
        case .user: return "off"
        case .panic: return "off (panic)"
        case .revoked(let why): return "revoked: \(why)"
        }
    }
}

/// Where an install is, for the progress bar.
public struct StoreProgress: Equatable, Sendable {
    public enum Step: String, Sendable, CaseIterable {
        case checking, downloading, verifying, unpacking, installing, done
    }
    public var step: Step
    /// App setup (`skyrose store setup --json`): what it is doing, live bytes/speed/ETA, and its own 0…1.
    public var title: String?
    public var detail: String?
    public var setupFraction: Double?
    public var fraction: Double { setupFraction ?? Double(Step.allCases.firstIndex(of: step) ?? 0) / Double(Step.allCases.count - 1) }
    public var label: String { title ?? step.rawValue.capitalized + "…" }
    public init(_ step: Step) { self.step = step }
    public init(setup e: AppSetupEvent) {
        step = .installing
        title = e.title
        detail = e.detail
        setupFraction = e.fraction
    }
}

/// Installed addons on disk: `<root>/state.json` and one folder per addon version
/// (`<root>/<id>/<version>/`). Every change holds an flock on `<root>/.lock`, so the CLI and the
/// WM can both change it. Installs unpack into a staging folder and only replace the old version
/// once everything is verified and the state is written: a failure at any step keeps what was there.
public final class AddonStore: @unchecked Sendable {
    public let root: URL
    public let policy: AddonPolicy
    public let skyRoseVersion: String
    /// Starts and stops app addons (their own processes, LaunchAgents).
    public var apps: AppHost
    private let fm = FileManager.default

    public init(root: URL = Paths.addonsDir, policy: AddonPolicy = .current, skyRoseVersion: String = CaelestiaVersion.string, apps: AppHost? = nil) {
        self.root = root
        self.policy = policy
        self.skyRoseVersion = skyRoseVersion
        self.apps = apps ?? AppHost(root: root)
    }

    var stateURL: URL { root.appendingPathComponent("state.json") }

    public func directory(for a: InstalledAddon) -> URL {
        root.appendingPathComponent(a.id, isDirectory: true).appendingPathComponent(a.version, isDirectory: true)
    }

    // MARK: State

    /// Every installed addon, by name. A missing or unreadable state file is an empty list.
    public func installed() -> [InstalledAddon] {
        guard let data = try? Data(contentsOf: stateURL) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return ((try? d.decode([InstalledAddon].self, from: data)) ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func installed(_ id: String) -> InstalledAddon? { installed().first { $0.id == id } }

    private func save(_ list: [InstalledAddon]) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try e.encode(list).write(to: stateURL, options: .atomic) } catch { throw StoreError.io("Could not save \(stateURL.path): \(error.localizedDescription)") }
    }

    /// Runs `body` holding the cross-process lock.
    private func locked<T>(_ body: () throws -> T) throws -> T {
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true) } catch {
            throw StoreError.io("Could not create \(root.path): \(error.localizedDescription)")
        }
        let fd = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw StoreError.io("Could not lock \(root.path)") }
        defer { flock(fd, LOCK_UN); close(fd) }
        flock(fd, LOCK_EX)
        return try body()
    }

    private func change(_ edit: (inout [InstalledAddon]) throws -> Void) throws {
        try locked {
            var list = installed()
            try edit(&list)
            try save(list)
        }
    }

    // MARK: Install / update

    /// Installs or updates `entry` to `version` (default: the newest this SkyRose can take).
    /// `approve` is asked only when the version wants permissions not granted yet.
    @discardableResult
    public func install(_ entry: StoreEntry, version: StoreVersion? = nil, source: StoreSource,
                        approve: (PermissionDiff) -> Bool, progress: (StoreProgress) -> Void = { _ in }) throws -> InstalledAddon {
        progress(StoreProgress(.checking))
        if let why = entry.revoked { throw StoreError.revoked(why) }
        guard let v = version ?? entry.latest(for: skyRoseVersion) else {
            throw StoreError.incompatible("\(entry.name) has no version for SkyRose \(skyRoseVersion).")
        }
        if let why = v.revoked { throw StoreError.revoked(why) }
        guard Updater.compare(v.minSkyRose, skyRoseVersion) != .orderedDescending else {
            throw StoreError.incompatible("\(entry.name) \(v.version) needs SkyRose \(v.minSkyRose) or newer.")
        }
        let requested = v.parsedPermissions
        guard requested.count == v.permissions.count else { throw StoreError.badIndex("\(entry.id) \(v.version) lists an unknown permission") }
        let refused = policy.issues(kind: entry.kind, permissions: requested, id: entry.id)
        guard refused.isEmpty else { throw StoreError.notInstallable(refused.joined(separator: "; ")) }
        let existing = installed(entry.id)
        if case .revoked(let why) = existing?.disabled { throw StoreError.revoked(why) }
        if let existing, existing.version == v.version { progress(StoreProgress(.done)); return existing }
        let diff = PermissionDiff(granted: existing?.permissions.compactMap(AddonPermission.init) ?? [], requested: requested)
        if diff.grows, !approve(diff) { throw StoreError.permissionsDeclined }

        progress(StoreProgress(.downloading))
        try source.check(v.url)
        let data = try source.fetch(v.url)
        guard data.count <= StoreSource.maxBundleBytes else { throw StoreError.tooLarge(data.count) }

        progress(StoreProgress(.verifying))
        let got = data.sha256Hex
        guard got == v.sha256.lowercased() else { throw StoreError.checksumMismatch(expected: v.sha256, got: got) }

        return try locked {
            let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            progress(StoreProgress(.unpacking))
            let content = try AddonBundle.unpack(data, into: staging)
            let manifest = try AddonBundle.verify(content, policy: policy)
            guard manifest.id == entry.id, manifest.version == v.version, manifest.kind == entry.kind,
                  Set(manifest.permissions) == Set(v.permissions) else {
                throw StoreError.mismatch("the manifest says \(manifest.id) \(manifest.version) (\(manifest.kind.rawValue), permissions \(manifest.permissions)); the index says \(entry.id) \(v.version)")
            }

            progress(StoreProgress(.installing))
            let item = InstalledAddon(id: entry.id, name: entry.name, author: entry.author, kind: entry.kind, version: v.version,
                                      permissions: v.permissions.sorted(), sha256: got,
                                      installedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)), // ISO 8601 keeps whole seconds
                                      disabled: existing?.disabled, setup: entry.kind == .app ? InstalledAddon.setupPending : nil)
            let dest = directory(for: item)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: content, to: dest)
            } catch { throw StoreError.io("Could not install into \(dest.path): \(error.localizedDescription)") }
            var list = installed()
            list.removeAll { $0.id == item.id }
            list.append(item)
            do { try save(list) } catch {
                try? fm.removeItem(at: dest) // rollback: the old version and state are untouched
                throw error
            }
            if let existing, existing.version != item.version { try? fm.removeItem(at: directory(for: existing)) }
            // An app addon is built next by `skyrose store setup` (out of process); until then
            // the old build (if any) keeps running.
            progress(StoreProgress(.done))
            return item
        }
    }

    /// Removes the addon and its folder. An app is stopped and its LaunchAgent removed first;
    /// `purge` also deletes the user data it declared (`entry.app.dataPaths`).
    public func uninstall(_ id: String, purge: Bool = false) throws {
        guard let a = installed(id) else { throw StoreError.notFound(id) }
        let manifest = a.kind == .app ? apps.manifest(a) : nil
        if a.kind == .app { apps.deactivate(a, removeAgent: true) }
        try change { list in
            guard list.contains(where: { $0.id == id }) else { throw StoreError.notFound(id) }
            list.removeAll { $0.id == id }
        }
        if a.kind == .widget { WidgetProcesses.kill(addonFolder: root.appendingPathComponent(id, isDirectory: true)) }
        try? fm.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
        if purge, let app = manifest?.entry.app {
            for p in app.dataPaths ?? [] where AddonManifest.isSafePath(p) {
                try? fm.removeItem(at: apps.home.appendingPathComponent(p, isDirectory: true))
            }
        }
    }

    /// A revoked addon cannot be switched back on. Apps are stopped (off) or started (on).
    public func setEnabled(_ id: String, _ on: Bool) throws {
        try change { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound(id) }
            if case .revoked(let why) = list[i].disabled { if on { throw StoreError.revoked(why) } else { return } }
            list[i].disabled = on ? nil : .user
        }
        guard let a = installed(id) else { return }
        if a.kind == .widget, !on { WidgetProcesses.kill(addonFolder: root.appendingPathComponent(id, isDirectory: true)) }
        guard a.kind == .app else { return }
        if on { apps.activate(a) } else { apps.deactivate(a, removeAgent: true) }
    }

    // MARK: Builtin features

    var seededURL: URL { root.appendingPathComponent("features-seeded.json") }

    /// Records each builtin feature as installed the first time this SkyRose sees it, so an update
    /// keeps every feature on. A later uninstall sticks: a feature is seeded only once.
    public func seedBuiltinFeatures() {
        let seen = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: seededURL))) ?? []
        guard BuiltinFeature.all.contains(where: { !seen.contains($0.id) }) else { return }
        try? locked {
            let seen = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: seededURL))) ?? []
            let new = BuiltinFeature.all.filter { !seen.contains($0.id) }
            guard !new.isEmpty else { return }
            var list = installed()
            for f in new where !list.contains(where: { $0.id == f.id }) { list.append(f.record(version: skyRoseVersion)) }
            try save(list)
            try JSONEncoder().encode(seen + new.map(\.id)).write(to: seededURL, options: .atomic)
        }
    }

    /// Installs a builtin feature again after an uninstall (no download). An existing record,
    /// revoked or off, is kept as it is.
    @discardableResult
    public func installBuiltin(_ id: String) throws -> InstalledAddon {
        guard let f = BuiltinFeature.named(id) else { throw StoreError.notFound(id) }
        seedBuiltinFeatures()
        var item = f.record(version: skyRoseVersion)
        try change { list in
            if let old = list.first(where: { $0.id == id }) { item = old; return }
            list.append(item)
        }
        return item
    }

    /// Off when uninstalled, switched off, turned off by a panic, or revoked.
    public func featureEnabled(_ id: String) -> Bool {
        seedBuiltinFeatures()
        return installed(id)?.enabled ?? false
    }

    /// App addons: records the setup result (`ready`, `pending`, `failed: …`).
    public func setSetup(_ id: String, _ value: String) throws {
        try change { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound(id) }
            list[i].setup = value
        }
    }

    /// The panic path: every enabled addon off, every app addon stopped without waiting (a
    /// signal each). Never throws; returns how many were on.
    @discardableResult
    public func disableAll() -> Int {
        var count = 0
        var stopped: [InstalledAddon] = []
        try? change { list in
            for i in list.indices where list[i].enabled {
                list[i].disabled = .panic
                count += 1
                if list[i].kind == .app || list[i].kind == .widget { stopped.append(list[i]) }
            }
        }
        // Also from the CLI while the WM hangs: widget processes are killed here, not by the WM.
        for a in stopped where a.kind == .widget { WidgetProcesses.kill(addonFolder: root.appendingPathComponent(a.id, isDirectory: true)) }
        for a in stopped where a.kind == .app { apps.deactivate(a, removeAgent: true, wait: false) }
        return count
    }

    /// The kill switch: disables every installed addon (or installed version) the index revoked.
    /// Returns the ones newly revoked.
    @discardableResult
    public func applyRevocations(_ index: StoreIndex) -> [InstalledAddon] {
        var hit: [InstalledAddon] = []
        try? change { list in
            for i in list.indices where !list[i].isRevoked {
                guard let e = index.entry(list[i].id) else { continue }
                if let why = e.revoked ?? e.version(list[i].version)?.revoked {
                    list[i].disabled = .revoked(why)
                    hit.append(list[i])
                }
            }
        }
        for a in hit where a.kind == .app { apps.deactivate(a, removeAgent: true) }
        for a in hit where a.kind == .widget { WidgetProcesses.kill(addonFolder: root.appendingPathComponent(a.id, isDirectory: true)) }
        return hit
    }

    /// Installed addons with a newer installable version in `index`.
    public func updates(_ index: StoreIndex) -> [(installed: InstalledAddon, entry: StoreEntry, version: StoreVersion)] {
        installed().compactMap { a in
            guard !a.isRevoked, let e = index.entry(a.id), let v = e.latest(for: skyRoseVersion),
                  Updater.compare(a.version, v.version) == .orderedAscending else { return nil }
            return (a, e, v)
        }
    }

    // MARK: Content (what SkyRose reads from enabled addons)

    /// Enabled scheme files: theme name `<id>/<file stem>` (never a built-in name), title, file.
    public func schemes() -> [(theme: String, title: String, url: URL)] {
        enabledFiles(.scheme) { a, m in m.entry.schemes ?? [] }.map { a, url in
            let stem = url.deletingPathExtension().lastPathComponent
            return ("\(a.id)/\(stem)", a.name + ((a.name.lowercased().contains(stem.lowercased())) ? "" : " · \(stem)"), url)
        }
    }

    /// The scheme for `appearance.theme` = `<id>/<stem>`, if that addon is installed and on.
    public func scheme(named theme: String) -> Scheme? {
        guard theme.contains("/"), let hit = schemes().first(where: { $0.theme == theme }) else { return nil }
        return try? SchemeLoader.load(from: hit.url)
    }

    /// Enabled wallpaper addons, one group each.
    public func wallpaperGroups() -> [(title: String, urls: [URL])] {
        let files = enabledFiles(.wallpaper) { _, m in m.entry.wallpapers ?? [] }
        return Dictionary(grouping: files, by: { $0.0.id }).values.compactMap { pairs in
            pairs.first.map { (title: "SkyStore/\($0.0.name)", urls: pairs.map(\.1)) }
        }.sorted { $0.title < $1.title }
    }

    /// Enabled widget addons: the record, its version folder, its `data` folder and its script entry.
    public func enabledWidgets() -> [(addon: InstalledAddon, dir: URL, data: URL, widget: WidgetEntry, permissions: [AddonPermission])] {
        installed().filter { $0.enabled && $0.kind == .widget }.compactMap { a in
            let dir = directory(for: a)
            guard let raw = try? Data(contentsOf: dir.appendingPathComponent(AddonManifest.fileName)),
                  let m = try? AddonManifest.decode(raw), let w = m.entry.widget, AddonManifest.isSafePath(w.script) else { return nil }
            // Granted = recorded at install, never more than the manifest says.
            let granted = m.parsedPermissions.filter { a.permissions.contains($0.description) }
            return (a, dir, root.appendingPathComponent(a.id, isDirectory: true).appendingPathComponent("data", isDirectory: true), w, granted)
        }
    }

    /// When `state.json` last changed (the WM restarts widgets when it does).
    public var stateModified: Date? { (try? fm.attributesOfItem(atPath: stateURL.path))?[.modificationDate] as? Date }

    private func enabledFiles(_ kind: AddonKind, _ pick: (InstalledAddon, AddonManifest) -> [String]) -> [(InstalledAddon, URL)] {
        installed().filter { $0.enabled && $0.kind == kind }.flatMap { a -> [(InstalledAddon, URL)] in
            let dir = directory(for: a)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(AddonManifest.fileName)),
                  let m = try? AddonManifest.decode(data) else { return [] }
            return pick(a, m).filter(AddonManifest.isSafePath).map { (a, dir.appendingPathComponent($0)) }
                .filter { fm.fileExists(atPath: $0.1.path) }
        }
    }
}

/// Reading and checking `.skyaddon` bundles (zip archives with `manifest.json` at the top).
public enum AddonBundle {
    public static let fileExtension = "skyaddon"

    /// Writes `data` into `staging`, refuses unsafe entry names, unzips, returns the content folder.
    static func unpack(_ data: Data, into staging: URL) throws -> URL {
        let fm = FileManager.default
        let zip = staging.appendingPathComponent("bundle.zip")
        let content = staging.appendingPathComponent("content", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try data.write(to: zip)
        } catch { throw StoreError.io("Could not write \(staging.path): \(error.localizedDescription)") }
        let list = run("/usr/bin/zipinfo", ["-1", zip.path])
        guard list.status == 0 else { throw StoreError.unsafeBundle("not a zip archive") }
        for name in list.out.split(separator: "\n").map(String.init) {
            let path = name.hasSuffix("/") ? String(name.dropLast()) : name
            guard AddonManifest.isSafePath(path) else { throw StoreError.unsafeBundle("entry '\(name)' points outside the bundle") }
        }
        guard run("/usr/bin/ditto", ["-x", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", zip.path, content.path]).status == 0 else {
            throw StoreError.unsafeBundle("could not unzip it")
        }
        return content
    }

    /// Checks an unpacked bundle: manifest valid for `policy`, no links, every file listed with its
    /// SHA-256 and nothing else present. Returns the manifest.
    public static func verify(_ dir: URL, policy: AddonPolicy) throws -> AddonManifest {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(AddonManifest.fileName)) else {
            throw StoreError.badManifest("no manifest.json at the top of the bundle")
        }
        let m = try AddonManifest.decode(data)
        let issues = policy.issues(m)
        guard issues.isEmpty else { throw StoreError.invalid(issues) }
        let present = try files(in: dir)
        for (path, sha) in m.files {
            guard let file = present[path] else { throw StoreError.mismatch("'\(path)' is missing") }
            let got = (try? Data(contentsOf: file))?.sha256Hex ?? ""
            guard got == sha else { throw StoreError.checksumMismatch(expected: sha, got: got) }
        }
        if let extra = present.keys.filter({ m.files[$0] == nil && $0 != AddonManifest.fileName }).sorted().first {
            throw StoreError.unsafeBundle("'\(extra)' is not listed in the manifest")
        }
        for s in m.entry.schemes ?? [] {
            do { _ = try SchemeLoader.load(from: dir.appendingPathComponent(s)) } catch {
                throw StoreError.invalid(["\(s) is not a colour scheme: \(error.localizedDescription)"])
            }
        }
        for w in m.entry.wallpapers ?? [] where !wallpaperExtensions.contains((w as NSString).pathExtension.lowercased()) {
            throw StoreError.invalid(["\(w) is not an image or video (\(wallpaperExtensions.sorted().joined(separator: ", ")))"])
        }
        return m
    }

    static let wallpaperExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "mp4", "mov", "m4v"]

    /// Regular files below `dir` by relative path; throws on a symbolic link or anything that is
    /// not a plain file or folder.
    public static func files(in dir: URL) throws -> [String: URL] {
        var out: [String: URL] = [:]
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: dir.path) else { return out }
        for case let rel as String in walker {
            let url = dir.appendingPathComponent(rel)
            // attributesOfItem does not follow links.
            let type = (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
            if type == .typeSymbolicLink { throw StoreError.unsafeBundle("'\(rel)' is a symbolic link") }
            if type == .typeDirectory { continue }
            guard type == .typeRegular else { throw StoreError.unsafeBundle("'\(rel)' is not a regular file") }
            out[rel] = url
        }
        return out
    }

    static func run(_ exe: String, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self))
    }
}
