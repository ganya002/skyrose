import XCTest
@testable import CaelestiaCore

final class ConfigAPITests: XCTestCase {
    private var dir: URL!
    private var file: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("configapi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("config.toml")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private var text: String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }

    func testParseCLI() {
        XCTAssertEqual(ConfigValue.parse(cli: "true"), .bool(true))
        XCTAssertEqual(ConfigValue.parse(cli: " false "), .bool(false))
        XCTAssertEqual(ConfigValue.parse(cli: "8"), .int(8))
        XCTAssertEqual(ConfigValue.parse(cli: "0.5"), .number(0.5))
        XCTAssertEqual(ConfigValue.parse(cli: "\"hi there\""), .string("hi there"))
        XCTAssertEqual(ConfigValue.parse(cli: "kitty"), .string("kitty"))
        XCTAssertEqual(ConfigValue.parse(cli: "[1, 2]"), .literal("[1, 2]"))
        XCTAssertEqual(ConfigValue.parse(cli: "{ a = 1 }"), .literal("{ a = 1 }"))
    }

    func testTomlRendering() {
        XCTAssertEqual(ConfigValue.bool(true).toml, "true")
        XCTAssertEqual(ConfigValue.int(3).toml, "3")
        XCTAssertEqual(ConfigValue.number(10).toml, "10.0")
        XCTAssertEqual(ConfigValue.number(10.256).toml, "10.26")
        XCTAssertEqual(ConfigValue.string("a\"b").toml, "\"a\\\"b\"")
        XCTAssertEqual(ConfigValue.literal("[1]").toml, "[1]")
        XCTAssertEqual(ConfigValue.tables([["name": .string("x"), "on": .bool(true)]]).toml, "[{ name = \"x\", on = true }]")
        XCTAssertEqual(ConfigValue.int(3).description, "3")
    }

    func testSetCreatesFileAndLoads() throws {
        let api = ConfigAPI(file: file)
        let result = try api.set("wm.gapsIn", .number(8))
        XCTAssertEqual(result.config.wm.gapsIn, 8)
        XCTAssertEqual(api.load().wm.gapsIn, 8)
        XCTAssertTrue(text.contains("[wm]"))
    }

    func testSetPreservesCommentsAndOtherKeys() throws {
        try Data("# my config\n[wm]\n# gaps between windows\ngapsIn = 5.0\nborderSize = 2\n".utf8).write(to: file)
        let api = ConfigAPI(file: file)
        try api.set("wm.gapsIn", .number(9))
        XCTAssertTrue(text.contains("# my config"))
        XCTAssertTrue(text.contains("# gaps between windows"))
        XCTAssertTrue(text.contains("borderSize = 2"))
        XCTAssertEqual(api.load().wm.gapsIn, 9)
    }

    func testInvalidValueRejectedFileUnchanged() throws {
        let original = "# keep\n[wm]\ngapsIn = 5.0\n"
        try Data(original.utf8).write(to: file)
        let api = ConfigAPI(file: file)
        XCTAssertThrowsError(try api.set("wm.gapsIn", .string("lots"))) { error in
            guard case ConfigAPIError.rejected = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try api.set("general.mode", .string("bogus")))
        XCTAssertEqual(text, original)
    }

    func testInvalidValueWithNoFileCreatesNoFile() {
        XCTAssertThrowsError(try ConfigAPI(file: file).set("wm.gapsIn", .string("x")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testResetRemovesKey() throws {
        let api = ConfigAPI(file: file)
        try api.set("wm.gapsIn", .number(9))
        XCTAssertEqual(api.load().wm.gapsIn, 9)
        try api.reset("wm.gapsIn")
        XCTAssertEqual(api.load().wm.gapsIn, Config().wm.gapsIn)
        XCTAssertFalse(text.contains("gapsIn"))
    }

    func testBatchSetWritesAll() throws {
        let api = ConfigAPI(file: file)
        try api.set([("wm.gapsIn", .number(7)), ("wm.gapsOut", .number(11)), ("shell.osd", .bool(false))])
        let c = api.load()
        XCTAssertEqual(c.wm.gapsIn, 7)
        XCTAssertEqual(c.wm.gapsOut, 11)
        XCTAssertFalse(c.shell.osd)
    }

    func testBatchWithOneInvalidWritesNothing() throws {
        let original = "[wm]\ngapsIn = 5.0\n"
        try Data(original.utf8).write(to: file)
        XCTAssertThrowsError(try ConfigAPI(file: file).set([("wm.gapsIn", .number(7)), ("wm.gapsOut", .string("bad"))]))
        XCTAssertEqual(text, original)
    }

    func testSplit() throws {
        var s = try ConfigAPI.split("wm.gapsIn")
        XCTAssertEqual(s.table, "wm"); XCTAssertEqual(s.key, "gapsIn")
        s = try ConfigAPI.split("wm.dwindle.preserveSplit")
        XCTAssertEqual(s.table, "wm.dwindle"); XCTAssertEqual(s.key, "preserveSplit")
        s = try ConfigAPI.split("appRules.com.apple.finder")
        XCTAssertEqual(s.table, "appRules"); XCTAssertEqual(s.key, "com.apple.finder")
        s = try ConfigAPI.split("displays.ABC-123.displayCornerRadius")
        XCTAssertEqual(s.table, ConfigFileEditor.displayTable("ABC-123")); XCTAssertEqual(s.key, "displayCornerRadius")
        XCTAssertThrowsError(try ConfigAPI.split("gapsIn"))
        XCTAssertThrowsError(try ConfigAPI.split("wm."))
        XCTAssertThrowsError(try ConfigAPI.split("appRules."))
        XCTAssertThrowsError(try ConfigAPI(file: file).set("nope", .bool(true)))
    }

    func testAppRuleAndDisplayPaths() throws {
        let api = ConfigAPI(file: file)
        try api.set("appRules.com.example.app", .string("float"))
        XCTAssertEqual(api.load().appRules["com.example.app"], "float")
        try api.set("displays.UUID-1.displayCornerRadius", .number(20))
        XCTAssertEqual(api.load().displays["UUID-1"]?.displayCornerRadius, 20)
        try api.reset("appRules.com.example.app")
        XCTAssertNil(api.load().appRules["com.example.app"])
    }

    func testValueAt() {
        let c = Config()
        XCTAssertEqual(ConfigAPI.value(at: "wm.gapsIn", in: c) as? Double, c.wm.gapsIn)
        XCTAssertEqual(ConfigAPI.value(at: "general.mode", in: c) as? String, "full")
        XCTAssertNotNil(ConfigAPI.value(at: "wm", in: c) as? [String: Any])
        XCTAssertNotNil(ConfigAPI.value(at: "", in: c))
        XCTAssertNil(ConfigAPI.value(at: "wm.nope", in: c))
        var c2 = c
        c2.appRules["com.example.app"] = "float"
        XCTAssertEqual(ConfigAPI.value(at: "appRules.com.example.app", in: c2) as? String, "float")
    }
}
