import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaLayout

/// Golden geometry from the 2026-11-05 Arch capture (`~/caelestia-ref/full-2026-11-05`,
/// `01-tiling/geometry.txt` and `ops-geometry.txt`; Hyprland 0.57, 5120×1440 at scale 1).
final class ArchParityLayoutTests: XCTestCase {
    /// The usable area: 5120×1440 minus the 10 px Caelestia frame on every edge.
    let area = CGRect(x: 10, y: 10, width: 5100, height: 1420)
    /// Where the pointer sat during the n1…n13 capture: every frame in geometry.txt is consistent
    /// with it (n3 and n5…n13 went to the left/top half, n2 and n4 to the right/bottom).
    let cursor = CGPoint(x: 2570, y: 730)

    /// Dwindle without the SkyRose minimum tile (Arch has none).
    var archDwindle: DwindleConfig {
        var d = DwindleConfig()
        d.minTileWidth = 0
        d.minTileHeight = 0
        return d
    }

    func frames(_ t: DwindleTree, params: LayoutParams = LayoutParams()) -> [WindowID: CGRect] {
        Dictionary(uniqueKeysWithValues: t.layout(area: area, params: params).map { ($0.window, $0.frame) })
    }

    func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

    /// geometry.txt n=1 … n=13, each new window splitting the focused (newest) one with the
    /// cursor at `cursor`.
    func testOpeningSequenceMatchesTheCaptureWindowByWindow() {
        let expected: [[WindowID: CGRect]] = [
            [1: r(31, 31, 5058, 1378)],
            [1: r(21, 21, 2533, 1398), 2: r(2566, 21, 2533, 1398)],
            [2: r(3836, 21, 1263, 1398), 3: r(2566, 21, 1258, 1398)],
            [3: r(2566, 21, 1258, 693), 4: r(2566, 726, 1258, 693)],
            [4: r(3201, 726, 623, 693), 5: r(2566, 726, 623, 693)],
            [5: r(2566, 1076, 623, 343), 6: r(2566, 726, 623, 338)],
            [6: r(2884, 726, 305, 338), 7: r(2566, 726, 306, 338)],
            [7: r(2566, 901, 306, 163), 8: r(2566, 726, 306, 163)],
            [8: r(2725, 726, 147, 163), 9: r(2566, 726, 147, 163)],
            [9: r(2566, 814, 147, 75), 10: r(2566, 726, 147, 76)],
            [10: r(2645, 726, 68, 76), 11: r(2566, 726, 67, 76)],
            [11: r(2566, 770, 67, 32), 12: r(2566, 726, 67, 32)],
            [12: r(2606, 726, 27, 32), 13: r(2566, 726, 28, 32)],
        ]
        var t = DwindleTree()
        for (i, step) in expected.enumerated() {
            let id = WindowID(i + 1)
            t.insert(id, relativeTo: i > 0 ? WindowID(i) : nil, cursor: cursor, in: area, config: archDwindle)
            let f = frames(t)
            for (w, frame) in step {
                XCTAssertEqual(f[w], frame, "n=\(i + 1) window \(w)")
            }
        }
    }

    func testCursorOutsideTheTargetTileGoesRightOrBottom() {
        var t = DwindleTree()
        t.insert(1, in: area, config: archDwindle)
        t.insert(2, relativeTo: 1, cursor: CGPoint(x: -500, y: -500), in: area, config: archDwindle)
        XCTAssertEqual(frames(t)[2], r(2566, 21, 2533, 1398))
        t.insert(3, relativeTo: 2, cursor: nil, in: area, config: archDwindle)
        XCTAssertEqual(frames(t)[3], r(3836, 21, 1263, 1398))
    }

    func testForceSplitOneAndTwoIgnoreTheCursor() {
        var d = archDwindle
        d.forceSplit = 2
        var t = DwindleTree()
        t.insert(1, in: area, config: d)
        t.insert(2, relativeTo: 1, cursor: CGPoint(x: 20, y: 20), in: area, config: d)
        XCTAssertEqual(frames(t)[2], r(2566, 21, 2533, 1398))
        d.forceSplit = 1
        var u = DwindleTree()
        u.insert(1, in: area, config: d)
        u.insert(2, relativeTo: 1, cursor: CGPoint(x: 5000, y: 1000), in: area, config: d)
        XCTAssertEqual(frames(u)[2], r(21, 21, 2533, 1398))
    }

    func testInFirstHalf() {
        let box = r(0, 0, 100, 50)
        XCTAssertTrue(DwindleTree.inFirstHalf(CGPoint(x: 50, y: 10), of: box, direction: .horizontal))
        XCTAssertFalse(DwindleTree.inFirstHalf(CGPoint(x: 51, y: 10), of: box, direction: .horizontal))
        XCTAssertTrue(DwindleTree.inFirstHalf(CGPoint(x: 90, y: 25), of: box, direction: .vertical))
        XCTAssertFalse(DwindleTree.inFirstHalf(CGPoint(x: 90, y: 26), of: box, direction: .vertical))
        XCTAssertFalse(DwindleTree.inFirstHalf(CGPoint(x: -1, y: 10), of: box, direction: .horizontal))
    }

    /// ops-geometry.txt base: 1 | (3 | 2), the focused pair is (3, 2).
    func opsBase() -> DwindleTree {
        var t = DwindleTree()
        t.insert(1, in: area, config: archDwindle)
        t.insert(2, relativeTo: 1, cursor: cursor, in: area, config: archDwindle)
        t.insert(3, relativeTo: 2, cursor: cursor, in: area, config: archDwindle)
        return t
    }

    func testBaseOfTheOpsCapture() {
        let f = frames(opsBase())
        XCTAssertEqual(f[1], r(21, 21, 2533, 1398))
        XCTAssertEqual(f[2], r(3836, 21, 1263, 1398))
        XCTAssertEqual(f[3], r(2566, 21, 1258, 1398))
    }

    func testToggleSplitAndBackMatchOps01And02() {
        var t = opsBase()
        XCTAssertTrue(t.toggleSplit(3))
        var f = frames(t)
        XCTAssertEqual(f[2], r(2566, 726, 2533, 693))
        XCTAssertEqual(f[3], r(2566, 21, 2533, 693))
        XCTAssertTrue(t.toggleSplit(3))
        f = frames(t)
        XCTAssertEqual(f[2], r(3836, 21, 1263, 1398))
        XCTAssertEqual(f[3], r(2566, 21, 1258, 1398))
    }

    func testSwapSplitMatchesOps03() {
        var t = opsBase()
        XCTAssertTrue(t.swapSplit(3))
        let f = frames(t)
        XCTAssertEqual(f[1], r(21, 21, 2533, 1398))
        XCTAssertEqual(f[2], r(2566, 21, 1258, 1398))
        XCTAssertEqual(f[3], r(3836, 21, 1263, 1398))
        var empty = DwindleTree()
        XCTAssertFalse(empty.swapSplit(1))
        var single = DwindleTree()
        single.insert(1, in: area)
        XCTAssertFalse(single.swapSplit(1), "the root has no pair")
    }

    func testPseudoMatchesOps08() {
        // ops08: slot 3836,21 1263×1398 → the window keeps 1248×1388, centred.
        XCTAssertEqual(WorkspaceLayout.pseudoFrame(CGSize(width: 1248, height: 1388), in: r(3836, 21, 1263, 1398)), r(3844, 26, 1248, 1388))
    }

    func testPseudoScalesDownToFit() {
        let slot = r(0, 0, 400, 300)
        // Too wide: scaled to the slot width, aspect kept, centred vertically.
        XCTAssertEqual(WorkspaceLayout.pseudoFrame(CGSize(width: 800, height: 400), in: slot), r(0, 50, 400, 200))
        // Too tall after the width scale: scaled to the height.
        XCTAssertEqual(WorkspaceLayout.pseudoFrame(CGSize(width: 800, height: 1200), in: slot), r(100, 0, 200, 300))
    }

    func testGroupBarReservesThirtyOne() {
        var t = opsBase()
        XCTAssertTrue(t.groupToggle(2, in: area))
        let p = t.layout(area: area, params: LayoutParams(groupBarHeight: 31))
        // ops16: 3836,21 1263×1398 → 3836,52 1263×1367.
        XCTAssertEqual(p.first { $0.window == 2 }?.frame, r(3836, 52, 1263, 1367))
    }

    // MARK: WorkspaceState (pseudo, float)

    func env() -> LayoutEnvironment {
        var wm = WMConfig()
        wm.dwindle = archDwindle
        return LayoutEnvironment(config: wm, areas: ["uw": area])
    }

    func opsState() -> WorkspaceState {
        var s = WorkspaceState()
        _ = s.ensureDisplay("uw")
        let e = env()
        s.addWindow(1, cursor: cursor, size: CGSize(width: 2530, height: 1380), env: e)
        s.addWindow(2, cursor: cursor, size: CGSize(width: 2530, height: 1380), env: e)
        s.addWindow(3, cursor: cursor, size: CGSize(width: 1248, height: 1388), env: e)
        return s
    }

    func placements(_ s: WorkspaceState) -> [WindowID: Placement] {
        let ws = s[s.workspace(of: 1)!]!
        let list = WorkspaceLayout.compute(ws, area: area, fullFrame: r(0, 0, 5120, 1440), config: env().config)
        return Dictionary(uniqueKeysWithValues: list.map { ($0.window, $0) })
    }

    func testTogglePseudoUsesTheNaturalSize() {
        var s = opsState()
        // The capture ran ops03 (swapsplit) before ops08, so window 3 sits in the 3836 slot.
        XCTAssertTrue(s.updateTree(of: 3) { $0.swapSplit(3) } ?? false)
        XCTAssertTrue(s.togglePseudo(3))
        XCTAssertTrue(s.isPseudo(3))
        let p = placements(s)
        XCTAssertEqual(p[3]?.frame, r(3844, 26, 1248, 1388))
        XCTAssertEqual(p[3]?.borderFrame, r(3843, 25, 1250, 1390), "the ring follows the pseudo frame")
        XCTAssertEqual(p[2]?.frame, r(2566, 21, 1258, 1398), "neighbours do not move")
        XCTAssertTrue(s.togglePseudo(3))
        XCTAssertEqual(placements(s)[3]?.frame, r(3836, 21, 1263, 1398), "ops09")
    }

    func testFloatCentresTheRememberedSizeOnTheTile() {
        var s = opsState()
        // ops21: window 2 (slot 2566,21 1258×1398 after the swap below) floats at 2530×1380
        // centred on its slot: 1930,30.
        XCTAssertTrue(s.updateTree(of: 2) { $0.swapSplit(2) } ?? false)
        XCTAssertTrue(s.setFloating(2, true, env: env()))
        XCTAssertEqual(s[s.workspace(of: 2)!]!.floating[2], r(1930, 30, 2530, 1380))
    }

    func testFloatIsKeptOnScreen() {
        var s = opsState()
        // A pseudotiled window floats at its own size, centred on its tile and on-screen.
        XCTAssertTrue(s.togglePseudo(3))
        XCTAssertTrue(s.setFloating(3, true, env: env()))
        let f = s[s.workspace(of: 3)!]!.floating[3]!
        XCTAssertTrue(area.contains(f), "\(f)")
        XCTAssertFalse(s.isPseudo(3), "floating drops pseudo")
    }

    // MARK: Minimum tile (SkyRose)

    func testMinimumTileSplitsTheLargestTileAndStacksWhenFull() {
        let air = CGRect(x: 10, y: 10, width: 1450, height: 936)
        var wm = WMConfig()
        wm.dwindle.minTileWidth = 120
        wm.dwindle.minTileHeight = 80
        let e = LayoutEnvironment(config: wm, areas: ["air": air])
        var s = WorkspaceState()
        _ = s.ensureDisplay("air")
        var stacked = 0
        for i in 1...150 {
            let id = WindowID(i)
            XCTAssertTrue(s.addWindow(id, cursor: CGPoint(x: 15, y: 15), size: CGSize(width: 600, height: 400), env: e))
            let ws = s[s.workspace(of: id)!]!
            XCTAssertFalse(ws.isFloating(id), "a full screen stacks; it does not float")
            if ws.tree.leaf(of: id)?.isGroup == true { stacked += 1 }
            let list = WorkspaceLayout.compute(ws, area: air, fullFrame: air, config: wm)
            let visible = list.filter { $0.kind == .tiled && !$0.hidden }
            for p in visible {
                XCTAssertGreaterThanOrEqual(p.frame.width, 120 - 0.5, "window \(p.window) after \(i)")
                XCTAssertGreaterThanOrEqual(p.frame.height, 80 - 0.5, "window \(p.window) after \(i)")
            }
            for a in visible.indices {
                for b in visible.indices where b > a {
                    XCTAssertFalse(WorkspaceLayout.overlaps(visible[a].frame, visible[b].frame), "overlap after \(i)")
                }
            }
        }
        XCTAssertGreaterThan(stacked, 0, "once the screen is full, new windows join a group")
    }

    func testNoMinimumMeansArchSlivers() {
        var t = DwindleTree()
        for i in 1...13 {
            t.insert(WindowID(i), relativeTo: i > 1 ? WindowID(i - 1) : nil, cursor: cursor, in: area, config: archDwindle,
                     enforceMinTile: true, tilePadding: 22)
        }
        XCTAssertEqual(frames(t)[12], r(2606, 726, 27, 32), "0 × 0 minimum = no limit")
    }

    func testSplitFits() {
        var d = DwindleConfig()
        d.minTileWidth = 120
        d.minTileHeight = 80
        XCTAssertTrue(DwindleTree.splitFits(r(0, 0, 284, 120), config: d, padding: 22))
        XCTAssertFalse(DwindleTree.splitFits(r(0, 0, 282, 120), config: d, padding: 22))
        XCTAssertFalse(DwindleTree.splitFits(r(0, 0, 400, 100), config: d, padding: 22), "too short")
    }
}
