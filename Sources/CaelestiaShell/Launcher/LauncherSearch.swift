import CaelestiaCore
import Foundation

/// A launcher action (`>` prefix, spec 5.3), as Caelestia lists them.
public struct LauncherCommand: Hashable, Sendable, Identifiable {
    public enum Effect: Hashable, Sendable {
        case session(SessionAction)
        /// Replaces the search text (`>calculator` turns into `=`).
        case fill(String)
        /// Writes these config keys in one edit (a `>scheme`, `>variant` or `>transparency` choice).
        case setConfig([ConfigSetting])
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
        LauncherCommand("calculator", "Do simple math equations", icon: "calculate", effect: .fill("=")),
        LauncherCommand("scheme", "Change the current colour scheme", icon: "palette", effect: .autocomplete("scheme")),
        LauncherCommand("wallpaper", "Change the current wallpaper", icon: "image", effect: .autocomplete("wallpaper")),
        LauncherCommand("variant", "Change the current scheme variant", icon: "contrast", effect: .autocomplete("variant")),
        LauncherCommand("transparency", "Change shell transparency", icon: "opacity", effect: .autocomplete("transparency")),
        LauncherCommand("random", "Switch to a random wallpaper", icon: "shuffle", effect: .randomWallpaper),
        LauncherCommand("lock", "Lock the current session", icon: "lock", effect: .session(.lock)),
        LauncherCommand("sleep", "Put the Mac to sleep", icon: "bedtime", effect: .session(.sleep)),
        LauncherCommand("shutdown", "Shut down the Mac", icon: "power_settings_new", effect: .session(.shutdown)),
        LauncherCommand("reboot", "Restart the Mac", icon: "cached", effect: .session(.reboot)),
        LauncherCommand("restart", "Restart SkyRose (windows are restored first)", icon: "restart_alt", effect: .session(.restartSkyRose)),
        LauncherCommand("logout", "Log out of the current session", icon: "logout", effect: .session(.logout)),
        LauncherCommand("settings", "Open SkyRose Settings", icon: "settings", effect: .openSettings),
        LauncherCommand("store", "Browse, install and update addons (SkyStore)", icon: "storefront", effect: .drawer(.store)),
    ]

    /// The choices behind `>scheme `, `>variant ` and `>transparency `, keyed by command name.
    /// `addonSchemes` are (theme id, title) of enabled SkyStore scheme addons. The current
    /// choice gets a check icon.
    public static func options(_ a: AppearanceConfig, addonSchemes: [(id: String, title: String)] = []) -> [String: [LauncherCommand]] {
        let dynamic = SchemeResolver.isDynamic(a)
        func pick(_ title: String, _ detail: String, current: Bool, icon: String, _ values: [(String, ConfigValue)]) -> LauncherCommand {
            LauncherCommand(title, detail, icon: current ? "check" : icon, effect: .setConfig(values.map { ConfigSetting(path: $0.0, value: $0.1) }))
        }
        var schemes = ["dark", "light"].map { mode in
            pick("Wallpaper colours (\(mode))", "Taken from your wallpaper, \(mode) mode",
                 current: dynamic && a.variant.lowercased() == mode, icon: "wallpaper",
                 [("appearance.schemeMode", .string("dynamic")), ("appearance.variant", .string(mode))])
        }
        let builtIn = SchemeLoader.builtInNames.map { ($0, SchemeLoader.builtInTitles[$0] ?? $0) }
        let current = SchemeLoader.canonicalName(a.theme)
        for (id, title) in builtIn + addonSchemes.map({ ($0.id, $0.title) }) {
            schemes.append(pick(title, "Static scheme \(id)", current: !dynamic && current == id, icon: "palette",
                                [("appearance.schemeMode", .string("static")), ("appearance.theme", .string(id))]))
        }
        let styleNotes = ["tonalspot": "Calm, the default", "vibrant": "Strong colour everywhere", "expressive": "Shifted, playful hues",
                          "fidelity": "Close to the wallpaper colour", "content": "Close to the wallpaper colour, softer accents",
                          "fruitsalad": "Bold, rotated hues", "rainbow": "Colourful accents on grey surfaces",
                          "neutral": "Nearly grey", "monochrome": "Grey only"]
        let variants = DynamicScheme.styles.map { s in
            pick(s, (styleNotes[s] ?? "") + " (wallpaper colours)", current: dynamic && a.paletteStyle.lowercased() == s, icon: "contrast",
                 [("appearance.schemeMode", .string("dynamic")), ("appearance.paletteStyle", .string(s))])
        }
        let levels: [(String, String, Double, Double)] = [("Low", "Mostly solid panels", 0.9, 0.5), ("Normal", "The default", 0.75, 0.35),
                                                          ("High", "See-through panels", 0.55, 0.25)]
        var transparency = [pick("Off", "Solid panels", current: !a.transparencyEnabled, icon: "opacity",
                                 [("appearance.transparencyEnabled", .bool(false))])]
        for (title, detail, base, layers) in levels {
            transparency.append(pick(title, detail, current: a.transparencyEnabled && abs(a.transparencyBase - base) < 0.001 && abs(a.transparencyLayers - layers) < 0.001,
                                     icon: "opacity", [("appearance.transparencyEnabled", .bool(true)), ("appearance.transparencyBase", .number(base)),
                                                       ("appearance.transparencyLayers", .number(layers))]))
        }
        return ["scheme": schemes, "variant": variants, "transparency": transparency]
    }
}

/// One config key and value a launcher choice writes.
public struct ConfigSetting: Hashable, Sendable {
    public var path: String
    public var value: ConfigValue
    public init(path: String, value: ConfigValue) { self.path = path; self.value = value }
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

    public static func results(for rawQuery: String, apps: [LaunchableApp], commands: [LauncherCommand] = LauncherCommand.all,
                               options: [String: [LauncherCommand]] = [:], limit: Int = 50) -> [LauncherItem] {
        // `>scheme dra`: the choices of that command, filtered by what follows its name.
        if rawQuery.hasPrefix(commandPrefix), let space = rawQuery.firstIndex(of: " "),
           let list = options[String(rawQuery[rawQuery.index(after: rawQuery.startIndex)..<space])] {
            return rank(String(rawQuery[space...]).trimmingCharacters(in: .whitespaces), list)
        }
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        if query.hasPrefix(commandPrefix) {
            return rank(String(query.dropFirst()).trimmingCharacters(in: .whitespaces), commands)
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

    /// Commands matching `rest` (name, or half weight on the description), best first; all of them, in order, for "".
    static func rank(_ rest: String, _ commands: [LauncherCommand]) -> [LauncherItem] {
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
