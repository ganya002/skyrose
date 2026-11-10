@testable import CaelestiaShell
import XCTest

final class BongoSpriteTests: XCTestCase {
    func testEveryPoseLoadsAtFourTimesTheGif() {
        for pose in 0...1 {
            for slapping in [false, true] {
                let image = BongoSprite.image(pose: pose, slapping: slapping)
                XCTAssertNotNil(image, "pose \(pose) slapping \(slapping)")
                XCTAssertEqual(image?.representations.first?.pixelsWide, 800)
            }
        }
    }

    func testRestingIsADifferentFrameFromTheSlap() {
        XCTAssertFalse(BongoSprite.image(pose: 0, slapping: false) === BongoSprite.image(pose: 0, slapping: true))
    }
}
