import XCTest
@testable import CaelestiaCore

final class RestoreManifestTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("manifest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("restore-manifest.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testFreshManifestNeedsNoReminder() {
        let m = RestoreManifest(url: url)
        XCTAssertFalse(m.everUsed(.sipOff))
        XCTAssertFalse(m.mustShowSIPReminder(csrutilStatus: "System Integrity Protection status: disabled."))
        XCTAssertFalse(m.mustShowSIPReminder(csrutilStatus: nil))
        XCTAssertNil(m.readError)
    }

    func testRecordSIPOffMode() throws {
        let m = RestoreManifest(url: url)
        try m.recordModeUsed(.sipOff, note: "test")
        try m.recordModeUsed(.sipOff)
        XCTAssertTrue(m.everUsed(.sipOff))
        XCTAssertTrue(m.mustShowSIPReminder(csrutilStatus: "System Integrity Protection status: unknown (Custom Configuration).\n\tFilesystem Protections: disabled"))
        XCTAssertTrue(m.mustShowSIPReminder(csrutilStatus: nil), "csrutil unreadable: the flag decides")
        XCTAssertFalse(m.mustShowSIPReminder(csrutilStatus: "System Integrity Protection status: enabled."), "SIP already back on")
        XCTAssertTrue(FileManager.default.fileExists(atPath: m.flagURL(.sipOff).path))
        XCTAssertEqual(try m.journal.entries().count, 1, "recorded once")
        XCTAssertEqual(try m.pendingRestores(), [], "modes have nothing to restore")
    }

    func testCorruptManifestDoesNotShowReminder() throws {
        try Data("{not json".utf8).write(to: url)
        let m = RestoreManifest(url: url)
        XCTAssertNotNil(m.readError)
        XCTAssertFalse(m.everUsed(.sipOff))
        XCTAssertFalse(m.mustShowSIPReminder(csrutilStatus: "System Integrity Protection status: disabled."), "never without the flag")
        XCTAssertThrowsError(try m.pendingRestores())
    }

    func testFlagFileSurvivesCorruptManifest() throws {
        let m = RestoreManifest(url: url)
        try m.recordModeUsed(.sipOff)
        try Data("{not json".utf8).write(to: url)
        XCTAssertTrue(m.everUsed(.sipOff))
        XCTAssertTrue(m.mustShowSIPReminder(csrutilStatus: "System Integrity Protection status: disabled."))
    }

    func testSIPStatusParsing() {
        XCTAssertEqual(SIPStatus.parse("System Integrity Protection status: enabled."), .enabled)
        XCTAssertEqual(SIPStatus.parse("System Integrity Protection status: disabled."), .disabled)
        XCTAssertEqual(SIPStatus.parse("System Integrity Protection status: unknown (Custom Configuration).\n\nConfiguration:\n\tDebugging Restrictions: disabled"), .custom)
        XCTAssertEqual(SIPStatus.parse("System Integrity Protection status: enabled (Custom Configuration)."), .custom)
        XCTAssertEqual(SIPStatus.parse(nil), .unknown)
        XCTAssertEqual(SIPStatus.parse(""), .unknown)
    }

    func testDecisionNeverWithoutFlag() {
        for s in [SIPStatus.enabled, .custom, .disabled, .unknown] {
            XCTAssertFalse(SIPReminderDecision.shouldShow(sipOffModeUsed: false, status: s))
        }
        XCTAssertFalse(SIPReminderDecision.shouldShow(sipOffModeUsed: true, status: .enabled))
        XCTAssertTrue(SIPReminderDecision.shouldShow(sipOffModeUsed: true, status: .custom))
        XCTAssertTrue(SIPReminderDecision.shouldShow(sipOffModeUsed: true, status: .disabled))
        XCTAssertTrue(SIPReminderDecision.shouldShow(sipOffModeUsed: true, status: .unknown))
    }

    func testPendingRestoresAndTitles() throws {
        let m = RestoreManifest(url: url)
        try m.journal.append(BackupEntry(domain: "com.apple.dock", key: "autohide", oldValue: .bool(false), newValue: .bool(true), kind: .defaults))
        try m.journal.append(BackupEntry(domain: "NSGlobalDomain", key: "_HIHideMenuBar", oldValue: .absent, newValue: .bool(true), kind: .defaults))
        try m.recordModeUsed(.sipOff)
        let items = try m.pendingRestores()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.title)), ["Dock: hide automatically", "Menu bar: hide automatically"])
        let dock = try XCTUnwrap(items.first { $0.title.hasPrefix("Dock") })
        XCTAssertEqual(dock.original, .bool(false))
        XCTAssertEqual(dock.current, .bool(true))
    }
}
