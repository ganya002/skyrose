import CoreGraphics
import Foundation
import XCTest

@testable import CaelestiaCore

final class MotionTests: XCTestCase {
    // MARK: - Reference implementations (independent of the production code paths)

    /// Bernstein-form cubic Bézier solved by plain bisection to machine precision.
    private func referenceBezier(_ c: CubicBezier, _ x: Double) -> Double {
        func bx(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * c.x1 + 3 * (1 - u) * u * u * c.x2 + u * u * u }
        func by(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * c.y1 + 3 * (1 - u) * u * u * c.y2 + u * u * u }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if bx(mid) < x { lo = mid } else { hi = mid }
        }
        return by((lo + hi) / 2)
    }

    private let namedCurves: [(String, CubicBezier)] = [
        ("default", .default), ("standard", .standard), ("emphasizedDecel", .emphasizedDecel),
        ("emphasizedAccel", .emphasizedAccel), ("specialWorkSwitch", .specialWorkSwitch),
        ("snappy", .snappy), ("linear", .linear),
    ]

    // MARK: - CubicBezier

    func testLinearMidpoint() {
        XCTAssertEqual(CubicBezier.linear.value(at: 0.5), 0.5, accuracy: 1e-8)
        XCTAssertEqual(CubicBezier.linear.value(at: 0.25), 0.25, accuracy: 1e-8)
        for i in 1..<100 {
            let x = Double(i) / 100
            XCTAssertEqual(CubicBezier.linear.value(at: x), x, accuracy: 1e-8, "linear at \(x)")
        }
    }

    func testStandardMidpointAgainstReference() {
        let value = CubicBezier.standard.value(at: 0.5)
        let reference = referenceBezier(.standard, 0.5)
        print("standard(0.5) = \(value) (reference \(reference))")
        XCTAssertEqual(value, reference, accuracy: 1e-6)
        // cubic-bezier(0.2, 0, 0, 1) at x = 0.5 is ≈ 0.878 (the parameter u ≈ 0.7817 gives u²(3 − 2u)).
        XCTAssertEqual(value, 0.8778, accuracy: 1e-3)
    }

    func testNamedCurvesMatchReferenceOnManySamples() {
        var worst = 0.0
        for (name, curve) in namedCurves {
            for i in 0...40 {
                let x = Double(i) / 40
                let got = curve.value(at: x)
                let want = referenceBezier(curve, x)
                worst = max(worst, abs(got - want))
                XCTAssertEqual(got, want, accuracy: 1e-3, "\(name) at \(x)")
                XCTAssertEqual(got, want, accuracy: 1e-5, "\(name) at \(x) (tight)")
            }
        }
        print("max bezier error vs reference: \(worst)")
    }

    func testBezierNumericalCoordinates() {
        XCTAssertEqual(CubicBezier.default, CubicBezier(x1: 0, y1: 0.75, x2: 0.15, y2: 1))
        XCTAssertEqual(CubicBezier.standard, CubicBezier(x1: 0.2, y1: 0, x2: 0, y2: 1))
        XCTAssertEqual(CubicBezier.emphasizedDecel, CubicBezier(x1: 0.05, y1: 0.7, x2: 0.1, y2: 1))
        XCTAssertEqual(CubicBezier.emphasizedAccel, CubicBezier(x1: 0.3, y1: 0, x2: 0.8, y2: 0.15))
        XCTAssertEqual(CubicBezier.specialWorkSwitch, CubicBezier(x1: 0.05, y1: 0.7, x2: 0.1, y2: 1))
        XCTAssertEqual(CubicBezier.snappy, CubicBezier(x1: 0.05, y1: 0.9, x2: 0.1, y2: 1.05))
        XCTAssertEqual(CubicBezier.linear, CubicBezier(x1: 0, y1: 0, x2: 1, y2: 1))
    }

    func testBezierEndpointsExactAndClamped() {
        for (name, curve) in namedCurves {
            XCTAssertEqual(curve.value(at: 0), 0, name)
            XCTAssertEqual(curve.value(at: 1), 1, name)
            XCTAssertEqual(curve.value(at: -0.5), 0, name)
            XCTAssertEqual(curve.value(at: 1.5), 1, name)
            XCTAssertEqual(curve.value(at: .nan), 0, name)
        }
    }

    func testBezierMonotonicForNonOvershootingCurves() {
        for (name, curve) in namedCurves where name != "snappy" {
            var previous = -Double.infinity
            for i in 0...1000 {
                let y = curve.value(at: Double(i) / 1000)
                XCTAssertGreaterThanOrEqual(y, previous - 1e-12, "\(name) not monotonic at \(i)")
                previous = y
            }
        }
    }

    func testSnappyOvershootsAndIsNotClamped() {
        let peak = (0...1000).map { CubicBezier.snappy.value(at: Double($0) / 1000) }.max()!
        print("snappy peak = \(peak)")
        XCTAssertGreaterThan(peak, 1.0)
        XCTAssertLessThan(peak, 1.05)
        XCTAssertEqual(CubicBezier.snappy.value(at: 1), 1)
    }

    func testBezierXControlPointsAreClamped() {
        let b = CubicBezier(x1: -1, y1: -0.5, x2: 2, y2: 1.5)
        XCTAssertEqual(b.x1, 0)
        XCTAssertEqual(b.x2, 1)
        XCTAssertEqual(b.y1, -0.5)
        XCTAssertEqual(b.y2, 1.5)
    }

    func testBezierNamedLookup() {
        for (name, curve) in namedCurves {
            XCTAssertEqual(CubicBezier.named(name), curve)
            XCTAssertEqual(CubicBezier.named(name.uppercased()), curve)
            let resolved = try? XCTUnwrap(curve.name, "\(name) should have a name")
            XCTAssertEqual(resolved.flatMap(CubicBezier.named), curve, "\(name) must round-trip through its name")
        }
        XCTAssertEqual(CubicBezier.standard.name, "standard")
        XCTAssertEqual(CubicBezier.snappy.name, "snappy")
        // specialWorkSwitch has the same control points as emphasizedDecel; the first table name wins.
        XCTAssertEqual(CubicBezier.specialWorkSwitch.name, "emphasizedDecel")
        XCTAssertEqual(CubicBezier.named("emphasized-decel"), .emphasizedDecel)
        XCTAssertEqual(CubicBezier.named(" special_work_switch "), .specialWorkSwitch)
        XCTAssertNil(CubicBezier.named("emphasized"))
        XCTAssertNil(CubicBezier.named(""))
        XCTAssertNil(CubicBezier.named("bogus"))
        XCTAssertEqual(CubicBezier.names, namedCurves.map(\.0))
        XCTAssertNil(CubicBezier(x1: 0.3, y1: 0.3, x2: 0.3, y2: 0.3).name)
    }

    func testBezierCodableRoundTripClampsX() throws {
        let data = try JSONEncoder().encode(CubicBezier.snappy)
        XCTAssertEqual(try JSONDecoder().decode(CubicBezier.self, from: data), .snappy)
        let raw = Data(#"{"x1":-2,"y1":0,"x2":3,"y2":1}"#.utf8)
        let decoded = try JSONDecoder().decode(CubicBezier.self, from: raw)
        XCTAssertEqual(decoded, .linear)
    }

    // MARK: - Spring

    func testRikoDampingRatioAndFrequency() {
        let s = Spring.riko
        XCTAssertEqual(s.mass, 1)
        XCTAssertEqual(s.stiffness, 180)
        XCTAssertEqual(s.damping, 20)
        XCTAssertGreaterThanOrEqual(s.dampingRatio, 0.74)
        XCTAssertLessThanOrEqual(s.dampingRatio, 0.75)
        XCTAssertEqual(s.naturalFrequency, 180.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(s.dampedFrequency, 180.0.squareRoot() * (1 - s.dampingRatio * s.dampingRatio).squareRoot(), accuracy: 1e-12)
        XCTAssertTrue(s.isUnderdamped)
        XCTAssertFalse(s.isCriticallyDamped)
        XCTAssertFalse(s.isOverdamped)
    }

    func testRikoSettlesBeforeDeadlineAndStaysSettled() {
        let s = Spring.riko
        let eps = 0.001
        let settling = s.settlingTime(epsilon: eps)
        print("riko settling time (eps 0.001) = \(settling) s")
        XCTAssertLessThan(settling, 1.2)
        XCTAssertGreaterThan(settling, 0.3)
        XCTAssertGreaterThanOrEqual(abs(s.position(at: settling - 1e-4) - 1), eps, "not the first settled time")
        var t = settling
        while t <= settling + 3 {
            XCTAssertLessThan(abs(s.position(at: t) - 1), eps, "unsettled at \(t)")
            t += 1e-4
        }
        let envelope = try! XCTUnwrap(s.envelopeBound(epsilon: eps, y0: -1, v0: 0))
        XCTAssertLessThanOrEqual(settling, envelope)
        XCTAssertGreaterThan(envelope, 0)
    }

    func testRikoOvershootIsAFewPercent() {
        let s = Spring.riko
        let overshoot = s.overshoot
        let z = s.dampingRatio
        let analytic = exp(-z * .pi / (1 - z * z).squareRoot())
        print("riko overshoot = \(overshoot) (\(overshoot * 100) %), analytic first peak \(analytic)")
        XCTAssertGreaterThanOrEqual(overshoot, 0.015)
        XCTAssertLessThanOrEqual(overshoot, 0.04)
        XCTAssertEqual(overshoot, analytic, accuracy: 1e-6)
        let sampledPeak = stride(from: 0.0, through: 2.0, by: 1e-4).map { s.position(at: $0) }.max()! - 1
        XCTAssertEqual(overshoot, sampledPeak, accuracy: 1e-6)
    }

    func testCriticallyAndOverdampedSpringsNeverOvershoot() {
        let critical = Spring(mass: 1, stiffness: 100, damping: 20)
        let over = Spring(mass: 1, stiffness: 100, damping: 40)
        XCTAssertEqual(critical.dampingRatio, 1, accuracy: 1e-12)
        XCTAssertTrue(critical.isCriticallyDamped)
        XCTAssertEqual(over.dampingRatio, 2, accuracy: 1e-12)
        XCTAssertTrue(over.isOverdamped)
        for s in [critical, over] {
            XCTAssertEqual(s.overshoot, 0)
            var previous = 0.0
            for i in 0...20000 {
                let x = s.position(at: Double(i) * 1e-4)
                XCTAssertLessThanOrEqual(x, 1 + 1e-12)
                XCTAssertGreaterThanOrEqual(x, previous - 1e-12, "non-monotonic at \(i)")
                previous = x
            }
            let settling = s.settlingTime()
            XCTAssertGreaterThan(settling, 0)
            XCTAssertLessThan(settling, 3)
            XCTAssertLessThan(abs(s.position(at: settling) - 1), 0.001 + 1e-9)
            XCTAssertGreaterThanOrEqual(abs(s.position(at: settling - 1e-4) - 1), 0.001)
        }
    }

    func testSpringInitialConditionsAndVelocityMatchFiniteDifference() {
        let springs = [
            Spring.riko, Spring(mass: 1, stiffness: 100, damping: 20), Spring(mass: 1, stiffness: 100, damping: 40),
            Spring(mass: 2, stiffness: 50, damping: 3),
        ]
        for s in springs {
            XCTAssertEqual(s.position(at: 0, from: 3, to: 7, initialVelocity: 2), 3)
            XCTAssertEqual(s.velocity(at: 0, from: 3, to: 7, initialVelocity: 2), 2)
            // Second-order Taylor expansion: x ≈ x0 + v0·t + ½·a0·t² with a0 = (k·(to − x0) − c·v0) / m.
            let a0 = (s.stiffness * 4 - s.damping * 2) / s.mass
            let t0 = 1e-3
            XCTAssertEqual(s.position(at: t0, from: 3, to: 7, initialVelocity: 2), 3 + 2 * t0 + 0.5 * a0 * t0 * t0, accuracy: 1e-5)
            XCTAssertEqual(s.position(at: 30, from: 3, to: 7, initialVelocity: 2), 7, accuracy: 1e-6)
            XCTAssertEqual(s.velocity(at: 30, from: 3, to: 7, initialVelocity: 2), 0, accuracy: 1e-6)
            for t in [0.05, 0.2, 0.5, 1.0] {
                let h = 1e-6
                let numeric = (s.position(at: t + h, from: 3, to: 7, initialVelocity: 2) - s.position(at: t - h, from: 3, to: 7, initialVelocity: 2)) / (2 * h)
                XCTAssertEqual(s.velocity(at: t, from: 3, to: 7, initialVelocity: 2), numeric, accuracy: 1e-5, "\(s) at \(t)")
            }
        }
    }

    func testSpringTimeScalingKeepsDampingRatio() {
        let slow = Spring.riko.timeScaled(by: 2)
        XCTAssertEqual(slow.dampingRatio, Spring.riko.dampingRatio, accuracy: 1e-12)
        XCTAssertEqual(slow.naturalFrequency, Spring.riko.naturalFrequency / 2, accuracy: 1e-12)
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(slow.position(at: 2 * t), Spring.riko.position(at: t), accuracy: 1e-12)
        }
        XCTAssertEqual(slow.settlingTime(), Spring.riko.settlingTime() * 2, accuracy: 2e-3)
        XCTAssertEqual(Spring.riko.timeScaled(by: 0), Spring.riko)
    }

    func testUndampedSpringReportsSettlingCap() {
        let s = Spring(mass: 1, stiffness: 100, damping: 0)
        XCTAssertEqual(s.settlingTime(), Spring.maxSettlingTime)
        XCTAssertEqual(s.overshoot, 1, accuracy: 1e-6, "an undamped spring swings all the way to 2")
        XCTAssertEqual(s.position(at: .pi / 10), 2, accuracy: 1e-9)
        XCTAssertEqual(AnimationSpec.spring(s).durationMs, Spring.maxSettlingTime * 1000)
    }

    // MARK: - AnimationSpec / durations

    func testSpeedToMilliseconds() {
        XCTAssertEqual(AnimationSpec.milliseconds(fromSpeed: 8), 800)
        XCTAssertEqual(AnimationSpec.speed(fromMilliseconds: 240), 2.4, accuracy: 1e-12)
        let spec = AnimationSpec.bezier(.default, speed: 8)
        XCTAssertEqual(spec.durationMs, 800)
        XCTAssertEqual(spec.duration, 0.8)
        XCTAssertEqual(spec.speed, 8)
        XCTAssertTrue(spec.enabled)
        XCTAssertEqual(spec.style, .none)
    }

    func testGabbySpringyTableValues() {
        let t = AnimationTable.gabbySpringy
        XCTAssertEqual(t[.global], .bezier(.default, milliseconds: 800))
        // Arch parity (2026-11-05 capture): close = emphasizedAccel 240 ms, open pops in from 80 %.
        XCTAssertEqual(t[.windowsOut].durationMs, 240)
        XCTAssertEqual(t[.windowsOut].curve, .bezier(.emphasizedAccel))
        XCTAssertEqual(t[.windowsOut].style, .popin(scale: 0.8))
        XCTAssertEqual(t[.windowsIn].curve, .spring(.snappy))
        XCTAssertEqual(t[.windowsIn].style, .popin(scale: 0.8))
        XCTAssertEqual(t[.windowsIn].durationMs, Spring.snappy.settlingTime() * 1000, accuracy: 1e-9)
        XCTAssertEqual(t[.windowsIn].durationMs, 303, accuracy: 1)
        XCTAssertEqual(t[.windowsMove], .spring(.snappy))
        for name in [AnimationName.workspaces, .workspacesIn, .workspacesOut] {
            XCTAssertEqual(t[name], .spring(.snappy, style: .slide), "\(name)")
        }
        XCTAssertEqual(t[.specialWorkspace], .spring(.snappy, style: .slideFadeVert(percent: 0.15)))
        XCTAssertEqual(t[.layersIn], .bezier(.emphasizedDecel, milliseconds: 400, style: .slide))
        XCTAssertEqual(t[.layersOut], .bezier(.emphasizedAccel, milliseconds: 320, style: .slide))
        XCTAssertEqual(t[.fadeLayers], .bezier(.standard, milliseconds: 400))
        for name in [AnimationName.fade, .fadeDim] {
            XCTAssertEqual(t[name], .bezier(.standard, milliseconds: 200), "\(name)")
        }
        // Border colour fade: Arch's 480 ms standard (a colour change; Gabby kept it over the cap).
        XCTAssertEqual(t[.border], .bezier(.standard, milliseconds: 480))
        for name in [AnimationName.borderangle, .glowangle, .shadowangle] {
            XCTAssertFalse(t[name].enabled, "\(name)")
            XCTAssertEqual(t[name].progress(at: 0), 1, "\(name)")
        }
        XCTAssertEqual(t[.shellSmall].durationMs, 160, accuracy: 1e-9)
        XCTAssertEqual(t[.shellNormal].durationMs, 320, accuracy: 1e-9)
        XCTAssertEqual(t[.shellLarge].durationMs, 480, accuracy: 1e-9)
        XCTAssertEqual(t[.shellExtraLarge].durationMs, 800, accuracy: 1e-9)
        XCTAssertEqual(t[.shellSmall].curve, .bezier(.standard))
        XCTAssertEqual(t[.shellNormal].curve, .bezier(.emphasizedDecel))
        XCTAssertEqual(Set(t.entries.keys), Set(AnimationName.allCases))
    }

    func testCaelestiaStockTableValues() {
        let t = AnimationTable.caelestiaStock
        XCTAssertEqual(t[.windowsIn], .bezier(.emphasizedDecel, milliseconds: 400, style: .popin(scale: 0.8)))
        XCTAssertEqual(t[.windowsMove], .bezier(.standard, milliseconds: 480))
        XCTAssertEqual(t[.windowsOut], .bezier(.emphasizedAccel, milliseconds: 240, style: .popin(scale: 0.8)))
        for name in [AnimationName.workspaces, .workspacesIn, .workspacesOut] {
            XCTAssertEqual(t[name], .bezier(.standard, milliseconds: 400, style: .slide), "\(name)")
        }
        XCTAssertEqual(t[.shellSmall].durationMs, 160, accuracy: 1e-9)
        XCTAssertEqual(AnimationTable.caelestiaStock(shellScale: 1.0)[.shellSmall].durationMs, 200, accuracy: 1e-9)
        XCTAssertEqual(AnimationTable.caelestiaStock(shellScale: 1.0)[.shellExtraLarge].durationMs, 1000, accuracy: 1e-9)
        XCTAssertEqual(AnimationTable.caelestiaStock(shellScale: 1.0)[.windowsMove].durationMs, 480)
        // windowsOut, specialWorkspace, fade, fadeDim and border now differ between the presets on purpose.
        let differing: [AnimationName] = [.windowsIn, .windowsMove, .windowsOut, .workspaces, .workspacesIn, .workspacesOut, .specialWorkspace, .fade, .fadeDim, .border]
        for name in AnimationName.allCases where !name.isShellDuration && !differing.contains(name) {
            XCTAssertEqual(t[name], AnimationTable.gabbySpringy[name], "\(name) should be shared between presets")
        }
    }

    func testReducedAndOffTables() {
        for name in AnimationName.allCases {
            XCTAssertEqual(AnimationTable.reduced[name], .bezier(.standard, milliseconds: 120, style: .fade), "\(name)")
            XCTAssertEqual(AnimationTable.off[name], .disabled, "\(name)")
            XCTAssertFalse(AnimationTable.off[name].enabled)
            XCTAssertEqual(AnimationTable.off[name].durationMs, 0)
            XCTAssertTrue(AnimationTable.off[name].isFinished(at: 0))
        }
    }

    func testGlobalMultiplierHalvesEveryDuration() {
        var config = AnimationsConfig()
        config.globalMultiplier = 0.5
        let base = AnimationTable.gabbySpringy
        let halved = AnimationTable.from(config: config, reduceMotion: false)
        for name in AnimationName.allCases {
            XCTAssertEqual(halved[name].durationMs, base[name].durationMs * 0.5, accuracy: 1e-9, "\(name)")
            XCTAssertEqual(halved[name].style, base[name].style, "\(name)")
            XCTAssertEqual(halved[name].enabled, base[name].enabled, "\(name)")
        }
        guard case .spring(let fast) = halved[.windowsMove].curve else { return XCTFail("windowsMove must stay a spring") }
        XCTAssertEqual(fast.dampingRatio, Spring.snappy.dampingRatio, accuracy: 1e-12)
        XCTAssertLessThan(abs(fast.position(at: halved[.windowsMove].duration) - 1), 0.0011)
        XCTAssertEqual(fast.settlingTime() * 1000, halved[.windowsMove].durationMs, accuracy: 1)
    }

    func testReduceMotionWinsWhenRespected() {
        var config = AnimationsConfig()
        config.globalMultiplier = 2
        config.overrides["windowsIn"] = AnimationOverride(speed: 4)
        XCTAssertEqual(AnimationTable.from(config: config, reduceMotion: true), .reduced)
        config.respectReduceMotion = false
        XCTAssertNotEqual(AnimationTable.from(config: config, reduceMotion: true), .reduced)
        config.preset = .off
        XCTAssertEqual(AnimationTable.from(config: config, reduceMotion: true), .off)
        XCTAssertEqual(AnimationTable.from(config: config, reduceMotion: false), .off)
        config.preset = .reduced
        config.respectReduceMotion = true
        XCTAssertEqual(AnimationTable.from(config: config, reduceMotion: false)[.windowsOut].durationMs, 240)
    }

    func testPresetSelectionUsesShellDurationScale() {
        var config = AnimationsConfig()
        config.preset = .caelestiaStock
        config.shellDurationScale = 1.0
        let t = AnimationTable.from(config: config, reduceMotion: false)
        XCTAssertEqual(t[.windowsIn].curve, .bezier(.emphasizedDecel))
        XCTAssertEqual(t[.shellNormal].durationMs, 400, accuracy: 1e-9)
        XCTAssertEqual(AnimationTable.from(config: AnimationsConfig(), reduceMotion: false), .gabbySpringy)
    }

    func testOverridesApplyEnabledCurveSpeedAndStyle() {
        var config = AnimationsConfig()
        config.overrides["windowsIn"] = AnimationOverride(speed: 4)
        config.overrides["WINDOWSOUT"] = AnimationOverride(enabled: false, curve: "standard", style: "slide")
        config.overrides["workspaces"] = AnimationOverride(curve: "riko")
        config.overrides["fade"] = AnimationOverride(curve: "nonsense", speed: 1, style: "gnomed")
        config.overrides["notAnAnimation"] = AnimationOverride(speed: 1)
        let t = AnimationTable.from(config: config, reduceMotion: false)

        let windowsIn = t[.windowsIn]
        XCTAssertEqual(windowsIn.durationMs, 400, accuracy: 1e-9)
        XCTAssertEqual(windowsIn.style, .popin(scale: 0.8))
        guard case .spring(let spring) = windowsIn.curve else { return XCTFail("windowsIn must stay a spring") }
        XCTAssertEqual(spring.dampingRatio, Spring.snappy.dampingRatio, accuracy: 1e-12)
        XCTAssertLessThan(abs(spring.position(at: 0.4) - 1), 0.0011)
        XCTAssertGreaterThanOrEqual(abs(spring.position(at: 0.39) - 1), 0.0009)

        XCTAssertEqual(t[.windowsOut], AnimationSpec(enabled: false, curve: .bezier(.standard), durationMs: 240, style: .slide))
        XCTAssertEqual(t[.workspaces].curve, .spring(.riko))
        XCTAssertEqual(t[.workspaces].durationMs, Spring.riko.settlingTime() * 1000, accuracy: 1e-9)
        XCTAssertEqual(t[.workspaces].style, .slide)
        XCTAssertEqual(t[.fade], .bezier(.standard, milliseconds: 100))
        XCTAssertEqual(t[.workspacesIn], AnimationTable.gabbySpringy[.workspacesIn])
    }

    func testStyleParsing() {
        XCTAssertEqual(AnimationStyle(hyprland: "popin 80%"), .popin(scale: 0.8))
        XCTAssertEqual(AnimationStyle(hyprland: "slidefadevert 15%"), .slideFadeVert(percent: 0.15))
        XCTAssertEqual(AnimationStyle(hyprland: "slide"), .slide)
        XCTAssertEqual(AnimationStyle(hyprland: "fade"), .fade)
        XCTAssertEqual(AnimationStyle(hyprland: "PopIn 80%"), .popin(scale: 0.8))
        XCTAssertEqual(AnimationStyle(hyprland: "  SlideFadeVert   15% "), .slideFadeVert(percent: 0.15))
        XCTAssertEqual(AnimationStyle(hyprland: "popin 80"), .popin(scale: 0.8))
        XCTAssertEqual(AnimationStyle(hyprland: "popin"), .popin(scale: 0))
        XCTAssertEqual(AnimationStyle(hyprland: "slidefadevert"), .slideFadeVert(percent: 1))
        XCTAssertEqual(AnimationStyle(hyprland: "slide left"), .slide)
        XCTAssertEqual(AnimationStyle(hyprland: ""), AnimationStyle.none)
        XCTAssertEqual(AnimationStyle(hyprland: "none"), AnimationStyle.none)
        XCTAssertNil(AnimationStyle(hyprland: "gnomed"))
        XCTAssertNil(AnimationStyle(hyprland: "bogus 80%"))
    }

    func testStyleHyprlandStringRoundTrip() {
        let styles: [AnimationStyle] = [.none, .popin(scale: 0.8), .slide, .slideFadeVert(percent: 0.15), .fade, .popin(scale: 0.125)]
        for style in styles {
            XCTAssertEqual(AnimationStyle(hyprland: style.hyprlandString), style, style.hyprlandString)
        }
        XCTAssertEqual(AnimationStyle.popin(scale: 0.8).hyprlandString, "popin 80%")
        XCTAssertEqual(AnimationStyle.slideFadeVert(percent: 0.15).hyprlandString, "slidefadevert 15%")
        XCTAssertEqual(AnimationStyle.popin(scale: 0.125).hyprlandString, "popin 12.5%")
    }

    func testCurveKindParsing() {
        XCTAssertEqual(CurveKind.named("standard"), .bezier(.standard))
        XCTAssertEqual(CurveKind.named("Snappy"), .bezier(.snappy))
        XCTAssertEqual(CurveKind.named("riko"), .spring(.riko))
        XCTAssertEqual(CurveKind.named("spring riko"), .spring(.riko))
        XCTAssertEqual(CurveKind.named("spring(1, 180, 20)"), .spring(.riko))
        XCTAssertEqual(CurveKind.named("spring(2, 50, 3)"), .spring(Spring(mass: 2, stiffness: 50, damping: 3)))
        XCTAssertEqual(CurveKind.named("bezier(0.2, 0, 0, 1)"), .bezier(.standard))
        XCTAssertEqual(CurveKind.named("cubic-bezier(0.3, -0.2, 0.7, 1.2)"), .bezier(CubicBezier(x1: 0.3, y1: -0.2, x2: 0.7, y2: 1.2)))
        XCTAssertNil(CurveKind.named("spring(1, 2)"))
        XCTAssertNil(CurveKind.named("bezier(1, 2, 3)"))
        XCTAssertNil(CurveKind.named(""))
        XCTAssertNil(CurveKind.named("emphasized"))
        XCTAssertEqual(CurveKind.bezier(.emphasizedDecel).name, "emphasizedDecel")
        XCTAssertEqual(CurveKind.spring(.riko).name, "riko")
        XCTAssertEqual(CurveKind.named(CurveKind.spring(Spring(mass: 2, stiffness: 50, damping: 3)).name), .spring(Spring(mass: 2, stiffness: 50, damping: 3)))
        XCTAssertEqual(CurveKind.named(CurveKind.bezier(CubicBezier(x1: 0.3, y1: -0.2, x2: 0.7, y2: 1.2)).name), .bezier(CubicBezier(x1: 0.3, y1: -0.2, x2: 0.7, y2: 1.2)))
        XCTAssertTrue(CurveKind.spring(.riko).isSpring)
        XCTAssertFalse(CurveKind.bezier(.linear).isSpring)
    }

    func testAnimationNameLookupAndInheritance() {
        XCTAssertEqual(AnimationName(configKey: "windowsin"), .windowsIn)
        XCTAssertEqual(AnimationName(configKey: "SpecialWorkspace"), .specialWorkspace)
        XCTAssertNil(AnimationName(configKey: "windows"))
        XCTAssertEqual(AnimationName.workspacesIn.parent, .workspaces)
        XCTAssertEqual(AnimationName.fadeDim.parent, .fade)
        XCTAssertEqual(AnimationName.windowsIn.parent, .global)
        XCTAssertNil(AnimationName.global.parent)

        var table = AnimationTable()
        XCTAssertEqual(table[.windowsIn], .disabled)
        table[.global] = .bezier(.default, speed: 8)
        XCTAssertEqual(table[.windowsIn], .bezier(.default, speed: 8))
        table[.workspaces] = .bezier(.snappy, speed: 3.2, style: .slide)
        XCTAssertEqual(table[.specialWorkspace], .bezier(.snappy, speed: 3.2, style: .slide))
        XCTAssertEqual(table[.fadeDim], .bezier(.default, speed: 8))
        XCTAssertEqual(table.entries.count, 2)
    }

    func testSpecProgressBezierAndSpring() {
        let bezier = AnimationSpec.bezier(.standard, speed: 3.2)
        XCTAssertEqual(bezier.progress(at: -1), 0)
        XCTAssertEqual(bezier.progress(at: 0), 0)
        XCTAssertEqual(bezier.progress(at: 0.16), CubicBezier.standard.value(at: 0.5), accuracy: 1e-12)
        XCTAssertEqual(bezier.progress(at: 0.32), 1)
        XCTAssertEqual(bezier.progress(at: 5), 1)
        XCTAssertFalse(bezier.isFinished(at: 0.3199))
        XCTAssertTrue(bezier.isFinished(at: 0.32))

        let spring = AnimationSpec.spring(.riko, style: .popin(scale: 0.8))
        XCTAssertEqual(spring.progress(at: 0), 0)
        XCTAssertEqual(spring.progress(at: 0.1), Spring.riko.position(at: 0.1), accuracy: 1e-12)
        XCTAssertGreaterThan(spring.progress(at: 0.351), 1.02, "riko overshoots near its first peak")
        XCTAssertFalse(spring.isFinished(at: spring.duration - 1e-6))
        XCTAssertLessThan(abs(spring.progress(at: spring.duration - 1e-6) - 1), 0.0011)
        XCTAssertEqual(spring.progress(at: spring.duration), 1)
        XCTAssertTrue(spring.isFinished(at: spring.duration))

        XCTAssertEqual(AnimationSpec.disabled.progress(at: 0), 1)
        XCTAssertTrue(AnimationSpec.disabled.isFinished(at: -5))
        var off = bezier
        off.enabled = false
        XCTAssertEqual(off.progress(at: 0.1), 1)
        XCTAssertTrue(off.isFinished(at: 0))
    }

    func testSpecScalingAndWithDuration() {
        let bezier = AnimationSpec.bezier(.standard, speed: 4, style: .slide)
        XCTAssertEqual(bezier.scaled(by: 0.5).durationMs, 200)
        XCTAssertEqual(bezier.scaled(by: 0.5).curve, .bezier(.standard))
        XCTAssertEqual(bezier.scaled(by: 0).durationMs, 0)
        XCTAssertEqual(bezier.scaled(by: -1).progress(at: 0), 1)
        XCTAssertEqual(bezier.withDuration(milliseconds: 250).durationMs, 250)
        XCTAssertEqual(bezier.withCurve(.bezier(.snappy)), .bezier(.snappy, speed: 4, style: .slide))

        let spring = AnimationSpec.spring(.riko)
        let doubled = spring.scaled(by: 2)
        XCTAssertEqual(doubled.durationMs, spring.durationMs * 2, accuracy: 1e-9)
        guard case .spring(let slow) = doubled.curve else { return XCTFail("expected a spring") }
        XCTAssertEqual(slow, Spring.riko.timeScaled(by: 2))
        XCTAssertEqual(spring.withDuration(milliseconds: 300).durationMs, 300)
        guard case .spring(let fast) = spring.withDuration(milliseconds: 300).curve else { return XCTFail("expected a spring") }
        XCTAssertEqual(fast.settlingTime() * 1000, 300, accuracy: 1)
        XCTAssertEqual(spring.withDuration(milliseconds: 0).durationMs, 0)
        XCTAssertEqual(bezier.withCurve(.spring(.riko)).durationMs, spring.durationMs, accuracy: 1e-9)
        XCTAssertEqual(spring.withCurve(.bezier(.linear)).durationMs, spring.durationMs)
    }

    func testTableCodableRoundTrip() throws {
        let table = AnimationTable.gabbySpringy
        let data = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(AnimationTable.self, from: data)
        XCTAssertEqual(decoded, table)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"windowsIn\""))
        let spec = try JSONDecoder().decode(AnimationSpec.self, from: JSONEncoder().encode(table[.specialWorkspace]))
        XCTAssertEqual(spec, table[.specialWorkspace])
    }

    // MARK: - Animator

    func testInterpolationLerp() {
        XCTAssertEqual(Interpolation.lerp(10, 20, 0.25), 12.5)
        XCTAssertEqual(Interpolation.lerp(10, 20, 1.05), 20.5, accuracy: 1e-12)
        let a = CGRect(x: 0, y: 0, width: 100, height: 50)
        let b = CGRect(x: 100, y: 20, width: 200, height: 150)
        XCTAssertEqual(Interpolation.lerp(a, b, 0), a)
        XCTAssertEqual(Interpolation.lerp(a, b, 1), b)
        XCTAssertEqual(Interpolation.lerp(a, b, 0.5), CGRect(x: 50, y: 10, width: 150, height: 100))
        XCTAssertEqual(Interpolation.lerp(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: -10), 0.1), CGPoint(x: 1, y: -1))
        XCTAssertEqual(Interpolation.lerp(CGSize(width: 2, height: 4), CGSize(width: 4, height: 8), 0.5), CGSize(width: 3, height: 6))
    }

    func testFrameSamplerReachesOneAndIsDone() {
        let spec = AnimationSpec.bezier(.snappy, milliseconds: 280, style: .slide)
        let sampler = FrameSampler(spec: spec, startTime: 10)
        XCTAssertEqual(spec.duration, 0.28, accuracy: 1e-12)
        XCTAssertEqual(sampler.endTime, 10.28, accuracy: 1e-12)
        XCTAssertEqual(sampler.value(at: 9.5), 0)
        XCTAssertFalse(sampler.isDone(at: 9.5))
        XCTAssertEqual(sampler.value(at: 10), 0)
        let mid = sampler.value(at: 10.14)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertEqual(mid, CubicBezier.snappy.value(at: 0.5), accuracy: 1e-12)
        XCTAssertFalse(sampler.isDone(at: sampler.endTime - 1e-4))
        XCTAssertEqual(sampler.value(at: sampler.endTime + 1e-9), 1)
        XCTAssertTrue(sampler.isDone(at: sampler.endTime + 1e-9))
        XCTAssertEqual(sampler.value(at: 11), 1)
        XCTAssertTrue(sampler.isDone(at: 11))

        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to = CGRect(x: 100, y: 100, width: 300, height: 200)
        XCTAssertEqual(sampler.frame(from: from, to: to, at: 10), from)
        XCTAssertEqual(sampler.frame(from: from, to: to, at: 20), to)
        XCTAssertEqual(sampler.scalar(from: 0.8, to: 1, at: 10.14), Interpolation.lerp(0.8, 1, mid), accuracy: 1e-12)
    }

    func testFrameSamplerSpringAndDisabled() {
        let spring = FrameSampler(spec: AnimationTable.gabbySpringy[.windowsMove], startTime: 100)
        XCTAssertEqual(spring.value(at: 100), 0)
        XCTAssertFalse(spring.isDone(at: 100))
        XCTAssertEqual(spring.value(at: 100.2), Spring.snappy.position(at: 0.2), accuracy: 1e-12)
        let end = spring.endTime
        XCTAssertFalse(spring.isDone(at: end - 1e-6))
        XCTAssertLessThan(abs(spring.value(at: end - 1e-6) - 1), 0.0011)
        XCTAssertEqual(spring.value(at: end), 1)
        XCTAssertTrue(spring.isDone(at: end))
        XCTAssertEqual(spring.value(at: end + 10), 1)

        let off = FrameSampler(spec: AnimationTable.off[.windowsMove], startTime: 100)
        XCTAssertEqual(off.value(at: 100), 1)
        XCTAssertTrue(off.isDone(at: 100))
        XCTAssertEqual(off.endTime, 100)
    }
}
