import CaelestiaCore
import CoreGraphics
import XCTest

@testable import CaelestiaShell

/// The shell side of the liquid motion language: panel slack for the swing, the bar's swell and
/// content offset, and Reduce Motion turning all of it off.
@MainActor
final class LiquidShellTests: XCTestCase {
    let layout = DisplayLayout(area: CGRect(x: 0, y: 0, width: 1470, height: 956), thickness: 10, barWidth: 60, topExtra: 33)

    private func theme(reduceMotion: Bool = false) -> ShellTheme {
        ShellTheme(scheme: ShellTheme.fallbackScheme, config: Config(), reduceMotion: reduceMotion)
    }

    func testRoomGrowsAwayFromTheEdgeOnly() {
        let f = CGRect(x: 100, y: 200, width: 300, height: 400)
        XCTAssertEqual(DisplayLayout.withRoom(f, edge: .right, room: 20), CGRect(x: 80, y: 200, width: 320, height: 400))
        XCTAssertEqual(DisplayLayout.withRoom(f, edge: .left, room: 20), CGRect(x: 100, y: 200, width: 320, height: 400))
        XCTAssertEqual(DisplayLayout.withRoom(f, edge: .bottom, room: 20), CGRect(x: 100, y: 200, width: 300, height: 420))
        XCTAssertEqual(DisplayLayout.withRoom(f, edge: .top, room: 20), CGRect(x: 100, y: 180, width: 300, height: 420))
        XCTAssertEqual(DisplayLayout.withRoom(f, edge: .top, room: 0), f)
    }

    func testRoomedDrawerStaysOnItsEdge() {
        let size = CGSize(width: 300, height: 500)
        for edge in [ShellEdge.top, .bottom, .left, .right] {
            let plain = layout.drawerFrame(size: size, edge: edge, barReveal: 1)
            let roomy = DisplayLayout.withRoom(plain, edge: edge, room: 24)
            XCTAssertTrue(roomy.contains(plain), "\(edge)")
            let inner = layout.inner(barReveal: 1)
            switch edge {
            case .top: XCTAssertEqual(roomy.maxY, inner.maxY)
            case .bottom: XCTAssertEqual(roomy.minY, inner.minY)
            case .left: XCTAssertEqual(roomy.minX, inner.minX)
            case .right: XCTAssertEqual(roomy.maxX, inner.maxX)
            }
        }
    }

    func testOvershootRoomCoversTheSwing() {
        let t = theme()
        for depth in [60.0, 120, 300, 700] {
            let swing = depth * LiquidMotion.drawerOvershoot(depth: depth)
            XCTAssertGreaterThanOrEqual(t.overshootRoom(depth: depth), swing, "\(depth)")
            XCTAssertLessThanOrEqual(t.overshootRoom(depth: depth), 32, "\(depth)")
        }
        XCTAssertEqual(theme(reduceMotion: true).overshootRoom(depth: 300), 0)
    }

    func testFrameSwellsOnlyWhenAsked() {
        XCTAssertEqual(layout.frameInsets(barReveal: 1.1).left, 60)
        XCTAssertEqual(layout.frameInsets(barReveal: 1.1, swell: true).left, 10 + 50 * 1.1, accuracy: 1e-9)
        XCTAssertEqual(layout.frameInsets(barReveal: 3, swell: true).left, 10 + 50 * LiquidMotion.barSwellCap, accuracy: 1e-9)
        XCTAssertEqual(layout.frameInsets(barReveal: 0.5, swell: true).left, layout.frameInsets(barReveal: 0.5).left)
    }

    func testBarContentFollowsTheSwell() {
        XCTAssertEqual(BarMotion.contentOffset(reveal: 0, width: 60), -60)
        XCTAssertEqual(BarMotion.contentOffset(reveal: 0.5, width: 60), -30)
        XCTAssertEqual(BarMotion.contentOffset(reveal: 1, width: 60), 0)
        XCTAssertEqual(BarMotion.contentOffset(reveal: 1.08, width: 60), 2.4, accuracy: 1e-9)
        XCTAssertEqual(BarMotion.contentOffset(reveal: 5, width: 60), (LiquidMotion.barSwellCap - 1) * 30, accuracy: 1e-9)
    }

    func testBarSpringIsShortAndOvershootsALittle() throws {
        let s = try XCTUnwrap(theme().barRevealSpring)
        let settle = s.settlingTime(epsilon: AnimationSpec.springSettlingEpsilon)
        XCTAssertEqual(settle, theme().seconds(ShellTheme.drawerOpenMs), accuracy: 0.005)
        XCTAssertLessThanOrEqual(settle, 0.35)
        XCTAssertGreaterThan(s.overshoot, 0.04)
        XCTAssertLessThan(1 + s.overshoot, LiquidMotion.barSwellCap)
        XCTAssertNil(theme(reduceMotion: true).barRevealSpring)
    }

    func testDrawerSpringsStayInsideTheTimeBudget() {
        let settle = theme().seconds(ShellTheme.drawerOpenMs)
        XCTAssertLessThanOrEqual(settle, 0.35)
        XCTAssertLessThanOrEqual(LiquidMotion.neckSpring(settle: settle).settlingTime(epsilon: AnimationSpec.springSettlingEpsilon), 0.35)
        for depth in [60.0, 300, 700] {
            XCTAssertEqual(LiquidMotion.drawerSpring(depth: depth, settle: settle).settlingTime(epsilon: AnimationSpec.springSettlingEpsilon),
                           settle, accuracy: 0.005)
        }
        XCTAssertLessThanOrEqual(theme().panelFadeInSeconds, 0.06)
        XCTAssertEqual(theme(reduceMotion: true).panelFadeInSeconds, theme(reduceMotion: true).drawerOpenSeconds * 0.6, accuracy: 1e-9)
    }
}
