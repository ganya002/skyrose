import XCTest
@testable import CaelestiaCore

final class SIPAssistantTests: XCTestCase {
    func testAppleSiliconIncludesTheBootArgumentAndIntelDoesNot() {
        let arm = SIPAssistant.enable(appleSilicon: true, loader: "sudo /tmp/loader")
        XCTAssertTrue(arm.contains { $0.command == SIPAssistant.bootArg })
        XCTAssertTrue(arm.contains { $0.command == "sudo /tmp/loader" })
        let intel = SIPAssistant.enable(appleSilicon: false, loader: nil)
        XCTAssertFalse(intel.contains { $0.id == "nvram" })
        XCTAssertFalse(intel.contains { $0.id == "load" })
        XCTAssertTrue(intel.contains { $0.command == SIPAssistant.csrutilLower })
    }

    func testRevertMatchesTheMachine() {
        XCTAssertEqual(SIPAssistant.script(SIPAssistant.revert(appleSilicon: true)), "\(SIPAssistant.csrutilFull)\n\(SIPAssistant.clearBootArg)")
        XCTAssertEqual(SIPAssistant.script(SIPAssistant.revert(appleSilicon: false)), SIPAssistant.csrutilFull)
    }

    func testTheRiskSaysSIPOnStillWorks() {
        XCTAssertTrue(SIPAssistant.risk.contains("fully on"))
        XCTAssertTrue(SIPAssistant.risk.contains("School"))
    }
}
