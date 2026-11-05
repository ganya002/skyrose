import XCTest
@testable import CaelestiaCore

final class EffectiveConfigTests: XCTestCase {
    func testFullModeUnchanged() {
        var c = Config()
        c.displays["d1"] = DisplayOverride()
        XCTAssertEqual(c.effective, c)
        XCTAssertFalse(c.shellOff)
    }

    func testWMModeTurnsShellOff() {
        var c = Config()
        c.general.mode = .wm
        var o = DisplayOverride()
        o.barEnabled = true
        o.screenFrame = true
        c.displays["d1"] = o
        let e = c.effective
        XCTAssertTrue(c.shellOff)
        XCTAssertFalse(e.bar.enabled)
        XCTAssertFalse(e.wm.screenFrame)
        XCTAssertFalse(e.shell.enabled)
        XCTAssertEqual(e.displays["d1"]?.barEnabled, false)
        XCTAssertEqual(e.displays["d1"]?.screenFrame, false)
        XCTAssertFalse(e.input.interceptMediaKeys)
        XCTAssertEqual(e.wm.gapsIn, c.wm.gapsIn, "tiling settings stay")
    }

    func testShellDisabledTurnsBarOffButKeepsFrame() {
        var c = Config()
        c.shell.enabled = false
        let e = c.effective
        XCTAssertTrue(c.shellOff)
        XCTAssertFalse(e.bar.enabled)
        XCTAssertEqual(e.wm.screenFrame, c.wm.screenFrame)
    }

    func testOSDOffStopsMediaKeyInterception() {
        var c = Config()
        c.shell.osd = false
        XCTAssertFalse(c.effective.input.interceptMediaKeys)
        XCTAssertTrue(c.effective.bar.enabled)
        XCTAssertTrue(Config().effective.input.interceptMediaKeys)
    }

    func testDefaultTomlParsesGeneralAndShell() throws {
        let c = try ConfigLoader.loadDefaultResource()
        XCTAssertEqual(c.general.mode, .full)
        XCTAssertTrue(c.shell.enabled)
        XCTAssertTrue(c.shell.osd)
        let wm = try ConfigLoader.parse(toml: "[general]\nmode = \"wm\"\n[shell]\nosd = false\n")
        XCTAssertEqual(wm.general.mode, .wm)
        XCTAssertFalse(wm.shell.osd)
    }

    func testSchemeLegacyNames() {
        XCTAssertEqual(SchemeLoader.canonicalName("caelestia-default"), "skyrose-default")
        XCTAssertEqual(SchemeLoader.canonicalName("Caelestia-Dynamic"), "skyrose-dynamic")
        XCTAssertEqual(SchemeLoader.canonicalName("caelestia-dynamic-dark"), "skyrose-dynamic-dark")
        XCTAssertEqual(SchemeLoader.canonicalName("Custom"), "custom")
        XCTAssertNotNil(SchemeLoader.builtIn(named: "caelestia-default"))
        XCTAssertEqual(SchemeLoader.builtIn(named: "caelestia-default"), SchemeLoader.builtIn(named: "skyrose-default"))
        XCTAssertNotNil(SchemeLoader.builtInResourceURL(named: "caelestia-dynamic"))
    }
}
