import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaLayout

/// Clamshell: closing the lid removes the built-in display (its workspaces move to the external);
/// opening it brings them back (Hyprland's last-monitor rule).
final class DisplayReturnTests: XCTestCase {
    let env = LayoutEnvironment(areas: [
        "ext": CGRect(x: 0, y: 0, width: 2560, height: 1440),
        "builtin": CGRect(x: 2560, y: 0, width: 1470, height: 956),
    ])

    /// ext shows ws1 (window 1); builtin has ws2 (window 2) and shows ws3 (window 3).
    func docked() -> WorkspaceState {
        var s = WorkspaceState()
        s.ensureDisplay("ext")
        s.addWindow(1, env: env)
        XCTAssertEqual(s.ensureDisplay("builtin"), 2)
        s.addWindow(2, to: .numbered(2), env: env)
        s.focusWorkspace(.numbered(3), display: "builtin")
        s.addWindow(3, to: .numbered(3), env: env)
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "builtin"), 3)
        return s
    }

    func testLidCloseAndOpenReturnsTheWorkspaces() {
        var s = docked()
        s.removeDisplay("builtin", movingTo: "ext")
        XCTAssertEqual(s.display(of: 2), "ext")
        XCTAssertEqual(s.display(of: 3), "ext")
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "ext"), 1, "the external keeps what it showed")

        XCTAssertEqual(s.ensureDisplay("builtin"), 3, "the built-in shows what it showed before")
        XCTAssertEqual(s.display(of: 2), "builtin")
        XCTAssertEqual(s.display(of: 3), "builtin")
        XCTAssertEqual(s.display(of: 1), "ext")
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "ext"), 1)
        XCTAssertNil(s.displayHomes)
        XCTAssertNil(s.homeActive)
    }

    func testExternalShowingAReturningWorkspaceFallsBackToItsOwn() {
        var s = docked()
        s.removeDisplay("builtin", movingTo: "ext")
        s.focusWorkspace(.numbered(3))
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "ext"), 3)
        s.ensureDisplay("builtin")
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "builtin"), 3)
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "ext"), 1, "lowest of its own")
        XCTAssertEqual(s.focusedDisplay, "builtin", "the focused window went with its workspace")
    }

    func testExternalWithNothingLeftGetsANewWorkspace() {
        var s = WorkspaceState()
        s.ensureDisplay("ext")  // ws1, empty
        s.ensureDisplay("builtin")  // ws2
        s.addWindow(2, to: .numbered(2), env: env)
        s.removeDisplay("builtin", movingTo: "ext")
        s.focusWorkspace(.numbered(2))  // empty ws1 is dropped
        XCTAssertNil(s[.numbered(1)])
        XCTAssertEqual(s.ensureDisplay("builtin"), 2)
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "ext"), 1)
        XCTAssertNotNil(s[.numbered(1)])
    }

    func testAWorkspaceClosedWhileAwayDoesNotComeBack() {
        var s = docked()
        s.removeDisplay("builtin", movingTo: "ext")
        s.removeWindow(2)
        XCTAssertNil(s[.numbered(2)])
        XCTAssertEqual(s.displayHomes, [3: "builtin"], "the closed workspace's home is forgotten")
        s.addWindow(9, to: .numbered(2), env: env)  // a new ws2 made on the external
        s.ensureDisplay("builtin")
        XCTAssertEqual(s.display(of: 9), "ext", "a recreated number stays where it was made")
        XCTAssertEqual(s.display(of: 3), "builtin")
    }

    func testWithoutHomesANewDisplayGetsTheNextFreeWorkspace() {
        var s = docked()
        XCTAssertEqual(s.ensureDisplay("third"), 2 + 2, "1–3 exist, so 4")
    }

    func testRestartWithTheLidClosedStillReturnsOnOpen() throws {
        let before = docked()
        var s = before.restored(keeping: [1, 2, 3], displays: ["ext"])
        // The snapshot (session.json) round-trips the homes.
        s = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(s.display(of: 3), "ext")
        XCTAssertEqual(s.ensureDisplay("builtin"), 3)
        XCTAssertEqual(s.display(of: 2), "builtin")
    }

    func testSnapshotsWithoutTheNewKeysStillDecode() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(docked())) as! [String: Any]
        json["displayHomes"] = nil
        json["homeActive"] = nil
        let s = try JSONDecoder().decode(WorkspaceState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(s.displayHomes)
    }
}
