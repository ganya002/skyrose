import Foundation

/// What ⌥ + T (`app.terminal`) opens: `apps.terminal` in config.toml.
///
/// - `"kitty"` → kitty, a new window each time (`open -n -b net.kovidgoyal.kitty`).
/// - `"rex"` → Rex (`com.superlogical.rex`), opened or brought forward.
/// - a bundle id (`com.apple.Terminal`) → that app, opened or brought forward.
/// - anything else → run as a shell command (`open -a iTerm`, `wezterm start`, …).
public enum TerminalChoice: Equatable, Sendable {
    case kitty
    case rex
    case app(bundleID: String)
    case command(String)

    public static let kittyBundleID = "net.kovidgoyal.kitty"
    public static let rexBundleID = "com.superlogical.rex"

    public init(config value: String) {
        let v = value.trimmingCharacters(in: .whitespaces)
        switch v.lowercased() {
        case "kitty", Self.kittyBundleID: self = .kitty
        case "rex", Self.rexBundleID: self = .rex
        default:
            if Self.looksLikeBundleID(v) { self = .app(bundleID: v) } else { self = .command(v.isEmpty ? "kitty" : v) }
        }
    }

    /// The value written to `apps.terminal`.
    public var configValue: String {
        switch self {
        case .kitty: return "kitty"
        case .rex: return "rex"
        case .app(let id): return id
        case .command(let c): return c
        }
    }

    public var bundleID: String? {
        switch self {
        case .kitty: return Self.kittyBundleID
        case .rex: return Self.rexBundleID
        case .app(let id): return id
        case .command: return nil
        }
    }

    /// `/usr/bin/open` arguments, or nil for a shell command.
    public var openArguments: [String]? {
        switch self {
        case .kitty: return ["-n", "-b", Self.kittyBundleID]
        case .rex: return ["-b", Self.rexBundleID]
        case .app(let id): return ["-b", id]
        case .command: return nil
        }
    }

    /// `com.example.App`: reverse-DNS, no spaces or slashes, at least one dot.
    public static func looksLikeBundleID(_ s: String) -> Bool {
        guard s.contains("."), !s.hasPrefix("."), !s.hasSuffix(".") else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }
}
