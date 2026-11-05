import XCTest

@testable import CaelestiaCore

/// Guards on how long the default window animations may take, and on `animations.speed`.
final class AnimationGuardTests: XCTestCase {
    /// Everything that moves or fades a window. The border *colour* fade is the one exception to
    /// the cap: Gabby chose Arch's 480 ms for it (2026-11-05 parity pass).
    private let windowSet: [AnimationName] = [
        .windowsIn, .windowsMove, .windowsOut, .workspaces, .workspacesIn, .workspacesOut, .specialWorkspace, .fade, .fadeDim,
    ]

    func testBorderColourFadeKeepsArchDuration() {
        let table = AnimationTable.from(config: AnimationsConfig(), reduceMotion: false)
        XCTAssertEqual(table[.border].durationMs, 480, accuracy: 1e-9)
        XCTAssertEqual(table[.border].curve, .bezier(.standard))
    }

    func testNoDefaultWindowAnimationExceeds350ms() {
        let table = AnimationTable.from(config: AnimationsConfig(), reduceMotion: false)
        for name in windowSet {
            XCTAssertLessThanOrEqual(table[name].durationMs, 350, "\(name) = \(table[name].durationMs) ms")
            XCTAssertGreaterThan(table[name].durationMs, 0, "\(name)")
            XCTAssertTrue(table[name].enabled, "\(name)")
        }
        XCTAssertEqual(table, AnimationTable.gabbySpringy)
    }

    func testTheSpringsSettleWithinTheirDuration() {
        let t = AnimationTable.gabbySpringy
        for name in [AnimationName.windowsIn, .windowsMove] {
            guard case .spring(let s) = t[name].curve else { return XCTFail("\(name) must be a spring") }
            XCTAssertEqual(s, .snappy)
            XCTAssertLessThan(abs(s.position(at: t[name].duration) - 1), 0.0011, "\(name)")
        }
    }

    func testSpeedTwoHalvesEveryDuration() {
        var config = AnimationsConfig()
        config.speed = 2
        XCTAssertEqual(config.durationFactor, 0.5, accuracy: 1e-12)
        let base = AnimationTable.gabbySpringy
        let fast = AnimationTable.from(config: config, reduceMotion: false)
        for name in windowSet {
            XCTAssertEqual(fast[name].durationMs, base[name].durationMs / 2, accuracy: 1e-9, "\(name)")
            XCTAssertLessThanOrEqual(fast[name].durationMs, 175, "\(name)")
            XCTAssertEqual(fast[name].style, base[name].style, "\(name)")
        }
        guard case .spring(let s) = fast[.windowsMove].curve else { return XCTFail("windowsMove stays a spring") }
        XCTAssertEqual(s.dampingRatio, Spring.snappy.dampingRatio, accuracy: 1e-12)
        XCTAssertEqual(s.settlingTime() * 1000, fast[.windowsMove].durationMs, accuracy: 1)
    }

    func testSpeedAndGlobalMultiplierCompose() {
        var config = AnimationsConfig()
        config.speed = 2
        config.globalMultiplier = 3
        XCTAssertEqual(config.durationFactor, 1.5, accuracy: 1e-12)
        let t = AnimationTable.from(config: config, reduceMotion: false)
        XCTAssertEqual(t[.windowsOut].durationMs, 240 * 1.5, accuracy: 1e-9)
        config.speed = 0.5
        config.globalMultiplier = 1
        XCTAssertEqual(AnimationTable.from(config: config, reduceMotion: false)[.fade].durationMs, 400, accuracy: 1e-9)
    }

    func testDefaultSpeedLeavesTheTableUntouched() {
        XCTAssertEqual(AnimationsConfig().speed, 1)
        XCTAssertEqual(AnimationsConfig().durationFactor, 1)
    }

    func testSpeedIsReadFromTheConfigFile() throws {
        let c = try ConfigLoader.parse(toml: "[animations]\nspeed = 2.0\n")
        XCTAssertEqual(c.animations.speed, 2)
        XCTAssertEqual(c.animations.durationFactor, 0.5, accuracy: 1e-12)
    }

    func testConfigLoaderRejectsSpeedOutOfRange() throws {
        for bad in ["0", "-1", "10.5", "100"] {
            XCTAssertThrowsError(try ConfigLoader.parse(toml: "[animations]\nspeed = \(bad)\n"), "speed = \(bad)") { error in
                XCTAssertTrue(String(describing: error).contains("animations.speed"), "\(error)")
            }
        }
        for good in ["0.1", "1", "10"] {
            XCTAssertNoThrow(try ConfigLoader.parse(toml: "[animations]\nspeed = \(good)\n"), "speed = \(good)")
        }
        var c = Config()
        c.animations.speed = 0
        XCTAssertEqual(ConfigLoader.validate(c).map(\.path), ["animations.speed"])
    }

    func testNamedSpringCurve() {
        XCTAssertEqual(CurveKind.named("spring"), .spring(.snappy))
        XCTAssertEqual(CurveKind.named("riko"), .spring(.riko))
        XCTAssertEqual(CurveKind.named("Spring Riko"), .spring(.riko))
        XCTAssertEqual(CurveKind.spring(.snappy).name, "snappy-spring")
        XCTAssertEqual(CurveKind.named(CurveKind.spring(.snappy).name), .spring(.snappy))
        XCTAssertEqual(CurveKind.named(CurveKind.spring(.riko).name), .spring(.riko))
    }

    func testSnappySpringSettlesInAboutThreeHundredMilliseconds() {
        XCTAssertEqual(Spring.snappy, Spring(mass: 1, stiffness: 800, damping: 46))
        XCTAssertEqual(Spring.snappy.settlingTime() * 1000, 303, accuracy: 1)
        XCTAssertLessThan(Spring.snappy.settlingTime(), Spring.riko.settlingTime() / 1.8, "about twice as fast as riko")
    }
}
