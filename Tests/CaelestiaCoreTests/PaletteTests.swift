import XCTest

@testable import CaelestiaCore

/// Synthetic RGBA images for the palette tests.
private func image(_ blocks: [(RGBA, Int)]) -> [UInt8] {
    var out: [UInt8] = []
    for (c, n) in blocks {
        for _ in 0..<n { out += [c.r, c.g, c.b, 255] }
    }
    return out
}

final class HctTests: XCTestCase {
    func testToneMatchesLstar() {
        for tone in stride(from: 5.0, through: 95.0, by: 10) {
            for hue in stride(from: 0.0, to: 360, by: 40) {
                let c = Hct(hue: hue, chroma: 30, tone: tone).rgba
                XCTAssertEqual(ColorMath.lstar(r: c.r, g: c.g, b: c.b), tone, accuracy: 1.5, "hue \(hue) tone \(tone)")
            }
        }
    }

    func testHueAndChromaRoundTrip() {
        for hue in stride(from: 10.0, to: 360, by: 35) {
            let c = Hct(hue: hue, chroma: 36, tone: 80).rgba
            let back = Hct(c)
            XCTAssertLessThan(ColorMath.differenceDegrees(back.hue, hue), 6, "hue \(hue) came back as \(back.hue)")
            XCTAssertEqual(back.chroma, 36, accuracy: 6, "hue \(hue)")
        }
    }

    func testOutOfGamutChromaIsReducedNotBroken() {
        let c = Hct(hue: 130, chroma: 200, tone: 30).rgba
        let back = Hct(c)
        XCTAssertEqual(back.tone, 30, accuracy: 2)
        XCTAssertLessThan(back.chroma, 200)
        XCTAssertGreaterThan(back.chroma, 20)
    }

    func testGreyAndExtremes() {
        XCTAssertEqual(Hct(hue: 200, chroma: 0, tone: 0).rgba, RGBA(r: 0, g: 0, b: 0))
        XCTAssertEqual(Hct(hue: 200, chroma: 40, tone: 100).rgba, RGBA(r: 255, g: 255, b: 255))
        let g = Hct(hue: 10, chroma: 0, tone: 50).rgba
        XCTAssertEqual(g.r, g.g)
        XCTAssertEqual(g.g, g.b)
    }

    func testKnownColourHct() {
        // #4285f4 (Google blue): CIE L* is 56.5; CAM16 puts it near hue 264, chroma 62.
        let h = Hct(r: 0x42, g: 0x85, b: 0xf4)
        XCTAssertEqual(h.hue, 264, accuracy: 5)
        XCTAssertEqual(h.chroma, 62, accuracy: 5)
        XCTAssertEqual(h.tone, 56.5, accuracy: 0.5)
    }
}

final class PaletteExtractionTests: XCTestCase {
    private let blue = RGBA(r: 0x2a, g: 0x5c, b: 0xd8)
    private let orange = RGBA(r: 0xe0, g: 0x80, b: 0x20)

    func testQuantizerFindsDominantColours() {
        let q = ColorQuantizer.quantize(rgba: image([(blue, 800), (orange, 200)]), maxColors: 16)
        XCTAssertGreaterThanOrEqual(q.count, 2)
        XCTAssertEqual(q.map(\.population).reduce(0, +), 1000)
        let top = q.max { $0.population < $1.population }!
        XCTAssertEqual(Int(top.r), Int(blue.r), accuracy: 8)
        XCTAssertEqual(Int(top.b), Int(blue.b), accuracy: 8)
    }

    func testDeterministic() {
        var pixels: [(RGBA, Int)] = []
        for i in 0..<60 { pixels.append((RGBA(r: UInt8(i * 4), g: UInt8(255 - i * 3), b: UInt8((i * 37) % 256)), 5 + i % 7)) }
        let img = image(pixels)
        let a = PaletteExtractor.scheme(rgba: img)
        let b = PaletteExtractor.scheme(rgba: img)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        XCTAssertEqual(ColorQuantizer.quantize(rgba: img), ColorQuantizer.quantize(rgba: img))
    }

    func testSourceIsTheDominantChromaticColour() {
        let src = PaletteExtractor.sourceColor(rgba: image([(blue, 900), (orange, 100)]))
        XCTAssertNotNil(src)
        XCTAssertLessThan(ColorMath.differenceDegrees(Hct(src!).hue, Hct(blue).hue), 12)
    }

    func testGreyEmptyAndTransparentFallBackToNil() {
        XCTAssertNil(PaletteExtractor.sourceColor(rgba: image([(RGBA(r: 120, g: 120, b: 120), 500), (RGBA(r: 30, g: 30, b: 30), 500)])))
        XCTAssertNil(PaletteExtractor.sourceColor(rgba: []))
        var transparent: [UInt8] = []
        for _ in 0..<100 { transparent += [200, 30, 30, 0] }
        XCTAssertNil(PaletteExtractor.sourceColor(rgba: transparent))
    }

    func testDifferentWallpapersGiveDifferentPrimaries() {
        let a = PaletteExtractor.scheme(rgba: image([(blue, 100)]))!
        let b = PaletteExtractor.scheme(rgba: image([(orange, 100)]))!
        XCTAssertNotEqual(a[.primary], b[.primary])
    }
}

final class DynamicSchemeTests: XCTestCase {
    private let base = SchemeLoader.builtIn(named: "caelestia-dynamic")!

    func testEveryRoleIsPresentAndReadable() {
        let s = DynamicScheme.make(source: RGBA(r: 0x6a, g: 0x76, b: 0x9b), base: base)
        XCTAssertTrue(s.isDark)
        for role in ColorRole.allCases { XCTAssertNotNil(s.colors[role.rawValue], role.rawValue) }
        // Text on surface and on primary must stay readable (WCAG contrast >= 4.5 for on-colours).
        func contrast(_ a: RGBA, _ b: RGBA) -> Double {
            let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
            return (hi + 0.05) / (lo + 0.05)
        }
        XCTAssertGreaterThan(contrast(s[.onSurface], s[.surface]), 7)
        XCTAssertGreaterThan(contrast(s[.onPrimary], s[.primary]), 4.5)
        XCTAssertGreaterThan(contrast(s[.onPrimaryContainer], s[.primaryContainer]), 4.5)
        XCTAssertGreaterThan(contrast(s[.onError], s[.error]), 4.5)
        // Dark surface ladder gets lighter.
        XCTAssertLessThan(s[.surface].luminance, s[.surfaceContainer].luminance)
        XCTAssertLessThan(s[.surfaceContainer].luminance, s[.surfaceContainerHighest].luminance)
        XCTAssertGreaterThan(s[.primary].luminance, s[.primaryContainer].luminance)
    }

    func testKeepsBaseExtrasAndHue() {
        let s = DynamicScheme.make(source: RGBA(r: 0xd8, g: 0x40, b: 0x30), base: base)
        XCTAssertEqual(s.term(3), base.term(3))
        XCTAssertEqual(s["mauve"], base["mauve"])
        XCTAssertLessThan(ColorMath.differenceDegrees(Hct(s[.primary]).hue, Hct(RGBA(r: 0xd8, g: 0x40, b: 0x30)).hue), 15)
    }

    func testLightVariantInvertsTheLadder() {
        let s = DynamicScheme.make(source: RGBA(r: 0x40, g: 0x80, b: 0x40), dark: false, base: base)
        XCTAssertFalse(s.isDark)
        XCTAssertGreaterThan(s[.surface].luminance, 0.8)
        XCTAssertLessThan(s[.onSurface].luminance, 0.1)
    }

    func testStaticPeriwinklePrimaryIsReproducedCloselyFromItsOwnSource() {
        // The default scheme's key colour #6a769b: the generated primary stays in the same family.
        let s = DynamicScheme.make(source: RGBA(r: 0x6a, g: 0x76, b: 0x9b), base: base)
        XCTAssertLessThan(ColorMath.differenceDegrees(Hct(s[.primary]).hue, Hct(base[.primary]).hue), 10)
        XCTAssertEqual(Hct(s[.primary]).tone, 80, accuracy: 2)
    }
}

final class SchemeResolverTests: XCTestCase {
    private var base: Scheme { SchemeResolver.staticScheme(AppearanceConfig())! }

    func testStaticModeAlwaysReturnsTheBaseScheme() {
        var a = AppearanceConfig()
        a.schemeMode = "static"
        XCTAssertEqual(SchemeResolver.resolve(appearance: a, base: base, wallpaperSource: RGBA(r: 200, g: 20, b: 20)), base)
    }

    func testDynamicWithoutASourceFallsBackToBase() {
        var a = AppearanceConfig()
        a.schemeMode = "dynamic"
        XCTAssertEqual(SchemeResolver.resolve(appearance: a, base: base, wallpaperSource: nil), base)
    }

    func testDynamicUsesTheWallpaperSourceAndTheAccentOverrideWins() {
        var a = AppearanceConfig()
        a.schemeMode = "Dynamic"
        let fromWallpaper = SchemeResolver.resolve(appearance: a, base: base, wallpaperSource: RGBA(r: 0x20, g: 0xa0, b: 0x40))
        XCTAssertNotEqual(fromWallpaper[.primary], base[.primary])
        a.accentOverride = "d04020"
        let overridden = SchemeResolver.resolve(appearance: a, base: base, wallpaperSource: RGBA(r: 0x20, g: 0xa0, b: 0x40))
        XCTAssertNotEqual(overridden[.primary], fromWallpaper[.primary])
        a.variant = "light"
        XCTAssertFalse(SchemeResolver.resolve(appearance: a, base: base, wallpaperSource: nil).isDark)
    }

    func testDefaultsAreStaticPeriwinkle() {
        XCTAssertEqual(AppearanceConfig().schemeMode, "static")
        XCTAssertEqual(base[.primary].hex, "bac5ee")
    }
}

final class DashboardConfigParsingTests: XCTestCase {
    func testDefaultsAndParsing() throws {
        let d = Config().dashboard
        XCTAssertTrue(d.showClockSeconds)
        XCTAssertTrue(d.showBattery)
        XCTAssertEqual(d.defaultTab, "overview")
        let c = try ConfigLoader.parse(toml: """
            [appearance]
            schemeMode = "dynamic"
            wallpaperFolder = "~/Wallpapers"
            [dashboard]
            showClockSeconds = false
            defaultTab = "media"
            """)
        XCTAssertEqual(c.appearance.schemeMode, "dynamic")
        XCTAssertEqual(c.appearance.wallpaperFolder, "~/Wallpapers")
        XCTAssertFalse(c.dashboard.showClockSeconds)
        XCTAssertEqual(c.dashboard.defaultTab, "media")
        XCTAssertTrue(c.dashboard.showBattery, "unset keys keep their default")
    }

    func testInvalidValuesAreRejected() {
        XCTAssertThrowsError(try ConfigLoader.parse(toml: "[appearance]\nschemeMode = \"rainbow\""))
        XCTAssertThrowsError(try ConfigLoader.parse(toml: "[dashboard]\ndefaultTab = \"weather\""))
    }

    func testSerializeRoundTripKeepsTheNewKeys() throws {
        var c = Config()
        c.appearance.schemeMode = "dynamic"
        c.dashboard.defaultTab = "performance"
        let back = try ConfigLoader.parse(toml: try ConfigLoader.serialize(c))
        XCTAssertEqual(back, c)
    }
}
