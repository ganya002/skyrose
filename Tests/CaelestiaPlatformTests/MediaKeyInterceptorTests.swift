import CaelestiaCore
import XCTest

@testable import CaelestiaPlatform

/// The thread-safe capability box the event tap asks per media key.
final class MediaKeyInterceptorTests: XCTestCase {
    func testDefaultsInterceptNothingUntilCapabilitiesAreKnown() {
        let i = MediaKeyInterceptor()
        for c in MediaKeyCommand.allCases {
            XCTAssertFalse(i.route(c).swallow, "\(c): enabled by default but nothing controllable yet")
        }
    }

    func testRoutesFollowTheUpdatedCapabilities() {
        let i = MediaKeyInterceptor()
        i.update(volumeControllable: true)
        XCTAssertTrue(i.route(.volumeUp).swallow)
        XCTAssertEqual(i.route(.volumeUp).osd, .volume)
        XCTAssertFalse(i.route(.brightnessUp).swallow, "brightness not controllable")
        XCTAssertNil(i.route(.brightnessUp).osd)

        i.update(brightnessControllable: true)
        XCTAssertEqual(i.route(.brightnessDown), MediaKeyRoute(swallow: true, command: .brightnessDown, osd: .brightness))
        XCTAssertNotEqual(i.route(.brightnessDown).osd, .volume)

        i.update(enabled: false)
        XCTAssertFalse(i.route(.volumeUp).swallow)
        XCTAssertEqual(i.route(.volumeUp).osd, .volume, "interception off: Apple's HUD and ours")
        XCTAssertFalse(i.route(.brightnessUp).swallow)
        XCTAssertEqual(i.route(.brightnessUp).osd, .brightness)

        i.update(enabled: true, volumeControllable: false)
        XCTAssertFalse(i.route(.mute).swallow)
        XCTAssertNil(i.route(.mute).osd)
        XCTAssertTrue(i.route(.brightnessUp).swallow, "nil arguments leave the other values alone")
    }

    func testNilCommandAlwaysPassesThrough() {
        let i = MediaKeyInterceptor()
        i.update(enabled: true, volumeControllable: true, brightnessControllable: true)
        XCTAssertEqual(i.route(nil), .passThrough)
    }

    func testConcurrentUpdatesAndRoutesAreSafe() {
        let i = MediaKeyInterceptor()
        DispatchQueue.concurrentPerform(iterations: 2000) { n in
            if n % 3 == 0 { i.update(enabled: n % 2 == 0, volumeControllable: n % 5 == 0, brightnessControllable: n % 7 == 0) }
            let r = i.route(MediaKeyCommand.allCases[n % MediaKeyCommand.allCases.count])
            if r.swallow { XCTAssertNotNil(r.command) }
        }
    }
}
