import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaPlatform
import XCTest
@testable import CaelestiaWMKit

/// Regressions from the first live test on a MacBook Air (2026-11-03).
@MainActor
final class LiveTestRegressionTests: XCTestCase {
    /// Bug 1: discovery must manage every standard window of every app that exists at launch
    /// (and a minimized one once it is restored), not just some of them.
    func testDiscoveryManagesEveryWindowOfEveryApp() {
        let h = Harness()
        let apps = ["org.mozilla.firefox", "com.apple.Terminal", "com.t3tools.t3code", "com.apple.finder", "com.anysphere.sand", "net.kovidgoyal.kitty"]
        let windows = apps.enumerated().map { i, bundle in
            h.system.existing(bundle, bundle: bundle, pid: pid_t(600 + i), frame: CGRect(x: 50 * i, y: 60, width: 500, height: 400))
        }
        let minimized = h.system.existing("minimized", bundle: "com.t3tools.t3code", pid: 602)
        minimized.isMinimized = true
        h.start()
        XCTAssertEqual(Set(h.wm.managedWindowIDs), Set(windows.map(\.windowID)))
        for w in windows { XCTAssertTrue(h.isOnScreen(w), w.bundleID) }
        minimized.isMinimized = false
        h.system.queue(.deminiaturized(minimized.windowID))
        h.settle()
        XCTAssertTrue(h.wm.isManaged(minimized.windowID))
    }

    /// Bug 2: `query windows` reported the frame the WM asked for, so a window moved away by
    /// something else (CatWM, in the live test) still showed as tiled. It must report reality.
    func testQueryWindowsReportsTheRealFrameNotTheTarget() throws {
        let h = Harness()
        let a = h.system.existing("a")
        h.system.existing("b")
        h.start()
        let elsewhere = CGRect(x: 400, y: 300, width: 300, height: 200)
        for _ in 0...WindowManager.maxSnapBackRetries {  // another WM keeps moving it; we give up
            a.appMoves(to: elsewhere)
            h.settle()
        }
        // After giving up it is auto-floated centred in the usable area: that is the real frame now.
        XCTAssertTrue(h.wm.isFloating(a.windowID))
        XCTAssertNotEqual(a.frame, elsewhere)
        XCTAssertTrue(h.wm.usableArea(of: TestDisplays.air).contains(a.frame))
        let entries = try XCTUnwrap(h.wm.respond(to: IPCRequest(.queryWindows)).response.result).decode([WindowQueryEntry].self)
        let entry = try XCTUnwrap(entries.first { $0.title == "a" })
        XCTAssertEqual(entry.at, [Int(a.frame.minX), Int(a.frame.minY)])
        XCTAssertEqual(entry.size, [Int(a.frame.width), Int(a.frame.height)])
        XCTAssertTrue(entry.floating)
    }

    /// Bugs 2/3 root cause: a second window manager (CatWM) was running. It is detected by
    /// process name and the daemon refuses to start; our own processes never match.
    func testCompetingWindowManagersAreDetected() {
        XCTAssertEqual(LaunchChecks.competingWindowManagers(processNames: ["kitty", "CatWM", "Finder"]), ["CatWM"])
        XCTAssertEqual(LaunchChecks.competingWindowManagers(processNames: ["yabai", "AeroSpace", "catwm"]), ["AeroSpace", "CatWM", "yabai"])
        XCTAssertEqual(LaunchChecks.competingWindowManagers(processNames: ["SkyRoseWM", "skyrose", "SkyRoseSettings", "TestWindows", "Dock", "WindowManager"]), [])
        // The pre-rename build would fight SkyRose over the same windows.
        XCTAssertEqual(LaunchChecks.competingWindowManagers(processNames: ["CaelestiaWM", "caelestia"]), ["CaelestiaWM (the old Caelestia for Mac build)"])
        XCTAssertTrue(LaunchChecks.competingWindowManagerMessage(["CatWM"]).contains("Quit it first"))
        XCTAssertFalse(LaunchChecks.runningProcessNames().isEmpty, "the process table is readable")
    }

    /// Bug 4: launched with `open`, a missing Accessibility grant must be explained on screen
    /// (the daemon now shows an alert and waits instead of exiting silently).
    func testAccessibilityMessageExplainsWhatToDo() {
        XCTAssertTrue(LaunchChecks.accessibilityMessage.contains("Privacy & Security → Accessibility"))
        XCTAssertTrue(LaunchChecks.accessibilityMessage.contains("Device Control and Data Access"), "the pane's newer name")
        XCTAssertTrue(LaunchChecks.accessibilityMessage.contains("starts by itself"))
    }

    /// Found during the live re-test: Finder's minimum width (475) was bigger than its 350 pt
    /// slot at the left edge; centring it on the slot put it at x = −44, half off-screen.
    func testMinSizeTileNeverLeavesTheUsableArea() {
        let h = Harness()
        let finder = h.system.existing("Finder")
        finder.minSize = CGSize(width: 475, height: 0)
        h.system.existing("Grok Bot")
        h.start()
        h.wm.state.recordFocus(finder.windowID)
        h.system.open("kitty")  // splits Finder's column: Finder on top
        h.settle()
        h.wm.state.recordFocus(finder.windowID)
        h.system.open("ParkProbe")  // splits Finder's cell side by side: Finder gets ~350 pt
        let passes = h.settle()
        let area = h.wm.usableArea(of: TestDisplays.air)
        XCTAssertGreaterThanOrEqual(finder.frame.width, 475, "the split gave Finder its minimum width")
        XCTAssertLessThanOrEqual(finder.frame.width, 475 + 40)
        XCTAssertGreaterThanOrEqual(finder.frame.minX, area.minX, "Finder pushed off the left edge")
        XCTAssertLessThanOrEqual(finder.frame.maxX, area.maxX)
        XCTAssertGreaterThanOrEqual(finder.frame.minY, area.minY)
        XCTAssertLessThanOrEqual(finder.frame.maxY, area.maxY)
        XCTAssertTrue(h.isOnScreen(finder))
        for other in h.system.windows.values where other.windowID != finder.windowID {
            XCTAssertFalse(finder.frame.intersects(other.frame), "\(other.title) overlaps Finder")
        }
        // Up to 4 passes: the two-read-back confirmation of the minimum costs one extra (was 3).
        XCTAssertLessThanOrEqual(passes, 4, "still converges")
        let writes = finder.setFrameCount
        h.wm.setNeedsLayout()
        h.settle()
        XCTAssertEqual(finder.setFrameCount, writes, "and stays put")
    }
}
