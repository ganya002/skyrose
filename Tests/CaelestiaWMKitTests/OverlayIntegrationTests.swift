import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaOverlay
import CaelestiaPlatform
import XCTest
@testable import CaelestiaWMKit

/// A border surface that only records what it was asked to do.
@MainActor
final class FakeSurface: BorderSurface {
    static var next = 9000
    let windowNumber: Int
    var renders = 0
    var lastSample: BorderSample?
    var orderedAbove: [CGWindowID] = []
    var closed = false
    var renderedAfterClose = false

    init() {
        Self.next += 1
        windowNumber = Self.next
    }

    func render(_ sample: BorderSample, target: BorderTarget, style: OverlayStyle) {
        if closed { renderedAfterClose = true }
        renders += 1
        lastSample = sample
    }

    func order(above id: CGWindowID) { orderedAbove.append(id) }
    func close() { closed = true }
}

/// The real overlay controller over fake surfaces, plus a recording of every WM call. `holds`
/// decides whether workspace changes are held until `resumeTransition()`.
@MainActor
final class TestDecorations: WindowDecorations {
    var now: TimeInterval = 100
    lazy var controller = OverlayController(
        ticking: .manual, makeSurface: { [unowned self] in
            let s = FakeSurface()
            self.allSurfaces.append(s)
            return s
        }, clock: { [unowned self] in self.now }, realFrame: { [unowned self] id in self.realFrames[id] },
        onScreen: { [unowned self] ids in ids.subtracting(self.offSpace) }
    )
    var allSurfaces: [FakeSurface] = []
    var realFrames: [CGWindowID: CGRect] = [:]
    /// Managed windows on another native Space.
    var offSpace: Set<CGWindowID> = []
    var scenes: [OverlayScene] = []
    var externalMoves: [WindowID] = []
    var transitions: [[WorkspaceTransition]] = []
    var didChange = 0
    var removeAllCount = 0
    var debugSnapshots: [DebugSnapshot?] = []
    var holds = false
    var pendingResume: (() -> Void)?

    var lastScene: OverlayScene? { scenes.last }
    var surfaces: [CGWindowID: any BorderSurface] { controller.surfaces }

    func apply(_ scene: OverlayScene) {
        scenes.append(scene)
        controller.apply(scene)
    }

    func externalMove(_ id: WindowID) {
        externalMoves.append(id)
        controller.noteExternalMove(id)
    }

    func workspaceWillChange(_ transitions: [WorkspaceTransition], resume: @escaping () -> Void) -> Bool {
        self.transitions.append(transitions)
        if holds {
            pendingResume = resume
            return true
        }
        resume()  // synchronous resume must work too
        return true
    }

    func resumeTransition() {
        let r = pendingResume
        pendingResume = nil
        r?()
    }

    func workspaceDidChange() { didChange += 1 }

    func removeAll() {
        removeAllCount += 1
        controller.removeAll()
    }

    func debug(_ snapshot: DebugSnapshot?) { debugSnapshots.append(snapshot) }

    func overlayEntries() -> [OverlayQueryEntry] {
        controller.engine.borders.keys.sorted().map { id in
            OverlayQueryEntry(target: id, overlay: controller.windowNumbers[id] ?? 0, frame: controller.engine.borders[id]!.target.frame,
                              alpha: 1, active: controller.engine.borders[id]!.target.isActive, vanishing: false, group: false)
        }
    }

    /// Lets every animation finish (1 s, the R2 deadline) and ticks.
    func settleAnimations() {
        now += 1
        controller.tick(at: now)
    }
}

@MainActor
final class OverlayIntegrationTests: XCTestCase {
    private func harness(displays: [DisplayInfo] = [TestDisplays.air]) -> (Harness, TestDecorations) {
        let h = Harness(displays: displays)
        let d = TestDecorations()
        h.wm.decorations = d
        return (h, d)
    }

    /// The set the overlay must draw: every visible, non-fullscreen, decorated managed window
    /// that is on screen (not on another native Space).
    private func expected(_ h: Harness, _ d: TestDecorations) -> Set<CGWindowID> { Set(h.wm.borderFrames.keys).subtracting(d.offSpace) }

    /// R2 at the overlay-window level: surfaces == visible decorated windows, nothing else.
    private func assertNoGhosts(_ h: Harness, _ d: TestDecorations, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        d.settleAnimations()
        XCTAssertEqual(Set(d.surfaces.keys), expected(h, d), "surfaces vs visible windows (\(context))", file: file, line: line)
        XCTAssertEqual(d.controller.engine.shownIDs, Set(h.wm.borderFrames.keys), "engine vs scene (\(context))", file: file, line: line)
        for (id, s) in d.surfaces {
            let f = try? XCTUnwrap((s as? FakeSurface)?.lastSample?.frame)
            XCTAssertEqual(f, h.wm.borderFrames[id], "border \(id) drawn at its border frame (\(context))", file: file, line: line)
        }
        XCTAssertFalse(d.allSurfaces.contains { $0.renderedAfterClose }, "a closed surface was drawn again (\(context))", file: file, line: line)
        let open = d.allSurfaces.filter { !$0.closed }.count
        XCTAssertEqual(open, expected(h, d).count, "open surfaces (\(context))", file: file, line: line)
    }

    // MARK: Scene contents

    func testSceneHasOneActiveBorderPerVisibleWindowAndPopsInOnce() throws {
        let (h, d) = harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        let scene = try XCTUnwrap(d.lastScene)
        XCTAssertEqual(scene.ids, [a.windowID, b.windowID])
        XCTAssertEqual(scene.borders.filter(\.isActive).map(\.id), [h.wm.state.focusedWindow].compactMap { $0 })
        XCTAssertTrue(scene.borders.allSatisfy { $0.appear == .popIn })
        for t in scene.borders {
            XCTAssertEqual(t.frame, h.wm.borderFrames[t.id])
            // 1 pt border outside the window frame (spec 4.3 golden: overlay = frame grown by 1).
            XCTAssertEqual(t.frame, h.wm.visiblePlacements[t.id]?.frame.insetBy(dx: -1, dy: -1))
        }
        // Coming back from another workspace is instant, not a second pop-in.
        h.press("2", Harness.lopt)
        h.press("1", Harness.lopt)
        XCTAssertTrue(try XCTUnwrap(d.lastScene).borders.allSatisfy { $0.appear == .instant })
        assertNoGhosts(h, d, "after switches")
    }

    func testFocusChangeMovesTheActiveBorder() throws {
        let (h, d) = harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        _ = a.focus()
        h.settle()
        XCTAssertEqual(try XCTUnwrap(d.lastScene).borders.filter(\.isActive).map(\.id), [a.windowID])
        _ = b.focus()
        h.settle()
        XCTAssertEqual(try XCTUnwrap(d.lastScene).borders.filter(\.isActive).map(\.id), [b.windowID])
    }

    func testClosedAndMinimizedWindowsFadeOutHiddenOnesVanishAtOnce() throws {
        let (h, d) = harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        let c = h.system.existing("c")
        h.start()
        d.settleAnimations()

        h.system.destroy(a.windowID)
        h.settle()
        XCTAssertEqual(d.lastScene?.vanish[a.windowID], .fadeOut)
        XCTAssertNotNil(d.surfaces[a.windowID], "fading out, still drawn")
        d.settleAnimations()
        XCTAssertNil(d.surfaces[a.windowID], "gone after the fade")

        b.isMinimized = true
        h.system.queue(.minimized(b.windowID))
        h.settle()
        XCTAssertEqual(d.lastScene?.vanish[b.windowID], .fadeOut)

        h.wm.state.recordFocus(c.windowID)
        h.wm.perform(Action(.workspaceMoveSilent, index: 3))
        h.settle()
        XCTAssertEqual(d.lastScene?.vanish[c.windowID], .instant)
        XCTAssertNil(d.surfaces[c.windowID], "parked: the border goes in the same pass")

        // Restored from the Dock: a new pop-in.
        b.isMinimized = false
        h.system.queue(.deminiaturized(b.windowID))
        h.settle()
        XCTAssertEqual(d.lastScene?.borders.first { $0.id == b.windowID }?.appear, .popIn)
        assertNoGhosts(h, d, "end")
    }

    func testRetileAnimatesTheBorderAndNeverWritesTheWindowTwice() throws {
        let (h, d) = harness()
        let a = h.system.existing("a")
        h.start()
        d.settleAnimations()
        let before = h.wm.borderFrames[a.windowID]!
        h.system.open("b")
        h.settle()
        let after = h.wm.borderFrames[a.windowID]!
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(d.lastScene?.borders.first { $0.id == a.windowID }?.motion, .animate)
        // The border fades out in place (never between the old and the new frame); the window
        // itself was written once (Standard mode: real windows snap).
        d.now += 0.05
        d.controller.tick(at: d.now)
        let mid = try XCTUnwrap((d.surfaces[a.windowID] as? FakeSurface)?.lastSample)
        XCTAssertEqual(mid.frame, before, "not interpolated")
        XCTAssertLessThan(mid.alpha, 1)
        d.now += BorderAnimator.moveSettle
        d.controller.tick(at: d.now)
        XCTAssertEqual((d.surfaces[a.windowID] as? FakeSurface)?.lastSample?.frame, after, "revealed at the final frame")
        assertNoGhosts(h, d, "settled")
    }

    func testDraggedFloatingWindowIsTrackedOneToOne() throws {
        let (h, d) = harness()
        let a = h.system.existing("a")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        h.wm.perform(Action(.windowToggleFloat))
        h.settle()
        d.settleAnimations()
        let moved = CGRect(x: 300, y: 200, width: 500, height: 400)
        d.realFrames[a.windowID] = moved
        a.appMoves(to: moved)
        h.settle()
        XCTAssertEqual(d.externalMoves.last, a.windowID)
        XCTAssertEqual(h.wm.borderFrames[a.windowID], moved.insetBy(dx: -1, dy: -1), "the scene follows the floating window")
        // While the user drags the border stays hidden, then shows at the final frame.
        d.now += 0.016
        d.controller.tick(at: d.now)
        XCTAssertEqual((d.surfaces[a.windowID] as? FakeSurface)?.lastSample?.alpha ?? 1, 0.9, accuracy: 0.9, "fading out")
        d.now += BorderAnimator.moveSettle + 0.01
        d.controller.tick(at: d.now)
        XCTAssertEqual((d.surfaces[a.windowID] as? FakeSurface)?.lastSample?.frame, moved.insetBy(dx: -1, dy: -1),
                       "shown at the dragged window's frame once it is still")
    }

    func testGroupBarIsReservedAndDescribed() throws {
        let (h, d) = harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        h.wm.perform(Action(.groupToggle))
        h.settle()
        let border = try XCTUnwrap(d.lastScene?.borders.first { $0.id == a.windowID })
        let group = try XCTUnwrap(border.group)
        XCTAssertEqual(group.titles.first, "a")
        XCTAssertEqual(group.activeIndex, 0)
        let frame = try XCTUnwrap(h.wm.visiblePlacements[a.windowID]?.frame)
        let reserved = h.wm.config.wm.groupBarHeight + 2 * h.wm.config.wm.groupBarGaps
        XCTAssertEqual(frame.minY - border.frame.minY, 1 + reserved, "bar strip between the top border and the window")
        XCTAssertNotNil(d.lastScene?.borders.first { $0.id == b.windowID })
        assertNoGhosts(h, d, "group")
    }

    // MARK: Workspace slide gate

    func testWorkspaceSwitchIsHeldUntilTheSlideIsReady() throws {
        let (h, d) = harness()
        let a = h.system.existing("a")
        h.start()
        d.holds = true
        let writes = a.setFrameCount + a.setPositionCount
        h.wm.perform(Action(.workspaceFocus, index: 2))
        h.settle()
        XCTAssertEqual(d.transitions.last?.map(\.kind), [.horizontal(forward: true)])
        XCTAssertEqual(d.transitions.last?.first?.region, TestDisplays.air.usableArea(reserved: .zero))
        XCTAssertFalse(h.wm.isParked(a.windowID), "nothing moves before the outgoing still is up")
        XCTAssertEqual(a.setFrameCount + a.setPositionCount, writes)
        d.resumeTransition()
        h.settle()
        XCTAssertTrue(h.wm.isParked(a.windowID))
        XCTAssertEqual(d.didChange, 1)

        h.wm.perform(Action(.workspaceFocus, index: 1))
        h.settle()
        XCTAssertEqual(d.transitions.last?.map(\.kind), [.horizontal(forward: false)])
        d.resumeTransition()
        h.settle()
        XCTAssertFalse(h.wm.isParked(a.windowID))
        assertNoGhosts(h, d, "after slides")
    }

    func testAHeldSwitchNeverStallsTheLayout() {
        let (h, d) = harness()
        let a = h.system.existing("a")
        h.start()
        d.holds = true
        h.wm.perform(Action(.workspaceFocus, index: 2))
        h.settle()
        XCTAssertFalse(h.wm.isParked(a.windowID))
        // The overlay never resumes (crash, lost capture): the next pass after the hold limit runs.
        h.clock.now += WindowManager.maxTransitionHold + 0.01
        h.wm.setNeedsLayout()
        h.settle()
        XCTAssertTrue(h.wm.isParked(a.windowID))
        d.resumeTransition()  // a late resume is harmless
        h.settle()
        XCTAssertTrue(h.wm.isParked(a.windowID))
    }

    func testSpecialWorkspaceSlidesVertically() {
        let (h, d) = harness()
        h.system.existing("a")
        h.start()
        h.wm.perform(Action(.specialToggle, name: "special"))
        h.settle()
        XCTAssertEqual(d.transitions.last?.map(\.kind), [.specialIn])
        h.wm.perform(Action(.specialToggle, name: "special"))
        h.settle()
        XCTAssertEqual(d.transitions.last?.map(\.kind), [.specialOut])
    }

    // MARK: Riko R2 (overlay windows)

    /// R2: after moves, closes, workspace switches, display changes, a SIGKILL'd app and
    /// sleep/wake, the overlay holds exactly one surface per visible managed window 1 s later.
    func testR2NoGhostOverlaysAcrossEveryScenario() {
        let (h, d) = harness(displays: [TestDisplays.air, TestDisplays.external])
        let a = h.system.existing("a")
        let b = h.system.existing("b", pid: 501)
        h.system.existing("c", pid: 502, frame: CGRect(x: 2000, y: 100, width: 800, height: 600))
        h.start()
        assertNoGhosts(h, d, "start")

        h.wm.state.recordFocus(a.windowID)
        h.wm.perform(Action(.windowSwap, direction: .right))
        h.settle()
        assertNoGhosts(h, d, "swap")

        h.wm.perform(Action(.workspaceMoveSilent, index: 5))
        h.settle()
        assertNoGhosts(h, d, "move silent")

        h.wm.perform(Action(.workspaceFocus, index: 5))
        h.settle()
        assertNoGhosts(h, d, "switch")

        h.system.kill(pid: 501)
        h.settle()
        assertNoGhosts(h, d, "kill -9")
        XCTAssertNil(d.surfaces[b.windowID])

        h.screens.change(to: [TestDisplays.air])
        h.settle()
        assertNoGhosts(h, d, "unplug")

        h.screens.change(to: [])
        h.settle()
        h.screens.change(to: [TestDisplays.air, TestDisplays.external])
        h.settle()
        assertNoGhosts(h, d, "wake")

        h.wm.perform(Action(.windowFullscreen))
        h.settle()
        assertNoGhosts(h, d, "fullscreen (no border)")
    }

    /// R2 under churn: 300 random steps (open, close, kill, switch, move, minimize, float, group,
    /// focus) with the slide gate holding and resuming; after every step + 1 s there is no ghost.
    func testR2RandomChurnLeavesNoGhosts() {
        let (h, d) = harness(displays: [TestDisplays.air, TestDisplays.external])
        h.system.existing("seed")
        h.start()
        var rng = SplitMix(seed: 0xCAE1E57)
        var open: [FakeWindow] = []
        for i in 0..<300 {
            d.holds = rng.next() % 3 == 0
            switch rng.next() % 10 {
            case 0, 1: if open.count < 8 { open.append(h.system.open("w\(i)", pid: pid_t(600 + Int(rng.next() % 5)))) }
            case 2: if !open.isEmpty { h.system.destroy(open.remove(at: Int(rng.next() % UInt64(open.count))).windowID) }
            case 3: h.wm.perform(Action(.workspaceFocus, index: Int(rng.next() % 4) + 1))
            case 4: if h.wm.state.focusedWindow != nil { h.wm.perform(Action(.workspaceMoveSilent, index: Int(rng.next() % 4) + 1)) }
            case 5:
                if let w = open.randomElement(using: &rng) {
                    w.isMinimized.toggle()
                    h.system.queue(w.isMinimized ? .minimized(w.windowID) : .deminiaturized(w.windowID))
                }
            case 6: h.wm.perform(Action(.windowToggleFloat))
            case 7: h.wm.perform(Action(.groupToggle))
            case 8: if let w = open.randomElement(using: &rng) { _ = w.focus() }
            default: h.wm.perform(Action(.specialToggle, name: "special"))
            }
            h.settle()
            d.resumeTransition()
            h.settle()
            assertNoGhosts(h, d, "step \(i)")
        }
    }

    /// Live finding: Finder/Firefox windows on another native Space are managed, and their
    /// borders came back on the current Space after ⌥2/⌥1. They must never be drawn here.
    func testR2WindowOnAnotherSpaceNeverGetsAVisibleBorder() {
        let (h, d) = harness()
        let here = h.system.existing("here")
        let away = h.system.existing("away")
        d.offSpace = [away.windowID]
        h.start()
        assertNoGhosts(h, d, "start")
        XCTAssertNil(d.surfaces[away.windowID])
        h.press("2", Harness.lopt)
        h.press("1", Harness.lopt)
        assertNoGhosts(h, d, "after ⌥2 ⌥1")
        XCTAssertNil(d.surfaces[away.windowID], "no ghost on the current Space")
        XCTAssertNotNil(d.surfaces[here.windowID])
        d.offSpace = []  // the user switches to that Space / drags the window here
        d.controller.refreshVisibility()
        assertNoGhosts(h, d, "window came on screen")
        XCTAssertNotNil(d.surfaces[away.windowID])
    }

    // MARK: Safety, IPC

    func testPanicRemovesEveryOverlay() {
        let (h, d) = harness()
        h.system.existing("a")
        h.system.existing("b")
        h.start()
        XCTAssertEqual(d.surfaces.count, 2)
        h.wm.panic()
        XCTAssertEqual(d.removeAllCount, 1)
        XCTAssertTrue(d.surfaces.isEmpty)
        XCTAssertTrue(d.allSurfaces.allSatisfy(\.closed))
    }

    func testGameModeDrawsNoBorders() {
        var config = Config()
        config.wm.gameMode = true
        let h = Harness(config: config)
        let d = TestDecorations()
        h.wm.decorations = d
        h.system.existing("a")
        h.start()
        XCTAssertTrue(h.wm.borderFrames.isEmpty)
        XCTAssertTrue(d.surfaces.isEmpty)
    }

    func testDebugOverlayAndOverlayQueryOverIPC() throws {
        let (h, d) = harness()
        let a = h.system.existing("a")
        h.start()
        let on = h.wm.respond(to: IPCRequest(.debugOverlay)).response
        XCTAssertEqual(on.result?.objectValue?["on"], .bool(true))
        let snapshot = try XCTUnwrap(d.debugSnapshots.last ?? nil)
        XCTAssertEqual(snapshot.displays.first?.usableArea, h.wm.usableArea(of: TestDisplays.air))
        XCTAssertEqual(snapshot.windows.count, 1)
        h.system.open("b")
        h.settle()
        XCTAssertEqual((d.debugSnapshots.last ?? nil)?.windows.count, 2, "refreshed on every layout pass")
        _ = h.wm.respond(to: IPCRequest(.debugOverlay, args: ["on": .bool(false)]))
        XCTAssertNil(d.debugSnapshots.last ?? DebugSnapshot(), "hidden")

        let entries = try XCTUnwrap(h.wm.respond(to: IPCRequest(.queryOverlays)).response.result).decode([OverlayQueryEntry].self)
        XCTAssertEqual(Set(entries.map(\.target)), [a.windowID, h.wm.managedWindowIDs.last!])
    }
}

/// Deterministic RNG for the churn test.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
final class SlideKeyTests: XCTestCase {
    /// The still taken when a workspace is left is reused on return only when nothing on it
    /// changed: the outgoing key of ⌥1→⌥2 equals the incoming key of ⌥2→⌥1, and a window
    /// opened on workspace 1 meanwhile breaks the match.
    func testContentKeysMatchOnlyWhenTheWorkspaceIsUnchanged() throws {
        let h = Harness()
        let d = TestDecorations()
        h.wm.decorations = d
        let a = h.system.existing("a")
        h.system.existing("b")
        h.start()
        _ = a.focus()
        h.settle()
        h.press("2", Harness.lopt)
        let leave1 = try XCTUnwrap(d.transitions.last?.first)
        h.press("1", Harness.lopt)
        let back1 = try XCTUnwrap(d.transitions.last?.first)
        XCTAssertEqual(leave1.outgoing, back1.incoming)
        XCTAssertTrue(leave1.outgoing.contains("|1|"), leave1.outgoing)
        XCTAssertNotEqual(leave1.outgoing, leave1.incoming)

        h.press("2", Harness.lopt)
        h.wm.perform(Action(.workspaceFocus, index: 1))
        h.settle()
        h.system.open("c")
        h.settle()
        h.press("2", Harness.lopt)
        let leaveAgain = try XCTUnwrap(d.transitions.last?.first)
        XCTAssertNotEqual(leaveAgain.outgoing, back1.incoming, "a new window changes the key")
    }
}
