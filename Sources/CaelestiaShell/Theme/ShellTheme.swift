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
    /// Bumped by ``fontsChanged()``: a theme made after new fonts were registered compares
    /// unequal, so every surface re-renders in them.
    public var fontGeneration: Int
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
    /// Drawer backgrounds are drawn by the frame's `LiquidSurface` (one SDF blob group) instead
    /// of per-panel frosted shapes; set by the controller when Metal is available.
    public var liquidSurface = false

    public init(scheme: Scheme, config: Config = Config(), reduceMotion: Bool = false) {
        self.scheme = scheme
        let a = config.appearance
        baseAlpha = a.transparencyEnabled ? a.transparencyBase : 1
        layerAlpha = a.transparencyEnabled ? a.transparencyLayers : 1
        fontSans = [a.fontSans] + a.fontSansFallbacks
        fontMono = [a.fontMono] + a.fontMonoFallbacks
        fontGeneration = Self.currentFontGeneration
        uiScale = a.uiScale
        durationScale = config.animations.shellDurationScale * config.animations.durationFactor
        self.reduceMotion = (reduceMotion && config.animations.respectReduceMotion) || config.animations.reduceMotion
        frameThickness = config.wm.screenFrame ? config.wm.screenFrameInset : 0
        frameRounding = config.wm.windowRounding + config.wm.gapsOut
        barWidth = config.bar.width
    }

    public static let gabby = ShellTheme(scheme: SchemeLoader.builtIn(named: "skyrose-dynamic-dark") ?? ShellTheme.fallbackScheme)

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

    nonisolated(unsafe) private static var generation = 0
    static var currentFontGeneration: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return generation
    }

    /// Call after fonts were registered or installed: forgets which families were missing.
    public static func fontsChanged() {
        cacheLock.lock()
        installedCache.removeAll()
        generation += 1
        cacheLock.unlock()
    }

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

    /// Base durations (ms, before `durationScale`). Round 4 shortened them: nothing in the shell
    /// runs over ~350 ms at the default 0.8 scale (open 304 ms, close 176 ms).
    public static let drawerOpenMs: Double = 380
    public static let drawerCloseMs: Double = 220
    /// Under Reduce Motion every shell transition is a cross-fade of this length (no slide or
    /// scale), like macOS itself does.
    public static let reducedFadeMs: Double = 120

    /// Drawer open (toasts and anything without a known depth): the liquid spring for a
    /// 300 pt drawer, settling in 380 ms × scale (304 ms at 0.8).
    public var drawerOpen: Animation { liquidSurface ? spatial : drawerSpring(depth: 300) }

    /// The liquid growth spring of a drawer `depth` points deep: it swings ~16 pt past full size
    /// (`LiquidMotion.bouncePoints`) and settles in 380 ms × scale. Interruptible: SwiftUI springs
    /// keep their velocity when retargeted.
    public func drawerSpring(depth: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: seconds(Self.drawerOpenMs)) }
        let s = LiquidMotion.drawerSpring(depth: depth, settle: seconds(Self.drawerOpenMs))
        return .interpolatingSpring(mass: s.mass, stiffness: s.stiffness, damping: s.damping, initialVelocity: 0)
    }

    /// The neck along the edge: critically damped, a little slower than the growth.
    public var neckSpring: Animation {
        if reduceMotion { return .easeInOut(duration: seconds(Self.drawerOpenMs)) }
        let s = LiquidMotion.neckSpring(settle: seconds(Self.drawerOpenMs))
        return .interpolatingSpring(mass: s.mass, stiffness: s.stiffness, damping: s.damping, initialVelocity: 0)
    }

    /// Drawer content fades in just after its body starts growing.
    public var contentFadeIn: Animation { .easeOut(duration: seconds(110)).delay(reduceMotion ? 0 : seconds(30)) }

    /// How long a drawer panel's own alpha takes to come in: the blob must look solid as it
    /// grows, so only a few frames; Reduce Motion keeps the cross-fade.
    public var panelFadeInSeconds: Double { reduceMotion ? drawerOpenSeconds * 0.6 : 0.05 }

    /// The bar reveal spring settling in 380 ms × scale; nil under Reduce Motion or at speed 0.
    public var barRevealSpring: CaelestiaCore.Spring? {
        let settle = seconds(Self.drawerOpenMs)
        guard !reduceMotion, settle > 0 else { return nil }
        let natural = LiquidMotion.barReveal.settlingTime(epsilon: AnimationSpec.springSettlingEpsilon)
        return LiquidMotion.barReveal.timeScaled(by: settle / natural)
    }

    /// Extra room on a drawer panel's far side for the swing (0 under Reduce Motion).
    public func overshootRoom(depth: Double) -> Double { reduceMotion ? 0 : LiquidMotion.overshootRoom(depth: depth) }
    /// Drawer close: emphasizedAccel, 220 ms × scale.
    public var drawerClose: Animation { curve(.emphasizedAccel, ms: Self.drawerCloseMs) }
    /// Colour / opacity changes (hover, selection, toggles): Caelestia expressiveDefaultEffects,
    /// 200 ms × scale (160 ms at 0.8). No overshoot.
    public var small: Animation { token(.defaultEffects) }
    /// Size / position changes inside a surface (rows, tab height, gauges, list moves):
    /// expressiveDefaultSpatial, 500 ms × scale (400 ms), with overshoot.
    public var spatial: Animation { token(.defaultSpatial) }
    /// Workspace indicator and other quick moves: expressiveFastSpatial, 350 ms × scale (280 ms).
    public var fastSpatial: Animation { token(.fastSpatial) }

    /// Seconds a drawer takes to open / close (the panel's fade and the delay before it is
    /// ordered out use the same numbers as the SwiftUI slide).
    public var drawerOpenSeconds: Double { seconds(Self.drawerOpenMs) }
    public var drawerCloseSeconds: Double { seconds(Self.drawerCloseMs) }

    public func curve(_ c: ShellCurve, ms: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: seconds(ms)) }
        return .timingCurve(c.x1, c.y1, c.x2, c.y2, duration: seconds(ms))
    }

    /// Scaled duration. Under Reduce Motion every transition is the short cross-fade.
    public func seconds(_ ms: Double) -> Double {
        let scale = max(0, durationScale)
        return (reduceMotion ? min(ms, Self.reducedFadeMs) : ms) * scale / 1000
    }

    /// Caelestia token `ms` scaled (`appearance.anim.durations.scale`), Reduce Motion aside.
    public func tokenSeconds(_ ms: Double) -> Double { ms * max(0, durationScale) / 1000 }
    /// A Caelestia token curve as a SwiftUI animation; Spatial curves fall back to standard under
    /// Reduce Motion, which also caps the duration at the short cross-fade.
    public func token(_ c: CaelestiaTokens.Curve, ms: Double? = nil) -> Animation {
        let ms = ms ?? c.milliseconds
        if reduceMotion { return .easeInOut(duration: seconds(ms)) }
        let b = c.bezier
        return .timingCurve(b.x1, b.y1, b.x2, b.y2, duration: tokenSeconds(ms))
    }

    /// A slide distance: 0 under Reduce Motion (drawers then only fade, through their panel).
    public func slide(_ distance: Double) -> Double { reduceMotion ? 0 : distance }
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

/// Shell icons: Material Symbols Rounded (Caelestia's icon font) when it is registered (Settings ›
/// Appearance › Fonts, `skyrose fonts download`), else SF Symbols. Call sites may pass either a
/// Material name (Caelestia IPC, toasts, session) or an SF name (older code paths).
public enum ShellIcon {
    /// What to draw for one icon name: the Material ligature (nil = no Material equivalent, SF
    /// only), whether it is the filled variant, and the SF Symbol fallback.
    public struct Glyph: Equatable, Sendable {
        public var material: String?
        public var fill: Bool
        public var sf: String
    }

    public static let materialFamily = "Material Symbols Rounded"

    /// SF Symbol names used in the shell → (Material name, filled).
    public static let fromSF: [String: (String, Bool)] = [
        "arrow.clockwise": ("refresh", false), "arrow.down.circle.dotted": ("downloading", false),
        "arrow.triangle.2.circlepath": ("cached", false), "arrow.up.right": ("arrow_outward", false),
        "backward.fill": ("skip_previous", true), "forward.fill": ("skip_next", true),
        "play.fill": ("play_arrow", true), "pause.fill": ("pause", true), "shuffle": ("shuffle", false),
        "battery.0percent": ("battery_0_bar", false), "battery.25percent": ("battery_2_bar", false),
        "battery.50percent": ("battery_4_bar", false), "battery.75percent": ("battery_6_bar", false),
        "battery.100percent": ("battery_full", false), "battery.100percent.bolt": ("battery_charging_full", false),
        "bell.fill": ("notifications", true), "bell.slash": ("notifications_off", false), "bell.slash.fill": ("notifications_off", true),
        "cable.connector": ("lan", false), "network": ("lan", false), "calendar": ("calendar_month", false),
        "capslock.fill": ("keyboard_capslock", false), "keyboard": ("keyboard", false),
        "checkmark": ("check", false), "checkmark.circle": ("check_circle", false), "checkmark.circle.fill": ("check_circle", true),
        "circle": ("radio_button_unchecked", false), "circle.lefthalf.filled": ("contrast", false),
        "chevron.left": ("chevron_left", false), "chevron.right": ("chevron_right", false),
        "clock.arrow.circlepath": ("history", false), "xmark": ("close", false), "trash": ("delete", false),
        "cloud": ("cloud", false), "cloud.fill": ("cloud", true), "cloud.fog.fill": ("foggy", true),
        "cloud.drizzle.fill": ("rainy_light", true), "cloud.heavyrain.fill": ("rainy_heavy", true),
        "cloud.sun.rain.fill": ("rainy", true), "cloud.moon.rain.fill": ("rainy", true),
        "cloud.sun.fill": ("partly_cloudy_day", true), "cloud.moon.fill": ("partly_cloudy_night", true),
        "cloud.snow.fill": ("weather_snowy", true), "cloud.bolt.fill": ("thunderstorm", true),
        "cloud.bolt.rain.fill": ("thunderstorm", true), "exclamationmark.icloud": ("cloud_off", false),
        "sun.max.fill": ("clear_day", true), "moon.stars.fill": ("clear_night", true), "moon.fill": ("dark_mode", true),
        "moon": ("bedtime", false), "sleep": ("bedtime", false), "sunrise.fill": ("wb_twilight", true), "sunset.fill": ("nights_stay", true),
        "sun.min.fill": ("brightness_low", true), "humidity.fill": ("humidity_percentage", true), "wind": ("air", false),
        "thermometer.medium": ("thermostat", false), "thermometer.variable": ("thermostat", false),
        "cpu": ("memory", false), "memorychip": ("memory_alt", false), "internaldrive": ("hard_drive", false),
        "display": ("developer_board", false), "macwindow": ("desktop_mac", false), "menubar.rectangle": ("toolbar", false),
        "gauge.with.dots.needle.33percent": ("speed", false), "gearshape": ("settings", false),
        "cup.and.saucer.fill": ("coffee", true), "laptopcomputer": ("laptop_mac", false), "dot.radiowaves.left.and.right": ("bluetooth", false),
        "drop.halffull": ("opacity", false), "equal.circle": ("calculate", false),
        "exclamationmark.circle.fill": ("error", true), "exclamationmark.triangle.fill": ("warning", true),
        "info": ("info", false), "info.circle.fill": ("info", true),
        "location.fill": ("location_on", true), "location.magnifyingglass": ("location_searching", false),
        "mappin.and.ellipse": ("location_on", false), "lock": ("lock", false), "lock.fill": ("lock", true),
        "magnifyingglass": ("search", false), "mic": ("mic", false), "microphone": ("mic", false), "mic.fill": ("mic", true),
        "mic.slash.fill": ("mic_off", true), "music.note": ("music_note", false), "music.note.list": ("queue_music", false),
        "paintpalette": ("palette", false), "photo": ("image", false), "photo.on.rectangle": ("wallpaper", false),
        "photo.on.rectangle.angled": ("wallpaper", false), "power": ("power_settings_new", false),
        "rectangle.portrait.and.arrow.right": ("logout", false), "sparkles": ("auto_awesome", true),
        "speaker.fill": ("volume_mute", true), "speaker.slash.fill": ("volume_off", true),
        "speaker.wave.1.fill": ("volume_down", true), "speaker.wave.2.fill": ("volume_up", true), "speaker.wave.3.fill": ("volume_up", true),
        "square.grid.2x2": ("apps", false), "square.grid.2x2.fill": ("apps", true), "terminal": ("terminal", false),
        "wifi": ("wifi", false), "wifi.slash": ("wifi_off", false), "wifi.exclamationmark": ("signal_wifi_bad", false),
    ]

    /// Resolves an SF or Material name. Unknown dotted names are SF only (e.g. `apple.logo`, which
    /// has no Material equivalent); unknown plain names are taken as Material names.
    public static func glyph(_ name: String) -> Glyph {
        if let (m, fill) = fromSF[name] { return Glyph(material: m, fill: fill, sf: name) }
        if name.contains(".") || name.isEmpty { return Glyph(material: nil, fill: false, sf: name.isEmpty ? "questionmark" : name) }
        return Glyph(material: name, fill: false, sf: sf(name))
    }

    /// Material wght axis (100–700) for a SwiftUI weight.
    public static func materialWeight(_ w: Font.Weight) -> Double {
        switch w {
        case .ultraLight: return 100
        case .thin: return 200
        case .light: return 300
        case .medium: return 500
        case .semibold: return 600
        case .bold, .heavy, .black: return 700
        default: return 400
        }
    }

    /// SF Symbols sit on a larger box than Material glyphs (20 of 24 units): a Material icon in
    /// place of an SF one at font size `s` is drawn at `s × materialScale` to look the same size.
    public static let materialScale = 1.25

    public static var materialAvailable: Bool { ShellTheme.isInstalled(materialFamily) }

    nonisolated(unsafe) private static var fontCache: [String: CTFont] = [:]
    private static let fontLock = NSLock()

    /// The variable font at `size` with FILL and wght set (opsz follows the size, GRAD 0), cached.
    public static func materialFont(size: Double, weight: Double, fill: Bool) -> CTFont {
        let key = "\(size)-\(weight)-\(fill)"
        fontLock.lock()
        defer { fontLock.unlock() }
        if let f = fontCache[key] { return f }
        let tag: (String) -> Int = { $0.unicodeScalars.reduce(0) { ($0 << 8) | Int($1.value) } }
        let variation: [NSNumber: NSNumber] = [
            NSNumber(value: tag("FILL")): NSNumber(value: fill ? 1 : 0),
            NSNumber(value: tag("wght")): NSNumber(value: weight),
            NSNumber(value: tag("opsz")): NSNumber(value: min(48, max(20, size))),
            NSNumber(value: tag("GRAD")): 0,
        ]
        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: materialFamily,
            kCTFontVariationAttribute: variation,
        ] as CFDictionary)
        let f = CTFontCreateWithFontDescriptor(desc, size, nil)
        fontCache[key] = f
        return f
    }

    /// Material Symbols names used by Caelestia → SF Symbols (the fallback without the font).
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
        case "dashboard": return "square.grid.2x2"
        case "clear_all": return "trash"
        case "bedtime", "dark_mode": return "moon"
        case "clear_day", "light_mode": return "sun.max.fill"
        case "clear_night": return "moon.stars.fill"
        case "notifications": return "bell.fill"
        case "notifications_off": return "bell.slash"
        case "delete": return "trash"
        case "close": return "xmark"
        case "check": return "checkmark"
        case "refresh": return "arrow.clockwise"
        case "wallpaper": return "photo.on.rectangle"
        case "auto_awesome": return "sparkles"
        case "thermostat": return "thermometer.medium"
        case "coffee": return "cup.and.saucer.fill"
        case "screenshot_region", "screenshot_monitor": return "camera.viewfinder"
        default:
            if let hit = fromSF.first(where: { $0.value.0 == material })?.key { return hit }
            return material
        }
    }
}
