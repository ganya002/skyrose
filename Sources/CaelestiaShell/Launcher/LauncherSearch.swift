import Foundation

/// A launcher action (`>` prefix, spec 5.3), as Caelestia lists them.
public struct LauncherCommand: Hashable, Sendable, Identifiable {
    public enum Effect: Hashable, Sendable {
        case session(SessionAction)
        /// Exists in Caelestia but needs a later phase (wallpaper, schemes, Settings).
        case later(String)
        /// Opens one of the part-2 drawers (wallpaper picker).
        case drawer(Drawer)
        case randomWallpaper
        /// Opens SkyRose Settings.
        case openSettings
        /// Fills the search with `>name ` (Caelestia `autocomplete`): `>wallpaper ` turns the
        /// launcher into the wallpaper carousel.
        case autocomplete(String)
    }

    public var id: String { name }
    public var name: String
    public var description: String
    /// Material Symbols name (mapped by `ShellIcon.sf`).
    public var icon: String
    public var effect: Effect

    public init(_ name: String, _ description: String, icon: String, effect: Effect) {
        self.name = name
        self.description = description
        self.icon = icon
        self.effect = effect
    }

    public static let all: [LauncherCommand] = [
        LauncherCommand("calculator", "Do simple math equations", icon: "calculate", effect: .later("Type = followed by an expression")),
        LauncherCommand("scheme", "Change the current colour scheme", icon: "palette", effect: .later("Set appearance.schemeMode = \"dynamic\" or \"static\" in config.toml")),
        LauncherCommand("wallpaper", "Change the current wallpaper", icon: "image", effect: .autocomplete("wallpaper")),
        LauncherCommand("variant", "Change the current scheme variant", icon: "contrast", effect: .later("Scheme variants arrive with dynamic colour")),
        LauncherCommand("transparency", "Change shell transparency", icon: "opacity", effect: .later("Transparency is set in config.toml for now")),
        LauncherCommand("random", "Switch to a random wallpaper", icon: "shuffle", effect: .randomWallpaper),
        LauncherCommand("lock", "Lock the current session", icon: "lock", effect: .session(.lock)),
        LauncherCommand("sleep", "Put the Mac to sleep", icon: "bedtime", effect: .session(.sleep)),
        LauncherCommand("shutdown", "Shut down the Mac", icon: "power_settings_new", effect: .session(.shutdown)),
        LauncherCommand("reboot", "Restart the Mac", icon: "cached", effect: .session(.reboot)),
        LauncherCommand("logout", "Log out of the current session", icon: "logout", effect: .session(.logout)),
        LauncherCommand("settings", "Open SkyRose Settings", icon: "settings", effect: .openSettings),
    ]
}

/// One row of the launcher list.
public enum LauncherItem: Hashable, Sendable, Identifiable {
    case app(LaunchableApp)
    case command(LauncherCommand)
    /// `result` is nil for an expression that does not parse.
    case calc(expression: String, result: String?)

    public var id: String {
        switch self {
        case .app(let a): return "app:" + a.id
        case .command(let c): return "cmd:" + c.name
        case .calc(let e, _): return "calc:" + e
        }
    }

    public var title: String {
        switch self {
        case .app(let a): return a.name
        case .command(let c): return c.name
        case .calc(_, let r): return r ?? "Invalid expression"
        }
    }

    public var subtitle: String {
        switch self {
        case .app(let a): return a.description.isEmpty ? a.name : a.description
        case .command(let c): return c.description
        case .calc(let e, let r): return r == nil ? e : "\(e) — press Enter to copy"
        }
    }
}

/// Pure ranking (spec 5.3): fuzzy over name, bundle file name, keywords and description,
/// weighted by how often each app was launched.
public enum LauncherSearch {
    public static let commandPrefix = ">"
    public static let calcPrefix = "="

    public static func results(for rawQuery: String, apps: [LaunchableApp], commands: [LauncherCommand] = LauncherCommand.all, limit: Int = 50) -> [LauncherItem] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        if query.hasPrefix(commandPrefix) {
            let rest = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty else { return commands.map(LauncherItem.command) }
            return commands
                .compactMap { c -> (LauncherCommand, Int)? in
                    let n = FuzzyMatcher.match(rest, in: c.name)?.score
                    let d = FuzzyMatcher.match(rest, in: c.description).map { $0.score / 2 }
                    guard let best = [n, d].compactMap({ $0 }).max() else { return nil }
                    return (c, best)
                }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
                .map { .command($0.0) }
        }
        if query.hasPrefix(calcPrefix) {
            let expr = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !expr.isEmpty else { return [.calc(expression: "", result: nil)] }
            return [.calc(expression: expr, result: (try? Calculator.evaluate(expr)).map(Calculator.format))]
        }
        var items: [LauncherItem] = []
        if Calculator.looksLikeMath(query), let v = try? Calculator.evaluate(query) {
            items.append(.calc(expression: query, result: Calculator.format(v)))
        }
        if query.isEmpty {
            let sorted = apps.sorted {
                $0.launchCount != $1.launchCount ? $0.launchCount > $1.launchCount
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return items + sorted.prefix(limit).map(LauncherItem.app)
        }
        let scored = apps.compactMap { app -> (LaunchableApp, Int)? in
            guard let s = score(query, app) else { return nil }
            return (app, s)
        }
        let ranked = scored.sorted {
            $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
        }
        return items + ranked.prefix(limit).map { .app($0.0) }
    }

    /// Best field score + frequency bonus; nil when nothing matches.
    public static func score(_ query: String, _ app: LaunchableApp) -> Int? {
        var best: Int?
        func consider(_ s: Int?) { if let s { best = max(best ?? s, s) } }
        consider(FuzzyMatcher.match(query, in: app.name)?.score)
        let fileName = app.url.deletingPathExtension().lastPathComponent
        if fileName != app.name { consider(FuzzyMatcher.match(query, in: fileName).map { $0.score - 4 }) }
        for k in app.keywords { consider(FuzzyMatcher.match(query, in: k).map { $0.score * 4 / 5 }) }
        if !app.description.isEmpty, query.count >= 3 {
            consider(FuzzyMatcher.match(query, in: app.description).map { $0.score / 2 })
        }
        guard let b = best else { return nil }
        return b + frequencyBonus(app.launchCount)
    }

    public static func frequencyBonus(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(30, Int((8 * log2(Double(1 + count))).rounded()))
    }
}
