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

    func testGameModeAndAnimationsOffStopMotion() {
        var config = Config()
        config.wm.gameMode = true
        let text = CatWMConfigText.make(config, area: nil, visible: nil)
        XCTAssertTrue(text.contains("catwm.motion.enabled = false"))
        XCTAssertTrue(text.contains("catwm.gaps.enabled = false"))
        XCTAssertFalse(text.contains("catwm.motion.duration"))
    }

    func testBindsMapToCatWMCommands() throws {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        func names(_ action: Action) -> [String]? {
            CatWMCommands.calls(for: action, area: area, perGroup: 10, current: "3")?.map(\.name)
        }
        XCTAssertEqual(names(Action(.workspaceFocus, index: 4)), ["workspace"])
        XCTAssertEqual(names(Action(.windowPin)), ["setfloating", "pin"])
        XCTAssertEqual(names(Action(.layoutToggleSplit)), ["layoutmsg"])
        XCTAssertEqual(names(Action(.groupLock)), [])
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
