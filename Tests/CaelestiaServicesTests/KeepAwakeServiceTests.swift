import Foundation
import XCTest
@testable import CaelestiaServices

@MainActor
final class KeepAwakeServiceTests: XCTestCase {
    func testTimedKeepAwakeEndsByItself() async throws {
        let ka = KeepAwakeService()
        var changes: [Bool] = []
        ka.onChange = { changes.append($0) }
        ka.set(on: true, duration: 0.3)
        XCTAssertTrue(ka.isEnabled)
        XCTAssertNotNil(ka.until)
        XCTAssertEqual(ka.duration, 0.3)
        XCTAssertTrue(ka.statusText.hasPrefix("Keeping awake · "), ka.statusText)
        XCTAssertLessThanOrEqual(ka.remaining ?? 99, 0.3)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertFalse(ka.isEnabled, "the assertion is released when the timer ends")
        XCTAssertNil(ka.until)
        XCTAssertNil(ka.duration)
        XCTAssertEqual(changes, [true, false])
    }

    func testUnlimitedAndReplacingATimer() async throws {
        let ka = KeepAwakeService()
        ka.set(on: true, duration: 0.2)
        ka.set(on: true)  // switched to "until turned off": the old timer must not fire
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(ka.isEnabled)
        XCTAssertNil(ka.until)
        XCTAssertNil(ka.duration)
        XCTAssertEqual(ka.statusText, "Keeping awake")
        ka.set(on: false)
        XCTAssertFalse(ka.isEnabled)
        XCTAssertEqual(ka.statusText, "Normal power management")
    }
}
