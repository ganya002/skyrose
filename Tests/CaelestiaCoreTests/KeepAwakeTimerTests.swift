import Foundation
import XCTest
@testable import CaelestiaCore

final class KeepAwakeTimerTests: XCTestCase {
    func testParse() throws {
        XCTAssertNil(try KeepAwakeTimer.parse(""))
        XCTAssertNil(try KeepAwakeTimer.parse("forever"))
        XCTAssertNil(try KeepAwakeTimer.parse("on"))
        XCTAssertEqual(try KeepAwakeTimer.parse("30m"), 1800)
        XCTAssertEqual(try KeepAwakeTimer.parse("1h"), 3600)
        XCTAssertEqual(try KeepAwakeTimer.parse("1h30m"), 5400)
        XCTAssertEqual(try KeepAwakeTimer.parse("90"), 5400, "a bare number is minutes")
        XCTAssertEqual(try KeepAwakeTimer.parse("45s"), 45)
        XCTAssertEqual(try KeepAwakeTimer.parse(" 2H "), 7200)
        XCTAssertThrowsError(try KeepAwakeTimer.parse("soon"))
        XCTAssertThrowsError(try KeepAwakeTimer.parse("10x"))
        XCTAssertThrowsError(try KeepAwakeTimer.parse("1h30"), "trailing number without a unit")
        XCTAssertThrowsError(try KeepAwakeTimer.parse("0m"))
        XCTAssertThrowsError(try KeepAwakeTimer.parse("8d"))
        XCTAssertThrowsError(try KeepAwakeTimer.parse("200h"))
    }

    func testTextAndLabels() {
        XCTAssertEqual(KeepAwakeTimer.remainingText(20), "under a minute left")
        XCTAssertEqual(KeepAwakeTimer.remainingText(60), "1 min left")
        XCTAssertEqual(KeepAwakeTimer.remainingText(41 * 60 + 5), "42 min left")
        XCTAssertEqual(KeepAwakeTimer.remainingText(3600 + 5 * 60), "1 h 05 min left")
        XCTAssertEqual(KeepAwakeTimer.presets.map(KeepAwakeTimer.label), ["∞", "15 min", "1 h", "2 h", "5 h"])
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(KeepAwakeTimer.status(enabled: false, until: nil, now: now), "Normal power management")
        XCTAssertEqual(KeepAwakeTimer.status(enabled: true, until: nil, now: now), "Keeping awake")
        XCTAssertEqual(KeepAwakeTimer.status(enabled: true, until: now.addingTimeInterval(900), now: now), "Keeping awake · 15 min left")
    }

    func testChipHighlightNeedsAnExactLength() {
        XCTAssertTrue(KeepAwakeTimer.isChosen(nil, enabled: true, duration: nil), "∞ chip for an unlimited keep-awake")
        XCTAssertFalse(KeepAwakeTimer.isChosen(nil, enabled: false, duration: nil), "nothing lit when off")
        XCTAssertTrue(KeepAwakeTimer.isChosen(900, enabled: true, duration: 900))
        XCTAssertFalse(KeepAwakeTimer.isChosen(900, enabled: true, duration: 60), "a CLI 1m timer lights no chip")
        XCTAssertFalse(KeepAwakeTimer.isChosen(nil, enabled: true, duration: 60))
    }
}
