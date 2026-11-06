import CaelestiaCore
@testable import CaelestiaShell
import XCTest

@MainActor
final class DockTests: XCTestCase {
    func pill(_ id: Int, active: Bool = false, apps: [String] = []) -> WorkspacePill {
        WorkspacePill(id: id, name: String(id), occupied: !apps.isEmpty, active: active, windowCount: apps.count, apps: apps)
    }

    func testPillKeepsAtMostFiveIcons() {
        XCTAssertEqual(pill(1, apps: (0..<8).map { "a\($0)" }).apps.count, 5)
    }

    func testWorkspaceGrowsWithItsIcons() {
        XCTAssertEqual(WorkspacesColumn.height(of: pill(1)), WorkspacesColumn.shape)
        let two = WorkspacesColumn.height(of: pill(1, apps: ["a", "b"]))
        XCTAssertEqual(two, WorkspacesColumn.shape + 2 * (WorkspacesColumn.icon + WorkspacesColumn.iconGap) + 4)
    }

    func testActiveSpanCoversTheActiveWorkspaceAndItsIcons() throws {
        let pills = [pill(1, apps: ["a"]), pill(2), pill(3, active: true, apps: ["b", "c"]), pill(4)]
        let span = try XCTUnwrap(WorkspacesColumn.activeSpan(pills))
        let h1 = WorkspacesColumn.height(of: pills[0]), h2 = WorkspacesColumn.height(of: pills[1])
        let s = WorkspacesColumn.padding + h1 + h2 + 2 * WorkspacesColumn.spacing
        XCTAssertEqual(span.start, s, accuracy: 1e-9)
        XCTAssertEqual(span.end, s + WorkspacesColumn.height(of: pills[2]), accuracy: 1e-9)
        XCTAssertNil(WorkspacesColumn.activeSpan([pill(1), pill(2)]))
    }

    /// Caelestia activeTrail: the edge in the direction of travel leads, the other is 1.5× slower.
    func testTrailLeadsInTheDirectionOfTravel() {
        let down = WorkspacesColumn.trailDurations(goingUp: false, leading: 500)
        XCTAssertEqual(down.end, 500)
        XCTAssertEqual(down.start, 750)
        let up = WorkspacesColumn.trailDurations(goingUp: true, leading: 500)
        XCTAssertEqual(up.start, 500)
        XCTAssertEqual(up.end, 750)
    }

    func testPopoutSizesFollowCaelestia() {
        XCTAssertEqual(PopoutKind.activeWindow.width, 400)
        XCTAssertEqual(PopoutKind.audio.width, 320)
        XCTAssertEqual(PopoutKind.network.width, 320)
        XCTAssertEqual(PopoutKind.battery.width, 250)
        XCTAssertGreaterThan(PopoutModel().bodyHeight(for: .activeWindow), PopoutModel.previewHeight)
    }

    func testBarItemsMapToPopouts() {
        XCTAssertEqual(PopoutKind.forBarItem("activeWindow"), .activeWindow)
        XCTAssertEqual(PopoutKind.forBarItem("audio"), .audio)
        XCTAssertNil(PopoutKind.forBarItem("kbLayout"))
    }
}
