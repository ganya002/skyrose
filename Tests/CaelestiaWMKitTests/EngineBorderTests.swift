import CaelestiaCore
import CaelestiaOverlay
@testable import CaelestiaWMKit
import CoreGraphics
import XCTest

@MainActor
final class FakeEngine: WindowEngine {
    let name = "fake"
    var onChange: (() -> Void)?
    var onFrames: (([UInt32: CGRect]) -> Void)?
    var state = EngineState()
    func start(config: Config, area: CGRect?) throws {}
    func apply(config: Config, area: CGRect?) {}
    var stopped: (@MainActor () -> Void)?
    func stop(then done: @escaping @MainActor () -> Void) { stopped = done }
    func perform(_ action: Action) -> Bool? { nil }
    var restored: [UInt32: String] = [:]
    func restore(workspaces: [UInt32: String]) { restored = workspaces }
}

@MainActor
final class EngineBorderTests: XCTestCase {
    func testBordersFollowTheEngine() {
        let h = Harness()
        let engine = FakeEngine()
        let decorations = TestDecorations()
        h.wm.engine = engine
        h.wm.decorations = decorations
        h.wm.start()
        let rest = CGRect(x: 60, y: 10, width: 400, height: 300)
        engine.state.windows = [
            EngineWindow(id: 1, bundleID: nil, title: "a", workspace: "1", display: nil, focused: true, floating: false,
                         visible: true, frame: rest),
            EngineWindow(id: 2, bundleID: nil, title: "parked", workspace: "2", display: nil, focused: false, floating: false,
                         visible: false, frame: rest),
        ]
        engine.onChange?()
        let first = try! XCTUnwrap(decorations.lastScene)
        XCTAssertEqual(first.borders.map(\.id), [1])
        XCTAssertEqual(first.borders.first?.frame, rest)
        XCTAssertEqual(first.borders.first?.isActive, true)

        let moving = CGRect(x: 100, y: 10, width: 400, height: 300)
        engine.onFrames?([1: moving])
        XCTAssertEqual(decorations.lastScene?.borders.first?.frame, moving)
        XCTAssertEqual(decorations.lastScene?.borders.first?.appear, .instant)
        engine.onFrames?([:])
        XCTAssertEqual(decorations.lastScene?.borders.first?.frame, rest)

        engine.state.windows[0].visible = false
        engine.onChange?()
        XCTAssertTrue(decorations.lastScene?.borders.isEmpty == true)
        XCTAssertEqual(decorations.lastScene?.vanish[1], .instant)
    }

    func testShutdownQuitsOnceTheEngineHasStopped() {
        let h = Harness()
        let engine = FakeEngine()
        h.wm.engine = engine
        h.wm.start()
        h.wm.shutdown()
        h.wm.shutdown()
        XCTAssertEqual(h.quitCount, 0, "quits only after the engine put the windows back")
        engine.stopped?()
        engine.stopped?()
        XCTAssertEqual(h.quitCount, 1)
    }

    func testQueriesReportTheEngineState() {
        let h = Harness()
        let engine = FakeEngine()
        h.wm.engine = engine
        h.wm.start()
        let display = h.wm.displays[0].id
        engine.state.shown = [display: "2"]
        engine.state.focusedDisplay = display
        engine.state.openSpecial = "term"
        var a = EngineWindow(id: 5, bundleID: "a.b", title: "A", workspace: "2", display: display, focused: true,
                             floating: false, visible: true, frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        a.pid = 42
        let b = EngineWindow(id: 6, bundleID: nil, title: "B", workspace: "special:term", display: display,
                             focused: false, floating: true)
        engine.state.windows = [a, b]

        let windows = h.wm.windowEntries()
        XCTAssertEqual(windows.map(\.title), ["A", "B"])
        XCTAssertEqual(windows[0].at, [10, 20])
        XCTAssertEqual(windows[0].pid, 42)
        XCTAssertEqual(windows[0].workspace.id, 2)
        XCTAssertEqual(windows[0].hidden, false)
        XCTAssertEqual(windows[1].hidden, true)
        XCTAssertEqual(windows[1].workspace.name, "special:term")

        let workspaces = h.wm.workspaceEntries()
        XCTAssertEqual(workspaces.map(\.name), ["2", "special:term"])
        XCTAssertEqual(workspaces.map(\.active), [true, false])
        XCTAssertEqual(workspaces[0].lastwindowtitle, "A")

        let monitor = h.wm.monitorEntries()[0]
        XCTAssertEqual(monitor.activeWorkspace.id, 2)
        XCTAssertEqual(monitor.specialWorkspace.name, "special:term")
        XCTAssertTrue(monitor.focused)
        XCTAssertEqual(h.wm.stateEntry().windowCount, 2)
    }

    func testTabbedWindowsGetOneBorderWithAGroupBar() {
        let h = Harness()
        let engine = FakeEngine()
        let decorations = TestDecorations()
        h.wm.engine = engine
        h.wm.decorations = decorations
        h.wm.start()
        let frame = CGRect(x: 60, y: 72, width: 400, height: 300)
        var front = EngineWindow(id: 1, bundleID: nil, title: "Front", workspace: "1", display: nil, focused: true,
                                 floating: false, visible: true, frame: frame)
        front.tabs = [2, 1]
        front.tabsLocked = true
        var back = EngineWindow(id: 2, bundleID: nil, title: "", workspace: "1", display: nil, focused: false,
                                floating: false, visible: true, frame: frame)
        back.tabs = [2, 1]
        back.tabBehind = true
        engine.state.windows = [front, back]
        engine.onChange?()
        let border = try! XCTUnwrap(decorations.lastScene?.borders.first)
        XCTAssertEqual(decorations.lastScene?.borders.count, 1)
        XCTAssertEqual(border.frame, CGRect(x: 60, y: 42, width: 400, height: 330), "takes in CatWM's tab strip")
        XCTAssertEqual(border.group, GroupBar(titles: ["window", "Front"], activeIndex: 1, isLocked: true))
    }
}
