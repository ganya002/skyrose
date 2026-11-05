import XCTest
@testable import CaelestiaCore

/// The one-time pre-rename (Caelestia for Mac) -> SkyRose move. Everything happens under a temp root.
final class LegacyMigrationTests: XCTestCase {
    private var root: URL!
    private var loc: LegacyMigration.Locations!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        loc = .under(root)
    }

    override func tearDown() {
        try? fm.removeItem(at: root)
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testNothingToDo() {
        let m = LegacyMigration(locations: loc)
        XCTAssertFalse(m.isNeeded)
        XCTAssertEqual(m.run().outcome, .nothingToDo)
        XCTAssertFalse(fm.fileExists(atPath: m.markerURL.path), "no marker when there was nothing to do")
    }

    func testWholeDirectoriesAreMoved() throws {
        try write("a = 1", to: loc.legacyConfigDir.appendingPathComponent("config.toml"))
        try write("x", to: loc.legacyAppSupport.appendingPathComponent("state.json"))
        try write("log", to: loc.legacyLogsDir.appendingPathComponent("wm.log"))
        let m = LegacyMigration(locations: loc)
        XCTAssertTrue(m.isNeeded)
        let report = m.run()
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(read(loc.configDir.appendingPathComponent("config.toml")), "a = 1")
        XCTAssertEqual(read(loc.appSupport.appendingPathComponent("state.json")), "x")
        XCTAssertEqual(read(loc.logsDir.appendingPathComponent("wm.log")), "log")
        XCTAssertFalse(fm.fileExists(atPath: loc.legacyConfigDir.path))
        XCTAssertFalse(fm.fileExists(atPath: loc.legacyAppSupport.path))
        XCTAssertEqual(report.moved.count, 3)
        XCTAssertTrue(fm.fileExists(atPath: m.markerURL.path))
    }

    func testMergeKeepsDuplicatesAside() throws {
        try write("old", to: loc.legacyConfigDir.appendingPathComponent("config.toml"))
        try write("only-old", to: loc.legacyConfigDir.appendingPathComponent("keymap.toml"))
        try write("new", to: loc.configDir.appendingPathComponent("config.toml"))
        let report = LegacyMigration(locations: loc).run()
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(read(loc.configDir.appendingPathComponent("config.toml")), "new", "the SkyRose file wins")
        XCTAssertEqual(read(loc.configDir.appendingPathComponent("keymap.toml")), "only-old")
        let aside = loc.legacyConfigDir.deletingLastPathComponent().appendingPathComponent("caelestia-mac-pre-skyrose")
        XCTAssertEqual(read(aside.appendingPathComponent("config.toml")), "old")
        XCTAssertEqual(report.keptAside.count, 1)
        XCTAssertFalse(fm.fileExists(atPath: loc.legacyConfigDir.path), "the emptied old folder is removed")
    }

    func testIPCSocketIsSkipped() throws {
        try write("sock", to: loc.legacyAppSupport.appendingPathComponent("ipc.sock"))
        try write("x", to: loc.legacyAppSupport.appendingPathComponent("a.txt"))
        try write("keep", to: loc.appSupport.appendingPathComponent("b.txt"))
        LegacyMigration(locations: loc).run()
        XCTAssertNil(read(loc.appSupport.appendingPathComponent("ipc.sock")))
        XCTAssertEqual(read(loc.appSupport.appendingPathComponent("a.txt")), "x")
    }

    func testIPCSocketNotCarriedInWholeDirMove() throws {
        try write("sock", to: loc.legacyAppSupport.appendingPathComponent("ipc.sock"))
        try write("x", to: loc.legacyAppSupport.appendingPathComponent("a.txt"))
        LegacyMigration(locations: loc).run()
        XCTAssertFalse(fm.fileExists(atPath: loc.appSupport.appendingPathComponent("ipc.sock").path))
        XCTAssertEqual(read(loc.appSupport.appendingPathComponent("a.txt")), "x")
    }

    func testBackupJsonBecomesRestoreManifest() throws {
        try write("{\"journal\":1}", to: loc.legacyAppSupport.appendingPathComponent("backup.json"))
        LegacyMigration(locations: loc).run()
        XCTAssertEqual(read(loc.appSupport.appendingPathComponent("restore-manifest.json")), "{\"journal\":1}")
        XCTAssertFalse(fm.fileExists(atPath: loc.appSupport.appendingPathComponent("backup.json").path))
    }

    func testThemeNamesRewritten() throws {
        try write("# my theme\ntheme = \"caelestia-dynamic-dark\" # keep\nother = \"caelestia-default\"\n",
                  to: loc.legacyConfigDir.appendingPathComponent("config.toml"))
        LegacyMigration(locations: loc).run()
        let text = read(loc.configDir.appendingPathComponent("config.toml")) ?? ""
        XCTAssertTrue(text.contains("theme = \"skyrose-dynamic-dark\" # keep"), text)
        XCTAssertTrue(text.contains("other = \"caelestia-default\""), "only the theme key is touched")
        XCTAssertTrue(text.contains("# my theme"))
    }

    func testRewritingThemeNamesPure() {
        XCTAssertEqual(LegacyMigration.rewritingThemeNames(in: "theme = \"caelestia-default\""), "theme = \"skyrose-default\"")
        XCTAssertEqual(LegacyMigration.rewritingThemeNames(in: "theme = \"caelestia-dynamic\""), "theme = \"skyrose-dynamic\"")
        XCTAssertEqual(LegacyMigration.rewritingThemeNames(in: "themeX = \"caelestia-default\""), "themeX = \"caelestia-default\"")
        XCTAssertEqual(LegacyMigration.rewritingThemeNames(in: "theme = \"custom\""), "theme = \"custom\"")
    }

    func testSecondRunIsAlreadyDone() throws {
        try write("a", to: loc.legacyConfigDir.appendingPathComponent("config.toml"))
        let m = LegacyMigration(locations: loc)
        XCTAssertEqual(m.run().outcome, .migrated)
        XCTAssertFalse(m.isNeeded)
        XCTAssertEqual(m.run().outcome, .alreadyDone)
        // Even if an old folder reappears, the marker wins.
        try write("b", to: loc.legacyConfigDir.appendingPathComponent("config.toml"))
        XCTAssertEqual(m.run().outcome, .alreadyDone)
    }

    func testSkippedWhileLegacyWMRunning() throws {
        try write("a", to: loc.legacyConfigDir.appendingPathComponent("config.toml"))
        let m = LegacyMigration(locations: loc)
        XCTAssertEqual(m.run(legacyWMRunning: true).outcome, .skippedLegacyRunning)
        XCTAssertTrue(fm.fileExists(atPath: loc.legacyConfigDir.path), "nothing touched")
        XCTAssertFalse(fm.fileExists(atPath: m.markerURL.path))
        XCTAssertEqual(m.run().outcome, .migrated, "the next launch tries again")
    }

    func testKittyThemeMovedWithCompatSymlink() throws {
        try write("colors", to: loc.legacyKittyTheme)
        let report = LegacyMigration(locations: loc).run()
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(read(loc.kittyTheme), "colors")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: loc.legacyKittyTheme.path), "skyrose-theme.conf")
    }
}
