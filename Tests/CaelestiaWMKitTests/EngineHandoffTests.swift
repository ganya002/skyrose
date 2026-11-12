import CaelestiaCore
import CaelestiaLayout
@testable import CaelestiaWMKit
import XCTest

@MainActor
final class EngineHandoffTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("handoff-\(UUID().uuidString).json")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    func testReadOnceThenGone() throws {
        EngineHandoff.write([7: "3", 8: "special:term"], to: url)
        XCTAssertEqual(EngineHandoff.take(from: url), [7: "3", 8: "special:term"])
        XCTAssertEqual(EngineHandoff.take(from: url), [:])
    }

    func testAnEarlierBootIsIgnored() throws {
        let old = EngineHandoff(bootTime: 1, workspaces: ["7": "3"])
        try JSONEncoder().encode(old).write(to: url)
        XCTAssertEqual(EngineHandoff.take(from: url), [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testOwnEngineQuitsIntoTheHandoffAndCatWMGetsIt() {
        let h = Harness()
        h.wm.handoffURL = url
        let a = h.system.existing("A")
        h.system.existing("B")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        _ = h.wm.state.moveWindow(a.windowID, to: .numbered(4), follow: false, env: h.wm.environment)
        h.settle()
        h.wm.shutdown()
        let saved = EngineHandoff.take(from: url)
        XCTAssertEqual(saved[a.windowID], "4")

        EngineHandoff.write(saved, to: url)
        let next = Harness()
        let engine = FakeEngine()
        next.wm.engine = engine
        next.wm.handoffURL = url
        next.wm.start()
        XCTAssertEqual(engine.restored[a.windowID], "4")
    }

    func testOwnEngineStartsFromAHandoff() {
        let h = Harness()
        let a = h.system.existing("A")
        h.system.existing("B")
        EngineHandoff.write([a.windowID: "5"], to: url)
        h.wm.handoffURL = url
        h.start()
        XCTAssertEqual(h.wm.state.workspace(of: a.windowID), .numbered(5))
        XCTAssertFalse(h.isOnScreen(a), "workspace 5 is hidden, so A is parked")
    }
}
