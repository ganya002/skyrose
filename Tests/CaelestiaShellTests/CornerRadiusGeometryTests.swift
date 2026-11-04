import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaShell

/// Physical display corners in the frame: which corners of a layout are real display corners,
/// the outer/inner radii derived from the display radius, and the band path they produce.
final class CornerRadiusGeometryTests: XCTestCase {
    let converter = CoordinateConverter(primaryHeight: 956)
    let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)

    func layout(dock: Insets = .zero, menuBar: Double = 0, radius: Double = 10, thickness: Double = 10) -> DisplayLayout {
        let d = DisplayInfo(id: "d", frame: screen, dockInsets: dock, shownMenuBarHeight: menuBar)
        return DisplayLayout(display: d, converter: converter, thickness: thickness, barWidth: 48, displayCornerRadius: radius)
    }

    // MARK: physicalCorners

    func testAllFourCornersArePhysicalWithoutDockOrMenuBar() {
        XCTAssertEqual(layout().physicalCorners, .all)
    }

    func testBottomDockRemovesTheBottomCorners() {
        let l = layout(dock: Insets(bottom: 70))
        XCTAssertEqual(l.physicalCorners, [.topLeft, .topRight])
    }

    func testLeftDockRemovesTheLeftCorners() {
        let l = layout(dock: Insets(left: 70))
        XCTAssertEqual(l.physicalCorners, [.topRight, .bottomRight])
    }

    func testRightDockRemovesTheRightCorners() {
        XCTAssertEqual(layout(dock: Insets(right: 70)).physicalCorners, [.topLeft, .bottomLeft])
    }

    func testShownMenuBarRemovesTheTopCorners() {
        XCTAssertEqual(layout(menuBar: 24).physicalCorners, [.bottomLeft, .bottomRight])
    }

    func testDockAndMenuBarTogetherLeaveOnlyTheFarCorner() {
        XCTAssertEqual(layout(dock: Insets(left: 70), menuBar: 24).physicalCorners, [.bottomRight])
        XCTAssertEqual(layout(dock: Insets(left: 70, bottom: 70), menuBar: 24).physicalCorners, [])
    }

    func testAreaInitDefaultsToAllCorners() {
        let l = DisplayLayout(area: CGRect(x: 0, y: 0, width: 100, height: 100), thickness: 10, barWidth: 48)
        XCTAssertEqual(l.physicalCorners, .all)
        XCTAssertEqual(l.displayCornerRadius, 0)
        XCTAssertEqual(l.outerRadii, .zero)
    }

    func testNegativeRadiusIsClampedToZero() {
        XCTAssertEqual(layout(radius: -3).displayCornerRadius, 0)
        XCTAssertEqual(DisplayLayout(area: .zero, thickness: 1, barWidth: 1, displayCornerRadius: -1).displayCornerRadius, 0)
    }

    // MARK: Radii

    func testOuterRadiiAreZeroWhereNotPhysical() {
        XCTAssertEqual(layout().outerRadii, .uniform(10))
        let bottomDock = layout(dock: Insets(bottom: 70), radius: 12)
        XCTAssertEqual(bottomDock.outerRadii, CornerRadii(topLeft: 12, topRight: 12, bottomRight: 0, bottomLeft: 0))
        let menuBar = layout(menuBar: 24, radius: 12)
        XCTAssertEqual(menuBar.outerRadii, CornerRadii(topLeft: 0, topRight: 0, bottomRight: 12, bottomLeft: 12))
    }

    func testInnerRadiiAreOuterMinusThicknessWhereRoundedAndBaseElsewhere() {
        let l = layout(dock: Insets(bottom: 70), radius: 30, thickness: 8)
        XCTAssertEqual(l.innerRadii(base: 25), CornerRadii(topLeft: 22, topRight: 22, bottomRight: 25, bottomLeft: 25))
        let square = layout(radius: 0, thickness: 8)
        XCTAssertEqual(square.innerRadii(base: 25), .uniform(25), "radius 0: every corner keeps the theme rounding")
        XCTAssertEqual(layout(radius: 10, thickness: 10).innerRadii(base: 25), .uniform(0), "radius ≤ band: square inner corner")
        XCTAssertEqual(layout(radius: 6, thickness: 10).innerRadii(base: 25), .uniform(0))
    }

    func testTopAndBottomRadiiAreSeparate() {
        let d = DisplayInfo(id: "d", frame: screen)
        let l = DisplayLayout(display: d, converter: converter, thickness: 10, barWidth: 48, displayCornerRadius: 14, bottomCornerRadius: 0)
        XCTAssertEqual(l.outerRadii, CornerRadii(topLeft: 14, topRight: 14, bottomRight: 0, bottomLeft: 0))
        XCTAssertEqual(l.innerRadii(base: 25), CornerRadii(topLeft: 4, topRight: 4, bottomRight: 25, bottomLeft: 25))
        XCTAssertEqual(layout(radius: 9).bottomCornerRadius, 9, "bottom defaults to the top radius")
    }

    /// The band's width measured along the corner diagonal equals its width on the edges when
    /// the inner arc is concentric (inner = outer − band).
    func testBandKeepsItsWidthAroundARoundedCorner() {
        let outer = CGRect(x: 0, y: 0, width: 1000, height: 600)
        for (r, b) in [(30.0, 10.0), (18, 6)] {
            let p = FramePath.path(outer: outer, insets: .uniform(b), outerRadii: .uniform(r), innerRadii: .uniform(r - b),
                                   cutouts: [], thickness: b)
            // Along the diagonal from the corner: the outer arc is at r − r/√2 · … ; walk and measure.
            var filledSteps = 0
            let step = 0.01
            var t = 0.0
            while t < r {
                if p.contains(CGPoint(x: t, y: t), using: .evenOdd) { filledSteps += 1 }
                t += step
            }
            let diagonalWidth = Double(filledSteps) * step * 2.0.squareRoot()
            XCTAssertEqual(diagonalWidth, b, accuracy: 0.05, "r \(r) band \(b)")
        }
    }

    // MARK: FramePath

    let outer = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let insets = Insets.uniform(10)

    func filled(_ p: CGPath, _ x: Double, _ y: Double) -> Bool {
        p.contains(CGPoint(x: x, y: y), using: .evenOdd)
    }

    func band(outerRadius: Double, inner: Double = 20, cutouts: [CGRect] = []) -> CGPath {
        FramePath.path(outer: outer, insets: insets, outerRadii: .uniform(outerRadius), innerRadii: .uniform(inner),
                       cutouts: cutouts, thickness: 10)
    }

    func testRoundedOuterCornerCutsTheCornerPixelsOut() {
        let rounded = band(outerRadius: 10, inner: 20)
        let square = band(outerRadius: 0, inner: 20)
        for (x, y) in [(0.5, 0.5), (999.5, 0.5), (0.5, 599.5), (999.5, 599.5)] {
            XCTAssertFalse(filled(rounded, x, y), "corner pixel (\(x), \(y)) is outside the rounded panel")
            XCTAssertTrue(filled(square, x, y), "…but filled when the outer edge is square")
        }
    }

    func testBandAndHoleAreUnaffectedAwayFromTheCorners() {
        for r in [0.0, 10, 30] {
            let p = band(outerRadius: r)
            XCTAssertTrue(filled(p, 500, 5), "top band")
            XCTAssertTrue(filled(p, 5, 300), "left band")
            XCTAssertTrue(filled(p, 995, 300), "right band")
            XCTAssertTrue(filled(p, 500, 595), "bottom band")
            XCTAssertFalse(filled(p, 500, 300), "hole interior")
            XCTAssertFalse(filled(p, 200, 200))
        }
    }

    func testMidBandPointNearTheCornerIsFilled() {
        let p = band(outerRadius: 10, inner: 20)
        // On the diagonal, inside the arc of radius 10 but outside the inner arc of radius 20.
        XCTAssertTrue(filled(p, 5, 5), "inside the band at the rounded corner")
        XCTAssertTrue(filled(p, 10, 3))
        XCTAssertTrue(filled(p, 3, 10))
    }

    func testBoundingBoxIsStillTheOuterRect() {
        let box = band(outerRadius: 10).boundingBoxOfPath
        XCTAssertEqual(box.minX, 0, accuracy: 0.01)
        XCTAssertEqual(box.minY, 0, accuracy: 0.01)
        XCTAssertEqual(box.width, 1000, accuracy: 0.01)
        XCTAssertEqual(box.height, 600, accuracy: 0.01)
    }

    func testPerCornerOuterRadii() {
        let p = FramePath.path(outer: outer, insets: insets,
                               outerRadii: CornerRadii(topLeft: 12, topRight: 0, bottomRight: 0, bottomLeft: 0),
                               innerRadii: .uniform(20), cutouts: [], thickness: 10)
        XCTAssertFalse(filled(p, 0.5, 0.5), "rounded corner")
        XCTAssertTrue(filled(p, 999.5, 0.5), "square corner")
        XCTAssertTrue(filled(p, 999.5, 599.5))
        XCTAssertTrue(filled(p, 0.5, 599.5))
    }

    func testPerCornerInnerRadiiShapeTheHole() {
        let p = FramePath.path(outer: outer, insets: insets, outerRadii: .zero,
                               innerRadii: CornerRadii(topLeft: 40, topRight: 0, bottomRight: 0, bottomLeft: 0),
                               cutouts: [], thickness: 10)
        // The hole's top-left corner is rounded (band fills the wedge), the others are square.
        XCTAssertTrue(filled(p, 12, 12), "wedge outside the 40 pt arc belongs to the band")
        XCTAssertFalse(filled(p, 988, 12), "square inner corner: hole reaches into it")
        XCTAssertFalse(filled(p, 12, 588))
        XCTAssertFalse(filled(p, 988, 588))
    }

    func testOuterRadiiWorkTogetherWithCutouts() {
        let notch = CGRect(x: 420, y: 0, width: 160, height: 32)
        let p = band(outerRadius: 10, inner: 20, cutouts: [notch])
        XCTAssertFalse(filled(p, 0.5, 0.5), "outer corner still rounded")
        XCTAssertFalse(filled(p, 999.5, 599.5))
        XCTAssertTrue(filled(p, 500, 25), "the band dips down around the notch")
        XCTAssertTrue(filled(p, 500, 5), "top band")
        XCTAssertFalse(filled(p, 500, 60), "below the dip (notch 32 + thickness 10) is the hole again")
        XCTAssertFalse(filled(p, 200, 40))
        XCTAssertTrue(filled(p, 5, 300))
    }

    func testRadiusOverloadMatchesUniformInnerRadii() {
        let a = FramePath.path(outer: outer, insets: insets, radius: 20, cutouts: [], thickness: 10)
        let b = FramePath.path(outer: outer, insets: insets, outerRadii: .zero, innerRadii: .uniform(20), cutouts: [], thickness: 10)
        for pt in [CGPoint(x: 12, y: 12), CGPoint(x: 15, y: 15), CGPoint(x: 500, y: 5), CGPoint(x: 500, y: 300), CGPoint(x: 990, y: 590)] {
            XCTAssertEqual(a.contains(pt, using: .evenOdd), b.contains(pt, using: .evenOdd))
        }
    }
}
