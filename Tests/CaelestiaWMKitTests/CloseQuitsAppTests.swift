import CaelestiaCore
import CoreGraphics
import XCTest
@testable import CaelestiaWMKit

/// Settings › Windows › "Red button quits the app" (`wm.closeQuitsApp`, off by default).
@MainActor
final class CloseQuitsAppTests: XCTestCase {
    private func rig(on: Bool = true, exceptions: [String]? = nil) -> (Harness, FakeAppTerminator) {
        var c = Config()
        c.wm.closeQuitsApp = on
        if let exceptions { c.wm.closeQuitsAppExceptions = exceptions }
        let h = Harness(config: c)
        let t = FakeAppTerminator()
        t.regular = [500, 600, 700]
        h.wm.appTerminator = t
        return (h, t)
    }

    /// Presses the red button of `w` (as the event tap reports it) and lets the app close it.
    private func redClose(_ h: Harness, _ w: FakeWindow) {
        h.settle()
        let button = w.closeButtonFrame()!
        let p = CGPoint(x: button.midX, y: button.midY)
        h.system.underCursor = w.windowID
        h.wm.pointerPressed(at: p)
        h.system.destroy(w.windowID)
        h.settle()
    }

    func testRedButtonOnTheLastWindowQuitsTheApp() {
        let (h, t) = rig()
        let w = h.system.existing("only", pid: 500)
        h.start()
        redClose(h, w)
        XCTAssertEqual(t.terminated, [500])
        XCTAssertEqual(h.wm.closeQuitApps, ["com.example.app"])
    }

    func testOffByDefault() {
        XCTAssertFalse(Config().wm.closeQuitsApp)
        XCTAssertEqual(Config().wm.closeQuitsAppExceptions, ["com.apple.finder"])
        let (h, t) = rig(on: false)
        let w = h.system.existing("only", pid: 500)
        h.start()
        redClose(h, w)
        XCTAssertTrue(t.terminated.isEmpty)
    }

    func testOtherWindowsOfTheAppKeepItRunning() {
        let (h, t) = rig()
        let a = h.system.existing("a", pid: 500)
        _ = h.system.existing("b", pid: 500, frame: CGRect(x: 800, y: 100, width: 500, height: 400))
        h.start()
        redClose(h, a)
        XCTAssertTrue(t.terminated.isEmpty, "only that window closes")
    }

    func testAWindowStillInTheAppsOwnListKeepsItRunning() {
        let (h, t) = rig()
        let w = h.system.existing("only", pid: 500)
        h.system.appWindowCounts[500] = 1  // e.g. a window SkyRose does not manage
        h.start()
        redClose(h, w)
        XCTAssertTrue(t.terminated.isEmpty)
    }

    func testOtherCloseWaysNeverQuit() {
        let (h, t) = rig()
        let w = h.system.existing("only", pid: 500)
        h.start()
        h.settle()
        // A click elsewhere on the title bar (yellow/green, or just the bar), then ⌘W / the app.
        h.system.underCursor = w.windowID
        h.wm.pointerPressed(at: CGPoint(x: w.frame.minX + 48, y: w.frame.minY + 12))
        h.system.destroy(w.windowID)
        h.settle()
        XCTAssertTrue(t.terminated.isEmpty)
    }

    func testExceptionsFinderAndSkyRoseNeverQuit() {
        let (h, t) = rig()
        let finder = h.system.existing("Finder", bundle: "com.apple.finder", pid: 600)
        let settings = h.system.existing("SkyRose Settings", bundle: "com.skyrose.mac.settings", pid: 700,
                                         frame: CGRect(x: 800, y: 100, width: 500, height: 400))
        h.start()
        redClose(h, finder)
        redClose(h, settings)
        XCTAssertTrue(t.terminated.isEmpty)
        XCTAssertTrue(CaelestiaWMKit.WindowManager.neverQuits("COM.APPLE.FINDER", exceptions: ["com.apple.finder"]))
        XCTAssertTrue(CaelestiaWMKit.WindowManager.neverQuits("com.skyrose.mac", exceptions: []))
        XCTAssertFalse(CaelestiaWMKit.WindowManager.neverQuits("com.skyrose.mac.testwindows", exceptions: []), "stands in for any app")
    }

    func testMenuBarAndBackgroundAppsNeverQuit() {
        let (h, t) = rig()
        t.regular = []  // an accessory app (close-to-tray utilities live in the menu bar)
        let w = h.system.existing("tray", pid: 500)
        h.start()
        redClose(h, w)
        XCTAssertTrue(t.terminated.isEmpty)
    }

    func testAPressLongAgoDoesNotCount() {
        let (h, t) = rig()
        let w = h.system.existing("only", pid: 500)
        h.start()
        h.settle()
        h.system.underCursor = w.windowID
        let button = w.closeButtonFrame()!
        h.wm.pointerPressed(at: CGPoint(x: button.midX, y: button.midY))
        h.wm.closeButtonPresses[w.windowID] = h.wm.now().addingTimeInterval(-120)
        h.system.destroy(w.windowID)
        h.settle()
        XCTAssertTrue(t.terminated.isEmpty)
    }
}
