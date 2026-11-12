import AppKit
import CaelestiaCore
import Foundation

/// What the Store drawer shows and does. The index is fetched (signed, HTTPS) only when the drawer
/// opens or, with addons installed, every few hours for the kill switch; installs run off the main
/// thread through `AddonStore`, so a failure keeps the version that was there.
@MainActor
public final class StoreModel: ObservableObject {
    public enum Tab: String, CaseIterable, Sendable {
        case featured, categories, installed, updates
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .featured: return "auto_awesome"
            case .categories: return "category"
            case .installed: return "inventory_2"
            case .updates: return "update"
            }
        }
    }

    public static let bodySize = CGSize(width: 900, height: 600)
    /// Re-check the index for revocations and updates this often while addons are installed.
    public static let checkInterval: TimeInterval = 6 * 3600

    @Published public var shown = false
    /// The drawer body on the display it opened on (at most `bodySize`).
    @Published public var size = StoreModel.bodySize
    @Published public var tab: Tab = .featured
    @Published public var query = ""
    @Published public var category: String?
    /// The entry whose detail page is open.
    @Published public var selected: String?
    @Published public private(set) var index: StoreIndex?
    @Published public private(set) var installed: [InstalledAddon] = []
    @Published public private(set) var loading = false
    /// Why the index is missing (not set up, offline, bad signature).
    @Published public private(set) var indexError: String?
    @Published public private(set) var busy: [String: StoreProgress] = [:]
    /// Last failure per addon, shown under its button.
    @Published public var errors: [String: String] = [:]
    /// The addon whose button is waiting for a second press (new permissions or uninstall).
    @Published public var confirming: String?

    public var config = StoreConfig()
    public let addons: AddonStore
    /// Fetches the index; replaced in tests.
    var loadIndex: @Sendable (StoreConfig) throws -> StoreIndex = { try StoreSource.from($0).loadIndex() }
    var source: (StoreConfig) -> StoreSource = { StoreSource.from($0) }
    private var fetchedAt: Date?
    private var timer: Timer?

    public var onClose: () -> Void = {}
    /// Scheme or wallpaper content changed (install, update, uninstall, on/off, revoked).
    public var onContentChanged: () -> Void = {}
    public var onRevoked: ([InstalledAddon]) -> Void = { _ in }

    public init(addons: AddonStore = AddonStore()) {
        self.addons = addons
    }

    // MARK: Lists

    public var updates: [(installed: InstalledAddon, entry: StoreEntry, version: StoreVersion)] {
        guard let index else { return [] }
        return addons.updates(index)
    }

    public var shelves: [String] { Array(Set((index?.addons ?? []).map(\.shelf))).sorted() }

    /// The grid for the current tab and search.
    public var visible: [StoreEntry] {
        let all = (index?.addons ?? []).filter { $0.revoked == nil && $0.kind != .unknown }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return all.filter { $0.matches(query) } }
        switch tab {
        case .featured:
            let f = all.filter { $0.featured == true }
            return f.isEmpty ? all : f
        case .categories: return all.filter { $0.shelf == (category ?? shelves.first) }
        case .installed, .updates: return []
        }
    }

    public func entry(_ id: String) -> StoreEntry? { index?.entry(id) }
    public func installed(_ id: String) -> InstalledAddon? { installed.first { $0.id == id } }

    /// What the button for `entry` does next.
    public enum Action: Equatable, Sendable {
        case install, update(String), installed, revoked(String), needsNewerSkyRose, notSupported
        /// An app addon whose build did not finish (or failed): run setup again.
        case setup(String?)
    }

    public func action(for e: StoreEntry) -> Action {
        if let a = installed(e.id), case .revoked(let why) = a.disabled { return .revoked(why) }
        if let why = e.revoked { return .revoked(why) }
        guard addons.policy.installable[e.kind] != nil else { return .notSupported }
        let latest = e.latest(for: addons.skyRoseVersion)
        guard let a = installed(e.id) else { return latest == nil ? .needsNewerSkyRose : .install }
        if let latest, Updater.compare(a.version, latest.version) == .orderedAscending { return .update(latest.version) }
        if a.kind == .app, a.enabled, a.setup != InstalledAddon.setupReady {
            return .setup(a.setup.flatMap { $0.hasPrefix("failed: ") ? String($0.dropFirst(8)) : nil })
        }
        return .installed
    }

    /// New permissions the next install/update of `e` would ask for.
    public func permissionDiff(for e: StoreEntry) -> PermissionDiff? {
        guard let v = e.latest(for: addons.skyRoseVersion) else { return nil }
        return PermissionDiff(granted: installed(e.id)?.permissions.compactMap(AddonPermission.init) ?? [], requested: v.parsedPermissions)
    }

    // MARK: Opening and refreshing

    public func prepare() {
        query = ""
        selected = nil
        confirming = nil
        installed = addons.installed()
        if fetchedAt.map({ Date().timeIntervalSince($0) > 600 }) ?? true || index == nil { refresh() }
    }

    public func refresh() {
        guard !loading else { return }
        loading = true
        let config = config, load = loadIndex, addons = addons
        Task.detached {
            let result = Result { try load(config) }
            let revoked = (try? result.get()).map { addons.applyRevocations($0) } ?? []
            await MainActor.run {
                self.loading = false
                switch result {
                case .success(let index):
                    self.index = index
                    self.indexError = nil
                    self.fetchedAt = Date()
                case .failure(let e):
                    self.indexError = (e as? LocalizedError)?.errorDescription ?? "\(e)"
                }
                self.installed = addons.installed()
                if !revoked.isEmpty {
                    self.onRevoked(revoked)
                    self.onContentChanged()
                }
            }
        }
    }

    /// The kill switch keeps working with the drawer closed, but only while something is installed
    /// (no addons: SkyRose never contacts the index on its own).
    public func startBackgroundChecks() {
        timer?.invalidate()
        let t = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.backgroundCheck() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        backgroundCheck()
    }

    func backgroundCheck() {
        installed = addons.installed()
        if !installed.isEmpty { refresh() }
    }

    // MARK: Actions

    /// Install or update. When the version asks for permissions not granted yet, the first press
    /// arms the button (it lists them) and the second press installs.
    public func install(_ e: StoreEntry) {
        guard busy[e.id] == nil else { return }
        if let diff = permissionDiff(for: e), diff.grows, confirming != e.id {
            confirming = e.id
            return
        }
        confirming = nil
        errors[e.id] = nil
        busy[e.id] = StoreProgress(.checking)
        let addons = addons, source = source(config), id = e.id
        Task.detached {
            let result = Result {
                try addons.install(e, source: source, approve: { _ in true }, progress: { p in
                    Task { @MainActor in if self.busy[id] != nil { self.busy[id] = p } }
                })
            }
            await MainActor.run {
                if case .success(let a) = result, a.kind == .app { self.installed = addons.installed(); self.runSetup(id); return }
                self.finish(id, result.map { _ in () })
            }
        }
    }

    /// The command that builds an app addon: `skyrose store setup <id> --json`, run as a child
    /// process (never inside the WM). Replaced in tests.
    var setupCommand: (String) -> (URL, [String])? = { id in
        let candidates = [Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("skyrose"),
                          Paths.home.appendingPathComponent("Applications/SkyRose.app/Contents/MacOS/skyrose"),
                          URL(fileURLWithPath: "/Applications/SkyRose.app/Contents/MacOS/skyrose")].compactMap { $0 }
        guard let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
        return (cli, ["store", "setup", id, "--json"])
    }

    /// Builds (again) an installed app addon out of process, showing each `AppSetupEvent` line
    /// (step, real bytes / speed / ETA while downloading) on the card's progress bar.
    public func runSetup(_ id: String) {
        guard busy[id] == nil || busy[id]?.step == .done || busy[id]?.setupFraction == nil else { return }
        errors[id] = nil
        guard let (exe, args) = setupCommand(id) else {
            finish(id, .failure(StoreError.io("The skyrose command was not found next to SkyRose, so the app could not be built. Run: skyrose store setup \(id)")))
            return
        }
        busy[id] = StoreProgress(setup: AppSetupEvent(.preflight, "Starting setup", fraction: 0))
        Task.detached {
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            var failure: String?
            do {
                try p.run()
                var buffer = Data()
                while true {
                    let chunk = out.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let nl = buffer.firstIndex(of: 0x0a) {
                        let line = Data(buffer[..<nl])
                        buffer.removeSubrange(...nl)
                        guard let e = try? JSONDecoder().decode(AppSetupEvent.self, from: line) else { continue }
                        if e.step == .failed { failure = e.title }
                        await MainActor.run { if self.busy[id] != nil { self.busy[id] = StoreProgress(setup: e) } }
                    }
                }
                p.waitUntilExit()
                if p.terminationStatus != 0, failure == nil { failure = "Setup stopped (exit \(p.terminationStatus))." }
            } catch { failure = error.localizedDescription }
            let result: Result<Void, Error> = failure.map { .failure(StoreError.io($0)) } ?? .success(())
            await MainActor.run { self.finish(id, result) }
        }
    }

    /// The first press arms, the second removes.
    public func uninstall(_ id: String) {
        guard busy[id] == nil else { return }
        guard confirming == id else { confirming = id; return }
        confirming = nil
        finish(id, Result { try addons.uninstall(id) })
    }

    public func setEnabled(_ id: String, _ on: Bool) {
        finish(id, Result { try addons.setEnabled(id, on) })
    }

    public func updateAll() {
        for u in updates { install(u.entry) }
    }

    private func finish(_ id: String, _ result: Result<Void, Error>) {
        busy[id] = nil
        if case .failure(let e) = result { errors[id] = (e as? LocalizedError)?.errorDescription ?? "\(e)" }
        installed = addons.installed()
        onContentChanged()
    }

    // MARK: Navigation

    public func open(_ id: String) {
        confirming = nil
        selected = id
    }

    public func back() {
        confirming = nil
        selected = nil
    }

    /// Esc leaves a detail page first, then closes.
    func key(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53 else { return false }
        if confirming != nil { confirming = nil } else if selected != nil { back() } else { onClose() }
        return true
    }
}
