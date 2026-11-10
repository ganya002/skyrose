import XCTest
@testable import CaelestiaCore

final class SetupFlowTests: XCTestCase {
    func testMenuBarPlan() {
        XCTAssertFalse(MenuBarPlan.hides(.shown))
        XCTAssertTrue(MenuBarPlan.hides(.auto))
        XCTAssertTrue(MenuBarPlan.hides(.off))
        XCTAssertTrue(MenuBarPlan.reserve(.shown))
        XCTAssertTrue(MenuBarPlan.reserve(.auto))
        XCTAssertFalse(MenuBarPlan.reserve(.off))
    }

    func testMenuBarChoiceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("menu-bar-\(UUID().uuidString)")
        let file = MenuBarChoiceStore.file(in: url)
        XCTAssertNil(MenuBarChoiceStore.read(file))
        try MenuBarChoiceStore.write(.off, to: file)
        XCTAssertEqual(MenuBarChoiceStore.read(file), .off)
        try? FileManager.default.removeItem(at: url)
    }

    func testGuidedOrder() {
        XCTAssertEqual(OnboardingStep.guided, [.mode, .permissions, .tweaks, .extras, .done])
    }

    func testRecommendedDecisions() {
        XCTAssertEqual(RecommendedSetup.dock(hidden: false), .apply)
        XCTAssertEqual(RecommendedSetup.dock(hidden: true), .already)
        XCTAssertEqual(RecommendedSetup.menuBar(autoHides: false), .apply)
        XCTAssertEqual(RecommendedSetup.cursor(configured: "", capeAvailable: true), .apply)
        XCTAssertEqual(RecommendedSetup.cursor(configured: RecommendedSetup.cursorName, capeAvailable: true), .already)
        XCTAssertEqual(RecommendedSetup.cursor(configured: "", capeAvailable: false), .skip("Bibata is not in this copy of SkyRose."))
        XCTAssertEqual(RecommendedSetup.wallpaper(alreadySet: false, bundled: true), .apply)
        XCTAssertEqual(RecommendedSetup.wallpaper(alreadySet: true, bundled: true), .already)
        XCTAssertEqual(RecommendedSetup.wallpaper(alreadySet: false, bundled: false).skipReason, "This copy has no starter pictures, so your wallpaper stays.")
        XCTAssertEqual(RecommendedSetup.corners(displayCornerRadius: -1), .already)
        XCTAssertEqual(RecommendedSetup.corners(displayCornerRadius: 12), .apply)
    }

    func testDoctorFixWritesAMissingConfigAndExplainsPermissions() {
        let plan = DoctorFix.plan(DoctorWorld(configExists: false, wmRunning: true, missingPermissions: ["Accessibility"]))
        XCTAssertEqual(plan.first, .writeDefaultConfig)
        XCTAssertTrue(plan.contains { if case .explain(let text) = $0 { return text.contains("Accessibility") }; return false })
    }

    func testDoctorFixRehidesWhatSkyRoseSetAndLeavesAHealthyMacAlone() {
        var world = DoctorWorld()
        XCTAssertTrue(DoctorFix.plan(world).isEmpty)
        world.dockJournaled = true
        world.dockHidden = false
        world.menuBarJournaled = true
        world.menuBarHidden = false
        world.cursor = ""
        world.socketPresent = true
        world.socketHealthy = false
        world.wmRunning = false
        let plan = DoctorFix.plan(world)
        XCTAssertEqual(plan, [.rehideDock, .rehideMenuBar, .restoreDefaultCursor, .removeStaleSocket])
    }

    func testDoctorFixDoesNotOverwriteABrokenConfigOrARunningSocket() {
        let broken = DoctorFix.plan(DoctorWorld(configBroken: true))
        XCTAssertFalse(broken.contains(.writeDefaultConfig))
        XCTAssertTrue(broken.contains { if case .explain = $0 { return true }; return false })
        let live = DoctorFix.plan(DoctorWorld(socketPresent: true, socketHealthy: false, wmRunning: true))
        XCTAssertFalse(live.contains(.removeStaleSocket))
    }
}

private extension RecommendedDecision {
    var skipReason: String? { if case .skip(let s) = self { return s }; return nil }
}
