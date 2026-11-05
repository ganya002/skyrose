import Foundation

// MARK: - Curves

/// The easing driving an animation: a fixed-duration cubic Bézier or a spring that runs until it
/// settles.
public enum CurveKind: Sendable, Hashable, Codable {
    case bezier(CubicBezier)
    case spring(Spring)

    /// Parses a config curve string: a named Bézier ("standard", "emphasizedDecel", ...), the
    /// named spring ("riko", "spring", "spring riko"), or the literal forms
    /// "spring(mass, stiffness, damping)" and "bezier(x1, y1, x2, y2)" / "cubic-bezier(...)".
    /// Matching ignores case and whitespace.
    public static func named(_ string: String) -> CurveKind? {
        if let bezier = CubicBezier.named(string) { return .bezier(bezier) }
        let key = CubicBezier.normalize(string)
        guard !key.isEmpty else { return nil }
        if key == "riko" || key == "springriko" { return .spring(.riko) }
        if key == "spring" || key == "snappyspring" || key == "springsnappy" { return .spring(.snappy) }
        let compact = string.lowercased().filter { !$0.isWhitespace }
        if let numbers = Self.arguments(of: compact, prefixes: ["spring(", "spring:"]), numbers.count == 3 {
            return .spring(Spring(mass: numbers[0], stiffness: numbers[1], damping: numbers[2]))
        }
        if let numbers = Self.arguments(of: compact, prefixes: ["cubic-bezier(", "cubicbezier(", "bezier("]), numbers.count == 4 {
            return .bezier(CubicBezier(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3]))
        }
        return nil
    }

    /// The config name of this curve: a Bézier name, "riko", or a literal spring/bezier form.
    public var name: String {
        switch self {
        case .bezier(let b):
            return b.name ?? "bezier(\(b.x1), \(b.y1), \(b.x2), \(b.y2))"
        case .spring(let s):
            if s == .riko { return "riko" }
            if s == .snappy { return "snappy-spring" }
            return "spring(\(s.mass), \(s.stiffness), \(s.damping))"
        }
    }

    public var isSpring: Bool {
        if case .spring = self { return true }
        return false
    }

    private static func arguments(of key: String, prefixes: [String]) -> [Double]? {
        for prefix in prefixes where key.hasPrefix(prefix) {
            var body = String(key.dropFirst(prefix.count))
            if prefix.hasSuffix("(") {
                guard body.hasSuffix(")") else { return nil }
                body.removeLast()
            }
            let parts = body.split(separator: ",").map { Double($0) }
            guard parts.allSatisfy({ $0 != nil }) else { return nil }
            return parts.compactMap { $0 }
        }
        return nil
    }
}

// MARK: - Styles

/// Hyprland animation styles that change *what* moves, not the timing.
public enum AnimationStyle: Sendable, Hashable, Codable {
    /// Plain interpolation to the target.
    case none
    /// Scale from `scale` (0...1, 0.8 = "popin 80%") around the center while fading in; the
    /// reverse on close.
    case popin(scale: Double)
    /// Slide from the edge (workspaces and shell layers).
    case slide
    /// Vertical slide over `percent` (0...1) of the height, with a fade ("slidefadevert 15%").
    case slideFadeVert(percent: Double)
    /// Opacity only.
    case fade

    /// Parses a Hyprland style string, case-insensitively: "popin 80%", "slidefadevert 15%",
    /// "slide", "fade", "" / "none". Like Hyprland, "popin" alone means 0 % and "slidefadevert"
    /// alone means 100 %; a bare number without "%" is also accepted as a percentage. Unknown
    /// styles return nil.
    public init?(hyprland string: String) {
        let tokens = string.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let head = tokens.first else {
            self = .none
            return
        }
        let percent = tokens.dropFirst().first.flatMap(Self.percentage)
        switch head {
        case "none": self = .none
        case "slide": self = .slide
        case "fade": self = .fade
        case "popin": self = .popin(scale: percent ?? 0)
        case "slidefadevert": self = .slideFadeVert(percent: percent ?? 1)
        default: return nil
        }
    }

    /// The Hyprland config representation ("popin 80%", "slidefadevert 15%", "slide", "fade", "").
    public var hyprlandString: String {
        switch self {
        case .none: return ""
        case .popin(let scale): return "popin \(Self.formatPercent(scale))%"
        case .slide: return "slide"
        case .slideFadeVert(let percent): return "slidefadevert \(Self.formatPercent(percent))%"
        case .fade: return "fade"
        }
    }

    private static func percentage(_ token: String) -> Double? {
        var t = token
        if t.hasSuffix("%") { t.removeLast() }
        guard let v = Double(t), v.isFinite else { return nil }
        return v / 100
    }

    private static func formatPercent(_ fraction: Double) -> String {
        let v = (fraction * 1e8).rounded() / 1e6
        return v == v.rounded() ? String(Int(v)) : String(v)
    }
}

// MARK: - Spec

/// One animation: on/off, curve, duration and style. For springs `durationMs` is the spring's
/// settling time (|x − 1| < 0.001); speeding a spring up or down re-parameterizes it so it
/// settles in the new duration (see `withDuration(milliseconds:)`).
public struct AnimationSpec: Sendable, Hashable, Codable {
    public var enabled: Bool
    public var curve: CurveKind
    /// Duration in milliseconds (Hyprland speed × 100).
    public var durationMs: Double
    public var style: AnimationStyle

    public init(enabled: Bool = true, curve: CurveKind, durationMs: Double, style: AnimationStyle = .none) {
        self.enabled = enabled
        self.curve = curve
        self.durationMs = durationMs
        self.style = style
    }

    /// Settling tolerance used to turn a spring into a duration.
    public static let springSettlingEpsilon = 0.001

    /// A disabled animation: progress is 1 immediately.
    public static let disabled = AnimationSpec(enabled: false, curve: .bezier(.linear), durationMs: 0, style: .none)

    /// Bézier animation from a Hyprland speed in deciseconds (8 → 800 ms).
    public static func bezier(_ curve: CubicBezier, speed: Double, style: AnimationStyle = .none, enabled: Bool = true) -> AnimationSpec {
        AnimationSpec(enabled: enabled, curve: .bezier(curve), durationMs: milliseconds(fromSpeed: speed), style: style)
    }

    /// Bézier animation with an explicit duration in milliseconds.
    public static func bezier(_ curve: CubicBezier, milliseconds: Double, style: AnimationStyle = .none, enabled: Bool = true) -> AnimationSpec {
        AnimationSpec(enabled: enabled, curve: .bezier(curve), durationMs: milliseconds, style: style)
    }

    /// Spring animation; the duration is the spring's settling time.
    public static func spring(_ spring: Spring, style: AnimationStyle = .none, enabled: Bool = true) -> AnimationSpec {
        AnimationSpec(
            enabled: enabled, curve: .spring(spring),
            durationMs: spring.settlingTime(epsilon: springSettlingEpsilon) * 1000, style: style)
    }

    // MARK: Duration math

    /// Hyprland speed (deciseconds) → milliseconds.
    public static func milliseconds(fromSpeed speed: Double) -> Double { speed * 100 }

    /// Milliseconds → Hyprland speed (deciseconds).
    public static func speed(fromMilliseconds ms: Double) -> Double { ms / 100 }

    /// Duration in seconds.
    public var duration: TimeInterval { durationMs / 1000 }

    /// Duration as a Hyprland speed in deciseconds.
    public var speed: Double { Self.speed(fromMilliseconds: durationMs) }

    /// The same animation with every duration multiplied by `factor`. Springs are re-parameterized
    /// to settle in the scaled time; a factor ≤ 0 makes the animation instantaneous.
    public func scaled(by factor: Double) -> AnimationSpec {
        var copy = self
        guard factor > 0, factor.isFinite else {
            copy.durationMs = 0
            return copy
        }
        copy.durationMs = durationMs * factor
        if case .spring(let spring) = curve {
            copy.curve = .spring(spring.timeScaled(by: factor))
        }
        return copy
    }

    /// The same animation lasting `milliseconds`. A spring is re-parameterized (same damping
    /// ratio) so it settles in exactly that time.
    public func withDuration(milliseconds: Double) -> AnimationSpec {
        var copy = self
        switch curve {
        case .bezier:
            copy.durationMs = max(0, milliseconds)
        case .spring(let spring):
            let natural = spring.settlingTime(epsilon: Self.springSettlingEpsilon) * 1000
            guard milliseconds > 0, natural > 0 else {
                copy.durationMs = 0
                return copy
            }
            copy.curve = .spring(spring.timeScaled(by: milliseconds / natural))
            copy.durationMs = milliseconds
        }
        return copy
    }

    /// The same animation with a different curve. Switching to a spring adopts its settling time;
    /// switching from a spring to a Bézier keeps the current duration.
    public func withCurve(_ newCurve: CurveKind) -> AnimationSpec {
        var copy = self
        copy.curve = newCurve
        if case .spring(let spring) = newCurve {
            copy.durationMs = spring.settlingTime(epsilon: Self.springSettlingEpsilon) * 1000
        }
        return copy
    }

    // MARK: Sampling

    /// Eased progress at `elapsedSeconds` since the start: 0 at the start, exactly 1 once
    /// finished, and whatever the curve says in between (overshooting curves exceed 1).
    /// Disabled or zero-length animations are always 1.
    public func progress(at elapsedSeconds: Double) -> Double {
        guard enabled, durationMs > 0 else { return 1 }
        if elapsedSeconds <= 0 { return 0 }
        if isFinished(at: elapsedSeconds) { return 1 }
        switch curve {
        case .bezier(let bezier):
            return bezier.value(at: elapsedSeconds / duration)
        case .spring(let spring):
            return spring.position(at: elapsedSeconds)
        }
    }

    /// True once `elapsedSeconds` reaches the duration (immediately for disabled animations).
    public func isFinished(at elapsedSeconds: Double) -> Bool {
        guard enabled, durationMs > 0 else { return true }
        return elapsedSeconds >= duration
    }
}

// MARK: - Names

/// Every animation the WM and shell can play. The raw values are the Hyprland / config names.
public enum AnimationName: String, CaseIterable, Sendable, Codable {
    case global
    case windowsIn, windowsMove, windowsOut
    case workspaces, workspacesIn, workspacesOut, specialWorkspace
    case layersIn, layersOut, fadeLayers
    case fade, fadeDim, border, borderangle, glowangle, shadowangle
    /// Material 3 "short" shell duration (200 ms × shell scale).
    case shellSmall
    /// Material 3 "medium" shell duration (400 ms × shell scale).
    case shellNormal
    /// Material 3 "long" shell duration (600 ms × shell scale).
    case shellLarge
    /// Material 3 "extra long" shell duration (1000 ms × shell scale).
    case shellExtraLarge

    /// The animation this one inherits from when a table has no explicit entry for it
    /// (Hyprland's tree, flattened to the names we have). `global` has no parent.
    public var parent: AnimationName? {
        switch self {
        case .global: return nil
        case .workspacesIn, .workspacesOut, .specialWorkspace: return .workspaces
        case .fadeDim, .fadeLayers: return .fade
        default: return .global
        }
    }

    /// True for the shell duration entries (shellSmall ... shellExtraLarge).
    public var isShellDuration: Bool {
        switch self {
        case .shellSmall, .shellNormal, .shellLarge, .shellExtraLarge: return true
        default: return false
        }
    }

    /// Case-insensitive lookup by config key ("windowsin" == "windowsIn").
    public init?(configKey: String) {
        let key = configKey.lowercased()
        guard let match = AnimationName.allCases.first(where: { $0.rawValue.lowercased() == key }) else { return nil }
        self = match
    }
}

// MARK: - Table

/// The effective animation for every `AnimationName`. Missing entries inherit from their parent
/// and finally from `global`; a table with no usable entry yields `AnimationSpec.disabled`.
public struct AnimationTable: Sendable, Equatable, Codable {
    public var entries: [AnimationName: AnimationSpec]

    public init(entries: [AnimationName: AnimationSpec] = [:]) {
        self.entries = entries
    }

    /// The effective spec for a name (walking up the inheritance chain), or sets it explicitly.
    public subscript(name: AnimationName) -> AnimationSpec {
        get {
            var current: AnimationName? = name
            while let n = current {
                if let spec = entries[n] { return spec }
                current = n.parent
            }
            return .disabled
        }
        set { entries[name] = newValue }
    }

    /// Every duration multiplied by `factor` (springs re-parameterized accordingly).
    public func scaled(by factor: Double) -> AnimationTable {
        AnimationTable(entries: entries.mapValues { $0.scaled(by: factor) })
    }

    // MARK: Presets

    /// Material 3 shell durations (small 200, normal 400, large 600, extra large 1000 ms) times
    /// `shellScale`. Small transitions use the standard curve; the larger ones use the
    /// emphasized-decelerate half of the M3 emphasized set (the entering half); exits should
    /// pair the same durations with `emphasizedAccel`, as `layersOut` does.
    public static func shellDurations(shellScale: Double = 0.8) -> [AnimationName: AnimationSpec] {
        [
            .shellSmall: .bezier(.standard, milliseconds: 200 * shellScale),
            .shellNormal: .bezier(.emphasizedDecel, milliseconds: 400 * shellScale),
            .shellLarge: .bezier(.emphasizedDecel, milliseconds: 600 * shellScale),
            .shellExtraLarge: .bezier(.emphasizedDecel, milliseconds: 1000 * shellScale),
        ]
    }

    /// Base Caelestia animations.lua: windowsIn emphasizedDecel 400 popin 80 %, windowsMove
    /// standard 480, workspaces standard 400 slide, plus the shared entries of section 2.3.
    /// `windowsOut` keeps the popin style so closing scales down and fades (Hyprland's default
    /// window style is popin).
    public static func caelestiaStock(shellScale: Double = 0.8) -> AnimationTable {
        var t = AnimationTable(entries: shellDurations(shellScale: shellScale))
        t[.global] = .bezier(.default, speed: 8)
        t[.windowsIn] = .bezier(.emphasizedDecel, speed: 4, style: .popin(scale: 0.8))
        t[.windowsMove] = .bezier(.standard, speed: 4.8)
        t[.windowsOut] = .bezier(.emphasizedAccel, speed: 2.4, style: .popin(scale: 0.8))
        t[.workspaces] = .bezier(.standard, speed: 4, style: .slide)
        t[.workspacesIn] = .bezier(.standard, speed: 4, style: .slide)
        t[.workspacesOut] = .bezier(.standard, speed: 4, style: .slide)
        t[.specialWorkspace] = .bezier(.specialWorkSwitch, speed: 3.2, style: .slideFadeVert(percent: 0.15))
        t[.layersIn] = .bezier(.emphasizedDecel, speed: 4, style: .slide)
        t[.layersOut] = .bezier(.emphasizedAccel, speed: 3.2, style: .slide)
        t[.fadeLayers] = .bezier(.standard, speed: 4)
        t[.fade] = .bezier(.standard, speed: 4.8)
        t[.fadeDim] = .bezier(.standard, speed: 4.8)
        t[.border] = .bezier(.standard, speed: 4.8)
        t[.borderangle] = .bezier(.default, speed: 8, enabled: false)
        t[.glowangle] = .bezier(.default, speed: 8, enabled: false)
        t[.shadowangle] = .bezier(.default, speed: 8, enabled: false)
        return t
    }

    /// Gabby's springy table, tuned shorter for macOS (round 4 of real-hardware testing: the
    /// riko spring's ~600 ms felt slow): windowsIn / windowsMove on the snappy spring (≈ 300 ms to
    /// settle, popin 85 % for windowsIn), windowsOut a 180 ms accelerating shrink + fade, the
    /// workspace slides on the snappy spring too. Nothing in the window set exceeds 350 ms.
    /// The riko spring is still available as `curve = "riko"` in an override.
    public static func gabbySpringy(shellScale: Double = 0.8) -> AnimationTable {
        var t = caelestiaStock(shellScale: shellScale)
        t[.windowsIn] = .spring(.snappy, style: .popin(scale: 0.85))
        t[.windowsMove] = .spring(.snappy)
        t[.windowsOut] = .bezier(.emphasizedAccel, milliseconds: 180, style: .popin(scale: 0.85))
        // Springs, not the front-loaded "snappy" Bézier: that one covers 62 % of a slide in its
        // first 7 % of time, so a full-screen slide moved ~900 pt in one frame (live, round 4).
        t[.workspaces] = .spring(.snappy, style: .slide)
        t[.workspacesIn] = .spring(.snappy, style: .slide)
        t[.workspacesOut] = .spring(.snappy, style: .slide)
        t[.specialWorkspace] = .spring(.snappy, style: .slideFadeVert(percent: 0.15))
        t[.fade] = .bezier(.standard, speed: 2)
        t[.fadeDim] = .bezier(.standard, speed: 2)
        t[.border] = .bezier(.standard, speed: 2.4)
        return t
    }

    /// Base Caelestia animations with the shell at 0.8 scale.
    public static let caelestiaStock = caelestiaStock(shellScale: 0.8)

    /// Gabby's effective animations with the shell at 0.8 scale (the default preset).
    public static let gabbySpringy = gabbySpringy(shellScale: 0.8)

    /// Reduce Motion: every animation is a 120 ms standard fade.
    public static let reduced = AnimationTable(entries: Dictionary(
        uniqueKeysWithValues: AnimationName.allCases.map { ($0, AnimationSpec.bezier(.standard, milliseconds: 120, style: .fade)) }))

    /// Everything disabled, 0 ms.
    public static let off = AnimationTable(entries: Dictionary(
        uniqueKeysWithValues: AnimationName.allCases.map { ($0, AnimationSpec.disabled) }))

    /// The table for a preset, with the shell durations at `shellScale`.
    public static func preset(_ preset: AnimationsConfig.Preset, shellScale: Double = 0.8) -> AnimationTable {
        switch preset {
        case .gabbySpringy: return gabbySpringy(shellScale: shellScale)
        case .caelestiaStock: return caelestiaStock(shellScale: shellScale)
        case .reduced: return reduced
        case .off: return off
        }
    }

    // MARK: Config

    /// Resolves the effective table: the preset (shell durations at `config.shellDurationScale`),
    /// then `config.overrides` (enabled / curve name / speed in deciseconds / Hyprland style
    /// string; unparseable values are ignored), then every duration × `config.durationFactor`
    /// (`globalMultiplier / speed`).
    /// When `reduceMotion` is on and `config.respectReduceMotion` is set the result is `.reduced`
    /// untouched; the `.off` preset always stays off.
    public static func from(config: AnimationsConfig, reduceMotion: Bool) -> AnimationTable {
        if config.preset == .off { return .off }
        if config.reduceMotion || (reduceMotion && config.respectReduceMotion) { return .reduced }
        var table = preset(config.preset, shellScale: config.shellDurationScale)
        for (key, override) in config.overrides {
            guard let name = AnimationName(configKey: key) else { continue }
            var spec = table[name]
            if let enabled = override.enabled { spec.enabled = enabled }
            if let curveName = override.curve, let curve = CurveKind.named(curveName) { spec = spec.withCurve(curve) }
            if let speed = override.speed, speed >= 0, speed.isFinite {
                spec = spec.withDuration(milliseconds: AnimationSpec.milliseconds(fromSpeed: speed))
            }
            if let styleString = override.style, let style = AnimationStyle(hyprland: styleString) { spec.style = style }
            table[name] = spec
        }
        return table.scaled(by: config.durationFactor)
    }
}
