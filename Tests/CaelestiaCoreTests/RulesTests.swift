import XCTest
import CoreGraphics
@testable import CaelestiaCore

/// Window rules from spec 4.5: the shipped defaults match the right Mac apps, TOML round-trips,
/// and floating frames come out sized and centred as Hyprland would place them.
final class RulesTests: XCTestCase {
    let rules = RuleSet.defaults
    let area = CGRect(x: 10, y: 43, width: 1450, height: 903)

    func effects(_ bundleID: String, title: String = "", subrole: String = "AXStandardWindow", category: String = "") -> RuleEffects {
        rules.effects(for: WindowDescriptor(bundleID: bundleID, title: title, subrole: subrole, category: category))
    }

    func testSerializedDefaultsRoundTrip() throws {
        let parsed = try RulesLoader.parse(toml: RulesLoader.serialize(rules))
        XCTAssertEqual(parsed.rules, rules.rules)
    }

    func testShippedTOMLMatchesBuiltInDefaults() throws {
        XCTAssertEqual(try RulesLoader.loadDefaultResource().rules, rules.rules)
    }

    func testEveryDefaultRuleValidates() {
        for rule in rules.rules {
            XCTAssertNoThrow(try RulesLoader.validate(rule), rule.id)
        }
    }

    func testSettingsAppsFloatAt70x80() throws {
        let e = effects("com.apple.systempreferences")
        XCTAssertEqual(e.float, true)
        XCTAssertEqual(e.sizeFraction, CGSize(width: 0.7, height: 0.8))
        let frame = try XCTUnwrap(resolvedFloatingFrame(effects: e, in: area, windowSize: CGSize(width: 100, height: 100)))
        XCTAssertEqual(frame.width, area.width * 0.7, accuracy: 1)
        XCTAssertEqual(frame.midX, area.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, area.midY, accuracy: 1)
    }

    func testUtilityAppsFloatAt50x60() {
        // Calculator now floats at its own size through the built-in app rule (AppRuleBook), not this rule.
        let e = effects("com.apple.ActivityMonitor")
        XCTAssertEqual(e.float, true)
        XCTAssertEqual(e.sizeFraction, CGSize(width: 0.5, height: 0.6))
        XCTAssertNil(effects("com.apple.calculator").sizeFraction)
        XCTAssertEqual(AppRuleBook().mode(for: "com.apple.calculator").mode, .float)
    }

    func testOpenSaveDialogsFloatAt60x70() {
        let e = effects("com.example.editor", title: "Save As")
        XCTAssertEqual(e.float, true)
        XCTAssertEqual(e.sizeFraction, CGSize(width: 0.6, height: 0.7))
    }

    func testBitwardenFloatsSmall() {
        let e = effects("com.bitwarden.desktop")
        XCTAssertEqual(e.float, true)
        XCTAssertEqual(e.sizeFraction, CGSize(width: 0.2, height: 0.54))
        let ext = effects("org.mozilla.firefox", title: "Extension: (Bitwarden Password Manager) - Bitwarden")
        XCTAssertEqual(ext.float, true)
    }

    func testPictureInPictureFloatsPinsAndMovesBottomRight() throws {
        for title in ["Picture-in-Picture", "Picture in picture"] {
            let e = effects("org.mozilla.firefox", title: title)
            XCTAssertEqual(e.float, true, title)
            XCTAssertEqual(e.pin, true, title)
            XCTAssertEqual(e.keepAspectRatio, true, title)
            XCTAssertNotNil(e.move, title)
        }
        let e = effects("org.mozilla.firefox", title: "Picture-in-Picture")
        let size = CGSize(width: 400, height: 225)
        let frame = try XCTUnwrap(resolvedFloatingFrame(effects: e, in: area, windowSize: size))
        XCTAssertEqual(frame.maxX, area.minX + area.width * 0.98, accuracy: 2)
        XCTAssertEqual(frame.maxY, area.minY + area.height * 0.97, accuracy: 2)
    }

    func testSpecialWorkspaceAssignments() {
        XCTAssertEqual(effects("com.spotify.client").workspace, "special:music")
        XCTAssertEqual(effects("com.apple.Music").workspace, "special:music")
        XCTAssertEqual(effects("com.hnc.Discord").workspace, "special:communication")
        XCTAssertEqual(effects("com.apple.MobileSMS").workspace, "special:communication")
        XCTAssertEqual(effects("com.apple.reminders").workspace, "special:todo")
    }

    func testOpaqueViewers() {
        for id in ["com.apple.Preview", "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc"] {
            XCTAssertEqual(effects(id).opacity, 1.0, id)
        }
    }

    func testGamesAreTaggedOpaqueAndInhibitIdle() {
        let r = rules.resolve(for: WindowDescriptor(bundleID: "com.valvesoftware.portal2", category: "public.app-category.action-games"))
        XCTAssertTrue(r.tags.contains("game"))
        XCTAssertEqual(r.effects.opacity, 1.0)
        XCTAssertEqual(r.effects.idleInhibit, true)
        XCTAssertEqual(r.effects.noAnim, true)
    }

    func testOrdinaryWindowsGetNoEffects() {
        XCTAssertEqual(effects("net.kovidgoyal.kitty", title: "~").float, nil)
        XCTAssertNil(effects("net.kovidgoyal.kitty", title: "~").workspace)
    }

    func testUserRulesOverrideDefaults() throws {
        let user = try RulesLoader.parse(toml: """
            [[rule]]
            id = "kitty-float"
            [rule.match]
            bundleID = "net.kovidgoyal.kitty"
            [rule.effects]
            float = true
            """)
        let merged = rules.merging(user)
        XCTAssertEqual(merged.effects(for: WindowDescriptor(bundleID: "net.kovidgoyal.kitty")).float, true)
    }
}
