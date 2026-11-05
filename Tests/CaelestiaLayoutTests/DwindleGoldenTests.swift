import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaLayout

/// Golden numbers from Gabby's clients.json (spec 4.3 / 12.1) plus the coverage invariant behind
/// the Riko R4 "unused screen space" test.
final class DwindleGoldenTests: XCTestCase {
    /// 5120×1440 ultrawide with the 10 px Caelestia screen frame on every edge.
    let ultrawide = DisplayInfo(id: "uw", frame: CGRect(x: 0, y: 0, width: 5120, height: 1440))
        .usableArea(reserved: .uniform(10))

    func tree(_ count: Int, in area: CGRect) -> DwindleTree {
        var t = DwindleTree()
        for i in 1...count {
            // Hyprland focuses each new window, so the next one splits it.
            t.insert(WindowID(i), relativeTo: i > 1 ? WindowID(i - 1) : nil, in: area)
        }
        return t
    }

    func frames(_ t: DwindleTree, in area: CGRect, params: LayoutParams = LayoutParams()) -> [WindowID: CGRect] {
        Dictionary(uniqueKeysWithValues: t.layout(area: area, params: params).map { ($0.window, $0.frame) })
    }

    func testUsableAreaOfUltrawide() {
        XCTAssertEqual(ultrawide, CGRect(x: 10, y: 10, width: 5100, height: 1420))
    }

    func testTwoWindowsMatchClientsJSON() throws {
        let f = frames(tree(2, in: ultrawide), in: ultrawide)
        XCTAssertEqual(f[1], CGRect(x: 21, y: 21, width: 2533, height: 1398)) // grok-bot
        XCTAssertEqual(f[2], CGRect(x: 2566, y: 21, width: 2533, height: 1398)) // kitty
    }

    func testClientsJSONFixtureAgreesWithLayout() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/ref/clients.json")
        let clients = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let expected = clients.filter { ($0["floating"] as? Bool) == false }.compactMap { c -> CGRect? in
            guard let at = c["at"] as? [Double], let size = c["size"] as? [Double] else { return nil }
            return CGRect(x: at[0], y: at[1], width: size[0], height: size[1])
        }.sorted { $0.minX < $1.minX }
        XCTAssertEqual(expected.count, 2)
        XCTAssertEqual(frames(tree(2, in: ultrawide), in: ultrawide).values.sorted { $0.minX < $1.minX }, expected)
    }

    func testBorderOverlaySitsOutsideTheFrame() {
        let p = tree(2, in: ultrawide).layout(area: ultrawide, params: LayoutParams())
        XCTAssertEqual(p.first { $0.window == 1 }?.borderFrame, CGRect(x: 20, y: 20, width: 2535, height: 1400))
    }

    func testSingleWindowUsesGapsOut20() {
        let f = frames(tree(1, in: ultrawide), in: ultrawide)
        XCTAssertEqual(f[1], CGRect(x: 31, y: 31, width: 5058, height: 1378))
    }

    func testSingleWindowRuleOffOnSpecialWorkspaces() {
        var ws = Workspace(id: .special("special"), displayID: "uw")
        ws.addTiled(1, cursor: nil, area: ultrawide, config: DwindleConfig())
        let p = WorkspaceLayout.compute(ws, area: ultrawide, fullFrame: ultrawide, config: WMConfig())
        XCTAssertEqual(p.first?.frame, CGRect(x: 21, y: 21, width: 5078, height: 1398))
    }

    func testThreeWindowsSplitTheFocusedRightHalfByAspect() {
        let f = frames(tree(3, in: ultrawide), in: ultrawide)
        XCTAssertEqual(f[1], CGRect(x: 21, y: 21, width: 2533, height: 1398))
        // The right box is wider than tall → side by side. Hyprland partitions the area minus
        // gaps_out, so the outer tile is the wider one (capture geometry.txt n3: 1258 | 1263).
        XCTAssertEqual(f[2], CGRect(x: 2566, y: 21, width: 1258, height: 1398))
        XCTAssertEqual(f[3], CGRect(x: 3836, y: 21, width: 1263, height: 1398))
    }

    func testFourWindowsStackOnceSlotsAreTall() {
        let f = frames(tree(4, in: ultrawide), in: ultrawide)
        // Window 3's box is 1275×1420 (taller than wide) → stacked.
        XCTAssertEqual(f[3], CGRect(x: 3836, y: 21, width: 1263, height: 693))
        XCTAssertEqual(f[4], CGRect(x: 3836, y: 726, width: 1263, height: 693))
    }

    func testAirTwoWindows() {
        // 13" M4 Air with a visible 33 pt menu bar.
        let area = DisplayInfo(id: "air", frame: CGRect(x: 0, y: 0, width: 1470, height: 956), menuBarHeight: 33)
            .usableArea(reserved: .uniform(10))
        XCTAssertEqual(area, CGRect(x: 10, y: 43, width: 1450, height: 903))
        let f = frames(tree(2, in: area), in: area)
        XCTAssertEqual(f[1], CGRect(x: 21, y: 54, width: 708, height: 881))
        XCTAssertEqual(f[2], CGRect(x: 741, y: 54, width: 708, height: 881))
    }

    /// R4: for 1–6 tiled windows on every tested display size, the frames grown by border and
    /// gaps tile the usable area exactly (no holes, no overlaps).
    func testFramesPlusGapsCoverUsableAreaExactly() {
        let sizes: [CGSize] = [
            CGSize(width: 1470, height: 956), CGSize(width: 1710, height: 1112), CGSize(width: 1512, height: 982),
            CGSize(width: 1728, height: 1117), CGSize(width: 2560, height: 1440), CGSize(width: 5120, height: 1440),
        ]
        let params = LayoutParams()
        for size in sizes {
            for menuBar in [0.0, 33.0] {
                let area = DisplayInfo(id: "d", frame: CGRect(origin: .zero, size: size), menuBarHeight: menuBar)
                    .usableArea(reserved: .uniform(10))
                for n in 1...6 {
                    let placements = tree(n, in: area).layout(area: area, params: params)
                    XCTAssertEqual(placements.count, n)
                    let outer = n == 1 ? 20.0 : 10.0
                    var covered = 0.0
                    for p in placements {
                        // Grow each side by border + (gapsOut at the area edge, gapsIn elsewhere).
                        var r = p.frame.insetBy(dx: -params.borderSize, dy: -params.borderSize)
                        let left = abs(r.minX - area.minX - outer) < 0.5 ? outer : params.gapsIn
                        let top = abs(r.minY - area.minY - outer) < 0.5 ? outer : params.gapsIn
                        let right = abs(area.maxX - r.maxX - outer) < 0.5 ? outer : params.gapsIn
                        let bottom = abs(area.maxY - r.maxY - outer) < 0.5 ? outer : params.gapsIn
                        r = CGRect(x: r.minX - left, y: r.minY - top, width: r.width + left + right, height: r.height + top + bottom)
                        XCTAssertTrue(area.insetBy(dx: -1, dy: -1).contains(r), "\(size) n=\(n) \(p.window) escapes area")
                        covered += r.width * r.height
                    }
                    for (i, a) in placements.enumerated() {
                        for b in placements[(i + 1)...] {
                            XCTAssertFalse(a.frame.intersects(b.frame), "\(size) n=\(n) overlap \(a.window)/\(b.window)")
                        }
                    }
                    XCTAssertEqual(covered, area.width * area.height, accuracy: (area.width + area.height) * 2, "\(size) n=\(n)")
                }
            }
        }
    }

    func testLayoutIsDeterministicAndIdempotent() {
        let t = tree(5, in: ultrawide)
        XCTAssertEqual(t.layout(area: ultrawide, params: LayoutParams()), t.layout(area: ultrawide, params: LayoutParams()))
    }
}
