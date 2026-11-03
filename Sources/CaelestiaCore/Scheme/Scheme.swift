import Foundation

/// An sRGB color with 8-bit channels and an alpha in 0...1. No AppKit here; the Shell/Overlay
/// modules convert to NSColor/CGColor.
public struct RGBA: Hashable, Sendable, Codable, CustomStringConvertible {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var alpha: Double

    public init(r: UInt8, g: UInt8, b: UInt8, alpha: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.alpha = alpha
    }

    /// Parses "RRGGBB", "#RRGGBB", "RRGGBBAA", "#RRGGBBAA" (and Hyprland "0xAARRGGBB" / "rgba(RRGGBBAA)").
    public init?(hex input: String) {
        var s = input.trimmingCharacters(in: .whitespaces)
        var hyprAlphaFirst = false
        if s.lowercased().hasPrefix("rgba(") && s.hasSuffix(")") {
            s = String(s.dropFirst(5).dropLast())
        } else if s.lowercased().hasPrefix("rgb(") && s.hasSuffix(")") {
            s = String(s.dropFirst(4).dropLast())
        } else if s.lowercased().hasPrefix("0x") {
            s = String(s.dropFirst(2))
            hyprAlphaFirst = true
        }
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF), alpha: 1)
        } else if hyprAlphaFirst {
            self.init(
                r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF),
                alpha: Double((v >> 24) & 0xFF) / 255.0)
        } else {
            self.init(
                r: UInt8((v >> 24) & 0xFF), g: UInt8((v >> 16) & 0xFF), b: UInt8((v >> 8) & 0xFF),
                alpha: Double(v & 0xFF) / 255.0)
        }
    }

    public func withAlpha(_ a: Double) -> RGBA { RGBA(r: r, g: g, b: b, alpha: a) }

    /// Alpha byte 0...255 → 0...1.
    public func withAlphaByte(_ a: UInt8) -> RGBA { withAlpha(Double(a) / 255.0) }

    public var hex: String { String(format: "%02x%02x%02x", r, g, b) }
    public var hexWithAlpha: String { String(format: "%02x%02x%02x%02x", r, g, b, UInt8((alpha * 255).rounded())) }
    public var description: String { "#" + (alpha < 1 ? hexWithAlpha : hex) }

    public var red: Double { Double(r) / 255 }
    public var green: Double { Double(g) / 255 }
    public var blue: Double { Double(b) / 255 }

    /// Relative luminance (WCAG), for picking readable text colors.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }
}

/// Material 3 color roles used by the shell, borders and the kitty theme writer.
public enum ColorRole: String, CaseIterable, Sendable, Codable {
    case background, onBackground, surface, surfaceDim, surfaceBright
    case surfaceContainerLowest, surfaceContainerLow, surfaceContainer, surfaceContainerHigh, surfaceContainerHighest
    case onSurface, surfaceVariant, onSurfaceVariant, outline, outlineVariant
    case inverseSurface, inverseOnSurface, shadow, scrim, surfaceTint
    case primary, primaryDim, onPrimary, primaryContainer, onPrimaryContainer, inversePrimary
    case primaryFixed, primaryFixedDim, onPrimaryFixed, onPrimaryFixedVariant
    case secondary, secondaryDim, onSecondary, secondaryContainer, onSecondaryContainer
    case secondaryFixed, secondaryFixedDim, onSecondaryFixed, onSecondaryFixedVariant
    case tertiary, tertiaryDim, onTertiary, tertiaryContainer, onTertiaryContainer
    case tertiaryFixed, tertiaryFixedDim, onTertiaryFixed, onTertiaryFixedVariant
    case error, errorDim, onError, errorContainer, onErrorContainer
    case success, onSuccess, successContainer, onSuccessContainer
}

/// A full color scheme: Material roles + term0-15 + the Catppuccin-named aliases + KDE accents.
public struct Scheme: Equatable, Sendable, Codable {
    public var name: String
    public var flavour: String
    /// "dark" or "light".
    public var mode: String
    /// Material variant ("tonalspot", ...).
    public var variant: String
    /// Every color by its role/alias name (lower-camel, as in Caelestia's scheme JSON).
    public var colors: [String: RGBA]

    public init(name: String, flavour: String = "default", mode: String = "dark", variant: String = "tonalspot", colors: [String: RGBA]) {
        self.name = name
        self.flavour = flavour
        self.mode = mode
        self.variant = variant
        self.colors = colors
    }

    public var isDark: Bool { mode.lowercased() != "light" }

    public subscript(_ role: ColorRole) -> RGBA {
        colors[role.rawValue] ?? Scheme.fallback(for: role, dark: isDark)
    }

    public subscript(_ name: String) -> RGBA? { colors[name] }

    /// term0...term15.
    public func term(_ i: Int) -> RGBA? { colors["term\(i)"] }

    // MARK: Derived decoration colors (section 1.2)

    /// primary @ 0xe6 (90%).
    public var activeBorder: RGBA { self[.primary].withAlphaByte(0xE6) }
    /// onSurfaceVariant @ 0x11 (~7%).
    public var inactiveBorder: RGBA { self[.onSurfaceVariant].withAlphaByte(0x11) }
    /// inversePrimary @ 0x10 (~6%).
    public var windowShadow: RGBA { self[.inversePrimary].withAlphaByte(0x10) }
    /// surfaceContainer, used when there is no wallpaper.
    public var desktopBackground: RGBA { self[.surfaceContainer] }
    public var groupBarActive: RGBA { self[.primary].withAlphaByte(0xD4) }
    public var groupBarInactive: RGBA { self[.outline].withAlphaByte(0xD4) }
    public var groupBarLockedActive: RGBA { self[.primary].withAlphaByte(0xD4) }
    public var groupBarLockedInactive: RGBA { self[.secondary].withAlphaByte(0xD4) }

    static func fallback(for role: ColorRole, dark: Bool) -> RGBA {
        // Conservative neutral fallbacks so a partially specified scheme never produces black tiles.
        switch role {
        case .background, .surface, .surfaceDim: return dark ? RGBA(r: 0x0d, g: 0x0e, b: 0x12) : RGBA(r: 0xfa, g: 0xf8, b: 0xfe)
        case .surfaceContainerLowest: return dark ? RGBA(r: 0, g: 0, b: 0) : RGBA(r: 0xff, g: 0xff, b: 0xff)
        case .surfaceContainerLow: return dark ? RGBA(r: 0x12, g: 0x13, b: 0x18) : RGBA(r: 0xf4, g: 0xf3, b: 0xf8)
        case .surfaceContainer: return dark ? RGBA(r: 0x18, g: 0x19, b: 0x20) : RGBA(r: 0xee, g: 0xed, b: 0xf2)
        case .surfaceContainerHigh: return dark ? RGBA(r: 0x1e, g: 0x1f, b: 0x26) : RGBA(r: 0xe8, g: 0xe7, b: 0xec)
        case .surfaceContainerHighest, .surfaceVariant: return dark ? RGBA(r: 0x23, g: 0x25, b: 0x2e) : RGBA(r: 0xe2, g: 0xe1, b: 0xe6)
        case .surfaceBright: return dark ? RGBA(r: 0x2a, g: 0x2c, b: 0x34) : RGBA(r: 0xfa, g: 0xf8, b: 0xfe)
        case .onBackground, .onSurface: return dark ? RGBA(r: 0xe4, g: 0xe5, b: 0xf0) : RGBA(r: 0x1b, g: 0x1b, b: 0x20)
        case .onSurfaceVariant: return dark ? RGBA(r: 0xa9, g: 0xaa, b: 0xb5) : RGBA(r: 0x46, g: 0x47, b: 0x50)
        case .outline: return RGBA(r: 0x73, g: 0x75, b: 0x7f)
        case .outlineVariant: return RGBA(r: 0x46, g: 0x47, b: 0x50)
        case .inverseSurface: return dark ? RGBA(r: 0xfa, g: 0xf8, b: 0xfe) : RGBA(r: 0x2f, g: 0x30, b: 0x36)
        case .inverseOnSurface: return dark ? RGBA(r: 0x54, g: 0x55, b: 0x5a) : RGBA(r: 0xf1, g: 0xf0, b: 0xf7)
        case .shadow, .scrim: return RGBA(r: 0, g: 0, b: 0)
        case .surfaceTint, .primary, .primaryFixedDim: return RGBA(r: 0xba, g: 0xc5, b: 0xee)
        case .primaryDim: return RGBA(r: 0xac, g: 0xb8, b: 0xe0)
        case .onPrimary: return RGBA(r: 0x33, g: 0x3f, b: 0x61)
        case .primaryContainer, .onPrimaryFixedVariant: return RGBA(r: 0x46, g: 0x51, b: 0x74)
        case .onPrimaryContainer: return RGBA(r: 0xdb, g: 0xe2, b: 0xff)
        case .inversePrimary: return RGBA(r: 0x52, g: 0x5e, b: 0x81)
        case .primaryFixed: return RGBA(r: 0xc8, g: 0xd3, b: 0xfd)
        case .onPrimaryFixed: return RGBA(r: 0x29, g: 0x35, b: 0x56)
        case .secondary: return RGBA(r: 0xc1, g: 0xc6, b: 0xdd)
        case .secondaryDim: return RGBA(r: 0xb3, g: 0xb8, b: 0xcf)
        case .onSecondary: return RGBA(r: 0x3a, g: 0x40, b: 0x52)
        case .secondaryContainer: return RGBA(r: 0x35, g: 0x3b, b: 0x4d)
        case .onSecondaryContainer: return RGBA(r: 0xb9, g: 0xbe, b: 0xd5)
        case .secondaryFixed: return RGBA(r: 0xdd, g: 0xe2, b: 0xf9)
        case .secondaryFixedDim: return RGBA(r: 0xcf, g: 0xd3, b: 0xeb)
        case .onSecondaryFixed: return RGBA(r: 0x39, g: 0x3f, b: 0x51)
        case .onSecondaryFixedVariant: return RGBA(r: 0x55, g: 0x5b, b: 0x6f)
        case .tertiary: return RGBA(r: 0xf2, g: 0xde, b: 0xff)
        case .tertiaryDim, .tertiaryContainer, .tertiaryFixed: return RGBA(r: 0xe8, g: 0xcd, b: 0xfd)
        case .onTertiary: return RGBA(r: 0x60, g: 0x4b, b: 0x73)
        case .onTertiaryContainer: return RGBA(r: 0x57, g: 0x42, b: 0x6a)
        case .tertiaryFixedDim: return RGBA(r: 0xda, g: 0xbf, b: 0xee)
        case .onTertiaryFixed: return RGBA(r: 0x43, g: 0x30, b: 0x56)
        case .onTertiaryFixedVariant: return RGBA(r: 0x61, g: 0x4c, b: 0x74)
        case .error: return RGBA(r: 0xfa, g: 0x74, b: 0x6f)
        case .errorDim: return RGBA(r: 0xc5, g: 0x4d, b: 0x4a)
        case .onError: return RGBA(r: 0x49, g: 0x00, b: 0x06)
        case .errorContainer: return RGBA(r: 0x87, g: 0x1f, b: 0x21)
        case .onErrorContainer: return RGBA(r: 0xff, g: 0x99, b: 0x93)
        case .success: return RGBA(r: 0xb5, g: 0xcc, b: 0xba)
        case .onSuccess: return RGBA(r: 0x21, g: 0x35, b: 0x28)
        case .successContainer: return RGBA(r: 0x37, g: 0x4b, b: 0x3e)
        case .onSuccessContainer: return RGBA(r: 0xd1, g: 0xe9, b: 0xd6)
        }
    }
}
