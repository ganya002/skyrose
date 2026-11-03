import XCTest
@testable import CaelestiaCore

/// Config and scheme loaders: shipped resources agree with the built-in defaults and the spec
/// numbers, hot reload delivers changes and keeps the last good config on errors (spec 1.2, 1.5,
/// 3.2).
final class ConfigLoaderTests: XCTestCase {
    func testShippedConfigEqualsBuiltInDefaults() throws {
        XCTAssertEqual(try ConfigLoader.loadDefaultResource(), Config())
    }

    func testDefaultsMatchSpecGeometry() {
        let wm = Config().wm
        XCTAssertEqual(wm.gapsIn, 5)
        XCTAssertEqual(wm.gapsOut, 10)
        XCTAssertEqual(wm.gapsOutSingle, 20)
        XCTAssertEqual(wm.gapsWorkspaces, 20)
        XCTAssertEqual(wm.borderSize, 1)
        XCTAssertEqual(wm.windowRounding, 15)
        XCTAssertEqual(wm.popupRounding, 10)
        XCTAssertEqual(wm.windowOpacity, 0.94)
        XCTAssertEqual(wm.screenFrameInset, 10)
        XCTAssertTrue(wm.dwindle.preserveSplit)
        XCTAssertFalse(wm.dwindle.smartSplit)
        XCTAssertTrue(wm.dwindle.smartResizing)
        XCTAssertTrue(wm.specialWsCloseAny)
        let a = Config().appearance
        XCTAssertEqual(a.transparencyBase, 0.75)
        XCTAssertEqual(a.transparencyLayers, 0.35)
    }

    func testSerializeRoundTrips() throws {
        var c = Config()
        c.wm.gapsIn = 7
        c.appearance.theme = "catppuccin-mocha"
        XCTAssertEqual(try ConfigLoader.parse(toml: ConfigLoader.serialize(c)), c)
    }

    func testPartialFileKeepsDefaultsForMissingKeys() throws {
        let c = try ConfigLoader.parse(toml: "[wm]\ngapsOut = 14\n")
        XCTAssertEqual(c.wm.gapsOut, 14)
        XCTAssertEqual(c.wm.gapsIn, 5)
    }

    func testInvalidValuesAreRejected() {
        XCTAssertThrowsError(try ConfigLoader.parse(toml: "[wm]\ngapsIn = -5\n"))
        XCTAssertThrowsError(try ConfigLoader.parse(toml: "[wm\n"))
    }

    func testWatcherReloadsAndKeepsLastGoodOnError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        try Data("[wm]\ngapsIn = 5\n".utf8).write(to: url)

        final class Box: @unchecked Sendable {
            var events: [ConfigWatcher.Event] = []
        }
        let box = Box()
        let loaded = expectation(description: "loaded")
        let failed = expectation(description: "failed")
        let watcher = ConfigWatcher(url: url, debounce: 0.05) { event in
            box.events.append(event)
            switch event {
            case .loaded: loaded.fulfill()
            case .failed: failed.fulfill()
            }
        }
        XCTAssertTrue(watcher.start())
        defer { watcher.stop() }

        let start = Date()
        try Data("[wm]\ngapsIn = 8\n".utf8).write(to: url, options: .atomic)
        wait(for: [loaded], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "spec asks for ~200 ms; allow CI slack")
        XCTAssertEqual(watcher.lastGood.wm.gapsIn, 8)

        try Data("[wm\ngapsIn = ".utf8).write(to: url, options: .atomic)
        wait(for: [failed], timeout: 2)
        XCTAssertEqual(watcher.lastGood.wm.gapsIn, 8, "a broken file keeps the last good config")
        if case let .failed(_, lastGood)? = box.events.last {
            XCTAssertEqual(lastGood.wm.gapsIn, 8)
        } else {
            XCTFail("expected a failure event")
        }
    }
}

final class SchemeLoaderTests: XCTestCase {
    func testEveryBuiltInSchemeLoadsCompletely() throws {
        for name in SchemeLoader.builtInNames {
            let scheme = try XCTUnwrap(SchemeLoader.builtIn(named: name), name)
            XCTAssertEqual(scheme.missingRoles, [], name)
            XCTAssertEqual(scheme.missingTerminalColors, [], name)
        }
    }

    func testDynamicDarkMatchesSpecColours() throws {
        let s = try XCTUnwrap(SchemeLoader.builtIn(named: "caelestia-dynamic"))
        XCTAssertEqual(s[.primary].hex, "bac5ee")
        XCTAssertEqual(s[.surfaceContainer].hex, "181920")
        XCTAssertEqual(s[.onSurfaceVariant].hex, "a9aab5")
        XCTAssertEqual(s[.inversePrimary].hex, "525e81")
        XCTAssertEqual(s.term(1)?.hex, "947dff")
        XCTAssertTrue(s.isDark)
    }

    func testDerivedDecorationColours() throws {
        let s = try XCTUnwrap(SchemeLoader.builtIn(named: "caelestia-dynamic"))
        XCTAssertEqual(s.activeBorder.hexWithAlpha, "bac5eee6")
        XCTAssertEqual(s.inactiveBorder.hexWithAlpha, "a9aab511")
        XCTAssertEqual(s.windowShadow.hexWithAlpha, "525e8110")
        XCTAssertEqual(s.groupBarActive.hexWithAlpha, "bac5eed4")
        XCTAssertEqual(s.desktopBackground.hex, "181920")
    }

    func testTOMLRoundTrip() throws {
        let s = try XCTUnwrap(SchemeLoader.builtIn(named: "catppuccin-mocha"))
        XCTAssertEqual(try SchemeLoader.parse(toml: SchemeLoader.serialize(s)), s)
    }

    func testCaelestiaJSONFixtureParses() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/scheme.json")
        let s = try SchemeLoader.parseCaelestiaJSON(Data(contentsOf: url))
        XCTAssertNotNil(s["primary"])
    }

    func testAccentOverride() throws {
        let s = try XCTUnwrap(SchemeLoader.builtIn(named: "caelestia-dynamic")).withAccentOverride(hex: "ff8800")
        XCTAssertEqual(s[.primary].hex, "ff8800")
        let unchanged = try XCTUnwrap(SchemeLoader.builtIn(named: "caelestia-dynamic")).withAccentOverride(hex: "nope")
        XCTAssertEqual(unchanged[.primary].hex, "bac5ee")
    }

    func testHexParsing() {
        XCTAssertEqual(RGBA(hex: "#bac5ee")?.hex, "bac5ee")
        XCTAssertEqual(RGBA(hex: "bac5eee6")?.alpha ?? 0, Double(0xE6) / 255, accuracy: 1e-9)
        XCTAssertNil(RGBA(hex: "xyz"))
    }
}
