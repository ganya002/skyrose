import XCTest

@testable import CaelestiaCore

/// Per-app tile / float / auto rules: the rule book, `[appRules]` parsing and the config editor.
final class AppRuleTests: XCTestCase {
    private func standard(_ bundle: String) -> WindowDescriptor { WindowDescriptor(bundleID: bundle) }

    // MARK: AppRuleBook

    func testBuiltInFloatingList() {
        let book = AppRuleBook()
        for id in ["com.apple.systempreferences", "com.apple.calculator", "com.apple.archiveutility", "com.apple.FontBook"] {
            XCTAssertTrue(book.isBuiltInFloating(id), id)
            XCTAssertEqual(book.mode(for: id).mode, .float, id)
            XCTAssertEqual(book.mode(for: id).source, .builtIn, id)
            XCTAssertTrue(book.floats(standard(id), ruleFloat: nil), id)
        }
        XCTAssertEqual(AppRuleBook.builtInFloating["com.apple.systempreferences"], "System Settings")
        XCTAssertEqual(AppRuleBook.builtInFloating["com.apple.calculator"], "Calculator")
        XCTAssertFalse(book.isBuiltInFloating("com.apple.finder"))
        XCTAssertEqual(book.mode(for: "com.apple.finder").mode, .auto)
        XCTAssertEqual(book.mode(for: "com.apple.finder").source, .none)
    }

    func testLookupIsCaseInsensitive() {
        XCTAssertTrue(AppRuleBook().isBuiltInFloating("COM.APPLE.CALCULATOR"))
        let book = AppRuleBook(user: ["com.Example.App": .float])
        XCTAssertEqual(book.userMode(for: "com.example.app"), .float)
        XCTAssertEqual(book.mode(for: "COM.EXAMPLE.APP").source, .user)
        var changed = book
        changed.set(.tile, for: "com.EXAMPLE.app")
        XCTAssertEqual(changed.user.count, 1, "the existing key is reused, not duplicated")
        XCTAssertEqual(changed.userMode(for: "com.example.app"), .tile)
    }

    func testUserRuleOverridesTheBuiltInList() {
        var book = AppRuleBook()
        book.set(.tile, for: "com.apple.calculator")
        XCTAssertEqual(book.mode(for: "com.apple.calculator").mode, .tile)
        XCTAssertEqual(book.mode(for: "com.apple.calculator").source, .user)
        XCTAssertFalse(book.floats(standard("com.apple.calculator"), ruleFloat: nil))
    }

    func testSettingAutoRemovesTheUserRule() {
        var book = AppRuleBook(user: ["com.example.app": .float])
        book.set(.auto, for: "com.example.app")
        XCTAssertTrue(book.user.isEmpty)
        XCTAssertEqual(book.mode(for: "com.example.app").source, .none)
        // Back to the built-in default for built-in apps.
        book.set(.tile, for: "com.apple.calculator")
        book.set(.auto, for: "com.apple.calculator")
        XCTAssertEqual(book.mode(for: "com.apple.calculator").source, .builtIn)
        XCTAssertEqual(AppRuleBook(user: ["x": .auto]).user.count, 0, "auto is never stored")
    }

    func testFloatsSemantics() {
        let d = standard("com.example.app")
        let auto = AppRuleBook()
        XCTAssertFalse(auto.floats(d, ruleFloat: nil))
        XCTAssertFalse(auto.floats(d, ruleFloat: false))
        XCTAssertTrue(auto.floats(d, ruleFloat: true), "auto defers to rules.toml")
        let tile = AppRuleBook(user: ["com.example.app": .tile])
        XCTAssertFalse(tile.floats(d, ruleFloat: true), "tile beats a rules.toml float")
        XCTAssertFalse(tile.floats(d, ruleFloat: nil))
        let float = AppRuleBook(user: ["com.example.app": .float])
        XCTAssertTrue(float.floats(d, ruleFloat: nil))
        XCTAssertTrue(float.floats(d, ruleFloat: false))
    }

    func testDialogsSheetsFixedSizeAndNonStandardAlwaysFloat() {
        let tile = AppRuleBook(user: ["com.example.app": .tile])
        var dialog = standard("com.example.app")
        dialog.subrole = "AXDialog"
        XCTAssertTrue(tile.floats(dialog, ruleFloat: nil))
        var sheet = standard("com.example.app")
        sheet.role = "AXSheet"
        XCTAssertTrue(tile.floats(sheet, ruleFloat: nil))
        var modal = standard("com.example.app")
        modal.isModal = true
        XCTAssertTrue(tile.floats(modal, ruleFloat: nil))
        var fixed = standard("com.example.app")
        fixed.isResizable = false
        XCTAssertTrue(tile.floats(fixed, ruleFloat: nil))
        var pinned = standard("com.example.app")
        pinned.minSize = CGSize(width: 300, height: 200)
        pinned.maxSize = CGSize(width: 300, height: 200)
        XCTAssertTrue(tile.floats(pinned, ruleFloat: nil))
        var panel = standard("com.example.app")
        panel.subrole = "AXUnknown"
        XCTAssertTrue(tile.floats(panel, ruleFloat: nil))
        XCTAssertTrue(AppRuleBook().floats(dialog, ruleFloat: false))
    }

    func testConfigStringsRoundTrip() {
        let book = AppRuleBook(config: ["com.a": "float", "com.b": "TILE", "com.c": "auto", "com.d": "bogus"])
        XCTAssertEqual(book.user, ["com.a": .float, "com.b": .tile])
        XCTAssertEqual(book.configValue, ["com.a": "float", "com.b": "tile"])
    }

    // MARK: config.toml [appRules]

    func testAppRulesTableParsesQuotedBundleIDs() throws {
        let toml = """
            [appRules]
            "com.apple.finder" = "float"
            "com.apple.calculator" = "tile"
            plain = "auto"
            """
        let result = try ConfigLoader.parseDetailed(toml: toml)
        XCTAssertEqual(result.config.appRules["com.apple.finder"], "float")
        XCTAssertEqual(result.config.appRules["com.apple.calculator"], "tile")
        XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
        let book = result.config.appRuleBook
        XCTAssertEqual(book.userMode(for: "com.apple.finder"), .float)
        XCTAssertEqual(book.mode(for: "com.apple.calculator").mode, .tile)
    }

    func testDefaultConfigHasNoAppRules() {
        XCTAssertTrue(Config().appRules.isEmpty)
        XCTAssertEqual(Config().appRuleBook, AppRuleBook())
    }

    func testAppRulesSurviveSerialization() throws {
        var c = Config()
        c.appRules = ["com.apple.finder": "float", "org.mozilla.firefox": "tile"]
        let back = try ConfigLoader.parse(toml: ConfigLoader.serialize(c))
        XCTAssertEqual(back.appRules, c.appRules)
    }

    func testInvalidAppRuleValueIsRejectedByValidation() throws {
        var c = Config()
        c.appRules = ["com.apple.finder": "sideways", "com.ok": "TILE"]
        let issues = ConfigLoader.validate(c)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].path.hasPrefix("appRules"), issues[0].path)
        XCTAssertTrue(issues[0].message.contains("tile"))
        XCTAssertThrowsError(try ConfigLoader.parse(toml: "[appRules]\n\"com.apple.finder\" = \"sideways\"\n"))
    }

    // MARK: ConfigFileEditor

    func testTomlKeyBareVersusQuoted() {
        XCTAssertEqual(ConfigFileEditor.tomlKey("speed"), "speed")
        XCTAssertEqual(ConfigFileEditor.tomlKey("my-key_2"), "my-key_2")
        XCTAssertEqual(ConfigFileEditor.tomlKey("com.apple.finder"), "\"com.apple.finder\"")
        XCTAssertEqual(ConfigFileEditor.tomlKey("has space"), "\"has space\"")
        XCTAssertEqual(ConfigFileEditor.tomlKey("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(ConfigFileEditor.tomlKey(""), "\"\"")
    }

    func testSettingADottedBundleIDWritesAQuotedKeyAndReplacesItOnTheSecondWrite() throws {
        let value = ConfigFileEditor.string("float")
        var text = ConfigFileEditor.setting("com.apple.finder", to: value, inTable: "appRules", in: "")
        XCTAssertTrue(text.contains("[appRules]"))
        XCTAssertTrue(text.contains("\"com.apple.finder\" = \"float\""), text)
        text = ConfigFileEditor.setting("com.apple.finder", to: ConfigFileEditor.string("tile"), inTable: "appRules", in: text)
        XCTAssertEqual(text.components(separatedBy: "com.apple.finder").count - 1, 1, "replaced, not duplicated: \(text)")
        XCTAssertTrue(text.contains("\"com.apple.finder\" = \"tile\""))
        text = ConfigFileEditor.setting("org.mozilla.firefox", to: value, inTable: "appRules", in: text)
        let parsed = try ConfigLoader.parse(toml: text)
        XCTAssertEqual(parsed.appRules, ["com.apple.finder": "tile", "org.mozilla.firefox": "float"])
    }

    func testSettingKeepsOtherTablesAndComments() throws {
        let original = "# my config\n[wm]\ngapsIn = 7\n\n[appRules]\n# keep me\n\"com.a.b\" = \"float\"\n\n[bar]\nwidth = 50\n"
        let text = ConfigFileEditor.setting("com.c.d", to: ConfigFileEditor.string("tile"), inTable: "appRules", in: original)
        XCTAssertTrue(text.contains("# my config"))
        XCTAssertTrue(text.contains("# keep me"))
        let parsed = try ConfigLoader.parse(toml: text)
        XCTAssertEqual(parsed.wm.gapsIn, 7)
        XCTAssertEqual(parsed.bar.width, 50)
        XCTAssertEqual(parsed.appRules, ["com.a.b": "float", "com.c.d": "tile"])
    }

    func testRemovingDeletesOnlyThatKey() throws {
        let text = "[appRules]\n\"com.a.b\" = \"float\"\n\"com.c.d\" = \"tile\"\n\n[bar]\nwidth = 50\n"
        let removed = ConfigFileEditor.removing("com.a.b", inTable: "appRules", in: text)
        XCTAssertFalse(removed.contains("com.a.b"))
        let parsed = try ConfigLoader.parse(toml: removed)
        XCTAssertEqual(parsed.appRules, ["com.c.d": "tile"])
        XCTAssertEqual(parsed.bar.width, 50)
        XCTAssertEqual(ConfigFileEditor.removing("com.zzz", inTable: "appRules", in: text), text, "unknown key: unchanged")
        XCTAssertEqual(ConfigFileEditor.removing("com.a.b", inTable: "nope", in: text), text, "unknown table: unchanged")
    }

    func testRemoveFromFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try ConfigFileEditor.set("com.a.b", to: ConfigFileEditor.string("float"), inTable: "appRules", file: url)
        XCTAssertEqual(try ConfigLoader.load(from: url).appRules, ["com.a.b": "float"])
        try ConfigFileEditor.remove("com.a.b", inTable: "appRules", file: url)
        XCTAssertTrue(try ConfigLoader.load(from: url).appRules.isEmpty)
        XCTAssertNoThrow(try ConfigFileEditor.remove("x", inTable: "appRules", file: url.appendingPathExtension("missing")))
    }

    /// Live finding: setting a rule and clearing it again left an empty `[appRules]` header in
    /// the user's config.toml. The round trip must give the file back unchanged.
    func testSetThenClearLeavesTheFileAsItWas() {
        for original in ["[displays.\"X\"]\ndisplayCornerRadius = 0.0\n", "", "# mine\n[wm]\ngapsIn = 4\n\n[shell]\nx = 1\n"] {
            let set = ConfigFileEditor.setting("com.caelestia.mac.testwindows", to: "\"float\"", inTable: "appRules", in: original)
            XCTAssertTrue(set.contains("[appRules]"))
            let cleared = ConfigFileEditor.removing("com.caelestia.mac.testwindows", inTable: "appRules", in: set)
            XCTAssertEqual(cleared, original, "round trip of \(original.debugDescription)")
        }
        // A table with other keys keeps its header.
        let two = "[appRules]\n\"a.b\" = \"tile\"\n\"c.d\" = \"float\"\n"
        XCTAssertEqual(ConfigFileEditor.removing("a.b", inTable: "appRules", in: two), "[appRules]\n\"c.d\" = \"float\"\n")
    }
}
