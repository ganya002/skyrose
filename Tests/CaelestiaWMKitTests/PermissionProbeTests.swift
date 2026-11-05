import CaelestiaCore
import XCTest
@testable import CaelestiaWMKit

final class PermissionProbeTests: XCTestCase {
    func testRoundTrip() throws {
        let snap = PermissionSnapshot(accessibility: false, inputMonitoring: true, screenRecording: false)
        XCTAssertEqual(PermissionProbe.decode(try PermissionProbe.encode(snap)), snap)
    }

    func testNoFlagReturns() {
        // Without the flag it must return (not exit) so the WM starts normally.
        PermissionProbe.runIfRequested(["SkyRoseWM"])
        PermissionProbe.runIfRequested(["SkyRoseWM", "--request", "accessibility"])
    }
}
