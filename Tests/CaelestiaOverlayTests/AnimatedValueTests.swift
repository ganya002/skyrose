import CaelestiaCore
import XCTest

@testable import CaelestiaOverlay

final class AnimatedValueTests: XCTestCase {
    private let riko = AnimationSpec.spring(.riko)

    func testSetIsImmediate() {
        var v = AnimatedValue(0)
        v.set(42)
        XCTAssertEqual(v.value(at: 0), 42)
        XCTAssertEqual(v.value(at: 100), 42)
        XCTAssertTrue(v.isDone(at: 0))
    }

    func testSpringReachesTargetExactlyWhenDone() {
        var v = AnimatedValue(0)
        v.animate(to: 100, spec: riko, at: 0)
        XCTAssertEqual(v.value(at: 0), 0, accuracy: 1e-9)
        XCTAssertFalse(v.isDone(at: 0.01))
        let end = riko.duration
        XCTAssertTrue(v.isDone(at: end + 0.001))
        XCTAssertEqual(v.value(at: end + 0.001), 100)
        XCTAssertEqual(v.value(at: 50), 100)
    }

    func testRikoOvershootsSlightly() {
        var v = AnimatedValue(0)
        v.animate(to: 100, spec: riko, at: 0)
        var peak = 0.0
        var t = 0.0
        while t <= riko.duration {
            peak = max(peak, v.value(at: t))
            t += 0.001
        }
        XCTAssertGreaterThan(peak, 100)
        XCTAssertLessThan(peak, 105)
    }

    func testRetargetKeepsValueContinuous() {
        var v = AnimatedValue(0)
        v.animate(to: 100, spec: riko, at: 0)
        let t = 0.08
        let before = v.value(at: t)
        v.animate(to: 300, spec: riko, at: t)
        XCTAssertEqual(v.value(at: t), before, accuracy: 1e-9)
    }

    func testRetargetKeepsVelocity() {
        var v = AnimatedValue(0)
        v.animate(to: 100, spec: riko, at: 0)
        let t = 0.08
        let vBefore = v.currentVelocity(at: t)
        XCTAssertNotEqual(vBefore, 0)
        v.animate(to: 300, spec: riko, at: t)
        let vAfter = v.currentVelocity(at: t)
        XCTAssertNotEqual(vAfter, 0)
        XCTAssertEqual(vAfter, vBefore, accuracy: 1e-6)
    }

    func testAnimatingToSameTargetIsNoOp() {
        var v = AnimatedValue(0)
        v.animate(to: 100, spec: riko, at: 0)
        let snapshot = v
        v.animate(to: 100, spec: riko, at: 0.05)
        XCTAssertEqual(v, snapshot)

        var rest = AnimatedValue(7)
        rest.animate(to: 7, spec: riko, at: 1)
        XCTAssertTrue(rest.isDone(at: 1))
        XCTAssertEqual(rest.value(at: 1), 7)
    }

    func testDisabledSpecJumps() {
        var v = AnimatedValue(0)
        v.animate(to: 50, spec: .disabled, at: 3)
        XCTAssertEqual(v.value(at: 3), 50)
        XCTAssertTrue(v.isDone(at: 3))
        XCTAssertEqual(v.currentVelocity(at: 3), 0)
    }
}
