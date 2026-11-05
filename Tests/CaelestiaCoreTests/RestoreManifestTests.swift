import XCTest
@testable import CaelestiaCore

final class RestoreManifestTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("manifest-\(UUID().uuidString).json")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    func testFreshManifestNeedsNoReminder() {
        let m = RestoreManifest(url: url)
        XCTAssertFalse(m.everUsed(.sipOff))
        XCTAssertFalse(m.mustShowSIPReminder)
        XCTAssertNil(m.readError)
    }

    func testRecordSIPOffMode() throws {
        let m = RestoreManifest(url: url)
        try m.recordModeUsed(.sipOff, note: "test")
        try m.recordModeUsed(.sipOff)
        XCTAssertTrue(m.everUsed(.sipOff))
        XCTAssertTrue(m.mustShowSIPReminder)
        XCTAssertEqual(try m.journal.entries().count, 1, "recorded once")
        XCTAssertEqual(try m.pendingRestores(), [], "modes have nothing to restore")
    }

    func testCorruptManifestForcesReminder() throws {
        try Data("{not json".utf8).write(to: url)
        let m = RestoreManifest(url: url)
        XCTAssertNotNil(m.readError)
        XCTAssertFalse(m.everUsed(.sipOff))
        XCTAssertTrue(m.mustShowSIPReminder)
        XCTAssertThrowsError(try m.pendingRestores())
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
