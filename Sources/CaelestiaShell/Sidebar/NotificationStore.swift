import Foundation

/// Notification history (our own toasts and `caelestia notify`; macOS offers no public way to read
/// other apps' notifications). Newest first, in memory only.
public struct NotificationStore: Equatable, Sendable {
    public private(set) var items: [ShellNotification] = []
    public var limit = 100
    public init(items: [ShellNotification] = []) { self.items = items }

    public mutating func add(_ n: ShellNotification) {
        items.insert(n, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    public mutating func dismiss(_ id: UUID) { items.removeAll { $0.id == id } }
    public mutating func clear() { items.removeAll() }
    public var count: Int { items.count }
}

public struct NotificationGroup: Equatable, Sendable, Identifiable {
    public var id: String { appName }
    public var appName: String
    public var icon: String
    public var items: [ShellNotification]
    public var latest: Date { items.first?.date ?? .distantPast }
}

public enum NotificationGrouper {
    /// Groups by app name; groups ordered by their newest notification, items newest first.
    public static func group(_ notifications: [ShellNotification]) -> [NotificationGroup] {
        var order: [String] = []
        var map: [String: NotificationGroup] = [:]
        for n in notifications.sorted(by: { $0.date > $1.date }) {
            if map[n.appName] == nil {
                order.append(n.appName)
                map[n.appName] = NotificationGroup(appName: n.appName, icon: n.icon, items: [])
            }
            map[n.appName]?.items.append(n)
        }
        return order.compactMap { map[$0] }.sorted { $0.latest > $1.latest }
    }

    /// "now", "5m", "3h", "1d", "2w".
    public static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let s = Int(max(0, now.timeIntervalSince(date)))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 7 * 86400 { return "\(s / 86400)d" }
        return "\(s / (7 * 86400))w"
    }

    public static func title(count: Int) -> String {
        count == 0 ? "No notifications" : (count == 1 ? "1 notification" : "\(count) notifications")
    }
}

/// A quick-toggle tile in the sidebar. Only things that can be switched without private API or a
/// silent system change are real toggles; the rest show state and open System Settings.
public struct QuickToggle: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case toggle, opensSettings }
    public var id: String
    public var label: String
    public var icon: String
    public var active: Bool
    public var kind: Kind
}

public enum QuickToggles {
    public static func make(status s: StatusInfo, dnd: Bool, darkMode: Bool) -> [QuickToggle] {
        var out: [QuickToggle] = []
        if s.wifiAvailable {
            out.append(QuickToggle(id: "wifi", label: "Wi-Fi", icon: s.wifiEnabled ? "wifi" : "wifi.slash", active: s.wifiEnabled, kind: .toggle))
        }
        if s.bluetoothAvailable {
            out.append(QuickToggle(id: "bluetooth", label: "Bluetooth (opens Settings)", icon: "dot.radiowaves.left.and.right", active: s.bluetoothOn, kind: .opensSettings))
        }
        out.append(QuickToggle(id: "dnd", label: "Do not disturb (Caelestia notifications)", icon: dnd ? "bell.slash.fill" : "bell.fill", active: dnd, kind: .toggle))
        out.append(QuickToggle(id: "darkmode", label: "Dark mode (macOS, opens Settings)", icon: darkMode ? "moon.fill" : "sun.max.fill", active: darkMode, kind: .opensSettings))
        return out
    }
}
