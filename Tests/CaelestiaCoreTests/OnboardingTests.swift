import XCTest
@testable import CaelestiaCore

final class OnboardingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private let all = PermissionSnapshot(accessibility: true, inputMonitoring: true, screenRecording: true)

    func testSimulatingMissing() {
        let s = all.simulatingMissing([.accessibility, .screenRecording])
        XCTAssertFalse(s.accessibility)
        XCTAssertTrue(s.inputMonitoring)
        XCTAssertFalse(s.screenRecording)
        XCTAssertEqual(s.granted, [.inputMonitoring])
        XCTAssertEqual(all.simulatingMissing([]), all)
        XCTAssertEqual(PermissionSnapshot.none.granted, [])
    }

    func testParseSimulated() {
        XCTAssertEqual(PermissionSnapshot.parseSimulated(nil), [])
        XCTAssertEqual(PermissionSnapshot.parseSimulated(""), [])
        XCTAssertEqual(PermissionSnapshot.parseSimulated("accessibility,screenRecording"), [.accessibility, .screenRecording])
        XCTAssertEqual(PermissionSnapshot.parseSimulated("inputMonitoring bogus"), [.inputMonitoring])
    }

    func testRequiredAndRestart() {
        XCTAssertTrue(SkyRosePermission.accessibility.isRequired(in: .full))
        XCTAssertFalse(SkyRosePermission.screenRecording.isRequired(in: .wm))
        XCTAssertTrue(SkyRosePermission.screenRecording.needsRestartAfterGrant)
        for p in SkyRosePermission.allCases { XCTAssertTrue(p.settingsURL.absoluteString.hasPrefix("x-apple.systempreferences:")) }
    }

    func testHistoryReportsLossOnceAndRegrantClears() {
        var h = PermissionHistory()
        XCTAssertEqual(h.observe(.none), [], "never granted: not a loss")
        XCTAssertEqual(h.observe(all), [])
        let lost = PermissionSnapshot(accessibility: false, inputMonitoring: true, screenRecording: true)
        XCTAssertEqual(h.observe(lost), [.accessibility])
        XCTAssertEqual(h.observe(lost), [], "reported once")
        XCTAssertEqual(h.observe(all), [], "regrant clears")
        XCTAssertTrue(h.reportedLost.isEmpty)
        XCTAssertEqual(h.observe(lost), [.accessibility], "a new loss is reported again")
    }

    func testHistorySaveLoad() {
        let url = dir.appendingPathComponent("seen.json")
        XCTAssertEqual(PermissionHistory.load(from: url), PermissionHistory())
        var h = PermissionHistory()
        _ = h.observe(all)
        _ = h.observe(.none)
        h.save(to: url)
        XCTAssertEqual(PermissionHistory.load(from: url), h)
    }

    func testStateRoundTrip() throws {
        let url = dir.appendingPathComponent("sub/onboarding.json")
        XCTAssertFalse(OnboardingState.load(from: url).completed)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try OnboardingState(completed: true, completedAt: date).save(to: url)
        let s = OnboardingState.load(from: url)
        XCTAssertTrue(s.completed)
        XCTAssertEqual(s.completedAt, date)
        XCTAssertEqual(s.version, OnboardingState.currentVersion)
        try Data("garbage".utf8).write(to: url)
        XCTAssertFalse(OnboardingState.load(from: url).completed, "corrupt file reads as not completed")
    }

    func testRequestArgumentsAndParse() {
        XCTAssertEqual(OnboardingRequest.firstRun.arguments, ["--onboarding"])
        XCTAssertEqual(OnboardingRequest.parse(["--onboarding"]), .firstRun)
        XCTAssertNil(OnboardingRequest.parse(["--other"]))
        let repair = OnboardingRequest.repair([.accessibility, .inputMonitoring])
        XCTAssertEqual(repair.arguments, ["--onboarding", "--repair", "--only", "accessibility,inputMonitoring"])
        XCTAssertEqual(OnboardingRequest.parse(repair.arguments), repair)
        let only = OnboardingRequest(onlyPermissions: [.screenRecording])
        XCTAssertEqual(only.arguments, ["--onboarding", "--only", "screenRecording"])
        XCTAssertEqual(OnboardingRequest.parse(only.arguments), only)
        XCTAssertEqual(OnboardingRequest.parse(["--onboarding", "--repair"]), .repair([]))
    }
}
