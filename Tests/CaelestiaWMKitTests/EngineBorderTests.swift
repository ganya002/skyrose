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
}
