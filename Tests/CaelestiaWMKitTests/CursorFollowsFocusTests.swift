import CaelestiaCore
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
}
