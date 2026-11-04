import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaPlatform

/// `ScreenFacts.isBuiltIn` reaches `DisplayInfo.isBuiltIn` (the frame's auto corner radius keys on it).
final class DisplayBuiltInTests: XCTestCase {
    typealias Facts = DisplayGeometry.ScreenFacts
    let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)

    func testDefaultsToExternal() {
        let f = Facts(uuid: "a", frame: frame, visibleFrame: frame)
        XCTAssertFalse(f.isBuiltIn)
        XCTAssertFalse(DisplayInfo(id: "a", frame: frame).isBuiltIn)
        XCTAssertFalse(DisplayGeometry.displays(from: [f])[0].isBuiltIn)
    }

    func testBuiltInFlagIsCarriedPerDisplay() {
        let internalPanel = Facts(uuid: "int", frame: frame, visibleFrame: frame, isBuiltIn: true)
        let external = Facts(uuid: "ext", frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440),
                             visibleFrame: CGRect(x: 1470, y: 0, width: 2560, height: 1440))
        let infos = DisplayGeometry.displays(from: [internalPanel, external])
        XCTAssertEqual(infos.first { $0.id == "int" }?.isBuiltIn, true)
        XCTAssertEqual(infos.first { $0.id == "ext" }?.isBuiltIn, false)
    }
}
