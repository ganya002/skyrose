import AppKit
import CaelestiaCore
import CaelestiaIPC
import CaelestiaShell
import Combine
import Foundation
import SwiftUI

/// The Settings app's model: the config as written in config.toml, the live state of the WM
/// (running, permissions), the colour scheme the shell draws with, and every write.
///
/// A write updates the model at once (the UI never waits), then goes to the WM's config API
/// (`config.set`, applied live, no restart) or, when SkyRose is not running, straight into
/// config.toml through the same ``ConfigAPI`` (validated; a rejected value is rolled back in the
/// file and in the UI, with a message). Slider drags are coalesced to one write per 120 ms.
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var config: Config
    @Published public private(set) var wmRunning = false
    /// SkyRose's permissions: from the WM when it answers, else from a probe of SkyRose.app
    /// (``PermissionProber``), so they stay live while SkyRose is not running. Nil until known.
    @Published public private(set) var permissions: PermissionSnapshot?
    /// Where `permissions` came from last.
    @Published public private(set) var permissionsSource: PermissionsSource = .unknown
    /// True while the WM is running but did not answer in time.
    @Published public private(set) var wmBusy = false
    @Published public private(set) var scheme: Scheme
    @Published public var message: String?
    @Published public private(set) var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// The frontmost other app (for "Add focused app"): Settings itself is frontmost while you
    /// click, so it is the app that was active before.
    @Published public private(set) var lastOtherApp: (bundleID: String, name: String)?
    @Published public private(set) var appRules: [AppRuleRow] = []

    public enum PermissionsSource: Equatable, Sendable { case unknown, wm, probe }

    public let api: ConfigAPI
    public let connection: WMConnection
    public let prober: PermissionProber?
    private var lastProbe: Date?
    /// Seconds between probes while the WM does not answer.
    public var probeInterval: TimeInterval = 2
    /// Permissions reported as missing without touching the real grants (`--simulate-missing`).
    public var simulatedMissing: Set<SkyRosePermission>
    /// Writes go only to the file (tests).
    public var offline = false

    private var pending: [String: ConfigValue] = [:]
    private var flushTimer: Timer?
    private var pollTimer: Timer?
    private var configStamp: Date?
    private var schemeStamp: Date?
    private var observers: [NSObjectProtocol] = []

    public init(api: ConfigAPI = ConfigAPI(), connection: WMConnection = WMConnection(),
                simulatedMissing: Set<SkyRosePermission> = [], prober: PermissionProber? = PermissionProber()) {
        self.api = api
        self.connection = connection
        self.prober = prober
        self.simulatedMissing = simulatedMissing
        let c = api.load()
        config = c
        scheme = Self.scheme(for: c)
        configStamp = Self.modified(api.file)
        defaultProcessCheck()
    }

    // MARK: Look

    public var look: SettingsLook {
        let reduce = systemReduceMotion && config.animations.respectReduceMotion || config.animations.reduceMotion
        return SettingsLook(theme: ShellTheme(scheme: scheme, config: config, reduceMotion: reduce),
                            motion: SettingsMotion(reduceMotion: reduce, speed: config.animations.speed))
    }

    /// The scheme the shell draws with right now (written by the WM), else the static theme.
    static func scheme(for c: Config, currentFile: URL = Paths.currentScheme) -> Scheme {
        if let s = try? SchemeLoader.load(from: currentFile) { return s }
        return SchemeResolver.staticScheme(c.appearance) ?? ShellTheme.gabby.scheme
    }

    // MARK: Live state

    public func start() {
        refresh()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier != Bundle.main.bundleIdentifier, app.activationPolicy == .regular, let id = app.bundleIdentifier
            else { return }
            MainActor.assumeIsolated { self?.lastOtherApp = (id, app.localizedName ?? id) }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        })
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier,
            let id = front.bundleIdentifier {
            lastOtherApp = (id, front.localizedName ?? id)
        }
    }

    /// Once a second: is the WM up, its permissions, external edits of config.toml, the scheme.
    public func refresh() {
        connection.call(.permissionsStatus, timeout: 1) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let v):
                self.wmRunning = true
                self.wmBusy = false
                let snap = PermissionSnapshot(
                    accessibility: v["accessibility"]?.boolValue ?? false,
                    inputMonitoring: v["inputMonitoring"]?.boolValue ?? false,
                    screenRecording: v["screenRecording"]?.boolValue ?? false
                )
                self.updatePermissions(snap, from: .wm)
            case .failure(.busy):
                // Running, just slow to answer (tiling every window after a grant): not "stopped".
                self.wmRunning = true
                self.wmBusy = true
                self.probeIfDue()
            case .failure(.refused):
                // It answered (and refused): it is running.
                self.wmRunning = true
                self.wmBusy = false
                self.probeIfDue()
            case .failure(.notRunning), .failure(.unreachable):
                // No socket, or no usable answer: running only if its process is alive (then it is
                // "not responding", and the WM rebinds a lost socket within a few seconds).
                let alive = self.wmProcessAlive()
                self.wmRunning = alive
                self.wmBusy = alive
                self.probeIfDue()
            }
        }
        if pending.isEmpty, Self.modified(api.file) != configStamp { reloadConfig() }
        let s = Self.modified(Paths.currentScheme)
        if s != schemeStamp {
            schemeStamp = s
            let next = Self.scheme(for: config)
            if next != scheme { scheme = next }
        }
    }

    func updatePermissions(_ snap: PermissionSnapshot, from source: PermissionsSource) {
        let s = snap.simulatingMissing(simulatedMissing)
        if s != permissions { permissions = s }
        if source != permissionsSource { permissionsSource = source }
    }

    /// Asks SkyRose.app itself (no WM needed), at most every `probeInterval` seconds.
    func probeIfDue() {
        guard let prober else { return }
        if let last = lastProbe, Date().timeIntervalSince(last) < probeInterval { return }
        lastProbe = Date()
        prober.probe { [weak self] snap in
            guard let self, let snap else { return }
            // The WM answered in the meantime: its answer wins.
            if self.wmRunning, !self.wmBusy, self.permissionsSource == .wm { return }
            self.updatePermissions(snap, from: .probe)
        }
    }

    public func reloadConfig() {
        config = api.load()
        configStamp = Self.modified(api.file)
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: Writes

    /// Sets one key: the model now, the WM (or the file) right after.
    public func set(_ path: String, _ value: ConfigValue, update: (inout Config) -> Void, coalesce: Bool = false) {
        var c = config
        update(&c)
        config = c
        pending[path] = value
        if coalesce {
            if flushTimer == nil {
                let t = Timer(timeInterval: 0.12, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
                RunLoop.main.add(t, forMode: .common)
                flushTimer = t
            }
        } else {
            flush()
        }
    }

    /// A binding for a config value at `keyPath` written to `path`.
    public func binding<T>(_ keyPath: WritableKeyPath<Config, T>, _ path: String, coalesce: Bool = false,
                           _ encode: @escaping (T) -> ConfigValue) -> Binding<T> {
        Binding(get: { self.config[keyPath: keyPath] },
                set: { v in self.set(path, encode(v), update: { $0[keyPath: keyPath] = v }, coalesce: coalesce) })
    }

    public func bool(_ keyPath: WritableKeyPath<Config, Bool>, _ path: String) -> Binding<Bool> {
        binding(keyPath, path) { .bool($0) }
    }

    public func number(_ keyPath: WritableKeyPath<Config, Double>, _ path: String) -> Binding<Double> {
        binding(keyPath, path, coalesce: true) { .number($0) }
    }

    /// Sets `wm.closeQuitsAppExceptions` (the apps the red button never quits), de-duplicated.
    public func setCloseQuitExceptions(_ ids: [String]) {
        var unique: [String] = []
        for id in ids where !id.isEmpty && !unique.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) { unique.append(id) }
        let literal = "[" + unique.map { ConfigValue.string($0).toml }.joined(separator: ", ") + "]"
        set("wm.closeQuitsAppExceptions", .literal(literal), update: { $0.wm.closeQuitsAppExceptions = unique })
    }

    /// Writes everything pending now (also called when a slider is released).
    public func flush() {
        flushTimer?.invalidate()
        flushTimer = nil
        let batch = pending
        pending.removeAll()
        guard !batch.isEmpty else { return }
        let items = batch.sorted { $0.key < $1.key }
        if offline || !wmRunning {
            writeLocally(items)
            return
        }
        for (path, value) in items {
            connection.call(.configSet, args: ["path": .string(path), "value": Self.json(value)]) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success: self.configStamp = Self.modified(self.api.file)
                case .failure(.notRunning), .failure(.unreachable): self.writeLocally([(path, value)])
                case .failure(.busy):
                    // It may still apply it; the file watcher and the next refresh show the result.
                    self.configStamp = nil
                case .failure(.refused(let m)):
                    self.message = m
                    self.reloadConfig()
                }
            }
        }
    }

    private func writeLocally(_ items: [(String, ConfigValue)]) {
        do {
            try api.set(items)
        } catch {
            message = String(describing: error)
        }
        reloadConfig()
    }

    static func json(_ v: ConfigValue) -> JSONValue {
        switch v {
        case .bool(let b): return .bool(b)
        case .int(let i): return .number(Double(i))
        case .number(let d): return .number(d)
        case .string(let s): return .string(s)
        case .tables, .literal: return .string(v.toml)
        }
    }

    // MARK: Window rules

    /// Running apps, apps with a rule and the built-in floating ones (from the WM), or the
    /// user's rules from config.toml when SkyRose is not running.
    public func loadAppRules() {
        connection.call(.rulesApps) { [weak self] result in
            guard let self else { return }
            if case .success(let v) = result {
                self.appRules = AppRuleRow.decode(v)
            } else {
                self.appRules = self.config.appRules.sorted { $0.key < $1.key }.map {
                    AppRuleRow(bundleID: $0.key, name: Self.appName($0.key), rule: $0.value, mode: $0.value)
                }
            }
        }
    }

    /// Sets an app's rule ("tile", "float", "auto"); applied to its open windows at once.
    public func setAppRule(_ mode: String, for bundleID: String, name: String? = nil) {
        if let i = appRules.firstIndex(where: { $0.bundleID == bundleID }) {
            appRules[i].rule = mode
            appRules[i].mode = mode
        } else {
            appRules.insert(AppRuleRow(bundleID: bundleID, name: name ?? Self.appName(bundleID), rule: mode, mode: mode), at: 0)
        }
        guard wmRunning, !offline else {
            do {
                if mode == "auto" { try api.reset("appRules.\(bundleID)") } else { try api.set("appRules.\(bundleID)", .string(mode)) }
            } catch { message = String(describing: error) }
            reloadConfig()
            return
        }
        connection.call(.rulesSet, args: ["bundleID": .string(bundleID), "mode": .string(mode)]) { [weak self] r in
            if case .failure(let e) = r { self?.message = e.description }
            self?.reloadConfig()
        }
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: WM actions

    public func requestPermission(_ p: SkyRosePermission) {
        guard wmRunning, !wmBusy else {
            // No WM to ask: a probe of SkyRose.app asks macOS (so SkyRose is in the list), then
            // the exact pane opens.
            if let prober {
                prober.probe(requesting: p) { [weak self] snap in
                    if let snap { self?.updatePermissions(snap, from: .probe) }
                    if snap?.isGranted(p) != true { NSWorkspace.shared.open(p.settingsURL) }
                }
            } else {
                NSWorkspace.shared.open(p.settingsURL)
            }
            return
        }
        connection.call(.permissionsRequest, args: ["kind": .string(p.rawValue)]) { _ in }
    }

    public func pauseHotkeys(_ seconds: Double) {
        connection.call(.keysPause, args: ["seconds": .number(seconds)]) { _ in }
    }

    public func setWallpaper(_ url: URL) {
        connection.call(.shellWallpaperSet, args: ["path": .string(url.path)]) { [weak self] r in
            if case .failure(let e) = r { self?.message = "Wallpaper: \(e)" }
        }
    }

    public func calibrateFrame() {
        connection.call(.frameCalibrate) { [weak self] r in
            if case .failure(let e) = r { self?.message = "Calibration: \(e)" }
        }
    }

    /// Asks the WM to re-read config.toml and keymap.toml (after a keymap edit).
    public func runReload() {
        guard wmRunning else { return }
        connection.call(.configReload) { [weak self] r in
            if case .failure(let e) = r { self?.message = e.description }
        }
    }

    public func runAction(_ name: String) {
        connection.call(.action, args: ["action": .string(name)]) { [weak self] r in
            if case .failure(let e) = r { self?.message = e.description }
        }
    }

    /// Starts SkyRose.app (next to this app, or wherever Launch Services has it).
    /// SkyRose.app's bundle id (the WM; permission probes share it, see ``wmProcesses()``).
    public static let wmBundleID = "com.skyrose.mac"

    /// Running SkyRose WM processes: every `com.skyrose.mac` instance except our own permission
    /// probes (short-lived copies of the same app) and anything that started under 2 s ago.
    func wmProcesses() -> [NSRunningApplication] {
        let probes = prober?.probePIDs ?? []
        return NSRunningApplication.runningApplications(withBundleIdentifier: Self.wmBundleID).filter { app in
            guard !app.isTerminated, !probes.contains(app.processIdentifier) else { return false }
            guard let launched = app.launchDate else { return true }
            return Date().timeIntervalSince(launched) > 2
        }
    }

    /// Whether a SkyRose WM process is alive (replaceable for tests: the real WM may be running
    /// on the machine that runs them).
    var wmProcessAlive: @MainActor () -> Bool = { false }
    private func defaultProcessCheck() { wmProcessAlive = { [weak self] in !(self?.wmProcesses().isEmpty ?? true) } }

    /// The sidebar footer's status.
    public var statusLine: String {
        guard wmRunning else { return "SkyRose is not running" }
        return wmBusy ? "SkyRose is running (busy)" : "SkyRose is running"
    }

    public func launchSkyRose() {
        guard let url = PermissionProber.defaultAppURL() else { message = "SkyRose.app was not found"; return }
        // A new instance on purpose: with a permission probe (same bundle id) alive, Launch
        // Services would otherwise just activate the probe and the WM never starts. A second
        // WM quits by itself when one already owns the socket.
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = !wmProcessAlive()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    }

    /// Quits and starts SkyRose again (a new Screen Recording grant needs it). Windows are
    /// restored by the quit and re-tiled by the start, which waits until the old process has
    /// really exited (restoring many windows can take a few seconds).
    public func restartSkyRose() {
        let old = wmProcesses()
        connection.call(.wmQuit, timeout: 5) { [weak self] _ in
            self?.launchWhenGone(old, deadline: Date().addingTimeInterval(15))
        }
    }

    private func launchWhenGone(_ old: [NSRunningApplication], deadline: Date) {
        if old.allSatisfy(\.isTerminated) || Date() > deadline {
            launchSkyRose()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MainActor.assumeIsolated { self.launchWhenGone(old, deadline: deadline) }
        }
    }
}
