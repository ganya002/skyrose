import CaelestiaCore
import XCTest
@testable import SkyRoseSettingsKit

final class SettingsLaunchOptionsTests: XCTestCase {
    func testDefaults() {
        let o = SettingsLaunchOptions.parse([])
        XCTAssertNil(o.onboarding)
        XCTAssertEqual(o.page, .general)
        XCTAssertTrue(o.simulateMissing.isEmpty)
        XCTAssertFalse(o.sipReminder)
        XCTAssertFalse(o.demoSIPPopup)
        XCTAssertTrue(SettingsLaunchOptions.parse(["--sip-reminder"]).sipReminder)
        XCTAssertTrue(SettingsLaunchOptions.parse(["--sip-reminder"]).sipReminderOnly)
        XCTAssertFalse(SettingsLaunchOptions.parse(["--sip-reminder", "--uninstaller"]).sipReminderOnly)
        XCTAssertFalse(SettingsLaunchOptions.parse(["--onboarding", "--sip-reminder"]).sipReminderOnly)
    }

    func testRepairAndSimulate() {
        let o = SettingsLaunchOptions.parse(["--onboarding", "--repair", "--only", "accessibility", "--simulate-missing", "screenRecording"],
                                            environment: ["SKYROSE_SIMULATE_MISSING": "inputMonitoring"])
        XCTAssertEqual(o.onboarding, .repair([.accessibility]))
        XCTAssertEqual(o.simulateMissing, [.screenRecording, .inputMonitoring])
    }

    func testPage() {
        XCTAssertEqual(SettingsLaunchOptions.parse(["--page", "keybinds"]).page, .keybinds)
        XCTAssertEqual(SettingsLaunchOptions.parse(["--page", "nope"]).page, .general)
    }
}
