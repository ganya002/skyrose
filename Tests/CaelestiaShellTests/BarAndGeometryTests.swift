import CaelestiaCore
import CoreGraphics
import XCTest

@testable import CaelestiaShell

final class BarVisibilityTests: XCTestCase {
    func testPersistentAlwaysShownAndPointerNeverChangesIt() {
        var v = BarVisibility(persistent: true)
        XCTAssertTrue(v.isShown)
        XCTAssertFalse(v.pointer(inHotZone: false, overBar: false, at: 0))
        XCTAssertFalse(v.pointer(inHotZone: false, overBar: false, at: 100))
        XCTAssertTrue(v.isShown)
        XCTAssertFalse(v.hidePending)
        XCTAssertFalse(v.tick(at: 1000))
        v.set(shown: false)
        XCTAssertTrue(v.isShown, "set(shown:) is ignored when persistent")
    }

    func testHotZoneShows() {
        var v = BarVisibility(persistent: false)
        XCTAssertFalse(v.isShown)
        XCTAssertTrue(v.pointer(inHotZone: true, overBar: false, at: 0))
        XCTAssertTrue(v.isShown)
        XCTAssertFalse(v.pointer(inHotZone: true, overBar: true, at: 0.1), "no change")
    }

    func testHotZoneIgnoredWithoutShowOnHover() {
        var v = BarVisibility(persistent: false, showOnHover: false)
        XCTAssertFalse(v.pointer(inHotZone: true, overBar: false, at: 0))
        XCTAssertFalse(v.isShown)
        v.set(shown: true)
        XCTAssertTrue(v.isShown)
    }

    func testLeavingHidesOnlyAfterDelay() {
        var v = BarVisibility(persistent: false)
        v.pointer(inHotZone: true, overBar: true, at: 0)
        XCTAssertFalse(v.pointer(inHotZone: false, overBar: false, at: 1))
        XCTAssertTrue(v.hidePending)
        XCTAssertFalse(v.pointer(inHotZone: false, overBar: false, at: 1 + BarVisibility.hideDelay - 0.01))
        XCTAssertTrue(v.isShown)
        XCTAssertTrue(v.pointer(inHotZone: false, overBar: false, at: 1 + BarVisibility.hideDelay))
        XCTAssertFalse(v.isShown)
        XCTAssertFalse(v.hidePending)
    }

    func testReturningCancelsPendingHide() {
        var v = BarVisibility(persistent: false)
        v.pointer(inHotZone: true, overBar: true, at: 0)
        v.pointer(inHotZone: false, overBar: false, at: 1)
        v.pointer(inHotZone: false, overBar: true, at: 1.1)
        XCTAssertFalse(v.hidePending)
        XCTAssertFalse(v.pointer(inHotZone: false, overBar: false, at: 1.2), "a new leave starts a fresh delay")
        XCTAssertFalse(v.tick(at: 1.2 + BarVisibility.hideDelay - 0.01))
        XCTAssertTrue(v.isShown)
    }

    func testPinnedPreventsHide() {
        var v = BarVisibility(persistent: false)
        v.pointer(inHotZone: true, overBar: true, at: 0)
        v.pinned = true
        v.pointer(inHotZone: false, overBar: false, at: 1)
        v.pointer(inHotZone: false, overBar: false, at: 5)
        XCTAssertTrue(v.isShown)
        XCTAssertFalse(v.tick(at: 10))
        v.pinned = false
        XCTAssertFalse(v.pointer(inHotZone: false, overBar: false, at: 11))
        XCTAssertTrue(v.pointer(inHotZone: false, overBar: false, at: 11 + BarVisibility.hideDelay))
    }

    func testTickHidesAfterDelay() {
        var v = BarVisibility(persistent: false)
        v.pointer(inHotZone: true, overBar: true, at: 0)
        XCTAssertFalse(v.tick(at: 5), "nothing pending")
        v.pointer(inHotZone: false, overBar: false, at: 1)
        XCTAssertFalse(v.tick(at: 1.1))
        XCTAssertTrue(v.tick(at: 1 + BarVisibility.hideDelay))
        XCTAssertFalse(v.isShown)
        XCTAssertFalse(v.tick(at: 100))
    }

    func testSetShown() {
        var v = BarVisibility(persistent: false)
        v.set(shown: true)
        XCTAssertTrue(v.isShown)
        v.set(shown: false)
        XCTAssertFalse(v.isShown)
    }

    func testSetPersistent() {
        var v = BarVisibility(persistent: false)
        v.pointer(inHotZone: false, overBar: false, at: 0)
        v.setPersistent(true)
        XCTAssertTrue(v.isShown)
        v.setPersistent(false)
        XCTAssertTrue(v.isShown, "stays up until the pointer leaves")
        XCTAssertFalse(v.hidePending)
        v.pointer(inHotZone: false, overBar: false, at: 1)
        XCTAssertTrue(v.tick(at: 2))
        XCTAssertFalse(v.isShown)
    }
}

final class ShellGeometryTests: XCTestCase {
    private let area = CGRect(x: 100, y: 50, width: 1000, height: 700)
    private func layout() -> DisplayLayout { DisplayLayout(area: area, thickness: 10, barWidth: 48) }

    func testFrameInsets() {
        let l = layout()
        XCTAssertEqual(l.frameInsets(barReveal: 0), Insets(top: 10, left: 10, bottom: 10, right: 10))
        XCTAssertEqual(l.frameInsets(barReveal: 0.5), Insets(top: 10, left: 29, bottom: 10, right: 10))
        XCTAssertEqual(l.frameInsets(barReveal: 1), Insets(top: 10, left: 48, bottom: 10, right: 10))
        XCTAssertEqual(l.frameInsets(barReveal: -3).left, 10, "clamped")
        XCTAssertEqual(l.frameInsets(barReveal: 7).left, 48, "clamped")
    }

    func testBarNarrowerThanThicknessNeverShrinksTheFrame() {
        let l = DisplayLayout(area: area, thickness: 10, barWidth: 4)
        XCTAssertEqual(l.frameInsets(barReveal: 1).left, 10)
        XCTAssertEqual(l.barFrame.width, 10)
    }

    func testInnerRect() {
        let l = layout()
        XCTAssertEqual(l.inner(barReveal: 0), CGRect(x: 110, y: 60, width: 980, height: 680))
        XCTAssertEqual(l.inner(barReveal: 1), CGRect(x: 148, y: 60, width: 942, height: 680))
    }

    func testBarFrameAndHotZone() {
        let l = layout()
        XCTAssertEqual(l.barFrame, CGRect(x: 100, y: 50, width: 48, height: 700))
        XCTAssertTrue(l.barHotZone(contains: CGPoint(x: 100, y: 300)))
        XCTAssertTrue(l.barHotZone(contains: CGPoint(x: 110, y: 300)))
        XCTAssertFalse(l.barHotZone(contains: CGPoint(x: 112, y: 300)))
        XCTAssertFalse(l.barHotZone(contains: CGPoint(x: 105, y: 49)))
        XCTAssertFalse(l.barHotZone(contains: CGPoint(x: 105, y: 751)))
        XCTAssertFalse(l.barHotZone(contains: CGPoint(x: 98, y: 300)))
    }

    func testDrawerFrameCenteredAndTouchesInnerEdge() {
        let l = layout()
        let inner = l.inner(barReveal: 1)
        let size = CGSize(width: 300, height: 200)
        let bottom = l.drawerFrame(size: size, edge: .bottom, barReveal: 1)
        XCTAssertEqual(bottom.minY, inner.minY)
        XCTAssertEqual(bottom.midX, inner.midX, accuracy: 0.5)
        let top = l.drawerFrame(size: size, edge: .top, barReveal: 1)
        XCTAssertEqual(top.maxY, inner.maxY)
        XCTAssertEqual(top.midX, inner.midX, accuracy: 0.5)
        let right = l.drawerFrame(size: size, edge: .right, barReveal: 1)
        XCTAssertEqual(right.maxX, inner.maxX)
        XCTAssertEqual(right.midY, inner.midY, accuracy: 0.5)
        let left = l.drawerFrame(size: size, edge: .left, barReveal: 1)
        XCTAssertEqual(left.minX, inner.minX)
        XCTAssertEqual(left.midY, inner.midY, accuracy: 0.5)
        for f in [bottom, top, right, left] { XCTAssertEqual(f.size, size) }
        XCTAssertEqual(l.drawerFrame(size: size, edge: .left, barReveal: 0).minX, 110, "follows the bar reveal")
    }

    func testDisplayInitSubtractsDockAndConvertsToBottomLeftWithAutoHidingMenuBar() {
        // menuBarHeight 30 but auto-hidden (shownMenuBarHeight 0): the frame runs to the top edge,
        // the band is even (no menu-bar top extra any more).
        let display = DisplayInfo(id: "d", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), menuBarHeight: 30,
                                  dockInsets: Insets(top: 0, left: 0, bottom: 50, right: 0), isPrimary: true)
        let l = DisplayLayout(display: display, converter: CoordinateConverter(primaryHeight: 800), thickness: 10, barWidth: 48)
        XCTAssertEqual(l.area.minX, 0)
        XCTAssertEqual(l.area.width, 1000)
        XCTAssertEqual(l.area.minY, 50, "bottom-left space: the Dock sits at the bottom")
        XCTAssertEqual(l.area.maxY, 800)
        XCTAssertEqual(l.topExtra, 0)
        XCTAssertEqual(l.thickness, 10)
        XCTAssertEqual(l.barWidth, 48)
    }

    func testDisplayInitStartsBelowAShownMenuBar() {
        let display = DisplayInfo(id: "d", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), menuBarHeight: 30,
                                  isPrimary: true, shownMenuBarHeight: 30)
        let l = DisplayLayout(display: display, converter: CoordinateConverter(primaryHeight: 800), thickness: 10, barWidth: 48)
        XCTAssertEqual(l.area.maxY, 770)
        XCTAssertEqual(l.topExtra, 0)
        XCTAssertTrue(l.cutouts.isEmpty)
    }

    func testDisplayInitWithoutSystemChromeIsTheWholeDisplay() {
        let display = DisplayInfo(id: "d", frame: CGRect(x: 1000, y: 0, width: 500, height: 400))
        let l = DisplayLayout(display: display, converter: CoordinateConverter(primaryHeight: 800), thickness: 10, barWidth: 48)
        XCTAssertEqual(l.area, CGRect(x: 1000, y: 400, width: 500, height: 400))
    }
}

final class DrawerPathTests: XCTestCase {
    private let rect = CGRect(x: 10, y: 20, width: 300, height: 120)
    private let f = 25.0
    private let r = 25.0

    /// Canonical (u along the edge, v towards the edge) → rect point, as DrawerPath documents.
    private func p(_ u: Double, _ v: Double, _ edge: ShellEdge, _ rect: CGRect) -> CGPoint {
        switch edge {
        case .bottom: return CGPoint(x: rect.minX + u, y: rect.minY + v)
        case .top: return CGPoint(x: rect.minX + u, y: rect.maxY - v)
        case .right: return CGPoint(x: rect.minX + v, y: rect.minY + u)
        case .left: return CGPoint(x: rect.maxX - v, y: rect.minY + u)
        }
    }

    func testBoundingBoxEqualsRectForEachEdge() {
        for edge in ShellEdge.allCases {
            let path = DrawerPath.path(in: rect, edge: edge, radius: r, fillet: f)
            let box = path.boundingBoxOfPath
            XCTAssertEqual(box.minX, rect.minX, accuracy: 0.01, "\(edge)")
            XCTAssertEqual(box.minY, rect.minY, accuracy: 0.01, "\(edge)")
            XCTAssertEqual(box.width, rect.width, accuracy: 0.01, "\(edge)")
            XCTAssertEqual(box.height, rect.height, accuracy: 0.01, "\(edge)")
        }
    }

    func testFillShapeAcrossEdges() {
        for edge in ShellEdge.allCases {
            let rc = (edge == .top || edge == .bottom) ? rect : CGRect(x: 10, y: 20, width: 120, height: 300)
            let along = (edge == .top || edge == .bottom) ? rc.width : rc.height
            let depth = (edge == .top || edge == .bottom) ? rc.height : rc.width
            let path = DrawerPath.path(in: rc, edge: edge, radius: r, fillet: f)
            XCTAssertTrue(path.contains(p(along / 2, depth / 2, edge, rc)), "body center \(edge)")
            // A point inside each fillet base (hugging the frame edge, next to the body).
            XCTAssertTrue(path.contains(p(f - 1, depth - 1, edge, rc)), "left fillet base \(edge)")
            XCTAssertTrue(path.contains(p(along - f + 1, depth - 1, edge, rc)), "right fillet base \(edge)")
            // Just outside the concave curve: inside the flare circle, centred (0, depth - f) / (along, depth - f).
            XCTAssertFalse(path.contains(p(3, depth - f, edge, rc)), "outside left fillet \(edge)")
            XCTAssertFalse(path.contains(p(along - 3, depth - f, edge, rc)), "outside right fillet \(edge)")
            // Far corner of the rect at the free side is rounded away and empty.
            XCTAssertFalse(path.contains(p(0.5, 0.5, edge, rc)), "free-side corner \(edge)")
            XCTAssertFalse(path.contains(p(-5, depth / 2, edge, rc)), "outside the rect \(edge)")
        }
    }

    func testZeroFilletAndRadiusIsPlainRect() {
        let path = DrawerPath.path(in: rect, edge: .bottom, radius: 0, fillet: 0)
        XCTAssertTrue(path.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 1)))
        XCTAssertTrue(path.contains(CGPoint(x: rect.maxX - 1, y: rect.maxY - 1)))
        XCTAssertEqual(path.boundingBoxOfPath.width, rect.width, accuracy: 0.01)
    }

    func testOversizedRadiiAreClamped() {
        let path = DrawerPath.path(in: CGRect(x: 0, y: 0, width: 40, height: 20), edge: .bottom, radius: 500, fillet: 500)
        let box = path.boundingBoxOfPath
        XCTAssertFalse(box.isNull)
        XCTAssertLessThanOrEqual(box.width, 40.01)
        XCTAssertLessThanOrEqual(box.height, 20.01)
    }
}

final class FramePathTests: XCTestCase {
    private let outer = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let insets = Insets(top: 10, left: 48, bottom: 10, right: 10)

    func testInnerRect() {
        XCTAssertEqual(FramePath.inner(of: outer, insets: insets), CGRect(x: 48, y: 10, width: 342, height: 280))
        XCTAssertEqual(FramePath.inner(of: outer, insets: .uniform(500)).size, .zero)
    }

    func testEvenOddBandVersusInnerHole() {
        let path = FramePath.path(outer: outer, insets: insets, radius: 25)
        XCTAssertTrue(path.contains(CGPoint(x: 5, y: 150), using: .evenOdd), "left band")
        XCTAssertTrue(path.contains(CGPoint(x: 30, y: 150), using: .evenOdd), "bar-wide band")
        XCTAssertTrue(path.contains(CGPoint(x: 200, y: 5), using: .evenOdd), "top band")
        XCTAssertTrue(path.contains(CGPoint(x: 395, y: 150), using: .evenOdd), "right band")
        XCTAssertFalse(path.contains(CGPoint(x: 200, y: 150), using: .evenOdd), "inner center")
        XCTAssertFalse(path.contains(CGPoint(x: 100, y: 100), using: .evenOdd))
        // The rounded inner corner leaves a fillet of band-colored area in the corner.
        XCTAssertTrue(path.contains(CGPoint(x: 49, y: 11), using: .evenOdd), "inside the inner rect's rounded corner")
        XCTAssertFalse(path.contains(CGPoint(x: 401, y: 301), using: .evenOdd), "outside the outer rect")
    }
}
