import Foundation

/// A value written through ``ConfigAPI``.
public enum ConfigValue: Equatable, Sendable, CustomStringConvertible {
    case bool(Bool)
    case number(Double)
    case int(Int)
    case string(String)
    /// An inline array of tables, e.g. `bar.statusIcons`: each element is `[key: TOML literal]`.
    case tables([[String: ConfigValue]])
    /// A TOML literal written as is (an array or inline table typed on the command line).
    case literal(String)

    /// The value as a TOML literal.
    public var toml: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .number(let d): return ConfigFileEditor.number(d)
        case .int(let i): return String(i)
        case .string(let s): return ConfigFileEditor.string(s)
        case .tables(let rows):
            let inner = rows.map { row in
                "{ " + row.keys.sorted().map { "\(ConfigFileEditor.tomlKey($0)) = \(row[$0]!.toml)" }.joined(separator: ", ") + " }"
            }
            return "[" + inner.joined(separator: ", ") + "]"
        case .literal(let t): return t
        }
    }

    public var description: String { toml }

    /// Reads a value from the command line / IPC: `true`/`false`, a number, else a string.
    public static func parse(cli text: String) -> ConfigValue {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t == "true" { return .bool(true) }
        if t == "false" { return .bool(false) }
        if let i = Int(t) { return .int(i) }
        if let d = Double(t) { return .number(d) }
        if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") { return .string(String(t.dropFirst().dropLast())) }
        if t.hasPrefix("[") || t.hasPrefix("{") { return .literal(t) }
        return .string(t)
    }
}

/// Errors from ``ConfigAPI``.
public enum ConfigAPIError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case badPath(String)
    /// The edit made the file invalid; it was rolled back.
    case rejected(path: String, reason: String)
    case io(String)

    public var description: String {
        switch self {
        case .badPath(let p): return "\"\(p)\" is not a config key (use table.key, e.g. wm.gapsIn)"
        case .rejected(let p, let r): return "\(p) not changed: \(r)"
        case .io(let m): return m
        }
    }

    public var errorDescription: String? { description }
}

/// The config API: one key at a time, written into the user's `config.toml` without touching
/// anything else in it (comments and order stay, see ``ConfigFileEditor``). Every edit is checked
/// by parsing the whole file with ``ConfigLoader``; an edit that would make it invalid (wrong
/// type, out of range, unknown mode) is rolled back and reported, so a running WM never sees a
/// bad file. The WM applies a good edit live (config watcher, or at once through the IPC
/// `config.set`). Used by SkyRose Settings, `skyrose config set` and the onboarding.
public struct ConfigAPI: Sendable {
    public let file: URL

    public init(file: URL = Paths.configFile) {
        self.file = file
    }

    /// The config as written (defaults for everything the file leaves out). Not ``Config/effective``.
    public func load() -> Config { ConfigLoader.loadUserOrDefault(url: file).config }

    /// Sets `path` (e.g. `wm.gapsIn`, `wm.dwindle.preserveSplit`, `displays.<uuid>.displayCornerRadius`,
    /// `appRules.<bundle id>`) and returns the new config.
    @discardableResult
    public func set(_ path: String, _ value: ConfigValue) throws -> ConfigParseResult {
        let (table, key) = try Self.split(path)
        return try edit(path) { ConfigFileEditor.setting(key, to: value.toml, inTable: table, in: $0) }
    }

    /// Removes `path` from the file (back to its default).
    @discardableResult
    public func reset(_ path: String) throws -> ConfigParseResult {
        let (table, key) = try Self.split(path)
        return try edit(path) { ConfigFileEditor.removing(key, inTable: table, in: $0) }
    }

    /// Several keys in one write (one reload in the WM).
    @discardableResult
    public func set(_ values: [(String, ConfigValue)]) throws -> ConfigParseResult {
        let parts = try values.map { (try Self.split($0.0), $0.1) }
        return try edit(values.map(\.0).joined(separator: ", ")) { text in
            parts.reduce(text) { t, p in ConfigFileEditor.setting(p.0.key, to: p.1.toml, inTable: p.0.table, in: t) }
        }
    }

    private func edit(_ path: String, _ change: (String) -> String) throws -> ConfigParseResult {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: file.path)
        let before = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let after = change(before)
        let result: ConfigParseResult
        do {
            result = try ConfigLoader.parseDetailed(toml: after)
        } catch {
            throw ConfigAPIError.rejected(path: path, reason: String(describing: error))
        }
        guard after != before else { return result }
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(after.utf8).write(to: file, options: .atomic)
        } catch {
            if !existed { try? fm.removeItem(at: file) }
            throw ConfigAPIError.io("cannot write \(file.path): \(error.localizedDescription)")
        }
        return result
    }

    /// `a.b.c` → table `a.b`, key `c`. `appRules.<bundle>` and `displays.<id>.<key>` keep the dots
    /// of a bundle id / quote the display id.
    public static func split(_ path: String) throws -> (table: String, key: String) {
        if path.hasPrefix("appRules.") {
            let key = String(path.dropFirst("appRules.".count))
            guard !key.isEmpty else { throw ConfigAPIError.badPath(path) }
            return ("appRules", key)
        }
        let parts = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { throw ConfigAPIError.badPath(path) }
        if parts[0] == "displays", parts.count == 3 {
            return (ConfigFileEditor.displayTable(parts[1]), parts[2])
        }
        return (parts.dropLast().joined(separator: "."), parts.last!)
    }

    /// The value at `path` in `config` as JSON-ish data (for `config.get`), nil when absent.
    public static func value(at path: String, in config: Config) -> Any? {
        guard let data = try? JSONEncoder().encode(config), var node = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if path.isEmpty { return node }
        let keys: [String]
        if path.hasPrefix("appRules.") { keys = ["appRules", String(path.dropFirst("appRules.".count))] } else {
            keys = path.split(separator: ".").map(String.init)
        }
        for k in keys {
            guard let dict = node as? [String: Any], let next = dict[k] else { return nil }
            node = next
        }
        return node
    }
}
