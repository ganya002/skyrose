import CaelestiaCore
import CatWMKit
import CoreGraphics
import XCTest
@testable import SkyRoseCatWM

final class CatWMBridgeTests: XCTestCase {
    func testConfigMakesCatWMWorkTheSkyRoseWay() {
        var config = Config()
        config.wm.gapsIn = 5
        config.wm.focusFollowsMouse = false
        let text = CatWMConfigText.make(config, area: CGRect(x: 10, y: 60, width: 1420, height: 800),
                                        visible: CGRect(x: 0, y: 25, width: 1440, height: 875))
        XCTAssertTrue(text.contains("catwm.workspaces.parked = true"))
        XCTAssertTrue(text.contains("catwm.layouts = [\"dwindle\", \"floating\"]"))
        XCTAssertTrue(text.contains("catwm.gaps.size = 10"))
        XCTAssertTrue(text.contains("catwm.padding.top = 35"))
        XCTAssertTrue(text.contains("catwm.padding.left = 10"))
        XCTAssertTrue(text.contains("catwm.padding.bottom = 40"))
        XCTAssertTrue(text.contains("catwm.focus.followsMouse = false"))
        XCTAssertTrue(text.contains("catwm.lab.resizeAnimation = \"snapshot\""))
    }

    func testCatWMSettingsReachTheConfig() {
        var config = Config()
        config.wm.catwm.layouts = ["tall", "nonsense", "floating"]
        config.wm.catwm.floatingApps = ["com.apple.Calculator", "x\"y"]
        config.wm.catwm.dragToSwap = false
        config.wm.catwm.extra = "catwm.resizeStep = 10"
        let text = CatWMConfigText.make(config, area: nil, visible: nil)
        XCTAssertTrue(text.contains("catwm.layouts = [\"tall\", \"floating\"]"))
        XCTAssertTrue(text.contains("catwm.floating.apps = [\"com.apple.Calculator\", \"x\\\"y\"]"))
        XCTAssertTrue(text.contains("catwm.mouse.swapsWindows = false"))
        XCTAssertTrue(text.hasSuffix("catwm.resizeStep = 10\n"))
        config.wm.catwm.layouts = ["nonsense"]
        XCTAssertTrue(CatWMConfigText.make(config, area: nil, visible: nil).contains("catwm.layouts = [\"dwindle\"]"))
    }

    func testGameModeAndAnimationsOffStopMotion() {
        var config = Config()
        config.wm.gameMode = true
        let text = CatWMConfigText.make(config, area: nil, visible: nil)
        XCTAssertTrue(text.contains("catwm.motion.enabled = false"))
        XCTAssertTrue(text.contains("catwm.gaps.enabled = false"))
        XCTAssertFalse(text.contains("catwm.motion.duration"))
    }

    func testSnapshotStateReadsWindowsAndTheOpenSpecial() {
        let state = CatWMHost.state(
            windows: [["id": .int(7), "app": .string("a.b"), "title": .string("t"), "workspace": .string("2"),
                       "focused": .bool(true), "floating": .bool(false), "minimized": .bool(false),
                       "visible": .bool(true), "fullscreen": .bool(false),
                       "frame": ["x": .number(1), "y": .number(2), "width": .number(3), "height": .number(4)],
                       "tabs": [.int(9), .int(7)], "tabsLocked": .bool(true), "tabBehind": .bool(false)],
                      ["id": .int(8), "minimized": .bool(true)]],
            screens: [["uuid": .string("D"), "workspace": .string("2"), "focused": .bool(true),
                       "special": .string("special:term")]])
        XCTAssertEqual(state.windows.map(\.id), [7])
        XCTAssertEqual(state.windows.first?.frame, CGRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(state.windows.first?.visible, true)
        XCTAssertEqual(state.shown, ["D": "2"])
        XCTAssertEqual(state.focusedDisplay, "D")
        XCTAssertEqual(state.openSpecial, "term")
        XCTAssertEqual(state.windows.first?.tabs, [9, 7])
        XCTAssertEqual(state.windows.first?.tabsLocked, true)
    }

    func testFrameJSONBecomesARect() {
        XCTAssertEqual(CatWMHost.rect(["x": .number(1), "y": .int(2), "width": .number(3), "height": .number(4)]),
                       CGRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertNil(CatWMHost.rect(.null))
    }

    func testBindsMapToCatWMCommands() throws {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        func names(_ action: Action) -> [String]? {
            CatWMCommands.calls(for: action, area: area, perGroup: 10, current: "3")?.map(\.name)
        }
        XCTAssertEqual(names(Action(.workspaceFocus, index: 4)), ["workspace"])
        XCTAssertEqual(names(Action(.windowPin)), ["setfloating", "pin"])
        XCTAssertEqual(names(Action(.layoutToggleSplit)), ["layoutmsg"])
        XCTAssertEqual(names(Action(.groupLock)), ["lockactivegroup"])
        XCTAssertEqual(names(Action(.groupToggle)), ["togglegroup"])
        XCTAssertEqual(names(Action(.windowDrag)), [])
        XCTAssertNil(names(Action(.launcherToggle)))
        let group = try XCTUnwrap(CatWMCommands.calls(for: Action(.workspaceFocusGroup, group: 3), area: area,
                                                      perGroup: 10, current: nil)?.first)
        XCTAssertEqual(group.args["workspace"], .string("21"))
        let resize = try XCTUnwrap(CatWMCommands.calls(
            for: Action(.windowResize, args: ["axis": .string("width"), "delta": .double(10)]), area: area,
            perGroup: 10, current: nil)?.first)
        XCTAssertEqual(resize.args["size"], .string("100 0"))
        let out = try XCTUnwrap(CatWMCommands.calls(for: Action(.workspaceMoveOutOfSpecial), area: area,
                                                    perGroup: 10, current: "3")?.first)
        XCTAssertEqual(out.args["workspace"], .string("3"))
    }

    /// CatWM itself parses the generated text. The features stay off so the engine touches no window
    /// and installs no tap.
    @MainActor func testCatWMAcceptsTheGeneratedConfig() async throws {
        let text = CatWMConfigText.make(Config(), area: CGRect(x: 10, y: 40, width: 1400, height: 840),
                                        visible: CGRect(x: 0, y: 30, width: 1440, height: 870))
            .replacingOccurrences(of: "catwm.features.windows.tiling = true", with: "")
            .replacingOccurrences(of: "catwm.features.windows.tabGroups = true", with: "")
            .replacingOccurrences(of: "catwm.features.input.mouse = true", with: "")
        let engine = try CatWMEngine(name: "skyrose-test")
        try engine.start(config: .text(text))
        XCTAssertTrue(engine.snapshot().diagnostics.isEmpty, "\(engine.snapshot().diagnostics)")
        XCTAssertEqual(engine.options.first { $0.id == "workspaces.parked" }?.value, .bool(true))
        await engine.stop()
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/catwm/instances/skyrose-test")
        try? FileManager.default.removeItem(at: folder)
    }
}
