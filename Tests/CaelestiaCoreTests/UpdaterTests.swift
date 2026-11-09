import CaelestiaCore
import XCTest

final class UpdaterTests: XCTestCase {
    func json(tag: String, zip: String = "file:///tmp/SkyRose.zip", sha: String = "file:///tmp/SkyRose.zip.sha256") -> Data {
        """
        {"tag_name":"\(tag)","assets":[
          {"name":"SkyRose.zip","browser_download_url":"\(zip)"},
          {"name":"SkyRose.zip.sha256","browser_download_url":"\(sha)"}
        ]}
        """.data(using: .utf8)!
    }

    func testNewerSameAndOlder() {
        XCTAssertEqual(Updater.compare("0.2.0", "v0.3.0"), .orderedAscending)
        XCTAssertEqual(Updater.compare("0.3.0", "v0.3.0"), .orderedSame)
        XCTAssertEqual(Updater.compare("0.4.0", "v0.3.0"), .orderedDescending)
        if case .update(let tag, _, _) = Updater.plan(current: "0.2.0", json: json(tag: "v0.3.0")) {
            XCTAssertEqual(tag, "v0.3.0")
        } else { XCTFail("expected an update") }
        XCTAssertEqual(Updater.plan(current: "0.3.0", json: json(tag: "v0.3.0")), .upToDate)
        XCTAssertEqual(Updater.plan(current: "0.9.0", json: json(tag: "v0.3.0")), .newerInstalled(tag: "v0.3.0"))
    }

    func testBadJSONAndBadChecksumKeepTheCurrentInstall() throws {
        if case .unreadable = Updater.plan(current: "0.2.0", json: Data("nope".utf8)) {} else { XCTFail("bad json") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("a.zip")
        try Data("zip".utf8).write(to: file)
        let sha = dir.appendingPathComponent("a.zip.sha256")
        try Data("deadbeef  a.zip\n".utf8).write(to: sha)
        XCTAssertFalse(Updater.checksumMatches(file: file, shaFile: sha))
        try Data("\(Updater.sha256(of: file)!)  a.zip\n".utf8).write(to: sha)
        XCTAssertTrue(Updater.checksumMatches(file: file, shaFile: sha))
        try FileManager.default.removeItem(at: dir)
    }

    func testOfflineJSONFileIsReportedByThePlan() {
        XCTAssertEqual(Updater.plan(current: "0.2.0", json: Data()), .unreadable("The release list could not be read."))
    }
}
