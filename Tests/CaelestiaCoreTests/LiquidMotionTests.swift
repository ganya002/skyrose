import XCTest

@testable import CaelestiaCore

/// The liquid pass: overshoot and squash, inside the hard limits (≤ 350 ms, springs settle).
final class LiquidMotionTests: XCTestCase {
    func testSpringsSettleIn300msAndOvershootAsDesigned() {
        for (s, z, os) in [(LiquidMotion.windowPop, 0.58, 0.107), (LiquidMotion.windowMove, 0.72, 0.039), (LiquidMotion.barReveal, 0.62, 0.08)] {
            XCTAssertEqual(s.dampingRatio, z, accuracy: 1e-9)
            XCTAssertEqual(s.settlingTime(), 0.30, accuracy: 0.002)
            XCTAssertEqual(s.overshoot, os, accuracy: 0.006)
        }
    }

    func testPopSwellsPast100Percent() {
        // 0.8 → 1 scale: the peak is above 1, and by 300 ms it is back within 0.1 %.
        let s = LiquidMotion.windowPop
        let peak = (0...300).map { s.position(at: Double($0) / 1000, from: 0.8, to: 1) }.max()!
        XCTAssertGreaterThan(peak, 1.015)
        XCTAssertLessThan(peak, 1.03)
        XCTAssertEqual(s.position(at: 0.30, from: 0.8, to: 1), 1, accuracy: 0.0003)
    }

    func testDampingForOvershootRoundTrips() {
        for f in [0.02, 0.05, 0.08, 0.15] {
            let z = LiquidMotion.dampingRatio(forOvershoot: f)
            XCTAssertEqual(LiquidMotion.spring(dampingRatio: z, settle: 0.3).overshoot, f, accuracy: 0.002)
        }
    }

    func testDrawersBounceAboutTheSameNumberOfPoints() {
        for depth in [200.0, 300, 400, 560] {
            let s = LiquidMotion.drawerSpring(depth: depth)
            XCTAssertEqual(s.overshoot * depth, LiquidMotion.bouncePoints, accuracy: 1.5, "depth \(depth)")
            XCTAssertLessThanOrEqual(s.settlingTime(), 0.302)
            XCTAssertGreaterThanOrEqual(LiquidMotion.overshootRoom(depth: depth), s.overshoot * depth)
        }
        // Small drawers are capped (no wobble); the room still covers the swing.
        let osd = LiquidMotion.drawerSpring(depth: 60)
        XCTAssertEqual(osd.overshoot, LiquidMotion.maxOvershoot, accuracy: 0.003)
        XCTAssertGreaterThanOrEqual(LiquidMotion.overshootRoom(depth: 60), 60 * osd.overshoot)
        XCTAssertEqual(LiquidMotion.drawerSpring(depth: 5000).overshoot, LiquidMotion.minOvershoot, accuracy: 0.002)
    }

    func testNeckIsCriticallyDampedAndSlower() {
        let n = LiquidMotion.neckSpring()
        XCTAssertEqual(n.dampingRatio, 1, accuracy: 1e-9)
        XCTAssertEqual(n.overshoot, 0)
        XCTAssertLessThanOrEqual(n.settlingTime(), 0.35)
        XCTAssertGreaterThan(n.settlingTime(), LiquidMotion.drawerSpring(depth: 300).settlingTime())
    }

    func testWorkspaceSlideIsArchSnappy() {
        let t = AnimationTable.gabbySpringy
        XCTAssertEqual(t[.workspaces].curve, .bezier(CubicBezier(x1: 0.05, y1: 0.9, x2: 0.1, y2: 1.05)))
        XCTAssertEqual(t[.workspaces].durationMs, 320)
        let peak = (0...1000).map { t[.workspaces].progress(at: 0.32 * Double($0) / 1000) }.max()!
        XCTAssertGreaterThan(peak, 1.005, "snappy overshoot")
    }

    func testReduceMotionDropsAllOfIt() {
        let t = AnimationTable.from(config: AnimationsConfig(), reduceMotion: true)
        for name in [AnimationName.windowsIn, .windowsMove, .workspaces] {
            XCTAssertEqual(t[name].style, .fade)
            XCTAssertFalse(t[name].curve.isSpring)
            XCTAssertLessThanOrEqual(t[name].durationMs, 120)
        }
    }
}
