import XCTest
@testable import CaelestiaCore

final class ClipboardHistoryTests: XCTestCase {
    func testTextIsNewestFirstAndRepeatsAreIgnored() {
        var h = ClipboardHistory(maxEntries: 3)
        XCTAssertTrue(h.record(text: "one", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 1)))
        XCTAssertFalse(h.record(text: "one", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 2)))
        XCTAssertTrue(h.record(text: "two", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(h.entries.map(\.text), ["two", "one"])
    }

    func testNewLimitsDropTheOldestAndLeaveTheRest() {
        var h = ClipboardHistory()
        for word in ["one", "two", "three"] { h.record(text: word, imagePNG: nil, types: [], at: Date()) }
        XCTAssertFalse(h.setLimits(maxEntries: 3, maxBytes: 1024))
        XCTAssertTrue(h.setLimits(maxEntries: 2, maxBytes: 1024))
        XCTAssertEqual(h.entries.map(\.text), ["three", "two"])
    }

    func testAConfigWithoutTheSectionGetsTheDefaultsAndBadLimitsAreRefused() throws {
        let c = try ConfigLoader.parse(toml: "[wm]\ngapsOut = 14\n")
        XCTAssertEqual(c.clipboard, ClipboardConfig())
        var bad = c
        bad.clipboard.maxEntries = 0
        XCTAssertFalse(ConfigLoader.validate(bad).isEmpty)
    }

    func testConcealedAndTransientNeverStored() {
        var h = ClipboardHistory()
        XCTAssertFalse(h.record(text: "hunter2", imagePNG: nil, types: [ClipboardHistory.concealedType], at: Date()))
        XCTAssertFalse(h.record(text: "temp", imagePNG: nil, types: [ClipboardHistory.transientType], at: Date()))
        XCTAssertTrue(h.entries.isEmpty)
    }

    func testPauseAndEvict() {
        var h = ClipboardHistory(maxEntries: 2, maxBytes: 4)
        h.paused = true
        XCTAssertFalse(h.record(text: "nope", imagePNG: nil, types: [], at: Date()))
        h.paused = false
        XCTAssertTrue(h.record(text: "a", imagePNG: Data([1, 2, 3, 4, 5]), types: [], at: Date(timeIntervalSince1970: 1)))
        XCTAssertTrue(h.record(text: "b", imagePNG: Data([9]), types: [], at: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(h.entries.map(\.text), ["b"], "the older image was over the byte cap")
        XCTAssertTrue(h.record(text: "c", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 3)))
        XCTAssertTrue(h.record(text: "d", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 4)))
        XCTAssertEqual(h.entries.map(\.text), ["d", "c"])
    }

    func testArchiveRoundTripDropsDeletedImages() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clips-\(UUID().uuidString)", isDirectory: true)
        var h = ClipboardHistory()
        XCTAssertTrue(h.record(text: "hi", imagePNG: Data([1, 2, 3]), types: [], at: Date(timeIntervalSince1970: 10)))
        let id = try XCTUnwrap(h.entries.first?.id)
        try ClipboardArchive.save(h, to: dir)
        h.remove(id: id)
        try ClipboardArchive.save(h, to: dir)
        let loaded = ClipboardArchive.load(from: dir)
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(id.uuidString + ".png").path))
        try? FileManager.default.removeItem(at: dir)
    }

    func testACopiedFileIsOneFileNotItsNameAndIcon() {
        var h = ClipboardHistory()
        XCTAssertTrue(h.record(text: "photo.png", imagePNG: Data([1]), types: [], at: Date(), files: ["/tmp/a/photo.png"]))
        let entry = h.entries[0]
        XCTAssertNil(entry.imagePNG)
        XCTAssertNil(entry.text)
        XCTAssertEqual(entry.preview, "photo.png")
        XCTAssertTrue(h.record(text: nil, imagePNG: nil, types: [], at: Date(), files: ["/a/one", "/a/two", "/a/three"]))
        XCTAssertEqual(h.entries[0].preview, "one and 2 more")
    }

    func testPasswordManagerTypesNeverStored() {
        var h = ClipboardHistory()
        for type in ClipboardHistory.blockedTypes {
            XCTAssertFalse(h.record(text: "secret", imagePNG: nil, types: [type], at: Date()), type)
        }
        XCTAssertTrue(h.entries.isEmpty)
    }

    func testFilesSurviveAReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString)", isDirectory: true)
        var h = ClipboardHistory()
        h.record(text: nil, imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 1), files: ["/a/b.txt"])
        try ClipboardArchive.save(h, to: dir)
        XCTAssertEqual(ClipboardArchive.load(from: dir).entries.first?.files, ["/a/b.txt"])
        try? FileManager.default.removeItem(at: dir)
    }
}
