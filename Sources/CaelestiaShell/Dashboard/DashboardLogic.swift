import Foundation

public enum DashboardTab: String, CaseIterable, Sendable {
    case overview, media, performance, weather
    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .media: return "Media"
        case .performance: return "Performance"
        case .weather: return "Weather"
        }
    }
    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .media: return "music.note.list"
        case .performance: return "gauge.with.dots.needle.33percent"
        case .weather: return "cloud.sun.fill"
        }
    }
    public init(config: String) { self = DashboardTab(rawValue: config.lowercased()) ?? .overview }
}

/// Vertical clock text (hours / minutes / seconds / AM-PM).
public struct ClockParts: Equatable, Sendable {
    public var hours: String
    public var minutes: String
    public var seconds: String?
    public var meridiem: String?

    public static func make(_ date: Date, use24h: Bool, seconds: Bool, calendar: Calendar = .current) -> ClockParts {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let h = c.hour ?? 0
        let shown = use24h ? h : (h % 12 == 0 ? 12 : h % 12)
        return ClockParts(
            hours: String(format: "%02d", shown), minutes: String(format: "%02d", c.minute ?? 0),
            seconds: seconds ? String(format: "%02d", c.second ?? 0) : nil, meridiem: use24h ? nil : (h < 12 ? "AM" : "PM"))
    }

    /// True when the current locale shows a 24 hour clock.
    public static func localeUses24h(_ locale: Locale = .current) -> Bool {
        let f = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "HH"
        return !f.contains("a")
    }
}

/// A month laid out as 6 weeks x 7 days.
public enum CalendarGrid {
    public struct Day: Equatable, Sendable, Identifiable {
        public var id: Int { offset }
        public var offset: Int
        public var number: Int
        public var inMonth: Bool
        public var isToday: Bool
    }

    public static func monthStart(containing date: Date, offsetMonths: Int, calendar: Calendar = .current) -> Date {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        return calendar.date(byAdding: .month, value: offsetMonths, to: first) ?? first
    }

    public static func weeks(monthStart: Date, today: Date, calendar: Calendar = .current) -> [[Day]] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: monthStart) ?? monthStart
        let month = calendar.component(.month, from: monthStart)
        var out: [[Day]] = []
        for w in 0..<6 {
            var row: [Day] = []
            for d in 0..<7 {
                let offset = w * 7 + d
                let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                row.append(Day(
                    offset: offset, number: calendar.component(.day, from: date), inMonth: calendar.component(.month, from: date) == month,
                    isToday: calendar.isDate(date, inSameDayAs: today)))
            }
            out.append(row)
        }
        return out
    }

    /// Weekday header labels starting at the calendar's first weekday ("Mon", "Tue", ...).
    public static func weekdayHeaders(calendar: Calendar = .current) -> [String] {
        let s = calendar.shortWeekdaySymbols
        return (0..<7).map { s[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}

/// Text helpers shared by the dashboard and the popouts (thin wrappers so the shell does not
/// depend on the services module's formatters).
public enum ShellText {
    public static func bytesText(_ n: UInt64) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var v = Double(n)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(n) B" : (v >= 100 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i]))
    }
    public static func rateText(_ bps: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var v = max(0, bps)
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }
    public static func uptimeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let d = total / 86400, h = (total % 86400) / 3600, m = (total % 3600) / 60
        func plural(_ n: Int, _ s: String) -> String { "\(n) \(s)\(n == 1 ? "" : "s")" }
        if d > 0 { return "up \(plural(d, "day")), \(plural(h, "hour"))" }
        if h > 0 { return "up \(plural(h, "hour")), \(m) min" }
        return "up \(m) min"
    }
    /// "48°C".
    public static func celsius(_ c: Double) -> String { "\(Int(c.rounded()))°C" }
    /// 20 °C → 0, 105 °C → 1 (the bar and sparkline scale for temperatures).
    public static func temperatureFraction(_ c: Double) -> Double { min(1, max(0, (c - 20) / 85)) }
    public static func thermalText(_ raw: Int) -> String { ["Nominal", "Fair", "Serious", "Critical"][max(0, min(3, raw))] }
}

public enum BatteryText {
    public static func status(_ s: StatusInfo) -> String {
        var parts: [String] = []
        if s.batteryCharging { parts.append("Charging") } else if s.batteryPluggedIn { parts.append("Plugged in") } else { parts.append("On battery") }
        if let m = s.batteryTimeRemainingMinutes, m > 0 {
            parts.append(m >= 60 ? String(format: "%d h %02d min left", m / 60, m % 60) : "\(m) min left")
        }
        if s.lowPowerMode { parts.append("Low Power Mode") }
        return parts.joined(separator: " · ")
    }
}
