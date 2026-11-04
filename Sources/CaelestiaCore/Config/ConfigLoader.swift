import Foundation
import TOMLKit

// MARK: - Errors

/// One validation problem in a config file, located by its TOML key path (`wm.gapsIn`,
/// `bar.statusIcons[2].id`, `displays."<uuid>".uiScale`).
public struct ConfigIssue: Hashable, Sendable, CustomStringConvertible {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String { "\(path): \(message)" }
}

/// Errors raised while loading, merging, validating or saving `config.toml`.
///
/// Unknown keys are never errors: they are reported as warnings (see ``ConfigParseResult``).
public enum ConfigError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    /// The document is not valid TOML. The payload includes the line/column from toml++.
    case syntax(String)
    /// A key exists with the wrong TOML type (e.g. a string where a number is expected).
    case typeMismatch(path: String, expected: String, found: String)
    /// A required key is missing (only possible inside user-defined map entries such as a new
    /// `[wm.specialWorkspaces.<name>]`, where `apps` and `launch` are mandatory).
    case missingKey(path: String)
    /// One or more values are out of range or malformed. Every issue is listed with its key path.
    case invalid([ConfigIssue])
    /// A bundled resource could not be found in `Bundle.module`.
    case resourceMissing(String)
    /// Reading or writing a file failed.
    case io(path: String, message: String)
    /// Encoding the Swift defaults failed; this indicates a programming error, not a user error.
    case internalFailure(String)

    public var description: String {
        switch self {
        case .syntax(let message): return "TOML syntax error: \(message)"
        case .typeMismatch(let path, let expected, let found): return "\(path): expected \(expected), found \(found)"
        case .missingKey(let path): return "\(path): required key is missing"
        case .invalid(let issues): return issues.map(\.description).joined(separator: "; ")
        case .resourceMissing(let name): return "bundled resource \"\(name)\" is missing"
        case .io(let path, let message): return "\(path): \(message)"
        case .internalFailure(let message): return "internal error: \(message)"
        }
    }

    public var errorDescription: String? { description }

    /// Key paths of every ``ConfigIssue`` in an ``invalid(_:)`` error, empty otherwise.
    public var issuePaths: [String] {
        if case .invalid(let issues) = self { return issues.map(\.path) }
        return []
    }
}

/// The outcome of a successful parse: the merged config plus non-fatal warnings (unknown keys).
public struct ConfigParseResult: Equatable, Sendable {
    public let config: Config
    public let warnings: [String]

    public init(config: Config, warnings: [String]) {
        self.config = config
        self.warnings = warnings
    }
}

// MARK: - Loader

/// Parses, merges, validates and writes `config.toml`.
///
/// Precedence (spec section 9): built-in defaults (`Config()`) < `~/.config/caelestia-mac/config.toml`
/// < per-display overrides (`[displays."<uuid>"]`, applied by `Config.resolved(forDisplay:)`).
///
/// The TOML layout mirrors the struct nesting: `[wm]`, `[wm.dwindle]`, `[wm.specialWorkspaces.<name>]`,
/// `[appearance]`, `[bar]`, `[[bar.statusIcons]]`, `[input]`, `[apps]`, `[animations]`,
/// `[animations.overrides.<name>]`, `[displays."<uuid>"]`. A user file may set any subset of keys;
/// everything it leaves out keeps the Swift default. Integers are accepted where a float is expected
/// (`gapsIn = 5`), unknown keys produce warnings, out-of-range values produce ``ConfigError/invalid(_:)``.
public enum ConfigLoader {
    /// File name of the fully commented default config shipped in the module resources.
    public static let defaultResourceName = "config.default.toml"

    // MARK: Parsing

    /// Parses a TOML document and merges it over `Config()`. Warnings are dropped; use
    /// ``parseDetailed(toml:)`` to receive them.
    public static func parse(toml: String) throws -> Config {
        try parseDetailed(toml: toml).config
    }

    /// Parses a TOML document, merges it over `Config()`, validates it and reports unknown keys.
    public static func parseDetailed(toml: String) throws -> ConfigParseResult {
        let user: TOMLTable
        do {
            user = try TOMLTable(string: toml)
        } catch let error as TOMLParseError {
            throw ConfigError.syntax(error.debugDescription)
        } catch {
            throw ConfigError.syntax(String(describing: error))
        }

        let base = try encodeTable(Config())
        let schema = try makeSchema()
        var warnings: [String] = []
        try merge(user: user, into: base, schema: schema, path: "", warnings: &warnings)
        ensureMapTables(in: base)

        let config: Config
        do {
            config = try TOMLDecoder().decode(Config.self, from: base)
        } catch let error as DecodingError {
            throw ConfigError(decodingError: error)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.internalFailure(String(describing: error))
        }

        let issues = validate(config)
        if !issues.isEmpty { throw ConfigError.invalid(issues) }
        return ConfigParseResult(config: config, warnings: warnings)
    }

    /// Serializes a full config (every key, including the defaults) as TOML.
    public static func serialize(_ config: Config) throws -> String {
        let body: String
        do {
            body = try TOMLEncoder().encode(config)
        } catch {
            throw ConfigError.internalFailure("encoding Config failed: \(error)")
        }
        return """
        # Caelestia for Mac configuration (written by ConfigLoader.serialize).
        # Every key is documented in config.default.toml; keys you remove fall back to the defaults.

        """ + body
    }

    // MARK: Files

    /// Loads and parses the file at `url` (warnings dropped).
    public static func load(from url: URL) throws -> Config {
        try loadDetailed(from: url).config
    }

    /// Loads and parses the file at `url`, returning warnings as well.
    public static func loadDetailed(from url: URL) throws -> ConfigParseResult {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError.io(path: url.path, message: error.localizedDescription)
        }
        return try parseDetailed(toml: text)
    }

    /// Loads `~/.config/caelestia-mac/config.toml` when it exists and parses cleanly; otherwise returns
    /// `Config()` with a warning describing the problem. A missing file is not a warning.
    public static func loadUserOrDefault(url: URL = Paths.configFile) -> (config: Config, warnings: [String]) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (Config(), []) }
        do {
            let result = try loadDetailed(from: url)
            return (result.config, result.warnings)
        } catch {
            let message = "\(url.path): \(error); using built-in defaults"
            Log.config.error("\(message, privacy: .public)")
            return (Config(), [message])
        }
    }

    /// Writes the config atomically, creating parent directories as needed.
    public static func save(_ config: Config, to url: URL) throws {
        let text = try serialize(config)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw ConfigError.io(path: url.path, message: error.localizedDescription)
        }
    }

    // MARK: Bundled default

    /// Location of `config.default.toml` inside the module bundle, if present.
    public static func defaultResourceURL() -> URL? {
        CoreResources.url(forResource: "config.default", withExtension: "toml")
    }

    /// The raw text of the bundled `config.default.toml`.
    public static func defaultResourceText() throws -> String {
        try CoreResources.string(forResource: "config.default", withExtension: "toml")
    }

    /// Parses the bundled `config.default.toml`. Tests assert the result equals `Config()`.
    public static func loadDefaultResource() throws -> Config {
        try parse(toml: defaultResourceText())
    }

    // MARK: - Schema & merge

    /// Tables whose keys are user-defined names rather than fixed fields. Their children are validated
    /// against the prototype stored under ``mapPrototypeKey`` in the schema table.
    static let mapTablePaths: Set<String> = ["displays", "animations.overrides", "wm.specialWorkspaces"]
    static let mapPrototypeKey = "*"

    static func encodeTable<T: Encodable>(_ value: T) throws -> TOMLTable {
        do {
            return try TOMLEncoder().encode(value)
        } catch {
            throw ConfigError.internalFailure("encoding \(T.self) failed: \(error)")
        }
    }

    /// Encodes a fully populated prototype so that every known key (including optional ones and the
    /// entries of user-keyed maps) exists in the schema table with its expected TOML type.
    static func makeSchema() throws -> TOMLTable {
        var proto = Config()
        var display = DisplayOverride()
        display.gapsIn = 0
        display.gapsOut = 0
        display.gapsOutSingle = 0
        display.barPersistent = true
        display.barEnabled = true
        display.uiScale = 1
        display.screenFrame = true
        display.displayCornerRadius = 0
        proto.displays = [mapPrototypeKey: display]
        proto.animations.overrides = [mapPrototypeKey: AnimationOverride(enabled: true, curve: "", speed: 1, style: "")]
        proto.wm.specialWorkspaces = [mapPrototypeKey: SpecialWorkspaceConfig(apps: [""], launch: "")]
        proto.bar.statusIcons = [BarConfig.StatusIcon(id: "", enabled: true)]
        return try encodeTable(proto)
    }

    /// Deep-merges `user` over `base`, validating every key against `schema`. Unknown keys are
    /// skipped with a warning; type mismatches throw; integers are widened to floats where the schema
    /// expects a float and integral floats are narrowed where it expects an integer.
    static func merge(user: TOMLTable, into base: TOMLTable, schema: TOMLTable, path: String, warnings: inout [String]) throws {
        let isMap = mapTablePaths.contains(path)
        for (key, raw) in user {
            let value = raw.tomlValue
            let childPath = joinPath(path, key)
            guard let schemaChild = (isMap ? schema[mapPrototypeKey] : schema[key])?.tomlValue else {
                warnings.append("unknown key \"\(childPath)\" (ignored)")
                continue
            }
            switch (schemaChild.type, value.type) {
            case (.table, .table):
                if base[key]?.table == nil { base[key] = TOMLTable() }
                guard let baseChild = base[key]?.table, let schemaTable = schemaChild.table, let userTable = value.table else {
                    throw ConfigError.internalFailure("table expected at \(childPath)")
                }
                try merge(user: userTable, into: baseChild, schema: schemaTable, path: childPath, warnings: &warnings)
            case (.array, .array):
                guard let schemaArray = schemaChild.array, let userArray = value.array else {
                    throw ConfigError.internalFailure("array expected at \(childPath)")
                }
                base[key] = try coerceArray(userArray, schema: schemaArray, path: childPath, warnings: &warnings)
            default:
                base[key] = try coerceScalar(value, schema: schemaChild, path: childPath)
            }
        }
    }

    private static func coerceArray(_ array: TOMLArray, schema: TOMLArray, path: String, warnings: inout [String]) throws -> TOMLArray {
        let result = TOMLArray()
        let prototype = schema.isEmpty ? nil : schema[0].tomlValue
        for (index, raw) in array.enumerated() {
            let element = raw.tomlValue
            let elementPath = "\(path)[\(index)]"
            guard let prototype else {
                result.append(element)
                continue
            }
            switch (prototype.type, element.type) {
            case (.table, .table):
                guard let protoTable = prototype.table, let elementTable = element.table else {
                    throw ConfigError.internalFailure("table expected at \(elementPath)")
                }
                let merged = TOMLTable()
                try merge(user: elementTable, into: merged, schema: protoTable, path: elementPath, warnings: &warnings)
                result.append(merged)
            case (.array, .array):
                guard let protoArray = prototype.array, let elementArray = element.array else {
                    throw ConfigError.internalFailure("array expected at \(elementPath)")
                }
                result.append(try coerceArray(elementArray, schema: protoArray, path: elementPath, warnings: &warnings))
            default:
                result.append(try coerceScalar(element, schema: prototype, path: elementPath))
            }
        }
        return result
    }

    private static func coerceScalar(_ value: TOMLValue, schema: TOMLValue, path: String) throws -> TOMLValueConvertible {
        switch (schema.type, value.type) {
        case (.double, .int):
            guard let i = value.int else { throw ConfigError.internalFailure("integer expected at \(path)") }
            return Double(i)
        case (.int, .double):
            guard let d = value.double, d == d.rounded(), abs(d) < 9_007_199_254_740_992 else {
                throw ConfigError.typeMismatch(path: path, expected: "integer", found: "floating-point number")
            }
            return Int(d)
        case (let expected, let found) where expected == found:
            return value
        case (let expected, let found):
            throw ConfigError.typeMismatch(path: path, expected: expected.description, found: found.description)
        }
    }

    /// Codable requires dictionary-valued fields to exist even when empty, but `TOMLEncoder` omits
    /// empty tables; make sure every map table exists before decoding.
    private static func ensureMapTables(in root: TOMLTable) {
        for path in mapTablePaths {
            var table = root
            for component in path.split(separator: ".").map(String.init) {
                if table[component]?.table == nil { table[component] = TOMLTable() }
                guard let next = table[component]?.table else { break }
                table = next
            }
        }
    }

    static func joinPath(_ parent: String, _ key: String) -> String {
        let quoted = key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) && !key.isEmpty ? key : "\"\(key)\""
        return parent.isEmpty ? quoted : "\(parent).\(quoted)"
    }

    // MARK: - Validation

    /// Checks ranges and formats. Returns every problem found (empty when the config is valid).
    public static func validate(_ c: Config) -> [ConfigIssue] {
        var issues: [ConfigIssue] = []
        func check(_ ok: Bool, _ path: String, _ message: String) {
            if !ok { issues.append(ConfigIssue(path: path, message: message)) }
        }
        func nonNegative(_ v: Double, _ path: String) { check(v >= 0, path, "must be >= 0 (got \(v))") }
        func positive(_ v: Double, _ path: String) { check(v > 0, path, "must be > 0 (got \(v))") }
        func unit(_ v: Double, _ path: String) { check(v >= 0 && v <= 1, path, "must be between 0 and 1 (got \(v))") }

        let wm = c.wm
        nonNegative(wm.gapsIn, "wm.gapsIn")
        nonNegative(wm.gapsOut, "wm.gapsOut")
        nonNegative(wm.gapsOutSingle, "wm.gapsOutSingle")
        nonNegative(wm.gapsWorkspaces, "wm.gapsWorkspaces")
        nonNegative(wm.borderSize, "wm.borderSize")
        nonNegative(wm.windowRounding, "wm.windowRounding")
        check(wm.roundingPower >= 1 && wm.roundingPower <= 10, "wm.roundingPower", "must be between 1 and 10 (got \(wm.roundingPower))")
        nonNegative(wm.popupRounding, "wm.popupRounding")
        unit(wm.windowOpacity, "wm.windowOpacity")
        nonNegative(wm.blurSize, "wm.blurSize")
        check(wm.blurPasses >= 0, "wm.blurPasses", "must be >= 0 (got \(wm.blurPasses))")
        nonNegative(wm.shadowRange, "wm.shadowRange")
        check(wm.shadowRenderPower >= 1 && wm.shadowRenderPower <= 4, "wm.shadowRenderPower", "must be between 1 and 4 (got \(wm.shadowRenderPower))")
        nonNegative(wm.screenFrameInset, "wm.screenFrameInset")
        check(c.frame.displayCornerRadius <= FrameConfig.maxRadius, "frame.displayCornerRadius", "must be at most \(Int(FrameConfig.maxRadius)) (got \(c.frame.displayCornerRadius); negative = auto)")
        check(wm.focusFollowsMouseDelayMs >= 0, "wm.focusFollowsMouseDelayMs", "must be >= 0 (got \(wm.focusFollowsMouseDelayMs))")
        check(wm.workspacesPerGroup >= 1, "wm.workspacesPerGroup", "must be >= 1 (got \(wm.workspacesPerGroup))")
        check(wm.workspaceGroups >= 1, "wm.workspaceGroups", "must be >= 1 (got \(wm.workspaceGroups))")
        check(
            wm.workspacesShown >= 1 && wm.workspacesShown <= max(1, wm.workspacesPerGroup), "wm.workspacesShown",
            "must be between 1 and workspacesPerGroup (got \(wm.workspacesShown))")

        let d = wm.dwindle
        check(d.forceSplit >= 0 && d.forceSplit <= 2, "wm.dwindle.forceSplit", "must be 0, 1 or 2 (got \(d.forceSplit))")
        positive(d.splitWidthMultiplier, "wm.dwindle.splitWidthMultiplier")
        check(d.minSplitRatio > 0 && d.minSplitRatio < 2, "wm.dwindle.minSplitRatio", "must be in (0, 2) (got \(d.minSplitRatio))")
        check(d.maxSplitRatio > 0 && d.maxSplitRatio < 2, "wm.dwindle.maxSplitRatio", "must be in (0, 2) (got \(d.maxSplitRatio))")
        check(d.minSplitRatio <= d.maxSplitRatio, "wm.dwindle.minSplitRatio", "must be <= maxSplitRatio")
        check(
            d.defaultSplitRatio >= d.minSplitRatio && d.defaultSplitRatio <= d.maxSplitRatio, "wm.dwindle.defaultSplitRatio",
            "must be between minSplitRatio and maxSplitRatio (got \(d.defaultSplitRatio))")

        for (name, ws) in wm.specialWorkspaces.sorted(by: { $0.key < $1.key }) {
            let path = joinPath("wm.specialWorkspaces", name)
            check(!name.isEmpty, "wm.specialWorkspaces", "workspace names must not be empty")
            check(!name.contains(":") && !name.contains(where: \.isWhitespace), path, "workspace names must not contain ':' or whitespace")
            for (i, app) in ws.apps.enumerated() {
                check(!app.isEmpty, "\(path).apps[\(i)]", "bundle ids must not be empty")
            }
        }

        let a = c.appearance
        unit(a.transparencyBase, "appearance.transparencyBase")
        unit(a.transparencyLayers, "appearance.transparencyLayers")
        check(!a.theme.isEmpty, "appearance.theme", "must not be empty")
        check(["dark", "light"].contains(a.variant.lowercased()), "appearance.variant", "must be \"dark\" or \"light\" (got \"\(a.variant)\")")
        check(
            a.accentOverride.isEmpty || RGBA(hex: a.accentOverride) != nil, "appearance.accentOverride",
            "must be empty or a hex color like \"bac5ee\" (got \"\(a.accentOverride)\")")
        check(["static", "dynamic"].contains(a.schemeMode.lowercased()), "appearance.schemeMode", "must be \"static\" or \"dynamic\" (got \"\(a.schemeMode)\")")
        check(["overview", "media", "performance"].contains(c.dashboard.defaultTab.lowercased()), "dashboard.defaultTab", "must be \"overview\", \"media\" or \"performance\" (got \"\(c.dashboard.defaultTab)\")")
        check(a.uiScale > 0 && a.uiScale <= 4, "appearance.uiScale", "must be in (0, 4] (got \(a.uiScale))")
        check(a.wallpaperRandomIntervalMinutes >= 0, "appearance.wallpaperRandomIntervalMinutes", "must be >= 0 (got \(a.wallpaperRandomIntervalMinutes))")

        positive(c.bar.width, "bar.width")
        var seenIcons: Set<String> = []
        for (i, icon) in c.bar.statusIcons.enumerated() {
            check(!icon.id.isEmpty, "bar.statusIcons[\(i)].id", "must not be empty")
            check(seenIcons.insert(icon.id).inserted, "bar.statusIcons[\(i)].id", "duplicate status icon \"\(icon.id)\"")
        }

        let input = c.input
        check(input.superTapMs >= 0, "input.superTapMs", "must be >= 0 (got \(input.superTapMs))")
        check(input.repeatDelayMs >= 0, "input.repeatDelayMs", "must be >= 0 (got \(input.repeatDelayMs))")
        check(input.repeatRatePerSecond >= 1, "input.repeatRatePerSecond", "must be >= 1 (got \(input.repeatRatePerSecond))")
        positive(input.scrollFactor, "input.scrollFactor")
        positive(input.scrollStepPoints, "input.scrollStepPoints")
        check(input.gestureFingers >= 1 && input.gestureFingers <= 10, "input.gestureFingers", "must be between 1 and 10 (got \(input.gestureFingers))")
        check(input.gestureFingersMore >= 1 && input.gestureFingersMore <= 10, "input.gestureFingersMore", "must be between 1 and 10 (got \(input.gestureFingersMore))")
        positive(input.gestureDistance, "input.gestureDistance")
        unit(input.gestureCancelRatio, "input.gestureCancelRatio")
        nonNegative(input.gestureMinSpeedToForce, "input.gestureMinSpeedToForce")
        nonNegative(input.gestureDirectionLockThreshold, "input.gestureDirectionLockThreshold")

        let anim = c.animations
        positive(anim.globalMultiplier, "animations.globalMultiplier")
        positive(anim.shellDurationScale, "animations.shellDurationScale")
        for (name, o) in anim.overrides.sorted(by: { $0.key < $1.key }) {
            let path = joinPath("animations.overrides", name)
            check(!name.isEmpty, "animations.overrides", "animation names must not be empty")
            if let speed = o.speed { positive(speed, "\(path).speed") }
        }

        for (id, o) in c.displays.sorted(by: { $0.key < $1.key }) {
            let path = joinPath("displays", id)
            check(!id.isEmpty, "displays", "display ids must not be empty")
            if let v = o.gapsIn { nonNegative(v, "\(path).gapsIn") }
            if let v = o.gapsOut { nonNegative(v, "\(path).gapsOut") }
            if let v = o.gapsOutSingle { nonNegative(v, "\(path).gapsOutSingle") }
            if let v = o.uiScale { check(v > 0 && v <= 4, "\(path).uiScale", "must be in (0, 4] (got \(v))") }
            if let v = o.displayCornerRadius { check(v <= FrameConfig.maxRadius, "\(path).displayCornerRadius", "must be at most \(Int(FrameConfig.maxRadius)) (got \(v); negative = auto)") }
        }
        return issues
    }
}

extension ConfigError {
    /// Maps a `DecodingError` from `TOMLDecoder` to a ``ConfigError`` with a dotted key path.
    init(decodingError error: DecodingError) {
        func join(_ keys: [CodingKey]) -> String {
            var out = ""
            for key in keys {
                if let index = key.intValue {
                    out += "[\(index)]"
                } else {
                    out = ConfigLoader.joinPath(out, key.stringValue)
                }
            }
            return out
        }
        switch error {
        case .keyNotFound(let key, let context):
            self = .missingKey(path: join(context.codingPath + [key]))
        case .valueNotFound(_, let context):
            self = .missingKey(path: join(context.codingPath))
        case .typeMismatch(let type, let context):
            self = .typeMismatch(path: join(context.codingPath), expected: String(describing: type), found: context.debugDescription)
        case .dataCorrupted(let context):
            self = .invalid([ConfigIssue(path: join(context.codingPath), message: context.debugDescription)])
        @unknown default:
            self = .internalFailure(String(describing: error))
        }
    }
}

// MARK: - Bundled resources

/// Locates files under `Sources/CaelestiaCore/Resources`, which SwiftPM copies into `Bundle.module`
/// as a `Resources` folder (`.copy("Resources")`). Falls back to a flat lookup for other layouts.
enum CoreResources {
    static func url(forResource name: String, withExtension ext: String, subdirectory: String? = nil) -> URL? {
        let bundle = Bundle.module
        let candidates: [String?] = subdirectory.map { ["Resources/\($0)", $0] } ?? ["Resources", nil]
        for sub in candidates {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: sub) { return url }
        }
        if let base = bundle.resourceURL {
            let relative = (subdirectory.map { "Resources/\($0)/" } ?? "Resources/") + "\(name).\(ext)"
            let url = base.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func string(forResource name: String, withExtension ext: String, subdirectory: String? = nil) throws -> String {
        let display = (subdirectory.map { "\($0)/" } ?? "") + "\(name).\(ext)"
        guard let url = url(forResource: name, withExtension: ext, subdirectory: subdirectory) else {
            throw ConfigError.resourceMissing(display)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError.io(path: url.path, message: error.localizedDescription)
        }
    }

    /// Names (without extension) of the resources in a bundled subdirectory, sorted.
    static func names(withExtension ext: String, subdirectory: String) -> [String] {
        let bundle = Bundle.module
        var urls: [URL] = []
        for sub in ["Resources/\(subdirectory)", subdirectory] {
            if let found = bundle.urls(forResourcesWithExtension: ext, subdirectory: sub), !found.isEmpty {
                urls = found
                break
            }
        }
        if urls.isEmpty, let base = bundle.resourceURL {
            let dir = base.appendingPathComponent("Resources/\(subdirectory)", isDirectory: true)
            let listed = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            urls = listed.filter { $0.pathExtension == ext }
        }
        return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }
}

// MARK: - Watcher

/// Watches `config.toml` (and its directory, so atomic saves and re-creation are seen), reloads
/// after a 100 ms debounce and delivers the result on the main queue. A broken file never replaces
/// the last good config: the handler receives ``Event/failed(_:lastGood:)`` instead.
public final class ConfigWatcher: @unchecked Sendable {
    /// What the handler receives after each (debounced) change.
    public enum Event: Sendable {
        /// The file parsed (or disappeared, in which case `Config()` is delivered with a warning).
        case loaded(Config, warnings: [String])
        /// Parsing or validation failed; `lastGood` is still in effect.
        case failed(any Error, lastGood: Config)
    }

    public typealias Handler = @Sendable (Event) -> Void

    public let url: URL
    public let debounce: TimeInterval

    private let handler: Handler
    private let queue = DispatchQueue(label: "com.caelestia.mac.config-watcher", qos: .utility)
    private let lock = NSLock()
    private var lastGoodConfig: Config
    private var lastContents: Data?
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var watchedDirectory: URL?
    private var pendingReload: DispatchWorkItem?
    private var running = false

    /// - Parameters:
    ///   - url: the config file to watch (defaults to `Paths.configFile`).
    ///   - initial: the config currently in effect (returned as `lastGood` until a reload succeeds).
    ///   - debounce: quiet period after the last file-system event before reloading.
    ///   - handler: invoked on the main queue.
    public init(url: URL = Paths.configFile, initial: Config = Config(), debounce: TimeInterval = 0.1, handler: @escaping Handler) {
        self.url = url
        self.debounce = debounce
        self.lastGoodConfig = initial
        self.handler = handler
    }

    deinit {
        pendingReload?.cancel()
        fileSource?.cancel()
        directorySource?.cancel()
    }

    /// The most recently loaded valid config (or the `initial` one).
    public var lastGood: Config {
        lock.withLock { lastGoodConfig }
    }

    /// Starts watching. A missing config directory is fine: the nearest existing ancestor is
    /// watched and the watch moves down as directories appear. Returns `false` only when not even
    /// an ancestor directory could be opened.
    ///
    /// The current file contents are snapshotted so only *subsequent* changes fire the handler, unless
    /// `emitInitial` is set, in which case one load is performed right away.
    @discardableResult
    public func start(emitInitial: Bool = false) -> Bool {
        queue.sync {
            guard !running else { return fileSource != nil || directorySource != nil }
            running = true
            lastContents = try? Data(contentsOf: url)
            armDirectorySource()
            armFileSource()
            if emitInitial { scheduleReload() }
            return fileSource != nil || directorySource != nil
        }
    }

    /// Stops watching; no further events are delivered.
    public func stop() {
        queue.sync {
            running = false
            pendingReload?.cancel()
            pendingReload = nil
            fileSource?.cancel()
            fileSource = nil
            directorySource?.cancel()
            directorySource = nil
        }
    }

    /// Forces a (debounced) reload even if no file-system event was observed.
    public func reload() {
        queue.async { self.scheduleReload(force: true) }
    }

    // MARK: Private (all on `queue`)

    private func makeSource(path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        source.setCancelHandler { close(fd) }
        return source
    }

    /// Watches the config's directory, or, while it does not exist yet, the nearest existing
    /// ancestor: creating `~/.config/caelestia-mac/` and then `config.toml` in it is seen (live
    /// finding: on a fresh Mac the directory is missing and the old watcher never armed).
    private func armDirectorySource() {
        let dir = Self.nearestExistingDirectory(for: url)
        if directorySource != nil, watchedDirectory == dir { return }
        directorySource?.cancel()
        directorySource = nil
        watchedDirectory = nil
        guard let source = makeSource(path: dir.path, mask: [.write, .rename, .delete, .attrib, .link]) else { return }
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                source.cancel()
                self.directorySource = nil
                self.watchedDirectory = nil
            }
            self.scheduleReload()
        }
        directorySource = source
        watchedDirectory = dir
        source.resume()
    }

    static func nearestExistingDirectory(for file: URL) -> URL {
        var dir = file.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        while dir.path.count > 1 {
            if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "/")
    }

    private func armFileSource() {
        guard fileSource == nil else { return }
        guard let source = makeSource(path: url.path, mask: [.write, .extend, .attrib, .rename, .delete]) else { return }
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                // Atomic saves replace the inode; the directory source keeps us alive meanwhile.
                source.cancel()
                self.fileSource = nil
            }
            self.scheduleReload()
        }
        fileSource = source
        source.resume()
    }

    private func scheduleReload(force: Bool = false) {
        guard running else { return }
        pendingReload?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.performReload(force: force) }
        pendingReload = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func performReload(force: Bool) {
        guard running else { return }
        pendingReload = nil
        armDirectorySource()
        armFileSource()

        let contents = try? Data(contentsOf: url)
        guard force || contents != lastContents else { return }
        lastContents = contents

        let event: Event
        if let contents {
            do {
                let result = try ConfigLoader.parseDetailed(toml: String(decoding: contents, as: UTF8.self))
                lock.withLock { lastGoodConfig = result.config }
                event = .loaded(result.config, warnings: result.warnings)
            } catch {
                Log.config.error("config reload failed: \(String(describing: error), privacy: .public)")
                event = .failed(error, lastGood: lastGood)
            }
        } else {
            let defaults = Config()
            lock.withLock { lastGoodConfig = defaults }
            event = .loaded(defaults, warnings: ["\(url.path): not found; using built-in defaults"])
        }
        let handler = self.handler
        DispatchQueue.main.async { handler(event) }
    }
}
