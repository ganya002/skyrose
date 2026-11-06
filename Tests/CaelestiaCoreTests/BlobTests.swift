import CaelestiaCore
import CoreGraphics
import XCTest

final class BlobTests: XCTestCase {
    // A 1000×600 surface with a 10 pt band (inner radius 25).
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
    var frame: BlobFrame {
        BlobFrame(outer: bounds.insetBy(dx: -50, dy: -50), inner: bounds.insetBy(dx: 10, dy: 10), radius: 25)
    }

    func testCircularSminIsMinAwayFromTheBlend() {
        XCTAssertEqual(BlobSDF.smin(30, 50, 20), 30)
        XCTAssertEqual(BlobSDF.smin(-5, 40, 20), -5)
        XCTAssertLessThan(BlobSDF.smin(5, 5, 20), 5)
        // Deepest blend at a == b is (√2 − 1)·k below... the arc: min − k + k(√2 − (…)).
        for a in stride(from: -10.0, through: 30, by: 2.5) {
            for b in stride(from: -10.0, through: 30, by: 2.5) {
                XCTAssertLessThanOrEqual(BlobSDF.smin(a, b, 20), min(a, b) + 1e-9)
            }
        }
    }

    func testEmptyFrameIsABandAroundTheScreen() {
        let s = BlobScene(rects: [], frame: frame)
        XCTAssertLessThan(BlobSDF.distance(at: CGPoint(x: 5, y: 300), scene: s), 0, "left band")
        XCTAssertLessThan(BlobSDF.distance(at: CGPoint(x: 500, y: 595), scene: s), 0, "bottom band")
        XCTAssertGreaterThan(BlobSDF.distance(at: CGPoint(x: 500, y: 300), scene: s), 0, "window area")
        // The inner corner is rounded: just inside the corner square is outside the band.
        XCTAssertLessThan(BlobSDF.distance(at: CGPoint(x: 12, y: 12), scene: s), 0)
        XCTAssertGreaterThan(BlobSDF.distance(at: CGPoint(x: 40, y: 40), scene: s), 0)
    }

    /// A launcher sitting on the bottom band: beside its foot the band swells into a concave
    /// fillet, far from it the band is flat again.
    func testDrawerGrowsOutOfTheBandWithAFillet() {
        let launcher = BlobRect(rect: CGRect(x: 350, y: 390, width: 300, height: 200), radii: .uniform(28))
        let s = BlobScene(rects: [launcher], frame: frame)
        XCTAssertLessThan(BlobSDF.distance(at: CGPoint(x: 500, y: 450), scene: s), 0, "body")
        // 4 pt left of the body, 6 pt above the band: inside the fillet.
        XCTAssertLessThan(BlobSDF.distance(at: CGPoint(x: 346, y: 584), scene: s), 0, "fillet")
        // The same height far from the drawer is window area.
        XCTAssertGreaterThan(BlobSDF.distance(at: CGPoint(x: 150, y: 584), scene: s), 0, "flat band")
        // Without the frame there is no fillet.
        XCTAssertGreaterThan(BlobSDF.distance(at: CGPoint(x: 346, y: 584), scene: BlobScene(rects: [launcher])), 0)
    }

    func testNeighbouringDrawersFuseUnlessExcluded() {
        let a = BlobRect(rect: CGRect(x: 600, y: 10, width: 390, height: 300), radii: .uniform(28))
        let b = BlobRect(rect: CGRect(x: 600, y: 316, width: 390, height: 274), radii: .uniform(28))
        let gap = CGPoint(x: 800, y: 313)
        XCTAssertLessThan(BlobSDF.distance(at: gap, scene: BlobScene(rects: [a, b])), 0, "6 pt gap closes")
        var ex = a
        ex.excludeMask = 1 << 1
        XCTAssertGreaterThan(BlobSDF.distance(at: gap, scene: BlobScene(rects: [ex, b])), 0, "excluded pair stays apart")
    }

    func testCornersOnTheBandAreSquaredFreeCornersStayRound() {
        let launcher = BlobRect(rect: CGRect(x: 350, y: 390, width: 300, height: 215), radii: .uniform(28))
        let r = BlobSDF.effectiveRadii(BlobScene(rects: [launcher], frame: frame))[0]
        XCTAssertEqual(r.topLeft, 28, accuracy: 1e-9)
        XCTAssertEqual(r.topRight, 28, accuracy: 1e-9)
        XCTAssertEqual(r.bottomLeft, BlobSDF.minRadius, accuracy: 1e-9)
        XCTAssertEqual(r.bottomRight, BlobSDF.minRadius, accuracy: 1e-9)
    }

    func testDeformedRectIsStretchedAlongTheMatrix() {
        let base = BlobRect(rect: CGRect(x: 400, y: 200, width: 200, height: 200), radii: .uniform(10))
        var wide = base
        wide.deform = BlobDeform(m00: 1.3, m01: 0, m11: 1 / 1.3)
        let p = CGPoint(x: 615, y: 300)
        XCTAssertGreaterThan(BlobSDF.distance(at: p, scene: BlobScene(rects: [base])), 0)
        XCTAssertLessThan(BlobSDF.distance(at: p, scene: BlobScene(rects: [wide])), 0)
        XCTAssertGreaterThan(BlobSDF.distance(at: CGPoint(x: 500, y: 395), scene: BlobScene(rects: [wide])), 0, "squashed vertically")
    }

    func testJellyTargetStretchesAlongTheMotionAndKeepsArea() {
        let t = Jelly.target(velocity: CGVector(dx: 2000, dy: 0), deformScale: 1e-4)
        XCTAssertEqual(t.m00, 1.2, accuracy: 1e-9)
        XCTAssertEqual(t.m11, 1 / 1.2, accuracy: 1e-9)
        XCTAssertEqual(t.m01, 0, accuracy: 1e-9)
        let capped = Jelly.target(velocity: CGVector(dx: 0, dy: -1e6), deformScale: 1e-4)
        XCTAssertEqual(capped.m11, 1 + Jelly.maxStretch, accuracy: 1e-9)
        let diag = Jelly.target(velocity: CGVector(dx: 700, dy: 700), deformScale: 1e-4)
        XCTAssertEqual(diag.m00 * diag.m11 - diag.m01 * diag.m01, 1, accuracy: 1e-9)
        XCTAssertEqual(Jelly.target(velocity: CGVector(dx: 3, dy: 0), deformScale: 1e-4), .identity)
    }

    func testJellySpringsWhileMovingAndSettlesToRest() {
        var j = Jelly(deformScale: Jelly.scale(deformAmount: 0.25))
        var y = 300.0
        j.step(center: CGPoint(x: 0, y: y), dt: 1 / 120)
        var peak = 1.0
        for _ in 0..<30 {
            y += 3000.0 / 120
            j.step(center: CGPoint(x: 0, y: y), dt: 1 / 120)
            peak = max(peak, j.deform.m11)
        }
        XCTAssertTrue(j.isActive)
        XCTAssertGreaterThan(peak, 1.02, "stretched along y")
        XCTAssertLessThan(j.deform.m00, 1, "squashed across")
        for _ in 0..<600 { j.step(center: CGPoint(x: 0, y: y), dt: 1 / 120) }
        XCTAssertFalse(j.isActive)
        XCTAssertEqual(j.deform, .identity)
    }

    func testJellyStaysStableOnLongFrames() {
        var j = Jelly(deformScale: 1e-3)
        j.step(center: .zero, dt: 0.016)
        var x = 0.0
        for _ in 0..<200 {
            x += 40
            j.step(center: CGPoint(x: x, y: 0), dt: 0.09)
            XCTAssertLessThan(abs(j.deform.m00), 3)
        }
    }

    func testTokensAtGabbysScale() {
        XCTAssertEqual(CaelestiaTokens.Duration.defaultSpatial * CaelestiaTokens.gabbyScale, 400)
        XCTAssertEqual(CaelestiaTokens.Duration.fastSpatial * CaelestiaTokens.gabbyScale, 280)
        XCTAssertEqual(CaelestiaTokens.Duration.slowSpatial * CaelestiaTokens.gabbyScale, 520)
        let s = CaelestiaTokens.Curve.defaultSpatial.bezier
        let peak = stride(from: 0.0, through: 1, by: 0.01).map { s.value(at: $0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1.0, "spatial curves overshoot")
        let e = CaelestiaTokens.Curve.defaultEffects.bezier
        XCTAssertLessThanOrEqual(stride(from: 0.0, through: 1, by: 0.01).map { e.value(at: $0) }.max() ?? 2, 1.0 + 1e-9)
        XCTAssertTrue(CaelestiaTokens.Curve.defaultSpatial.overshoots)
        XCTAssertFalse(CaelestiaTokens.Curve.defaultEffects.overshoots)
    }
}
