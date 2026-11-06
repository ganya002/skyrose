import XCTest
@testable import CaelestiaCore

final class ClamshellTests: XCTestCase {
    func f(lid: Bool = true, closed: Bool = false, sleeps: Bool? = nil, ac: Bool, ext: Int) -> ClamshellFacts {
        ClamshellFacts(hasLid: lid, lidClosed: closed, closingCausesSleep: sleeps, onAC: ac, externalDisplays: ext)
    }

    func testModesFromTheDocumentedConditions() {
        XCTAssertEqual(Clamshell.mode(f(lid: false, ac: true, ext: 1)), .noLid)
        XCTAssertEqual(Clamshell.mode(f(ac: true, ext: 1)), .openWillStayAwake)
        XCTAssertEqual(Clamshell.mode(f(ac: false, ext: 1)), .openWillSleep, "battery sleeps even with a display")
        XCTAssertEqual(Clamshell.mode(f(ac: true, ext: 0)), .openWillSleep, "no display sleeps even on power")
        XCTAssertEqual(Clamshell.mode(f(closed: true, ac: true, ext: 1)), .closedRunning)
    }

    func testTheKernelFlagWinsWhenPublished() {
        XCTAssertEqual(Clamshell.mode(f(sleeps: true, ac: true, ext: 1)), .openWillSleep)
        XCTAssertEqual(Clamshell.mode(f(sleeps: false, ac: false, ext: 0)), .openWillStayAwake)
    }

    func testSummaries() {
        XCTAssertEqual(Clamshell.summary(f(ac: false, ext: 0)), "Closing the lid sleeps the Mac · needs a power adapter and an external display")
        XCTAssertEqual(Clamshell.summary(f(ac: true, ext: 0)), "Closing the lid sleeps the Mac · needs an external display")
        XCTAssertEqual(Clamshell.summary(f(ac: false, ext: 2)), "Closing the lid sleeps the Mac · needs a power adapter")
        XCTAssertEqual(Clamshell.summary(f(sleeps: true, ac: true, ext: 1)), "Closing the lid sleeps the Mac")
        XCTAssertEqual(Clamshell.summary(f(ac: true, ext: 1)), "Closing the lid keeps the Mac running")
        XCTAssertEqual(Clamshell.summary(f(closed: true, ac: true, ext: 1)), "Lid closed · running on the external display")
        XCTAssertEqual(Clamshell.summary(f(lid: false, ac: true, ext: 1)), "No lid")
    }

    func testKeepAwakeOnlyWhileRunningLidClosedAndOptedIn() {
        XCTAssertTrue(Clamshell.holdsKeepAwake(f(closed: true, ac: true, ext: 1), enabled: true))
        XCTAssertFalse(Clamshell.holdsKeepAwake(f(closed: true, ac: true, ext: 1), enabled: false))
        XCTAssertFalse(Clamshell.holdsKeepAwake(f(ac: true, ext: 1), enabled: true), "lid open: not held")
    }

    func testDefaultConfigIsOff() {
        XCTAssertFalse(Config().clamshell.keepAwake)
    }
}
