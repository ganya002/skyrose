import Foundation

/// Material You "tonal spot" scheme generation (spec 1.3), mapped onto Caelestia's role names.
public enum DynamicScheme {
    /// Tone table per role. Dark surfaces use the tones of Caelestia's periwinkle scheme
    /// (surface about L* 4, container about 10) so a dynamic scheme looks like the default one.
    private struct Tones {
        let surface, surfaceDim, surfaceBright, lowest, low, container, high, highest: Double
        let onSurface, onSurfaceVariant, outline, outlineVariant, surfaceVariant: Double
        let inverseSurface, inverseOnSurface: Double
        let accent, onAccent, accentContainer, onAccentContainer, inverseAccent, accentDim: Double
    }

    private static let dark = Tones(
        surface: 4, surfaceDim: 4, surfaceBright: 20, lowest: 2, low: 7, container: 10, high: 13, highest: 16,
        onSurface: 90, onSurfaceVariant: 72, outline: 50, outlineVariant: 28, surfaceVariant: 30,
        inverseSurface: 90, inverseOnSurface: 20,
        accent: 80, onAccent: 25, accentContainer: 30, onAccentContainer: 90, inverseAccent: 40, accentDim: 72)
    private static let light = Tones(
        surface: 98, surfaceDim: 87, surfaceBright: 98, lowest: 100, low: 96, container: 94, high: 92, highest: 90,
        onSurface: 10, onSurfaceVariant: 30, outline: 50, outlineVariant: 80, surfaceVariant: 90,
        inverseSurface: 20, inverseOnSurface: 95,
        accent: 40, onAccent: 100, accentContainer: 90, onAccentContainer: 10, inverseAccent: 80, accentDim: 35)

    /// Builds the scheme for `source`. Keys the generator does not produce (term0-15, the
    /// Catppuccin aliases, KDE accents) are copied from `base`, so every consumer keeps working.
    public static func make(source: RGBA, dark isDark: Bool = true, base: Scheme? = nil, name: String = "Dynamic") -> Scheme {
        let hue = Hct(source).hue
        let primary = TonalPalette(hue: hue, chroma: 36)
        let secondary = TonalPalette(hue: hue, chroma: 16)
        let tertiary = TonalPalette(hue: hue + 60, chroma: 24)
        let neutral = TonalPalette(hue: hue, chroma: 6)
        let neutralVariant = TonalPalette(hue: hue, chroma: 8)
        let error = TonalPalette(hue: 25, chroma: 84)
        let success = TonalPalette(hue: 145, chroma: 24)
        let t = isDark ? dark : light

        var c: [String: RGBA] = base?.colors ?? [:]
        func set(_ role: ColorRole, _ palette: TonalPalette, _ tone: Double) { c[role.rawValue] = palette.tone(tone) }

        set(.background, neutral, t.surface); set(.surface, neutral, t.surface); set(.surfaceDim, neutral, t.surfaceDim)
        set(.surfaceBright, neutral, t.surfaceBright)
        set(.surfaceContainerLowest, neutral, t.lowest); set(.surfaceContainerLow, neutral, t.low)
        set(.surfaceContainer, neutral, t.container); set(.surfaceContainerHigh, neutral, t.high)
        set(.surfaceContainerHighest, neutral, t.highest)
        set(.onBackground, neutral, t.onSurface); set(.onSurface, neutral, t.onSurface)
        set(.surfaceVariant, neutralVariant, t.surfaceVariant); set(.onSurfaceVariant, neutralVariant, t.onSurfaceVariant)
        set(.outline, neutralVariant, t.outline); set(.outlineVariant, neutralVariant, t.outlineVariant)
        set(.inverseSurface, neutral, t.inverseSurface); set(.inverseOnSurface, neutral, t.inverseOnSurface)
        c[ColorRole.shadow.rawValue] = RGBA(r: 0, g: 0, b: 0)
        c[ColorRole.scrim.rawValue] = RGBA(r: 0, g: 0, b: 0)
        set(.surfaceTint, primary, t.accent)

        func accent(_ p: TonalPalette, _ base: String, container: Bool = true) {
            c[base] = p.tone(t.accent)
            c["on" + base.prefix(1).uppercased() + base.dropFirst()] = p.tone(t.onAccent)
            c[base + "Container"] = p.tone(t.accentContainer)
            c["on" + base.prefix(1).uppercased() + base.dropFirst() + "Container"] = p.tone(t.onAccentContainer)
        }
        accent(primary, "primary"); accent(secondary, "secondary"); accent(tertiary, "tertiary"); accent(error, "error")
        accent(success, "success")
        set(.primaryDim, primary, t.accentDim); set(.secondaryDim, secondary, t.accentDim)
        set(.tertiaryDim, tertiary, t.accentDim); set(.errorDim, error, t.accentDim)
        set(.inversePrimary, primary, t.inverseAccent)
        for (name, p) in [("primary", primary), ("secondary", secondary), ("tertiary", tertiary)] {
            let cap = name.prefix(1).uppercased() + name.dropFirst()
            c[name + "Fixed"] = p.tone(90)
            c[name + "FixedDim"] = p.tone(80)
            c["on" + cap + "Fixed"] = p.tone(10)
            c["on" + cap + "FixedVariant"] = p.tone(30)
        }
        return Scheme(name: name, flavour: "dynamic", mode: isDark ? "dark" : "light", variant: "tonalspot", colors: c)
    }
}

/// Extracts a source colour from wallpaper pixels and resolves the scheme the shell should use.
public enum PaletteExtractor {
    /// The most suitable source colour in tightly packed RGBA8 pixels, or nil for grey / empty
    /// images (callers then keep the static scheme).
    public static func sourceColor(rgba: [UInt8], maxColors: Int = 128) -> RGBA? {
        let quantized = ColorQuantizer.quantize(rgba: rgba, maxColors: maxColors)
        return SourceColorScorer.rank(quantized, desired: 1).first
    }

    public static func scheme(rgba: [UInt8], dark: Bool = true, base: Scheme? = nil) -> Scheme? {
        sourceColor(rgba: rgba).map { DynamicScheme.make(source: $0, dark: dark, base: base) }
    }
}

/// Which scheme the shell shows, from the config and what is known about the wallpaper.
public enum SchemeResolver {
    public static let staticMode = "static"
    public static let dynamicMode = "dynamic"

    /// The static scheme named by `appearance.theme` (periwinkle SkyRose Dynamic by default).
    public static func staticScheme(_ a: AppearanceConfig) -> Scheme? {
        SchemeLoader.builtIn(named: a.theme) ?? SchemeLoader.builtIn(named: "skyrose-dynamic")
    }

    public static func isDynamic(_ a: AppearanceConfig) -> Bool { a.schemeMode.lowercased() == dynamicMode }

    /// `wallpaperSource` is the colour extracted from the wallpaper (nil when unreadable or grey).
    /// A manual `accentOverride` wins over the wallpaper. Anything missing falls back to `base`.
    public static func resolve(appearance a: AppearanceConfig, base: Scheme, wallpaperSource: RGBA?) -> Scheme {
        guard isDynamic(a) else { return base }
        let source = RGBA(hex: a.accentOverride) ?? wallpaperSource
        guard let source else { return base }
        return DynamicScheme.make(source: source, dark: a.variant.lowercased() != "light", base: base)
    }
}
