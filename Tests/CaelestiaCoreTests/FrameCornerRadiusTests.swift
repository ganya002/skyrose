import XCTest
@testable import CaelestiaCore

/// `[frame] displayCornerRadius` and its per-display override: auto default, clamping, validation,
/// the bundled default file, and the comment-preserving config editor `frame calibrate` saves with.
final class FrameCornerRadiusTests: XCTestCase {
    // MARK: FrameConfig

    func testAutoIsTenOnBuiltInAppleSiliconAndZeroElsewhere() {
        let f = FrameConfig()
        XCTAssertEqual(f.displayCornerRadius, -1)
        XCTAssertEqual(f.cornerRadius(isBuiltIn: true, isAppleSilicon: true), 10)
        XCTAssertEqual(f.cornerRadius(isBuiltIn: false, isAppleSilicon: true), 0)
        XCTAssertEqual(f.cornerRadius(isBuiltIn: true, isAppleSilicon: false), 0)
        XCTAssertEqual(f.cornerRadius(isBuiltIn: false, isAppleSilicon: false), 0)
        XCTAssertEqual(FrameConfig.autoBuiltInRadius, 10)
    }

    func testExplicitValueWinsOverAutoEverywhere() {
        var f = FrameConfig()
        f.displayCornerRadius = 12.5
        for builtIn in [true, false] {
            for silicon in [true, false] {
                XCTAssertEqual(f.cornerRadius(isBuiltIn: builtIn, isAppleSilicon: silicon), 12.5)
            }
        }
        f.displayCornerRadius = 0
        XCTAssertEqual(f.cornerRadius(isBuiltIn: true, isAppleSilicon: true), 0, "an explicit 0 is square, not auto")
    }

    func testRadiusIsClampedToMax() {
        var f = FrameConfig()
        f.displayCornerRadius = 500
        XCTAssertEqual(f.cornerRadius(isBuiltIn: false, isAppleSilicon: true), FrameConfig.maxRadius)
        XCTAssertEqual(FrameConfig.maxRadius, 60)
    }

    func testPerDisplayOverrideWinsOverGlobal() {
        var c = Config()
        c.frame.displayCornerRadius = 8
        var o = DisplayOverride()
        o.displayCornerRadius = 11
        c.displays["A"] = c.displays["A"] ?? o
        c.displays["A"]?.displayCornerRadius = 11
        XCTAssertEqual(c.resolved(forDisplay: "A").frame.displayCornerRadius, 11)
        XCTAssertEqual(c.resolved(forDisplay: "B").frame.displayCornerRadius, 8)
        XCTAssertEqual(c.resolved(forDisplay: "A").frame.cornerRadius(isBuiltIn: false, isAppleSilicon: true), 11)
        // An override without the key leaves the global value alone.
        c.displays["C"] = DisplayOverride()
        XCTAssertEqual(c.resolved(forDisplay: "C").frame.displayCornerRadius, 8)
    }

    // MARK: Validation

    func testValidationRejectsOverMaxGlobalAndPerDisplay() {
        var c = Config()
        XCTAssertTrue(ConfigLoader.validate(c).isEmpty)
        c.frame.displayCornerRadius = 60
        XCTAssertTrue(ConfigLoader.validate(c).isEmpty, "60 is allowed")
        c.frame.displayCornerRadius = 61
        XCTAssertEqual(ConfigLoader.validate(c).map(\.path), ["frame.displayCornerRadius"])
        c.frame.displayCornerRadius = -1
        var o = DisplayOverride()
        o.displayCornerRadius = 60.5
        c.displays["X"] = o
        XCTAssertEqual(ConfigLoader.validate(c).map(\.path), ["displays.X.displayCornerRadius"])
        c.displays["X"]?.displayCornerRadius = 60
        XCTAssertTrue(ConfigLoader.validate(c).isEmpty)
    }

    func testValidationAcceptsNegativeAsAuto() {
        var c = Config()
        c.frame.displayCornerRadius = -5
        XCTAssertTrue(ConfigLoader.validate(c).isEmpty)
    }

    // MARK: Bundled default + parsing

    func testBundledDefaultKeepsAutoAndEqualsBuiltIn() throws {
        let c = try ConfigLoader.loadDefaultResource()
        XCTAssertEqual(c, Config())
        XCTAssertEqual(c.frame.displayCornerRadius, -1)
        let text = try ConfigLoader.defaultResourceText()
        XCTAssertTrue(text.contains("[frame]"))
    }

    func testParsesGlobalAndPerDisplayRadius() throws {
        let c = try ConfigLoader.parse(toml: """
        [frame]
        displayCornerRadius = 12.5

        [displays."X"]
        displayCornerRadius = 9
        """)
        XCTAssertEqual(c.frame.displayCornerRadius, 12.5)
        XCTAssertEqual(c.displays["X"]?.displayCornerRadius, 9)
        XCTAssertEqual(c.resolved(forDisplay: "X").frame.displayCornerRadius, 9)
        XCTAssertEqual(c.resolved(forDisplay: "Y").frame.displayCornerRadius, 12.5)
    }

    func testSerializeRoundTripsRadius() throws {
        var c = Config()
        c.frame.displayCornerRadius = 14.25
        c.displays["X"] = DisplayOverride()
        c.displays["X"]?.displayCornerRadius = 7
        XCTAssertEqual(try ConfigLoader.parse(toml: ConfigLoader.serialize(c)), c)
    }

    // MARK: ConfigFileEditor

    private func set(_ text: String, key: String = "displayCornerRadius", value: String = "10.0", table: String = "displays.\"X\"") -> String {
        ConfigFileEditor.setting(key, to: value, inTable: table, in: text)
    }

    func testEmptyTextAppendsTheTable() {
        XCTAssertEqual(set(""), "[displays.\"X\"]\ndisplayCornerRadius = 10.0\n")
    }

    func testMissingTableIsAppendedAfterABlankLine() {
        let out = set("[wm]\ngapsIn = 3\n")
        XCTAssertEqual(out, "[wm]\ngapsIn = 3\n\n[displays.\"X\"]\ndisplayCornerRadius = 10.0\n")
        // No extra blank line when the file already ends with one.
        XCTAssertEqual(set("[wm]\ngapsIn = 3\n\n"), "[wm]\ngapsIn = 3\n\n[displays.\"X\"]\ndisplayCornerRadius = 10.0\n")
    }

    func testKeyIsInsertedAfterTheLastKeyLineLeavingCommentsAndOtherTablesAlone() {
        let text = """
        # my config
        [displays."X"]
        gapsIn = 1
        # note about gapsOut
        gapsOut = 2
        # trailing comment

        [wm]
        gapsIn = 3

        """
        let out = set(text)
        XCTAssertEqual(out, """
        # my config
        [displays."X"]
        gapsIn = 1
        # note about gapsOut
        gapsOut = 2
        displayCornerRadius = 10.0
        # trailing comment

        [wm]
        gapsIn = 3

        """)
    }

    func testKeyIsInsertedRightAfterAnEmptyTableHeader() {
        XCTAssertEqual(set("[displays.\"X\"]\n[wm]\ngapsIn = 3\n"), "[displays.\"X\"]\ndisplayCornerRadius = 10.0\n[wm]\ngapsIn = 3\n")
    }

    func testExistingKeyIsReplacedAndItsTrailingCommentDropped() {
        let text = "[displays.\"X\"]\ndisplayCornerRadius = 3.0 # old\ngapsIn = 1\n[displays.\"Y\"]\ndisplayCornerRadius = 4.0\n"
        XCTAssertEqual(set(text, value: "9.5"), "[displays.\"X\"]\ndisplayCornerRadius = 9.5\ngapsIn = 1\n[displays.\"Y\"]\ndisplayCornerRadius = 4.0\n")
    }

    func testTableNameMatchingIgnoresSpacesAroundDotsButRespectsQuotes() {
        let spaced = "[displays . \"X\"]\ngapsIn = 1\n"
        XCTAssertEqual(set(spaced), "[displays . \"X\"]\ngapsIn = 1\ndisplayCornerRadius = 10.0\n")
        // Spaces inside quotes are part of the name: "X Y" is not "XY".
        let quoted = "[displays.\"X Y\"]\ngapsIn = 1\n"
        let out = set(quoted, table: "displays.\"XY\"")
        XCTAssertEqual(out, "[displays.\"X Y\"]\ngapsIn = 1\n\n[displays.\"XY\"]\ndisplayCornerRadius = 10.0\n")
        XCTAssertEqual(set(quoted, table: "displays.\"X Y\""), "[displays.\"X Y\"]\ngapsIn = 1\ndisplayCornerRadius = 10.0\n")
    }

    func testArrayTableHeadersAreNotMistakenForTheTable() {
        let text = "[[displays]]\nname = \"a\"\n"
        let out = set(text, table: "displays")
        XCTAssertEqual(out, "[[displays]]\nname = \"a\"\n\n[displays]\ndisplayCornerRadius = 10.0\n")
    }

    func testResultAlwaysEndsWithExactlyOneNewline() {
        for text in ["", "[wm]", "[wm]\n", "[wm]\ngapsIn = 1", "[displays.\"X\"]\n", "[displays.\"X\"]\ngapsIn = 1"] {
            let out = set(text)
            XCTAssertTrue(out.hasSuffix("\n"), text)
            XCTAssertFalse(out.hasSuffix("\n\n"), text)
        }
    }

    func testNumberFormatting() {
        XCTAssertEqual(ConfigFileEditor.number(10), "10.0")
        XCTAssertEqual(ConfigFileEditor.number(0), "0.0")
        XCTAssertEqual(ConfigFileEditor.number(10.25), "10.25")
        XCTAssertEqual(ConfigFileEditor.number(10.5), "10.5")
        XCTAssertEqual(ConfigFileEditor.number(10.123), "10.12")
        XCTAssertEqual(ConfigFileEditor.number(10.999), "11.0")
        XCTAssertEqual(ConfigFileEditor.displayTable("AB-12"), "displays.\"AB-12\"")
    }

    func testSetFileCreatesMissingFoldersAndEditsInPlace() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cfgedit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a/b/config.toml")
        try ConfigFileEditor.set("displayCornerRadius", to: "10.0", inTable: ConfigFileEditor.displayTable("X"), file: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "[displays.\"X\"]\ndisplayCornerRadius = 10.0\n")
        try ConfigFileEditor.set("displayCornerRadius", to: "11.5", inTable: ConfigFileEditor.displayTable("X"), file: file)
        try ConfigFileEditor.set("displayCornerRadius", to: "7.0", inTable: ConfigFileEditor.displayTable("Y"), file: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(text, "[displays.\"X\"]\ndisplayCornerRadius = 11.5\n\n[displays.\"Y\"]\ndisplayCornerRadius = 7.0\n")
        let c = try ConfigLoader.load(from: file)
        XCTAssertEqual(c.resolved(forDisplay: "X").frame.displayCornerRadius, 11.5)
        XCTAssertEqual(c.resolved(forDisplay: "Y").frame.displayCornerRadius, 7)
    }

    func testEditedUserFileParsesToTheIntendedResolvedValue() throws {
        let user = """
        # my settings
        [wm]
        gapsIn = 4 # tight

        [frame]
        displayCornerRadius = 8

        [displays."Built-in"]
        uiScale = 1.25
        """
        let out = ConfigFileEditor.setting("displayCornerRadius", to: ConfigFileEditor.number(10.456),
                                           inTable: ConfigFileEditor.displayTable("Built-in"), in: user)
        XCTAssertTrue(out.contains("# my settings"))
        XCTAssertTrue(out.contains("gapsIn = 4 # tight"))
        let c = try ConfigLoader.parse(toml: out)
        XCTAssertEqual(c.wm.gapsIn, 4)
        XCTAssertEqual(c.displays["Built-in"]?.uiScale, 1.25)
        XCTAssertEqual(c.resolved(forDisplay: "Built-in").frame.displayCornerRadius, 10.46)
        XCTAssertEqual(c.resolved(forDisplay: "Other").frame.displayCornerRadius, 8)
    }
}
