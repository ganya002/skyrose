@testable import CaelestiaPlatform
import XCTest

final class SkyRoseAppTests: XCTestCase {
    func testOtherAccountsCopiesAreSkipped() {
        XCTAssertTrue(SkyRoseApp.inOtherHome("/Users/testuser/Applications/SkyRose.app", home: "/Users/gabbo"))
        XCTAssertTrue(SkyRoseApp.inOtherHome("/Users/gabbo2/SkyRose.app", home: "/Users/gabbo"))
        XCTAssertFalse(SkyRoseApp.inOtherHome("/Users/gabbo/Projects/caelestia-mac/dist/SkyRose.app", home: "/Users/gabbo"))
        XCTAssertFalse(SkyRoseApp.inOtherHome("/Applications/SkyRose.app", home: "/Users/gabbo"))
    }
}
