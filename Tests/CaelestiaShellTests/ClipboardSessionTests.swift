import AppKit
import CaelestiaCore
import XCTest
@testable import CaelestiaShell

@MainActor
final class ClipboardSessionTests: XCTestCase {
    private var dir: URL!
    private var board: NSPasteboard!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString)", isDirectory: true)
        board = NSPasteboard(name: NSPasteboard.Name("skyrose.test.\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: dir)
    }

    private func session() -> ClipboardSession { ClipboardSession(directory: dir, board: board) }

    private func copy(_ text: String, type: String? = nil) {
        board.clearContents()
        board.setString(text, forType: .string)
        if let type { board.setString("1", forType: NSPasteboard.PasteboardType(type)) }
    }

    func testCopiesAreRecordedAndConcealedOnesAreNot() {
        let s = session()
        copy("hello")
        s.poll()
        copy("hunter2", type: ClipboardHistory.concealedType)
        s.poll()
        XCTAssertEqual(s.history.entries.map(\.text), ["hello"])
    }

    func testSearchIsFuzzyAndBestFirst() {
        let s = session()
        for t in ["kubernetes deploy", "the quick fox", "qfx"] {
            s.history.record(text: t, imagePNG: nil, types: [], at: Date())
        }
        s.query = "qfx"
        XCTAssertEqual(s.rows.map(\.text), ["qfx", "the quick fox"])
        s.query = "zzz"
        XCTAssertTrue(s.rows.isEmpty)
    }

    func testReturnPutsTheEntryBackClosesThenPastes() {
        let s = session()
        s.history.record(text: "older", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 1))
        s.history.record(text: "newest", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 2))
        var order: [String] = []
        s.onClose = { order.append("close") }
        s.typePaste = { order.append("paste") }
        s.selected = 1
        s.activateSelected(alsoPaste: true)
        XCTAssertEqual(board.string(forType: .string), "older")
        XCTAssertEqual(order, ["close"], "the paste waits until the drawer has let go of the keyboard")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(order, ["close", "paste"])
    }

    func testShiftReturnOnlyCopiesAndIsNotRecordedAgain() {
        let s = session()
        s.history.record(text: "kept", imagePNG: nil, types: [], at: Date())
        var pasted = false
        s.typePaste = { pasted = true }
        s.activateSelected(alsoPaste: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(pasted)
        XCTAssertEqual(board.string(forType: .string), "kept")
        s.poll()
        XCTAssertEqual(s.history.entries.count, 1)
    }

    func testAnImageGetsASmallThumbnail() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let thumb = try XCTUnwrap(ClipboardSession.scaled(png, maxPixels: 96))
        XCTAssertEqual(max(thumb.size.width, thumb.size.height), 96)
        XCTAssertNil(ClipboardSession.scaled(Data([1, 2, 3]), maxPixels: 96))
    }

    func testCopiedImageIsStoredAndRemovedLocally() throws {
        let s = session()
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        board.clearContents()
        board.setData(try XCTUnwrap(rep.representation(using: .png, properties: [:])), forType: .png)
        s.poll()
        let id = try XCTUnwrap(s.history.entries.first?.id)
        let file = dir.appendingPathComponent(id.uuidString + ".png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        s.selected = 0
        s.deleteSelected()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    private func press(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    func testKeysReachTheListBeforeTheSearchField() {
        let s = session()
        s.history.record(text: "one", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 1))
        s.history.record(text: "two", imagePNG: nil, types: [], at: Date(timeIntervalSince1970: 2))
        var pasted = false
        s.typePaste = { pasted = true }

        XCTAssertTrue(s.key(press(125)))
        XCTAssertEqual(s.selected, 1)
        XCTAssertTrue(s.key(press(36, .shift)), "Shift+Return copies")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(pasted)
        XCTAssertEqual(board.string(forType: .string), "one")

        XCTAssertTrue(s.key(press(51)), "Delete removes the row when the field is empty")
        XCTAssertEqual(s.history.entries.map(\.text), ["two"])

        s.query = "tw"
        XCTAssertFalse(s.key(press(51)), "with text in the field, Delete is typing")
        XCTAssertEqual(s.history.entries.count, 1)
    }
}
