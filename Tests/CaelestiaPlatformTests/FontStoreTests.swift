import CaelestiaCore
import Foundation
import XCTest

@testable import CaelestiaPlatform

final class FontStoreTests: XCTestCase {
    private var root: URL!
    private var cache: URL { root.appendingPathComponent("cache") }
    private var userFonts: URL { root.appendingPathComponent("Library/Fonts") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fontstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var rubik: FontPack.Family { FontPack.families.first { $0.name == "Rubik" }! }

    /// Puts a size-correct stand-in of `family` in the cache (the hash is checked only on download).
    private func fakeCache(_ family: FontPack.Family) throws {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for a in family.files { try Data(count: a.bytes).write(to: cache.appendingPathComponent(a.fileName)) }
    }

    func testChecksumMismatchKeepsNothing() async throws {
        let store = FontStore(cacheDirectory: cache, userFontsDirectory: userFonts, fetch: { _ in Data("not a font".utf8) })
        do {
            try await store.download()
            XCTFail("a corrupt download must fail")
        } catch let e as FontStore.FontStoreError {
            guard case .checksum = e else { return XCTFail("\(e)") }
        }
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
        XCTAssertTrue(kept.isEmpty, "\(kept)")
    }

    func testDownloadSkipsWhatIsCached() async throws {
        for f in FontPack.families { try fakeCache(f) }
        for f in FontPack.families { try Data("x".utf8).write(to: cache.appendingPathComponent(f.licenceFile.fileName)) }
        let store = FontStore(cacheDirectory: cache, userFontsDirectory: userFonts, fetch: { url in
            XCTFail("fetched \(url)"); return Data()
        })
        let fetched = try await store.download()
        XCTAssertEqual(fetched, [])
        XCTAssertTrue(store.status().allSatisfy(\.downloaded))
    }

    func testInstallCopiesOnlyMissingFilesAndUninstallRemovesOnlyThose() throws {
        try fakeCache(rubik)
        let store = FontStore(cacheDirectory: cache, userFontsDirectory: userFonts)
        try FileManager.default.createDirectory(at: userFonts, withIntermediateDirectories: true)
        let theirs = userFonts.appendingPathComponent("TheirFont.ttf")
        try Data("theirs".utf8).write(to: theirs)
        let journal = BackupJournal(url: root.appendingPathComponent("backup.json"))

        let notes = try store.installForUser(families: ["Rubik", "Inter"], journal: journal)
        XCTAssertEqual(notes.filter { $0.hasPrefix("installed") }.count, 1)
        XCTAssertTrue(notes.contains("Inter: not downloaded"))
        let copied = userFonts.appendingPathComponent(rubik.files[0].fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(try journal.entries().map(\.kind), [.font])
        XCTAssertEqual(store.status().first { $0.name == "Rubik" }?.installedBySkyRose, true)

        XCTAssertTrue(try store.installForUser(families: ["Rubik"]).isEmpty, "already there: nothing copied twice")

        try store.uninstallUser()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(try Data(contentsOf: theirs), Data("theirs".utf8), "never touches other fonts")
        XCTAssertEqual(store.status().first { $0.name == "Rubik" }?.installedBySkyRose, false)
    }

    func testAFontAlreadyInstalledIsNotOverwritten() throws {
        try fakeCache(rubik)
        try FileManager.default.createDirectory(at: userFonts, withIntermediateDirectories: true)
        let existing = userFonts.appendingPathComponent(rubik.files[0].fileName)
        try Data("user copy".utf8).write(to: existing)
        let store = FontStore(cacheDirectory: cache, userFontsDirectory: userFonts)
        try store.installForUser(families: ["Rubik"])
        try store.uninstallUser()
        XCTAssertEqual(try Data(contentsOf: existing), Data("user copy".utf8))
    }
}
