import Foundation

/// Keep-awake durations (Amphetamine-style timers on Caelestia's idle inhibitor): parsing for the
/// CLI, the sidebar's presets and the "time left" text. Pure.
public enum KeepAwakeTimer {
    /// Sidebar chips: 15 min, 1 h, 2 h, 5 h (nil = until turned off).
    public static let presets: [TimeInterval?] = [nil, 15 * 60, 60 * 60, 2 * 3600, 5 * 3600]

    /// "30m", "1h", "1h30m", "90" (minutes), "45s"; "forever" / "on" / "" = no limit (nil).
    /// Throws for anything else or for 0 / more than 7 days.
    public static func parse(_ text: String) throws -> TimeInterval? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty || t == "forever" || t == "on" || t == "indefinitely" { return nil }
        if let minutes = Double(t) { return try checked(minutes * 60, text) }
        var total = 0.0
        var number = ""
        var sawUnit = false
        for ch in t {
            if ch.isNumber || ch == "." { number.append(ch); continue }
            guard let n = Double(number) else { throw ParseError.invalid(text) }
            switch ch {
            case "h": total += n * 3600
            case "m": total += n * 60
            case "s": total += n
            default: throw ParseError.invalid(text)
            }
            number = ""
            sawUnit = true
        }
        guard sawUnit, number.isEmpty else { throw ParseError.invalid(text) }
        return try checked(total, text)
    }

    private static func checked(_ s: TimeInterval, _ text: String) throws -> TimeInterval {
        guard s >= 1, s <= 7 * 86400 else { throw ParseError.outOfRange(text) }
        return s
    }

    public enum ParseError: Error, Equatable, LocalizedError {
        case invalid(String), outOfRange(String)
        public var errorDescription: String? {
            switch self {
            case .invalid(let t): return "\"\(t)\" is not a duration (try 30m, 1h, 1h30m or forever)"
            case .outOfRange(let t): return "\"\(t)\" must be between 1 second and 7 days"
            }
        }
    }

    /// "1 h 05 min left", "42 min left", "under a minute left".
    public static func remainingText(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        if s < 60 { return "under a minute left" }
        let minutes = (s + 59) / 60
        if minutes < 60 { return "\(minutes) min left" }
        return String(format: "%d h %02d min left", minutes / 60, minutes % 60)
    }

    /// Chip label: "∞", "15 min", "1 h", "2 h".
    public static func label(_ d: TimeInterval?) -> String {
        guard let d else { return "∞" }
        let m = Int(d / 60)
        return m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) h" : String(format: "%d h %02d", m / 60, m % 60))
    }

    /// Whether a sidebar chip is the running keep-awake: the ∞ chip for an unlimited one, a timed
    /// chip only for exactly its length (a CLI `on 1m` lights none).
    public static func isChosen(_ preset: TimeInterval?, enabled: Bool, duration: TimeInterval?) -> Bool {
        enabled && preset == duration
    }

    /// The sidebar's status line.
    public static func status(enabled: Bool, until: Date?, now: Date = Date()) -> String {
        guard enabled else { return "Normal power management" }
        guard let until else { return "Keeping awake" }
        return "Keeping awake · \(remainingText(until.timeIntervalSince(now)))"
    }
}
