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
}
