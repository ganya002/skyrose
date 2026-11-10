import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
import XCTest

@testable import CaelestiaWMKit

@MainActor
final class CursorFollowsFocusTests: XCTestCase {
    func testKeyboardFocusWarpsToTheCentre() throws {
        let h = Harness()
        var warps: [CGPoint] = []
        h.wm.warpCursor = { warps.append($0) }
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.system.cursorLocation = CGPoint(x: 2, y: 2)
        h.start()
        warps.removeAll()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        let target = h.wm.state.focusedWindow == a.windowID ? b.windowID : a.windowID
        h.wm.state.recordFocus(target)
        h.wm.setNeedsLayout()
        h.settle()
        let frame = try XCTUnwrap(h.wm.visiblePlacements[target]?.frame)
        let point = try XCTUnwrap(warps.last)
        XCTAssertEqual(point.x, frame.midX, accuracy: 0.5)
        XCTAssertEqual(point.y, frame.midY, accuracy: 0.5)
    }

    func testAClickInsideTheWindowDoesNotWarp() {
        let h = Harness()
        var warps: [CGPoint] = []
        h.wm.warpCursor = { warps.append($0) }
        let a = h.system.existing("a")
        h.system.existing("b")
        h.start()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        let frame = h.wm.visiblePlacements[a.windowID]!.frame
        h.system.cursorLocation = CGPoint(x: frame.midX, y: frame.midY)
        warps.removeAll()
        h.system.queue(.focused(a.windowID))
        h.settle()
        XCTAssertTrue(warps.isEmpty)
    }

    func testAHeldButtonDoesNotWarp() {
        let h = Harness()
        var warps: [CGPoint] = []
        h.wm.warpCursor = { warps.append($0) }
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.system.cursorLocation = CGPoint(x: 2, y: 2)
        h.system.isLeftMouseDown = true
        h.start()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        warps.removeAll()
        let target = h.wm.state.focusedWindow == a.windowID ? b.windowID : a.windowID
        h.wm.state.recordFocus(target)
        h.wm.setNeedsLayout()
        h.settle()
        XCTAssertTrue(warps.isEmpty)
    }

    func testLastModeReturnsToTheRememberedPoint() throws {
        var config = Config()
        config.wm.cursorWarpMode = .last
        let h = Harness(config: config)
        var warps: [CGPoint] = []
        h.wm.warpCursor = { warps.append($0) }
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.system.cursorLocation = CGPoint(x: 2, y: 2)
        h.start()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        let frame = try XCTUnwrap(h.wm.visiblePlacements[b.windowID]?.frame)
        let spot = CGPoint(x: frame.minX + 12, y: frame.minY + 18)
        h.wm.pointerPressed(at: spot)
        h.system.cursorLocation = CGPoint(x: 2, y: 2)
        if h.wm.state.focusedWindow == b.windowID {
            h.wm.state.recordFocus(a.windowID)
            h.wm.setNeedsLayout()
            h.settle()
        }
        h.clock.now = h.clock.now.addingTimeInterval(1)
        warps.removeAll()
        h.wm.state.recordFocus(b.windowID)
        h.wm.setNeedsLayout()
        h.settle()
        let point = try XCTUnwrap(warps.last)
        XCTAssertEqual(point.x, spot.x, accuracy: 0.5)
        XCTAssertEqual(point.y, spot.y, accuracy: 0.5)
    }

    func testHoverFocusesAfterTheDelayAndDoesNotWarpOrRaise() throws {
        var config = Config()
        config.wm.focusFollowsMouseDelayMs = 100
        config.wm.raiseOnHover = false
        let h = Harness(config: config)
        var warps: [CGPoint] = []
        h.wm.warpCursor = { warps.append($0) }
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.system.cursorLocation = CGPoint(x: 2, y: 2)
        h.start()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        h.wm.state.recordFocus(a.windowID)
        h.wm.setNeedsLayout()
        h.settle()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        warps.removeAll()
        let frame = try XCTUnwrap(h.wm.visiblePlacements[b.windowID]?.frame)
        let spot = CGPoint(x: frame.midX, y: frame.midY)
        h.system.cursorLocation = spot
        let raisesBefore = b.raiseCount
        h.wm.pointerMoved(at: spot)
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
        h.clock.now = h.clock.now.addingTimeInterval(0.1)
        h.wm.pointerMoved(at: spot)
        h.settle()
        XCTAssertEqual(h.wm.state.focusedWindow, b.windowID)
        XCTAssertEqual(b.raiseCount, raisesBefore, "hover focus does not raise the window")
        XCTAssertTrue(warps.isEmpty, "the pointer is already inside the window, so focus must not warp it")
    }

    func testADragAndAWarpDoNotStealFocus() throws {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        h.wm.state.recordFocus(a.windowID)
        h.wm.setNeedsLayout()
        h.settle()
        let frame = try XCTUnwrap(h.wm.visiblePlacements[b.windowID]?.frame)
        let spot = CGPoint(x: frame.midX, y: frame.midY)
        h.wm.drag = nil
        h.system.isLeftMouseDown = true
        h.clock.now = h.clock.now.addingTimeInterval(1)
        h.wm.pointerMoved(at: spot)
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
        h.system.isLeftMouseDown = false
        h.wm.ignorePointerFocusUntil = h.clock.now.addingTimeInterval(5)
        h.wm.pointerMoved(at: spot)
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID, "a warp's move does not focus whatever it landed on")
    }

    /// A settled harness with two overlapping windows, `a` focused, and the pointer over both.
    private func overlapping() throws -> (Harness, FakeWindow, FakeWindow, CGPoint) {
        var config = Config()
        config.wm.focusFollowsMouseDelayMs = 100
        let h = Harness(config: config)
        h.wm.warpCursor = { _ in }
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.system.cursorLocation = CGPoint(x: 2, y: 2)
        h.start()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        h.wm.state.recordFocus(a.windowID)
        h.wm.setNeedsLayout()
        h.settle()
        h.clock.now = h.clock.now.addingTimeInterval(1)
        let frame = try XCTUnwrap(h.wm.visiblePlacements[a.windowID]?.frame)
        return (h, a, b, CGPoint(x: frame.midX + 20, y: frame.midY + 20))
    }

    private func hover(_ h: Harness, _ spot: CGPoint) {
        h.wm.pointerMoved(at: spot)
        h.clock.now = h.clock.now.addingTimeInterval(0.1)
        h.wm.pointerMoved(at: spot)
        h.settle()
    }

    func testHoverNeverFocusesTheWindowBehindTheTopOne() throws {
        let (h, a, b, spot) = try overlapping()
        // `b` has the larger id and sits behind `a`, which is what the old search got wrong.
        h.system.stackOverride = [CGWindowSnapshot(id: a.windowID, pid: a.pid, bounds: CGRect(origin: .zero, size: CGSize(width: 4000, height: 4000))),
                                  CGWindowSnapshot(id: b.windowID, pid: b.pid, bounds: CGRect(origin: .zero, size: CGSize(width: 4000, height: 4000)))]
        hover(h, spot)
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
    }

    func testTheStackIsReadAgainRightBeforeFocusing() throws {
        let (h, a, b, spot) = try overlapping()
        let cover = CGRect(origin: .zero, size: CGSize(width: 4000, height: 4000))
        let top = CGWindowSnapshot(id: b.windowID, pid: b.pid, bounds: cover)
        let other = CGWindowSnapshot(id: a.windowID, pid: a.pid, bounds: cover)
        h.system.stackOverride = [top, other]
        h.wm.pointerMoved(at: spot)
        h.clock.now = h.clock.now.addingTimeInterval(0.1)
        h.system.stackOverride = [other, top]   // `a` came to the front during the delay
        h.wm.pointerMoved(at: spot)
        h.settle()
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
    }

    func testAMenuOverTheWindowHoldsFocus() throws {
        let (h, a, b, spot) = try overlapping()
        let cover = CGRect(origin: .zero, size: CGSize(width: 4000, height: 4000))
        h.system.stackOverride = [CGWindowSnapshot(id: 77, pid: 9, layer: 101, bounds: CGRect(x: spot.x - 50, y: spot.y - 50, width: 200, height: 200)),
                                  CGWindowSnapshot(id: b.windowID, pid: b.pid, bounds: cover)]
        hover(h, spot)
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
    }

    func testAKeyboardFocusHoldsHoverBriefly() throws {
        let (h, a, b, spot) = try overlapping()
        let cover = CGRect(origin: .zero, size: CGSize(width: 4000, height: 4000))
        h.system.stackOverride = [CGWindowSnapshot(id: b.windowID, pid: b.pid, bounds: cover),
                                  CGWindowSnapshot(id: a.windowID, pid: a.pid, bounds: cover)]
        h.wm.hoverHoldUntil = h.clock.now.addingTimeInterval(0.3)
        hover(h, spot)
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
        h.clock.now = h.clock.now.addingTimeInterval(0.3)
        hover(h, spot)
        XCTAssertEqual(h.wm.state.focusedWindow, b.windowID)
    }
}
