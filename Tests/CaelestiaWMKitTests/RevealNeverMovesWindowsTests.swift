import AppKit
import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
import XCTest
@testable import CaelestiaShell
@testable import CaelestiaWMKit

/// A pointer reveal of the bar or a drawer is an overlay: it must never retile, resize or move a
/// window (live finding: revealing the bar resized the tiles and dwindle flipped the split).
///
/// Part 1 drives the WM (`setBarRevealed`, `usableArea`); part 2 drives a real ShellController
/// (its panels are created, no services or monitors started) whose host forwards
/// `shellBarReservation` to the harness WM exactly like `ShellBridge` does.
@MainActor
final class RevealNeverMovesWindowsTests: XCTestCase {
    private var air: DisplayInfo { TestDisplays.air }
    private var ext: DisplayInfo { TestDisplays.external }

    // MARK: Helpers

    private struct Snapshot: Equatable {
        var frames: [WindowID: CGRect]
        var setFrames: Int
        var setPositions: Int
        var placements: [WindowID: CGRect]
    }

    private func snapshot(_ h: Harness, _ windows: [FakeWindow]) -> Snapshot {
        Snapshot(
            frames: Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0.frame) }),
            setFrames: windows.reduce(0) { $0 + $1.setFrameCount },
            setPositions: windows.reduce(0) { $0 + $1.setPositionCount },
            placements: h.wm.visiblePlacements.mapValues(\.frame)
        )
    }

    // MARK: WM level

    func testManyRevealsAcrossTwoDisplaysNeverTouchAWindow() {
        let h = Harness(displays: [air, ext])
        let windows = [
            h.system.existing("a1", frame: CGRect(x: 100, y: 100, width: 600, height: 400)),
            h.system.existing("a2", frame: CGRect(x: 300, y: 200, width: 600, height: 400)),
            h.system.existing("e1", frame: CGRect(x: 1600, y: 100, width: 800, height: 500)),
            h.system.existing("e2", frame: CGRect(x: 2000, y: 400, width: 800, height: 500)),
            h.system.existing("e3", frame: CGRect(x: 1700, y: 700, width: 700, height: 500)),
        ]
        h.start()
        let before = snapshot(h, windows)
        let passes = h.wm.counters.layoutPasses
        let sequence: [(String, Bool)] = [
            ("air", true), ("ext", true), ("air", false), ("air", true), ("air", true), ("ext", false),
            ("ext", false), ("ext", true), ("air", false), ("ext", false), ("air", true), ("ext", true),
        ]
        for (display, revealed) in sequence {
            h.wm.setBarRevealed(revealed, display: display)
            XCTAssertFalse(h.wm.needsLayout, "\(display) \(revealed)")
            XCTAssertEqual(h.settle(), 0)
            XCTAssertEqual(snapshot(h, windows), before, "\(display) \(revealed)")
        }
        XCTAssertEqual(h.wm.counters.layoutPasses, passes, "no layout pass at all")
        XCTAssertEqual(h.wm.barRevealed, ["air", "ext"], "the reveal is still recorded for queries")
    }

    func testRevealInterleavedWithRealLayoutPassesNeverChangesTheResult() {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        // The tiles with no reveal at all, for comparison.
        let reference = Harness()
        let ra = reference.system.existing("a")
        let rb = reference.system.existing("b")
        reference.start()

        h.wm.setBarRevealed(true, display: "air")
        let c = h.system.open("c")
        let rc = reference.system.open("c")
        h.settle()
        reference.settle()
        h.wm.setBarRevealed(false, display: "air")
        h.wm.setBarRevealed(true, display: "air")
        h.wm.setNeedsLayout()
        h.settle()
        reference.wm.setNeedsLayout()
        reference.settle()
        h.wm.setBarRevealed(false, display: "air")
        h.settle()
        XCTAssertEqual([h.frame(a), h.frame(b), h.frame(c)], [reference.frame(ra), reference.frame(rb), reference.frame(rc)],
                       "windows tiled with reveals going on end up exactly where they do without any")
    }

    func testFramesAreByteIdenticalAndNothingIsWrittenOverAReveal() {
        let h = Harness()
        let windows = (0..<4).map { h.system.existing("w\($0)", frame: CGRect(x: 50 * $0, y: 40 * $0 + 30, width: 500, height: 350)) }
        h.start()
        let writes = windows.map { $0.setFrameCount + $0.setPositionCount }
        let frames = windows.map(\.frame)
        for _ in 0..<5 {
            h.wm.setBarRevealed(true, display: "air")
            h.settle()
            h.wm.setBarRevealed(false, display: "air")
            h.settle()
        }
        XCTAssertEqual(windows.map(\.frame), frames)
        XCTAssertEqual(windows.map { $0.setFrameCount + $0.setPositionCount }, writes)
    }

    func testPersistentBarStillReservesItsWidthAndRevealChangesNothing() {
        var config = Config()
        config.bar.persistent = true
        let h = Harness(displays: [air, ext], config: config)
        let windows = [h.system.existing("a", frame: CGRect(x: 300, y: 100, width: 600, height: 400)),
                       h.system.existing("e", frame: CGRect(x: 1700, y: 100, width: 800, height: 500))]
        h.start()
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 48)
        XCTAssertEqual(h.wm.usableArea(of: ext).minX, ext.frame.minX + 48)
        for w in windows { XCTAssertGreaterThanOrEqual(w.frame.minX, 48) }
        let before = snapshot(h, windows)
        for revealed in [true, false, true] {
            h.wm.setBarRevealed(revealed, display: "air")
            h.wm.setBarRevealed(revealed, display: "ext")
            XCTAssertFalse(h.wm.needsLayout)
            XCTAssertEqual(h.settle(), 0)
            XCTAssertEqual(h.wm.usableArea(of: air).minX, 48)
            XCTAssertEqual(h.wm.usableArea(of: ext).minX, ext.frame.minX + 48)
            XCTAssertEqual(snapshot(h, windows), before)
        }
    }

    func testPersistentPerDisplayOverrideReservesOnlyThere() {
        var config = Config()
        var o = DisplayOverride()
        o.barPersistent = true
        config.displays["ext"] = o
        let h = Harness(displays: [air, ext], config: config)
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 10)
        XCTAssertEqual(h.wm.usableArea(of: ext).minX, ext.frame.minX + 48)
        h.wm.setBarRevealed(true, display: "air")
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 10)
    }

    func testUsableAreaIsIndependentOfTheRevealSet() {
        let h = Harness(displays: [air, ext])
        let a = h.wm.usableArea(of: air), e = h.wm.usableArea(of: ext)
        for set in [["air"], ["ext"], ["air", "ext"], []] as [[String]] {
            for d in ["air", "ext"] { h.wm.setBarRevealed(set.contains(d), display: d) }
            XCTAssertEqual(h.wm.usableArea(of: air), a)
            XCTAssertEqual(h.wm.usableArea(of: ext), e)
        }
    }

    // MARK: Shell level

    /// What `ShellBridge` does with the shell's bar reservation, plus a log of every call.
    @MainActor
    final class ForwardingHost: ShellHost {
        weak var wm: WindowManager?
        var reservations: [(display: String, reserved: Bool)] = []
        var workspaceFocus: [Int] = []
        var cycles: [Int] = []

        func shellFocusWorkspace(_ number: Int, display: String) { workspaceFocus.append(number) }
        func shellCycleWorkspace(_ delta: Int, display: String) { cycles.append(delta) }
        func shellBarReservation(display: String, reserved: Bool) {
            reservations.append((display, reserved))
            wm?.setBarRevealed(reserved, display: display)
        }
        var reserved: [String] { reservations.map { "\($0.display):\($0.reserved)" } }
    }

    private struct Rig {
        let h: Harness
        let host: ForwardingHost
        let shell: ShellController
        let windows: [FakeWindow]
    }

    private func rig(displays: [DisplayInfo] = [TestDisplays.air], persistent: Bool = false) -> Rig {
        var config = Config()
        config.bar.persistent = persistent
        let h = Harness(displays: displays, config: config)
        var windows: [FakeWindow] = []
        for (i, d) in displays.enumerated() {
            for n in 0..<2 {
                windows.append(h.system.existing("w\(i)\(n)", frame: CGRect(x: d.frame.minX + 100 + Double(n) * 120, y: 100, width: 500, height: 400)))
            }
        }
        h.start()
        let host = ForwardingHost()
        host.wm = h.wm
        let state = ShellState(scheme: ShellTheme.gabby.scheme, config: config, animations: AnimationTable.gabbySpringy,
                               displays: displays, converter: CoordinateConverter(primaryHeight: 956))
        let shell = ShellController(state: state, host: host)
        shell.start(services: false)
        return Rig(h: h, host: host, shell: shell, windows: windows)
    }

    /// Settles the harness and asserts nothing about the windows changed since `before`.
    private func assertUntouched(_ r: Rig, _ before: Snapshot, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(r.h.wm.needsLayout, "\(what): a layout was scheduled", file: file, line: line)
        XCTAssertEqual(r.h.settle(), 0, "\(what): a layout pass ran", file: file, line: line)
        XCTAssertEqual(snapshot(r.h, r.windows), before, "\(what): a window frame changed or was written", file: file, line: line)
    }

    /// Spins the main run loop until `condition` holds (or 2 s pass).
    private func wait(for condition: @autoclosure () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    func testPointerIntoTheHotZoneRevealsTheBarAndOutHidesItWithoutMovingWindows() throws {
        let r = rig()
        defer { r.shell.stop() }
        let before = snapshot(r.h, r.windows)
        let layout = try XCTUnwrap(r.shell.layouts["air"])
        XCTAssertFalse(r.shell.visibility["air"]?.isShown ?? true)

        // Into the left band.
        r.shell.pointerMoved(CGPoint(x: layout.area.minX + 2, y: layout.area.midY))
        XCTAssertTrue(r.shell.visibility["air"]?.isShown ?? false, "the hot zone reveals the bar")
        XCTAssertEqual(r.host.reserved, ["air:true"], "the shell told the WM")
        XCTAssertEqual(r.h.wm.barRevealed, ["air"])
        assertUntouched(r, before, "reveal")

        // Wander over the bar itself: stays shown, still nothing moves.
        r.shell.pointerMoved(CGPoint(x: layout.area.minX + 20, y: layout.area.midY - 50))
        XCTAssertTrue(r.shell.visibility["air"]?.isShown ?? false)
        assertUntouched(r, before, "over the bar")

        // Out into the middle of the screen: the hide fires after the delay (timer on the run loop).
        r.shell.pointerMoved(CGPoint(x: layout.area.midX, y: layout.area.midY))
        wait(for: r.host.reservations.count >= 2)
        XCTAssertEqual(r.host.reserved, ["air:true", "air:false"])
        XCTAssertFalse(r.shell.visibility["air"]?.isShown ?? true)
        XCTAssertTrue(r.h.wm.barRevealed.isEmpty)
        assertUntouched(r, before, "hide")
    }

    func testRepeatedRevealHideCyclesOnTwoDisplaysNeverTouchWindows() throws {
        let r = rig(displays: [TestDisplays.air, TestDisplays.external])
        defer { r.shell.stop() }
        let before = snapshot(r.h, r.windows)
        for _ in 0..<4 {
            for id in ["air", "ext"] {
                let layout = try XCTUnwrap(r.shell.layouts[id])
                r.shell.pointerMoved(CGPoint(x: layout.area.minX + 1, y: layout.area.midY))
                XCTAssertTrue(r.shell.visibility[id]?.isShown ?? false)
                assertUntouched(r, before, "reveal \(id)")
                r.shell.setBarShown(false, display: id)
                XCTAssertFalse(r.shell.visibility[id]?.isShown ?? true)
                assertUntouched(r, before, "hide \(id)")
            }
        }
        XCTAssertEqual(r.host.reservations.count, 16)
        XCTAssertTrue(r.h.wm.barRevealed.isEmpty)
        XCTAssertEqual(r.h.wm.usableArea(of: TestDisplays.air).minX, 10)
    }

    func testPointerAtTheTopEdgeDoesNothing() throws {
        let r = rig(displays: [TestDisplays.air, TestDisplays.external])
        defer { r.shell.stop() }
        let before = snapshot(r.h, r.windows)
        for id in ["air", "ext"] {
            let layout = try XCTUnwrap(r.shell.layouts[id])
            // AppKit space is y-up: the top edge is maxY.
            for x in [layout.area.midX, layout.area.maxX - 30, layout.area.minX + 200] {
                for y in [layout.area.maxY, layout.area.maxY - 1, layout.area.maxY - 5, layout.area.maxY + 3] {
                    r.shell.pointerMoved(CGPoint(x: x, y: y))
                }
            }
            XCTAssertFalse(r.shell.visibility[id]?.isShown ?? true, "no top-edge reveal on \(id)")
            XCTAssertFalse(r.shell.barIsShown(id))
        }
        XCTAssertTrue(r.host.reservations.isEmpty, "nothing was reserved")
        XCTAssertTrue(r.host.workspaceFocus.isEmpty && r.host.cycles.isEmpty)
        XCTAssertTrue(r.h.wm.barRevealed.isEmpty)
        assertUntouched(r, before, "top edge")
    }

    func testTopLeftCornerRevealsLikeTheLeftEdgeAndStillRetilesNothing() throws {
        let r = rig()
        defer { r.shell.stop() }
        let before = snapshot(r.h, r.windows)
        let layout = try XCTUnwrap(r.shell.layouts["air"])
        r.shell.pointerMoved(CGPoint(x: layout.area.minX + 1, y: layout.area.maxY))
        XCTAssertEqual(r.host.reserved, ["air:true"])
        assertUntouched(r, before, "corner")
    }

    func testPersistentBarNeverTellsTheWMAnythingOnPointerMoves() throws {
        let r = rig(persistent: true)
        defer { r.shell.stop() }
        XCTAssertEqual(r.h.wm.usableArea(of: TestDisplays.air).minX, 48)
        let before = snapshot(r.h, r.windows)
        let layout = try XCTUnwrap(r.shell.layouts["air"])
        for p in [CGPoint(x: layout.area.minX + 1, y: layout.area.midY), CGPoint(x: layout.area.midX, y: layout.area.midY),
                  CGPoint(x: layout.area.midX, y: layout.area.maxY)] {
            r.shell.pointerMoved(p)
        }
        XCTAssertTrue(r.shell.visibility["air"]?.isShown ?? false)
        XCTAssertTrue(r.host.reservations.isEmpty)
        XCTAssertEqual(r.h.wm.usableArea(of: TestDisplays.air).minX, 48, "the persistent bar still reserves its width")
        assertUntouched(r, before, "persistent")
    }

    func testEveryDrawerOpensAndClosesWithoutMovingWindows() throws {
        let r = rig()
        defer { r.shell.stop() }
        let before = snapshot(r.h, r.windows)
        // The bar is revealed while the pointer is on it, as when a drawer is opened from it.
        let layout = try XCTUnwrap(r.shell.layouts["air"])
        r.shell.pointerMoved(CGPoint(x: layout.area.minX + 2, y: layout.area.midY))
        XCTAssertEqual(r.host.reserved, ["air:true"])

        for drawer in [Drawer.sidebar, .utilities, .dashboard, .launcher, .session, .wallpaper] {
            r.shell.open(drawer, display: "air")
            XCTAssertTrue(r.shell.isOpen(drawer) || drawer == .utilities || drawer == .sidebar, "\(drawer) opened")
            assertUntouched(r, before, "open \(drawer)")
            r.shell.toggle(drawer, display: "air")
            assertUntouched(r, before, "close \(drawer)")
            r.shell.closeAll()
        }
        // Toggling, switching between drawers and closing all in a row.
        for drawer in [Drawer.dashboard, .sidebar, .launcher, .session, .launcher, .dashboard] {
            r.shell.toggle(drawer, display: "air")
            assertUntouched(r, before, "toggle \(drawer)")
        }
        r.shell.closeAll()
        assertUntouched(r, before, "closeAll")
        XCTAssertTrue(r.host.workspaceFocus.isEmpty, "drawers never switch workspaces")
    }

    func testPopoutsOpenAndCloseWithoutMovingWindows() throws {
        let r = rig()
        defer { r.shell.stop() }
        let before = snapshot(r.h, r.windows)
        let layout = try XCTUnwrap(r.shell.layouts["air"])
        r.shell.pointerMoved(CGPoint(x: layout.area.minX + 2, y: layout.area.midY))
        for kind in PopoutKind.allCases {
            r.shell.openPopout(kind, display: "air", layout: layout, anchorMidY: layout.area.midY)
            XCTAssertEqual(r.shell.popoutKind, kind)
            assertUntouched(r, before, "popout \(kind)")
            // Pinned: moving off the bar does not hide it while the popout is up.
            r.shell.pointerMoved(CGPoint(x: layout.area.midX, y: layout.area.midY))
            assertUntouched(r, before, "pointer away with \(kind)")
            r.shell.closePopout()
            assertUntouched(r, before, "close popout \(kind)")
        }
        r.shell.statusIconClicked("audio", display: "air", windowMidY: layout.area.midY)
        assertUntouched(r, before, "status icon")
        r.shell.closePopout()
    }

    func testStoppingTheShellWithTheBarRevealedReleasesTheReservationOnly() throws {
        let r = rig()
        let before = snapshot(r.h, r.windows)
        let layout = try XCTUnwrap(r.shell.layouts["air"])
        r.shell.pointerMoved(CGPoint(x: layout.area.minX + 2, y: layout.area.midY))
        r.shell.stop()
        XCTAssertEqual(r.host.reserved, ["air:true", "air:false"])
        XCTAssertTrue(r.h.wm.barRevealed.isEmpty)
        assertUntouched(r, before, "stop")
    }
}
