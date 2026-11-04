import AppKit
import CaelestiaCore
import SwiftUI

/// Colors, fonts, geometry and motion of the shell (spec 1.2, 1.4, 1.5, 1.6), derived from the
/// scheme and the config. Pure value: views read it from the environment; a theme change swaps it
/// and every surface re-renders.
public struct ShellTheme: Equatable, Sendable {
    public var scheme: Scheme
    /// Panel/bar background alpha (shell.json appearance.transparency.base) and the inner-card
    /// alpha over a panel (layers). Transparency off: both 1.
    public var baseAlpha: Double
    public var layerAlpha: Double
    public var fontSans: [String]
    public var fontMono: [String]
    public var uiScale: Double
    /// All shell animations run at this fraction of their Material duration (0.8).
    public var durationScale: Double
    public var reduceMotion: Bool

    // Geometry (Caelestia defaults: border.thickness 10, border.rounding 25, rounding.large 25).
    /// Screen frame band thickness.
    public var frameThickness: Double
    /// Inner radius of the screen frame (window rounding 15 + gaps_out 10 → concentric 25).
    public var frameRounding: Double
    public var barWidth: Double

    public init(scheme: Scheme, config: Config = Config(), reduceMotion: Bool = false) {
        self.scheme = scheme
        let a = config.appearance
        baseAlpha = a.transparencyEnabled ? a.transparencyBase : 1
        layerAlpha = a.transparencyEnabled ? a.transparencyLayers : 1
        fontSans = [a.fontSans] + a.fontSansFallbacks
        fontMono = [a.fontMono] + a.fontMonoFallbacks
        uiScale = a.uiScale
        durationScale = config.animations.shellDurationScale
        self.reduceMotion = reduceMotion && config.animations.respectReduceMotion
        frameThickness = config.wm.screenFrame ? config.wm.screenFrameInset : 0
        frameRounding = config.wm.windowRounding + config.wm.gapsOut
        barWidth = config.bar.width
    }

    public static let gabby = ShellTheme(scheme: SchemeLoader.builtIn(named: "caelestia-dynamic-dark") ?? ShellTheme.fallbackScheme)

    static let fallbackScheme: Scheme = {
        var colors: [String: RGBA] = [:]
        let hexes: [ColorRole: String] = [
            .surface: "0d0e12", .surfaceContainerLow: "121318", .surfaceContainer: "181920",
            .surfaceContainerHigh: "1e1f26", .surfaceContainerHighest: "23252e", .onSurface: "e4e5f0",
            .onSurfaceVariant: "a9aab5", .outline: "73757f", .outlineVariant: "464750", .primary: "bac5ee",
            .onPrimary: "333f61", .primaryContainer: "465174", .onPrimaryContainer: "dbe2ff",
            .secondary: "c1c6dd", .secondaryContainer: "353b4d", .onSecondaryContainer: "b9bed5",
            .tertiary: "f2deff", .error: "fa746f", .onError: "490006", .errorContainer: "871f21",
            .success: "b5ccba", .successContainer: "374b3e", .inversePrimary: "525e81",
        ]
        for (role, hex) in hexes { colors[role.rawValue] = RGBA(hex: hex) }
        return Scheme(name: "fallback", colors: colors)
    }()

    public subscript(_ role: ColorRole) -> Color { Color(rgba: scheme[role]) }
    public func ns(_ role: ColorRole, alpha: Double = 1) -> NSColor { NSColor(rgba: scheme[role].withAlpha(alpha)) }

    /// The drawer / frame / bar fill: surface at the base transparency, over a behind-window
    /// blur (`underWindowBackground`, the darkest material: Hyprland's blur adds no light).
    /// Calibrated against 1-launcher.jpg / 01-empty.jpg (panel ≈ #14181f over dark windows).
    public var panelFill: NSColor { ns(.surface, alpha: baseAlpha) }
    public var panelColor: Color { Color(nsColor: panelFill) }

    // MARK: Fonts

    /// UI sans font: the first installed of Rubik → Inter → SF Pro (the system font).
    public func sans(_ size: Double, weight: Font.Weight = .regular) -> Font {
        if let name = Self.firstInstalled(fontSans) { return .custom(name, size: size * uiScale).weight(weight) }
        return .system(size: size * uiScale, weight: weight)
    }

    public func mono(_ size: Double, weight: Font.Weight = .regular) -> Font {
        if let name = Self.firstInstalled(fontMono) { return .custom(name, size: size * uiScale).weight(weight) }
        return .system(size: size * uiScale, weight: weight, design: .monospaced)
    }

    /// Family names that exist on this Mac (SF Pro is the system font and never "installed").
    nonisolated(unsafe) private static var installedCache: [String: Bool] = [:]
    private static let cacheLock = NSLock()

    public static func firstInstalled(_ families: [String]) -> String? {
        for f in families where f != "SF Pro" && isInstalled(f) { return f }
        return nil
    }

    public static func isInstalled(_ family: String) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let hit = installedCache[family] { return hit }
        let found = NSFontManager.shared.availableMembers(ofFontFamily: family) != nil || NSFont(name: family, size: 12) != nil
        installedCache[family] = found
        return found
    }

    // MARK: Motion (Material 3 expressive, as Caelestia's Appearance.anim)

    /// Drawer open: expressiveDefaultSpatial (overshoots slightly), 500 ms × scale.
    public var drawerOpen: Animation { curve(.expressiveDefaultSpatial, ms: 500) }
    /// Drawer close: emphasizedAccel, 200 ms × scale.
    public var drawerClose: Animation { curve(.emphasizedAccel, ms: 250) }
    /// Small state changes (selection, hover): standard, 200 ms × scale.
    public var small: Animation { curve(.standard, ms: 200) }
    /// Workspace indicator: expressiveFastSpatial, 350 ms × scale.
    public var fastSpatial: Animation { curve(.expressiveFastSpatial, ms: 350) }

    public func curve(_ c: ShellCurve, ms: Double) -> Animation {
        if reduceMotion { return .linear(duration: 0) }
        return .timingCurve(c.x1, c.y1, c.x2, c.y2, duration: seconds(ms))
    }

    public func seconds(_ ms: Double) -> Double { reduceMotion ? 0 : ms * durationScale / 1000 }
}

/// Material 3 curves used by Caelestia (`Appearance.anim.curves`), single-segment versions.
public struct ShellCurve: Equatable, Sendable {
    public var x1: Double, y1: Double, x2: Double, y2: Double
    public static let standard = ShellCurve(x1: 0.2, y1: 0, x2: 0, y2: 1)
    public static let standardDecel = ShellCurve(x1: 0, y1: 0, x2: 0, y2: 1)
    public static let emphasizedDecel = ShellCurve(x1: 0.05, y1: 0.7, x2: 0.1, y2: 1)
    public static let emphasizedAccel = ShellCurve(x1: 0.3, y1: 0, x2: 0.8, y2: 0.15)
    public static let expressiveDefaultSpatial = ShellCurve(x1: 0.38, y1: 1.21, x2: 0.22, y2: 1)
    public static let expressiveFastSpatial = ShellCurve(x1: 0.42, y1: 1.67, x2: 0.21, y2: 0.9)

    public var bezier: CubicBezier { CubicBezier(x1: x1, y1: y1, x2: x2, y2: y2) }
    public var timing: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
    }
}

public extension Color {
    init(rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

public extension NSColor {
    convenience init(rgba: RGBA) {
        self.init(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
}

private struct ShellThemeKey: EnvironmentKey {
    static let defaultValue = ShellTheme.gabby
}

public extension EnvironmentValues {
    var shellTheme: ShellTheme {
        get { self[ShellThemeKey.self] }
        set { self[ShellThemeKey.self] = newValue }
    }
}

/// Material Symbols names used by Caelestia → SF Symbols (Material Symbols Rounded is not
/// installed and not bundled yet; spec 7.1).
public enum ShellIcon {
    public static func sf(_ material: String) -> String {
        switch material {
        case "logout": return "rectangle.portrait.and.arrow.right"
        case "power_settings_new": return "power"
        case "downloading": return "arrow.down.circle.dotted"
        case "bedtime": return "moon"
        case "cached", "restart_alt": return "arrow.triangle.2.circlepath"
        case "lock": return "lock"
        case "search": return "magnifyingglass"
        case "volume_up": return "speaker.wave.2.fill"
        case "volume_down": return "speaker.wave.1.fill"
        case "volume_mute": return "speaker.fill"
        case "volume_off": return "speaker.slash.fill"
        case "brightness_high": return "sun.max.fill"
        case "brightness_low": return "sun.min.fill"
        case "wifi": return "wifi"
        case "wifi_off": return "wifi.slash"
        case "lan": return "cable.connector"
        case "bluetooth": return "dot.radiowaves.left.and.right"
        case "keyboard_capslock": return "capslock.fill"
        case "mic": return "mic.fill"
        case "mic_off": return "mic.slash.fill"
        case "battery": return "battery.75percent"
        case "error": return "exclamationmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "info": return "info.circle.fill"
        case "check_circle": return "checkmark.circle.fill"
        case "terminal": return "terminal"
        case "calculate": return "equal.circle"
        case "settings": return "gearshape"
        case "image": return "photo"
        case "palette": return "paintpalette"
        case "contrast": return "circle.lefthalf.filled"
        case "opacity": return "drop.halffull"
        case "shuffle": return "shuffle"
        case "apps": return "square.grid.2x2"
        default: return material
        }
    }
}
