import XCTest
@testable import CaelestiaCore

final class KeymapFileEditorTests: XCTestCase {
    private var dir: URL!
    private var file: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("keymapedit-\(UUID().uuidString)", isDirectory: true)
        file = dir.appendingPathComponent("keymap.toml")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testFirstEditCopiesDefaultAndSetsKeys() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let editor = KeymapFileEditor(file: file)
        let km = try editor.setKeys(["SUPER + Y"], forBind: "app.terminal")
        XCTAssertEqual(km.bind(id: "app.terminal")?.keys, ["SUPER + Y"])
        let text = try String(contentsOf: file, encoding: .utf8)
        let defaults = try KeymapLoader.defaultKeymapText()
        XCTAssertTrue(text.contains("SUPER + Y"))
        XCTAssertEqual(text.components(separatedBy: "\n").count, defaults.components(separatedBy: "\n").count, "only the one line changed")
        XCTAssertEqual(try KeymapParser.parse(toml: text).binds.count, try KeymapLoader.loadDefaultOrThrow().binds.count)
    }

    func testSetEnabledAndReset() throws {
        let editor = KeymapFileEditor(file: file)
        var km = try editor.setEnabled(false, forBind: "app.terminal")
        XCTAssertEqual(km.bind(id: "app.terminal")?.enabled, false)
        try editor.setKeys(["SUPER + Y"], forBind: "app.terminal")
        km = try editor.resetBind("app.terminal")
        let d = try KeymapLoader.loadDefaultOrThrow().bind(id: "app.terminal")
        XCTAssertEqual(km.bind(id: "app.terminal")?.keys, d?.keys)
        XCTAssertEqual(km.bind(id: "app.terminal")?.enabled, d?.enabled)
    }

    func testPanicBindIsFixed() throws {
        let editor = KeymapFileEditor(file: file)
        XCTAssertThrowsError(try editor.setKeys(["SUPER + P"], forBind: KeymapParser.panicBindID)) {
            XCTAssertEqual($0 as? KeymapEditError, .fixedBind(KeymapParser.panicBindID))
        }
        XCTAssertThrowsError(try editor.setEnabled(false, forBind: KeymapParser.panicBindID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "nothing written")
    }

    func testUnknownBind() {
        let editor = KeymapFileEditor(file: file)
        XCTAssertThrowsError(try editor.setKeys(["SUPER + Y"], forBind: "no.such.bind")) {
            XCTAssertEqual($0 as? KeymapEditError, .unknownBind("no.such.bind"))
        }
        XCTAssertThrowsError(try editor.resetBind("no.such.bind"))
    }

    func testInvalidChordRejectedFileUnchanged() throws {
        let editor = KeymapFileEditor(file: file)
        try editor.setKeys(["SUPER + Y"], forBind: "app.terminal")
        let before = try String(contentsOf: file, encoding: .utf8)
        XCTAssertThrowsError(try editor.setKeys(["BOGUS + NOPE"], forBind: "app.terminal")) { error in
            guard case KeymapEditError.rejected = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), before)
    }
}
