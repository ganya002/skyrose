import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CoreGraphics
import Foundation

/// One app as the rules API reports it (the future Settings app lists these).
public struct AppRuleEntry: Codable, Equatable, Sendable {
    public var bundleID: String
    public var name: String
    /// What the user set ("tile", "float"), or "auto" when there is no user rule.
    public var rule: String
    /// The effective mode: "tile", "float" or "auto" (auto = rules.toml / heuristics decide).
    public var mode: String
    /// "user", "builtIn" or "none".
    public var source: String
    public var running: Bool
    /// Managed windows of the app, and how many of them float now.
    public var windows: Int
    public var floatingWindows: Int

    public init(bundleID: String, name: String, rule: String, mode: String, source: String, running: Bool, windows: Int, floatingWindows: Int) {
        self.bundleID = bundleID
        self.name = name
        self.rule = rule
        self.mode = mode
        self.source = source
        self.running = running
        self.windows = windows
        self.floatingWindows = floatingWindows
    }
}

public enum AppRuleError: Error, Equatable, CustomStringConvertible {
    case emptyBundleID
    case persistFailed(String)

    public var description: String {
        switch self {
        case .emptyBundleID: return "a bundle id is required"
        case .persistFailed(let m): return "could not save the rule: \(m)"
        }
    }
}

/// Per-app tile / float / auto rules (config.toml `[appRules]`), as one small API for the CLI, IPC
/// and the future Settings app:
/// - `appRuleEntries()`: running apps with windows, every app with a user rule and the built-in
///   floating apps, each with its effective mode;
/// - `setAppRule(_:for:)`: sets (or with `.auto` clears) a rule, saves it and applies it to the
///   app's open windows at once;
/// - `focusedAppRule()`: the entry for the app of the focused window.
extension WindowManager {
    public func appRuleEntries() -> [AppRuleEntry] {
        let book = config.appRuleBook
        var names: [String: String] = [:]
        var running: Set<String> = []
        for app in runningApps() where !app.bundleID.isEmpty {
            running.insert(app.bundleID)
            names[app.bundleID] = app.name
        }
        var windows: [String: (all: Int, floating: Int)] = [:]
        for id in managedWindowIDs {
            guard let bundle = handles[id]?.bundleID, !bundle.isEmpty else { continue }
            running.insert(bundle)
            if names[bundle] == nil, let n = descriptors[id]?.appName, !n.isEmpty { names[bundle] = n }
            var c = windows[bundle] ?? (0, 0)
            c.all += 1
            if isFloating(id) { c.floating += 1 }
            windows[bundle] = c
        }
        var bundles = running.union(book.user.keys)
        bundles.formUnion(AppRuleBook.builtInFloating.keys)
        return bundles.sorted { a, b in
            let ra = running.contains(a), rb = running.contains(b)
            if ra != rb { return ra }
            return (names[a] ?? AppRuleBook.builtInFloating[a] ?? a).localizedCaseInsensitiveCompare(names[b] ?? AppRuleBook.builtInFloating[b] ?? b) == .orderedAscending
        }.map { entry(for: $0, book: book, name: names[$0], running: running.contains($0), counts: windows[$0]) }
    }

    public func appRuleEntry(for bundleID: String) -> AppRuleEntry {
        let counts = managedWindowIDs.reduce(into: (all: 0, floating: 0)) { c, id in
            guard handles[id]?.bundleID.lowercased() == bundleID.lowercased() else { return }
            c.all += 1
            if isFloating(id) { c.floating += 1 }
        }
        let name = runningApps().first { $0.bundleID.lowercased() == bundleID.lowercased() }?.name
            ?? managedWindowIDs.lazy.compactMap { id in self.handles[id]?.bundleID == bundleID ? self.descriptors[id]?.appName : nil }.first
        let running = counts.all > 0 || runningApps().contains { $0.bundleID.lowercased() == bundleID.lowercased() }
        return entry(for: bundleID, book: config.appRuleBook, name: name, running: running, counts: counts)
    }

    public func focusedAppRule() -> AppRuleEntry? {
        guard let f = state.focusedWindow, let bundle = handles[f]?.bundleID, !bundle.isEmpty else { return nil }
        return appRuleEntry(for: bundle)
    }

    /// Sets the rule for `bundleID`, saves it (`appRulePersister`, config.toml in the daemon) and
    /// applies it to the app's open windows. `.auto` removes the user rule.
    @discardableResult
    public func setAppRule(_ mode: AppLayoutMode, for bundleID: String) throws -> AppRuleEntry {
        let bundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundle.isEmpty else { throw AppRuleError.emptyBundleID }
        if let persist = appRulePersister {
            do { try persist(bundle, mode) } catch { throw AppRuleError.persistFailed(String(describing: error)) }
        }
        var c = config
        var book = c.appRuleBook
        book.set(mode, for: bundle)
        c.appRules = book.configValue
        apply(config: c)
        return appRuleEntry(for: bundle)
    }

    private func entry(for bundle: String, book: AppRuleBook, name: String?, running: Bool, counts: (all: Int, floating: Int)?) -> AppRuleEntry {
        let m = book.mode(for: bundle)
        return AppRuleEntry(
            bundleID: bundle, name: name ?? AppRuleBook.builtInFloating[bundle] ?? bundle,
            rule: book.userMode(for: bundle)?.rawValue ?? AppLayoutMode.auto.rawValue,
            mode: m.mode.rawValue, source: m.source.rawValue, running: running,
            windows: counts?.all ?? 0, floatingWindows: counts?.floating ?? 0)
    }

    /// After a rule change, windows of the apps whose effective mode changed are tiled or
    /// floated to match. Apps whose mode did not change keep whatever the user did by hand.
    func reapplyAppRules(from old: AppRuleBook) {
        let new = config.appRuleBook
        guard new != old else { return }
        for id in managedWindowIDs {
            guard let d = descriptors[id], userFloatChoice(d) == nil,
                  old.mode(for: d.bundleID).mode != new.mode(for: d.bundleID).mode else { continue }
            let shouldFloat = new.floats(d, ruleFloat: effects[id]?.float)
            guard shouldFloat != isFloating(id), let area = area(of: id) else { continue }
            if shouldFloat {
                let current = handles[id]?.frame ?? .null
                let size = current.isNull ? CGSize(width: area.width * 0.6, height: area.height * 0.7) : current.size
                state.setFloating(id, true, frame: Self.clamp(centered(size, in: area), to: area).integralPoints, env: environment)
            } else {
                state.setFloating(id, false, env: environment)
            }
            forceApply.insert(id)
        }
        setNeedsLayout()
    }
}
