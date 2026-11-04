import Foundation

/// How the WM treats an app's windows (per bundle id; `[appRules]` in config.toml).
public enum AppLayoutMode: String, Codable, Sendable, CaseIterable {
    /// Standard windows are tiled, even when a built-in default or a rules.toml rule would float
    /// them. Dialogs, sheets, panels and fixed-size windows still float, and a window whose
    /// minimum size cannot fit on the screen is still floated (never off-screen).
    case tile
    /// Every window floats, centred at its own size.
    case float
    /// The built-in default for the app, then rules.toml, then the window heuristics.
    case auto
}

/// Where an app's effective mode comes from.
public enum AppRuleSource: String, Codable, Sendable {
    /// `[appRules]` in config.toml (set by hand, `caelestia rules set`, or the Settings app).
    case user
    /// `AppRuleBook.builtInFloating`.
    case builtIn
    /// No per-app rule: rules.toml and the window heuristics decide.
    case none
}

/// The per-app rule book: user rules over the built-in floating list. Pure value; the WM asks it
/// whether a new window floats (`floats(_:ruleFloat:)`) and the Settings app lists/sets entries.
public struct AppRuleBook: Equatable, Sendable {
    /// Apps that float by default. Utility apps with small or fixed-size windows that look wrong
    /// tiled. Dialogs, sheets, pickers and utility panels are covered by the subrole heuristics
    /// (`WindowDescriptor.isDialogLike`, `isStandardWindow`) for every app.
    public static let builtInFloating: [String: String] = [
        "com.apple.systempreferences": "System Settings",
        "com.apple.calculator": "Calculator",
        "com.apple.archiveutility": "Archive Utility",
        "com.apple.SystemProfiler": "System Information",
        "com.apple.DigitalColorMeter": "Digital Color Meter",
        "com.apple.ScreenSharing": "Screen Sharing",
        "com.apple.Installer": "Installer",
        "com.apple.print.PrintCenter": "Print Center",
        "com.apple.FontBook": "Font Book",
        "com.apple.BluetoothFileExchange": "Bluetooth File Exchange",
        "com.apple.CoreLocationAgent": "Location prompts",
        "com.apple.UserNotificationCenter": "System alerts",
        "com.apple.SecurityAgent": "Password prompts",
        "com.apple.loginwindow": "Login window",
        "com.apple.ScreenContinuity": "iPhone Mirroring",
    ]

    /// User rules by bundle id (`auto` entries are dropped: auto is the absence of a rule).
    public private(set) var user: [String: AppLayoutMode]

    public init(user: [String: AppLayoutMode] = [:]) {
        self.user = user.filter { $0.value != .auto }
    }

    /// From config.toml's `[appRules]` strings; unknown values are ignored (the loader warns).
    public init(config: [String: String]) {
        var rules: [String: AppLayoutMode] = [:]
        for (bundle, value) in config {
            if let mode = AppLayoutMode(rawValue: value.lowercased()) { rules[bundle] = mode }
        }
        self.init(user: rules)
    }

    /// The config.toml representation (`[appRules]`).
    public var configValue: [String: String] { user.mapValues(\.rawValue) }

    /// Bundle ids compare case-insensitively (LaunchServices does too).
    private func lookup<T>(_ table: [String: T], _ bundleID: String) -> T? {
        if let v = table[bundleID] { return v }
        let lower = bundleID.lowercased()
        return table.first { $0.key.lowercased() == lower }?.value
    }

    /// The rule the user set for `bundleID`, if any.
    public func userMode(for bundleID: String) -> AppLayoutMode? { lookup(user, bundleID) }

    public func isBuiltInFloating(_ bundleID: String) -> Bool { lookup(Self.builtInFloating, bundleID) != nil }

    /// The effective mode and where it comes from. Built-in floating apps report `.float`.
    public func mode(for bundleID: String) -> (mode: AppLayoutMode, source: AppRuleSource) {
        if let m = userMode(for: bundleID) { return (m, .user) }
        if isBuiltInFloating(bundleID) { return (.float, .builtIn) }
        return (.auto, .none)
    }

    /// Sets (or with `.auto` removes) the user rule for `bundleID`.
    public mutating func set(_ mode: AppLayoutMode, for bundleID: String) {
        let key = user.keys.first { $0.lowercased() == bundleID.lowercased() } ?? bundleID
        if mode == .auto { user[key] = nil } else { user[key] = mode }
    }

    /// Whether a new window floats. `ruleFloat` is rules.toml's `float` effect for the window.
    /// Non-standard windows (dialogs, sheets, popovers, utility panels, pickers) and fixed-size
    /// windows always float, whatever the app rule says.
    public func floats(_ d: WindowDescriptor, ruleFloat: Bool?) -> Bool {
        if d.isDialogLike || d.isFixedSize || !d.isStandardWindow { return true }
        switch mode(for: d.bundleID).mode {
        case .tile: return false
        case .float: return true
        case .auto: return ruleFloat == true
        }
    }
}
