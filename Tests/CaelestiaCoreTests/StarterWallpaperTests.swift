import CaelestiaCore
import XCTest

final class StarterWallpaperTests: XCTestCase {
    func testCopiesNewFilesSkipsExistingNamesAndDuplicateHashesAndJournalsTheHash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("starters-\(UUID().uuidString)", isDirectory: true)
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let dest = root.appendingPathComponent("Static", isDirectory: true)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: bundled.appendingPathComponent("SkyRose - Dawn.png"))
        try Data("two".utf8).write(to: bundled.appendingPathComponent("SkyRose - Dusk.png"))
        try Data("notes".utf8).write(to: bundled.appendingPathComponent("CREDITS.md"))
        try Data("two".utf8).write(to: dest.appendingPathComponent("Already - Dusk.png"))
        let journal = BackupJournal(url: root.appendingPathComponent("journal.json"))
        let report = try StarterWallpapers.install(bundled: bundled, destination: dest, journal: journal, hasSkyRoseWallpaper: false)
        XCTAssertEqual(report.copied.map(\.lastPathComponent), ["SkyRose - Dawn.png"])
        XCTAssertTrue(report.skipped.contains("SkyRose - Dusk.png"))
        XCTAssertEqual(report.suggested?.lastPathComponent, "SkyRose - Dawn.png")
        let again = try StarterWallpapers.install(bundled: bundled, destination: dest, journal: journal, hasSkyRoseWallpaper: true)
        XCTAssertTrue(again.copied.isEmpty)
        XCTAssertNil(again.suggested)
        let entries = try journal.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .file)
        XCTAssertEqual(entries[0].oldValue, .absent)
        XCTAssertEqual(entries[0].newValue, .string(StarterWallpapers.sha256(url: bundled.appendingPathComponent("SkyRose - Dawn.png"))))
        try FileManager.default.removeItem(at: root)
    }
}
