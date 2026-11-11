@testable import CaelestiaShell
import XCTest

final class HelperCardFlowTests: XCTestCase {
    func testHappyPath() {
        var f = HelperCardFlow()
        XCTAssertFalse(f.installDaemon, "the boot daemon is opt-in")
        f.handle(.needed(true))
        XCTAssertEqual(f.phase, .offer)
        f.handle(.enable)
        XCTAssertEqual(f.phase, .waitingForPassword)
        XCTAssertTrue(f.isBusy)
        f.handle(.rootFinished)
        XCTAssertEqual(f.phase, .loading)
        f.handle(.helperActive)
        XCTAssertEqual(f.phase, .success)
        // A late "cannot reach it" timer must not overwrite success.
        f.handle(.rootFailed("late"))
        XCTAssertEqual(f.phase, .success)
        f.handle(.dismissAfterSuccess)
        XCTAssertEqual(f.phase, .hidden)
    }

    func testCancelClosesQuietlyAndSnoozes() {
        var f = HelperCardFlow()
        f.handle(.needed(true))
        f.handle(.enable)
        f.handle(.passwordCancelled)
        XCTAssertEqual(f.phase, .hidden)
        f.handle(.needed(true))
        XCTAssertEqual(f.phase, .hidden, "a cancelled prompt does not pop the card straight back")
        f.handle(.requested)
        XCTAssertEqual(f.phase, .offer, "Settings can always ask for it")
    }

    func testFailureAndRetry() {
        var f = HelperCardFlow()
        f.handle(.needed(true))
        f.handle(.enable)
        f.handle(.rootFailed("the app signature does not match the running SkyRose"))
        XCTAssertEqual(f.phase, .failed("the app signature does not match the running SkyRose"))
        XCTAssertFalse(f.isBusy)
        f.handle(.enable)
        XCTAssertEqual(f.phase, .waitingForPassword)
    }

    func testNotNowSnoozesUntilRequested() {
        var f = HelperCardFlow()
        f.handle(.needed(true))
        f.handle(.notNow)
        XCTAssertEqual(f.phase, .hidden)
        XCTAssertTrue(f.snoozed)
        f.handle(.needed(true))
        XCTAssertEqual(f.phase, .hidden)
        f.handle(.requested)
        XCTAssertEqual(f.phase, .offer)
        XCTAssertFalse(f.snoozed)
    }

    func testTerminalFallback() {
        var f = HelperCardFlow()
        f.handle(.needed(true))
        f.handle(.showTerminal)
        XCTAssertEqual(f.phase, .terminal)
        f.handle(.backFromTerminal)
        XCTAssertEqual(f.phase, .offer)
    }

    func testHelperLoadedElsewhereHidesOrConfirms() {
        var f = HelperCardFlow()
        f.handle(.needed(true))
        f.handle(.needed(false))
        XCTAssertEqual(f.phase, .hidden, "the boot daemon loaded it before the user did anything")
        f.handle(.helperActive)
        XCTAssertEqual(f.phase, .hidden, "a hidden card stays hidden")
        // Busy states ignore needed(false): the result comes from the loader and the probe.
        f.handle(.requested)
        f.handle(.enable)
        f.handle(.needed(false))
        XCTAssertEqual(f.phase, .waitingForPassword)
    }
}
