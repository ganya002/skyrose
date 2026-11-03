import Foundation
import TOMLKit

/// Errors raised while reading or converting colour schemes.
public enum SchemeError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    /// The document is not valid TOML / JSON.
    case syntax(String)
    /// `name` or the `[colors]` table is missing (or empty).
    case missingField(String)
    /// A colour value is not `RRGGBB` / `RRGGBBAA` hex.
    case invalidColor(key: String, value: String)
    /// A bundled scheme could not be found in `Bundle.module`.
    case resourceMissing(String)
    /// Reading a file failed.
    case io(path: String, message: String)

    public var description: String {
        switch self {
        case .syntax(let message): return "scheme syntax error: \(message)"
        case .missingField(let field): return "scheme is missing \"\(field)\""
        case .invalidColor(let key, let value): return "colors.\(key): \"\(value)\" is not a hex colour (RRGGBB or RRGGBBAA)"
        case .resourceMissing(let name): return "bundled scheme \"\(name)\" is missing"
        case .io(let path, let message): return "\(path): \(message)"
        }
    }

    public var errorDescription: String? { description }
}

/// Reads and writes colour schemes.
///
/// TOML format (the shipped schemes live in `Resources/schemes/*.toml`):
///
/// ```toml
/// name = "Caelestia Dynamic"
/// flavour = "default"      # optional, "default"
/// mode = "dark"            # optional, "dark" | "light"
/// variant = "tonalspot"    # optional, Material variant or "static"
///
/// [colors]                 # "colours" is accepted too
/// primary = "bac5ee"       # RRGGBB (RRGGBBAA allowed), '#' optional
/// ```
///
/// Every Material role, `term0`...`term15`, the Catppuccin-named aliases and the KDE `k*` accents are
/// plain keys of `[colors]`; roles that are absent resolve through `Scheme.fallback`.
public enum SchemeLoader {
    /// Names accepted by ``builtIn(named:)``, in menu order.
    public static let builtInNames: [String] = ["caelestia-dynamic", "caelestia-default", "catppuccin-mocha", "noctalia"]

    /// Human-readable titles for the built-in names (for menus).
    public static let builtInTitles: [String: String] = [
        "caelestia-dynamic": "Caelestia Dynamic",
        "caelestia-default": "Caelestia Default",
        "catppuccin-mocha": "Catppuccin Mocha",
        "noctalia": "Noctalia",
    ]

    /// Resource file name (without extension) for each built-in name.
    static let builtInFiles: [String: String] = [
        "caelestia-dynamic": "caelestia-dynamic-dark",
        "caelestia-default": "caelestia-default",
        "catppuccin-mocha": "catppuccin-mocha",
        "noctalia": "noctalia",
    ]

    static let resourceSubdirectory = "schemes"

    // MARK: TOML

    /// Parses a scheme in the TOML format described above.
    public static func parse(toml: String) throws -> Scheme {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: toml)
        } catch let error as TOMLParseError {
            throw SchemeError.syntax(error.debugDescription)
        } catch {
            throw SchemeError.syntax(String(describing: error))
        }
        guard let name = table["name"]?.string, !name.isEmpty else { throw SchemeError.missingField("name") }
        let flavour = table["flavour"]?.string ?? "default"
        let mode = table["mode"]?.string ?? "dark"
        let variant = table["variant"]?.string ?? "tonalspot"
        guard let colorsTable = table["colors"]?.table ?? table["colours"]?.table else {
            throw SchemeError.missingField("colors")
        }
        var colors: [String: RGBA] = [:]
        for (key, value) in colorsTable {
            guard let text = value.string, let color = RGBA(hex: text) else {
                throw SchemeError.invalidColor(key: key, value: value.string ?? value.debugDescription)
            }
            colors[key] = color
        }
        guard !colors.isEmpty else { throw SchemeError.missingField("colors") }
        return Scheme(name: name, flavour: flavour, mode: mode, variant: variant, colors: colors)
    }

    /// Serializes a scheme in the TOML format: Material roles first (in `ColorRole` order), then
    /// `term0`...`term15`, then every other key sorted. Colours with alpha < 1 are written as `RRGGBBAA`.
    public static func serialize(_ scheme: Scheme) -> String {
        var lines: [String] = []
        lines.append("# Caelestia for Mac colour scheme")
        lines.append("")
        lines.append("name = \(tomlString(scheme.name))")
        lines.append("flavour = \(tomlString(scheme.flavour))")
        lines.append("mode = \(tomlString(scheme.mode))")
        lines.append("variant = \(tomlString(scheme.variant))")
        lines.append("")
        lines.append("[colors]")
        var written: Set<String> = []
        func emit(_ key: String) {
            guard let color = scheme.colors[key], !written.contains(key) else { return }
            written.insert(key)
            let hex = color.alpha < 1 ? color.hexWithAlpha : color.hex
            lines.append("\(key) = \"\(hex)\"")
        }
        for role in ColorRole.allCases { emit(role.rawValue) }
        for i in 0..<16 { emit("term\(i)") }
        for key in scheme.colors.keys.sorted() { emit(key) }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Caelestia JSON

    /// Parses Caelestia's `scheme.json`: `{"name","flavour","mode","variant","colours":{role: "rrggbb"}}`
    /// (`colors` is accepted as well).
    public static func parseCaelestiaJSON(_ data: Data) throws -> Scheme {
        struct Raw: Decodable {
            var name: String?
            var flavour: String?
            var mode: String?
            var variant: String?
            var colours: [String: String]?
            var colors: [String: String]?
        }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw SchemeError.syntax(String(describing: error))
        }
        guard let map = raw.colours ?? raw.colors, !map.isEmpty else { throw SchemeError.missingField("colours") }
        var colors: [String: RGBA] = [:]
        for (key, value) in map {
            guard let color = RGBA(hex: value) else { throw SchemeError.invalidColor(key: key, value: value) }
            colors[key] = color
        }
        return Scheme(
            name: raw.name ?? "dynamic", flavour: raw.flavour ?? "default", mode: raw.mode ?? "dark",
            variant: raw.variant ?? "tonalspot", colors: colors)
    }

    // MARK: Files & resources

    /// Loads a scheme from disk: `.json` files use the Caelestia JSON format, everything else TOML.
    public static func load(from url: URL) throws -> Scheme {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SchemeError.io(path: url.path, message: error.localizedDescription)
        }
        if url.pathExtension.lowercased() == "json" {
            return try parseCaelestiaJSON(data)
        }
        return try parse(toml: String(decoding: data, as: UTF8.self))
    }

    /// A bundled scheme by name ("caelestia-dynamic", "caelestia-default", "catppuccin-mocha",
    /// "noctalia"; resource file names such as "caelestia-dynamic-dark" are accepted too, case-insensitively).
    public static func builtIn(named name: String) -> Scheme? {
        let key = name.lowercased()
        if let scheme = builtIns[key] { return scheme }
        if let canonical = builtInFiles.first(where: { $0.value == key })?.key { return builtIns[canonical] }
        return nil
    }

    /// Location of a bundled scheme file, if present.
    public static func builtInResourceURL(named name: String) -> URL? {
        guard let file = builtInFiles[name.lowercased()] else { return nil }
        return CoreResources.url(forResource: file, withExtension: "toml", subdirectory: resourceSubdirectory)
    }

    /// All bundled schemes, loaded once. A scheme that fails to parse is logged and omitted.
    private static let builtIns: [String: Scheme] = {
        var result: [String: Scheme] = [:]
        for name in builtInNames {
            guard let file = builtInFiles[name] else { continue }
            do {
                let text = try CoreResources.string(forResource: file, withExtension: "toml", subdirectory: resourceSubdirectory)
                result[name] = try parse(toml: text)
            } catch {
                Log.config.error("built-in scheme \(name, privacy: .public) failed to load: \(String(describing: error), privacy: .public)")
            }
        }
        return result
    }()

    static func tomlString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

public extension Scheme {
    /// Material roles that have no explicit colour (they resolve through the neutral fallbacks).
    var missingRoles: [ColorRole] {
        ColorRole.allCases.filter { colors[$0.rawValue] == nil }
    }

    /// Indices in 0...15 whose `term<i>` colour is missing.
    var missingTerminalColors: [Int] {
        (0..<16).filter { term($0) == nil }
    }

    /// Replaces the accent (`primary`, `primaryDim`, `surfaceTint`, `primaryFixedDim`) with `accent` and
    /// recomputes `onPrimary` as a dark or light tone depending on the accent's luminance.
    ///
    /// This is an approximation until the Material tonal-palette generator lands: a real generator
    /// would re-derive the whole primary palette (containers, fixed tones, inverse) from the hue.
    func withAccentOverride(_ accent: RGBA) -> Scheme {
        var result = self
        let opaque = accent.withAlpha(1)
        for role in [ColorRole.primary, .primaryDim, .surfaceTint, .primaryFixedDim] {
            result.colors[role.rawValue] = opaque
        }
        // WCAG mid-point: above it black text reads better than white.
        let light = opaque.luminance > 0.179
        result.colors[ColorRole.onPrimary.rawValue] = light ? opaque.mixed(with: RGBA(r: 0, g: 0, b: 0), amount: 0.75)
            : opaque.mixed(with: RGBA(r: 255, g: 255, b: 255), amount: 0.8)
        return result
    }

    /// ``withAccentOverride(_:)`` with a hex string; returns the scheme unchanged when `hex` does not
    /// parse (config validation rejects such strings before they get here).
    func withAccentOverride(hex: String) -> Scheme {
        guard let accent = RGBA(hex: hex) else {
            Log.config.error("ignoring invalid accent override \(hex, privacy: .public)")
            return self
        }
        return withAccentOverride(accent)
    }
}

public extension RGBA {
    /// Linear per-channel blend towards `other` (`amount` 0 = self, 1 = other). Alpha is kept.
    func mixed(with other: RGBA, amount: Double) -> RGBA {
        let t = min(max(amount, 0), 1)
        func channel(_ a: UInt8, _ b: UInt8) -> UInt8 {
            let v = (Double(a) * (1 - t) + Double(b) * t).rounded()
            return UInt8(min(max(v, 0), 255))
        }
        return RGBA(r: channel(r, other.r), g: channel(g, other.g), b: channel(b, other.b), alpha: alpha)
    }
}
