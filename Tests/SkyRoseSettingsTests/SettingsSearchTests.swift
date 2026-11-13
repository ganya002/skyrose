import XCTest
@testable import SkyRoseSettingsKit

final class SettingsSearchTests: XCTestCase {
    func testSearchMatchesTitlesAndKeywords() {
        let hits = { (q: String) in SettingsPage.allCases.filter { $0.matches(q) } }
        XCTAssertEqual(hits("kitty"), [.terminal])
        XCTAssertEqual(hits("SCREEN recording"), [.permissions])
        XCTAssertTrue(hits("wallpaper").contains(.appearance))
        XCTAssertEqual(hits("about"), [.about])
        XCTAssertTrue(hits("zzz").isEmpty)
    }
}
