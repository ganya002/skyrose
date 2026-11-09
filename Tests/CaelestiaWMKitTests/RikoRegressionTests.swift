import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaPlatform
import XCTest
@testable import CaelestiaWMKit

/// Riko regression suite R1–R6 (spec 12.2), headless: fake windows and displays stand in for
/// TestWindows.app and real screens. What needs real pixels or the shell (ScreenCaptureKit black
/// checks, overlay windows in CGWindowList, the bar's NSPanel) is covered here through the WM's
/// own model of it; the doc comment on each test says exactly what is and is not checked.
@MainActor
final class RikoRegressionTests: XCTestCase {
    /// Every managed window is either at its placement frame on-screen, or parked off-screen with
    /// a journal record; the journal holds exactly the parked windows; the border model is exactly
    /// the visible decorated windows.
    func assertConsistent(_ h: Harness, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let wm = h.wm
        var parked: Set<WindowID> = []
        for id in wm.managedWindowIDs {
            guard let w = h.system.windows[id] else {
                XCTFail("\(context): managed #\(id) no longer exists", file: file, line: line)
                continue
            }
            if let p = wm.visiblePlacements[id] {
                XCTAssertEqual(w.frame, p.frame, "\(context): #\(id) not at its placement", file: file, line: line)
                XCTAssertFalse(w.frame.isEmpty, "\(context): #\(id) empty frame", file: file, line: line)
                XCTAssertTrue(h.isOnScreen(w), "\(context): visible #\(id) off-screen", file: file, line: line)
            } else {
                parked.insert(id)
                XCTAssertTrue(wm.isParked(id), "\(context): hidden #\(id) not parked", file: file, line: line)
                XCTAssertFalse(h.isOnScreen(w), "\(context): hidden #\(id) still on-screen", file: file, line: line)
            }
        }
        XCTAssertEqual(Set(h.journal.records().map(\.windowID)), parked, "\(context): journal ≠ parked set", file: file, line: line)
        XCTAssertEqual(Set(wm.borderFrames.keys), Set(wm.visiblePlacements.keys).filter { wm.visiblePlacements[$0]?.kind != .fullscreen },
                       "\(context): border model ≠ visible windows", file: file, line: line)
    }

    // MARK: R1 black tiles

    /// R1 (headless part): after 200 open/close/switch cycles every tile the WM shows is a real,
    /// non-empty, on-screen window at its tile frame, and nothing the WM hides is left on-screen
    /// (a stale or empty rectangle is what reads as a black tile). NOT covered: the
    /// ScreenCaptureKit pixel sampling and the "panel has alpha within 1 frame" check, which need a
    /// screen and the shell.
    func testR1NoStaleOrEmptyTilesAfter200Cycles() {
        let h = Harness(displays: [TestDisplays.air, TestDisplays.external])
        h.system.existing("seed")
        h.start()
        // At most 8 windows open at once (spec 13 load: 20 windows over 5 workspaces). Far more
        // windows on one workspace makes dwindle hand out 0×0 slots, which real apps clamp.
        var open: [FakeWindow] = []
        for i in 0..<200 {
            let step = i % 5
            if step == 4 {
                h.wm.perform(Action(.workspaceFocus, index: i % 4 + 1))
            } else if step != 2, open.count < 8 {
                open.append(h.system.open("w\(i)", pid: pid_t(500 + i % 7)))
            } else if !open.isEmpty {
                h.system.destroy(open.removeFirst().windowID)
            }
            if i % 11 == 0 { h.wm.perform(Action(.specialToggle, name: "special")) }
            if i % 13 == 0, h.wm.state.focusedWindow != nil { h.wm.perform(Action(.workspaceMoveSilent, index: i % 3 + 1)) }
            h.settle()
            assertConsistent(h, "cycle \(i)")
        }
    }

    // MARK: R2 ghost overlays

    /// R2 (WM side): the border model the overlay layer draws from has exactly one entry per
    /// visible managed window after moves, closes, workspace switches, a display change, a SIGKILL'd
    /// app and sleep/wake. NOT covered: the overlay windows themselves (CaelestiaOverlay is not
    /// built yet), so "zero leftovers in CGWindowList after 1 s" is still open.
    func testR2BorderModelMatchesVisibleWindowsExactly() {
        let h = Harness(displays: [TestDisplays.air, TestDisplays.external])
        let a = h.system.existing("a")
        let b = h.system.existing("b", pid: 501)
        h.system.existing("c", pid: 502, frame: CGRect(x: 2000, y: 100, width: 800, height: 600))
        h.start()
        assertConsistent(h, "start")

        h.wm.state.recordFocus(a.windowID)
        h.wm.perform(Action(.windowSwap, direction: .right))
        h.settle()
        assertConsistent(h, "swap")

        // Workspace 2 lives on the external display (new displays get the next free number), so
        // use one that does not exist yet: it is created hidden on the Air.
        h.wm.perform(Action(.workspaceMoveSilent, index: 5))
        h.settle()
        assertConsistent(h, "move silent")
        XCTAssertNil(h.wm.borderFrames[a.windowID])

        h.wm.perform(Action(.workspaceFocus, index: 5))
        h.settle()
        assertConsistent(h, "switch")

        h.system.kill(pid: 501)  // SIGKILL: b vanishes with no close
        h.settle()
        assertConsistent(h, "kill -9")
        XCTAssertNil(h.wm.borderFrames[b.windowID])

        h.screens.change(to: [TestDisplays.air])
        h.settle()
        assertConsistent(h, "unplug")

        // Sleep/wake: displays vanish transiently, then come back.
        h.screens.change(to: [])
        h.settle()
        h.screens.change(to: [TestDisplays.air, TestDisplays.external])
        h.settle()
        assertConsistent(h, "wake")
    }

    // MARK: R3 flashing / retile loops

    /// R3: once settled, 10 s of idle (our own echoes arriving late, repeated focus reports, extra
    /// layout requests) produce 0 setFrame calls and ≤ 1 layout pass.
    func testR3IdleProducesNoFrameWrites() {
        let h = Harness()
        let ws = (0..<3).map { h.system.existing("w\($0)") }
        h.start()
        h.press("2", Harness.lopt)
        h.press("1", Harness.lopt)
        let before = h.wm.counters

        for w in ws { h.system.queue(.frameChanged(w.windowID, frame: w.frame, isEcho: true)) }
        h.system.queue(.focused(h.wm.state.focusedWindow))
        // A frame report within the 2 pt echo tolerance that the filter missed.
        h.system.queue(.frameChanged(ws[0].windowID, frame: ws[0].frame.offsetBy(dx: 1, dy: 0), isEcho: false))
        h.settle()
        h.wm.setNeedsLayout()
        h.settle()

        XCTAssertEqual(h.wm.counters.setFrameCalls, before.setFrameCalls)
        XCTAssertEqual(h.wm.counters.parkCalls, before.parkCalls)
        XCTAssertLessThanOrEqual(h.wm.counters.layoutPasses - before.layoutPasses, 1)
    }

    /// R3: an app whose minimum size is bigger than its slot converges (the min size is learned
    /// from the read-back, confirmed by a second read-back, and the split then gives it the room)
    /// and then stops. The two-read confirmation costs one pass, hence "<= 4" (was 3).
    func testR3MinSizeBiggerThanSlotConvergesAndStops() {
        let h = Harness()
        let a = h.system.existing("a")
        h.start()
        let b = h.system.open("stubborn") { $0.minSize = CGSize(width: 900, height: 0) }
        let passes = h.settle()
        XCTAssertLessThanOrEqual(passes, 4)
        XCTAssertEqual(h.wm.learnedMinSize(b.windowID)?.width, 900)
        XCTAssertGreaterThanOrEqual(b.frame.width, 900)
        let slot = h.wm.visiblePlacements[b.windowID]!.frame
        XCTAssertGreaterThanOrEqual(slot.width, 900, "the split gives the window its room")
        XCTAssertLessThanOrEqual(slot.width, 940)
        XCTAssertFalse(slot.intersects(h.wm.visiblePlacements[a.windowID]!.frame), "no overlap with the neighbour")
        XCTAssertFalse(h.wm.visiblePlacements[b.windowID]!.overflows)
        XCTAssertEqual(h.wm.counters.autoFloats, 0)

        let writes = a.setFrameCount + b.setFrameCount
        for _ in 0..<10 {
            h.wm.setNeedsLayout()
            h.settle()
        }
        XCTAssertEqual(a.setFrameCount + b.setFrameCount, writes, "no oscillation once converged")
    }

    /// R3: an app that snaps its window back after every write is re-applied at most
    /// `maxSnapBackRetries` times in a burst. It stays tiled. The reconcile pass puts it back
    /// once the cooldown has passed, and a second reconcile writes nothing.
    func testR3SnapBackAppIsNotFoughtForever() {
        let h = Harness()
        h.system.existing("a")
        let b = h.system.existing("snaps back")
        h.start()
        let slot = h.wm.visiblePlacements[b.windowID]!.frame
        let original = CGRect(x: 300, y: 300, width: 500, height: 300)
        let writesBefore = b.setFrameCount
        for _ in 0..<20 {
            b.appMoves(to: original)
            h.settle()
        }
        XCTAssertLessThanOrEqual(b.setFrameCount - writesBefore, WindowManager.maxSnapBackRetries + 1)
        XCTAssertEqual(h.wm.counters.snapBacks, WindowManager.maxSnapBackRetries)
        XCTAssertEqual(h.wm.counters.autoFloats, 0)
        XCTAssertFalse(h.wm.isFloating(b.windowID), "it stays tiled")
        XCTAssertEqual(b.frame, original, "the burst stops; the window is not dragged around")

        let stalled = b.setFrameCount
        b.appMoves(to: CGRect(x: 120, y: 140, width: 500, height: 300))
        h.settle()
        XCTAssertEqual(b.setFrameCount, stalled)

        h.clock.now.addTimeInterval(WindowManager.reconcileInterval + 0.1)
        h.wm.reconcileTiling()
        h.settle()
        XCTAssertFalse(WorkspaceLayout.overlaps(b.frame, h.wm.visiblePlacements.values.first { $0.window != b.windowID }?.frame ?? .null))
        XCTAssertEqual(b.frame, slot)
        let quiet = b.setFrameCount
        h.wm.reconcileTiling()
        h.settle()
        XCTAssertEqual(b.setFrameCount, quiet, "a second reconcile is a no-op")
    }

    /// R3: a window that ignores every write (read-back = old frame) does not loop either.
    func testR3WindowIgnoringWritesDoesNotLoop() {
        let h = Harness()
        h.system.existing("a")
        h.start()
        let w = h.system.open("frozen") { $0.ignoresWrites = true }
        XCTAssertLessThanOrEqual(h.settle(), 3)
        let writes = w.setFrameCount
        h.wm.setNeedsLayout()
        h.settle()
        XCTAssertEqual(w.setFrameCount, writes)
    }

    // MARK: R4 unused screen space

    /// R4 end to end: for 1–4 tiled windows on each tested size, with the menu bar/notch shown and
    /// hidden, the Dock shown and auto-hidden, and the bar persistent and auto-hidden, the frames
    /// the fake windows actually received + borders + gaps cover the usable area exactly, and the
    /// usable area is the display minus exactly what is reserved.
    func testR4AppliedFramesCoverTheUsableAreaExactly() {
        let sizes: [CGSize] = [
            CGSize(width: 1470, height: 956), CGSize(width: 1710, height: 1112), CGSize(width: 1512, height: 982),
            CGSize(width: 1728, height: 1117), CGSize(width: 2560, height: 1440), CGSize(width: 5120, height: 1440),
        ]
        for size in sizes {
            for menuBar in [0.0, 33.0, 38.0] {
                for dock in [0.0, 70.0] {
                    for persistentBar in [false, true] {
                        var config = Config()
                        config.bar.persistent = persistentBar
                        let display = DisplayInfo(
                            id: "d", frame: CGRect(origin: .zero, size: size), menuBarHeight: menuBar,
                            dockInsets: Insets(bottom: dock), isPrimary: true
                        )
                        let ctx = "\(Int(size.width))x\(Int(size.height)) menu \(menuBar) dock \(dock) bar \(persistentBar)"
                        let h = Harness(displays: [display], config: config)
                        let area = h.wm.usableArea(of: display)
                        XCTAssertEqual(area.minX, persistentBar ? 60 : 10, ctx)
                        XCTAssertEqual(area.minY, menuBar + 10, ctx)
                        XCTAssertEqual(area.maxX, size.width - 10, ctx)
                        XCTAssertEqual(area.maxY, size.height - dock - 10, ctx)
                        h.start()
                        var windows: [FakeWindow] = []
                        for n in 1...4 {
                            windows.append(h.system.open("w\(n)"))
                            h.settle()
                            assertCovers(windows.map(\.frame), area: area, context: "\(ctx) n=\(n)")
                        }
                    }
                }
            }
        }
    }

    func assertCovers(_ frames: [CGRect], area: CGRect, context: String, file: StaticString = #filePath, line: UInt = #line) {
        let gapsIn = 5.0
        let border = 1.0
        let outer = frames.count == 1 ? 20.0 : 10.0
        var covered = 0.0
        for f in frames {
            var r = f.insetBy(dx: -border, dy: -border)
            let left = abs(r.minX - area.minX - outer) < 0.5 ? outer : gapsIn
            let top = abs(r.minY - area.minY - outer) < 0.5 ? outer : gapsIn
            let right = abs(area.maxX - r.maxX - outer) < 0.5 ? outer : gapsIn
            let bottom = abs(area.maxY - r.maxY - outer) < 0.5 ? outer : gapsIn
            r = CGRect(x: r.minX - left, y: r.minY - top, width: r.width + left + right, height: r.height + top + bottom)
            XCTAssertTrue(area.insetBy(dx: -1, dy: -1).contains(r), "\(context): \(f) escapes \(area)", file: file, line: line)
            covered += r.width * r.height
        }
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] { XCTAssertFalse(a.intersects(b), "\(context): overlap", file: file, line: line) }
        }
        XCTAssertEqual(covered, area.width * area.height, accuracy: (area.width + area.height) * 2, context, file: file, line: line)
    }

    // MARK: R5 missing bar

    /// R5 (WM side): with a persistent bar, its width is reserved on EVERY display, at the
    /// configured edge, and recomputed after connect/disconnect, sleep/wake and a config change;
    /// with the Arch default (auto-hide) nothing is reserved. NOT covered: that the bar window is
    /// actually visible and correctly layered within 500 ms — the shell is not built yet.
    func testR5BarReservationOnEveryDisplay() {
        var config = Config()
        config.bar.persistent = true
        let h = Harness(displays: [TestDisplays.air], config: config)
        h.system.existing("a")
        h.system.existing("b", frame: CGRect(x: 2000, y: 100, width: 800, height: 600))
        h.start()

        func check(_ ctx: String) {
            for d in h.screens.displays {
                let area = h.wm.usableArea(of: d)
                XCTAssertEqual(area.minX - d.frame.minX, h.wm.config.bar.persistent ? 60 : 10, "\(ctx) \(d.id)")
                for (_, p) in h.wm.visiblePlacements where h.wm.state.display(of: p.window) == d.id && p.kind == .tiled {
                    XCTAssertGreaterThanOrEqual(p.borderFrame.minX, area.minX, "\(ctx): a tile covers the bar on \(d.id)")
                }
            }
        }
        check("launch")
        h.screens.change(to: [TestDisplays.air, TestDisplays.external])
        h.settle()
        check("connect")
        h.screens.change(to: [])
        h.screens.change(to: [TestDisplays.air, TestDisplays.external])
        h.settle()
        check("wake")
        h.screens.change(to: [TestDisplays.air])
        h.settle()
        check("disconnect")

        config.bar.edge = .right
        h.wm.apply(config: config)
        h.settle()
        let area = h.wm.usableArea(of: TestDisplays.air)
        XCTAssertEqual(area.minX, 10)
        XCTAssertEqual(TestDisplays.air.frame.maxX - area.maxX, 60, "the bar replaces the frame band: max, not the sum")

        h.wm.apply(config: Config())  // Arch default: auto-hide
        h.settle()
        check("auto-hide")
    }

    // MARK: R6 window safety

    /// R6: kill -9 with windows parked; the relaunched WM puts every window on-screen during
    /// `start()` (well inside 2 s) and empties the journal.
    func testR6CrashWithParkedWindowsRestoresEverythingOnRelaunch() {
        let first = Harness()
        let a = first.system.existing("a")
        let b = first.system.existing("b")
        first.start()
        first.wm.state.recordFocus(b.windowID)
        first.press("3", Harness.lopt | Harness.shift)  // b → ws 3, parked
        first.press("2", Harness.lopt)  // a parked too
        XCTAssertFalse(first.isOnScreen(a))
        XCTAssertFalse(first.isOnScreen(b))
        XCTAssertEqual(first.journal.records().count, 2)

        // SIGKILL: no shutdown, no cleanup. The windows stay where they were parked.
        let second = Harness(system: first.system, journalURL: first.journalURL)
        let started = Date()
        second.start()
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(second.wm.counters.restoredOnLaunch, 2)
        XCTAssertTrue(second.isOnScreen(a))
        XCTAssertTrue(second.isOnScreen(b))
        XCTAssertTrue(second.journal.records().isEmpty)
        XCTAssertEqual(Set(second.wm.managedWindowIDs), [a.windowID, b.windowID])
    }

    /// R6: a journaled window whose app quit while the WM was down is dropped, not retried forever.
    func testR6CrashJournalDropsWindowsThatNoLongerExist() {
        let first = Harness()
        first.system.existing("a")
        let gone = first.system.existing("gone", pid: 777)
        first.start()
        first.press("2", Harness.lopt)
        first.system.windows[gone.windowID] = nil
        let second = Harness(system: first.system, journalURL: first.journalURL)
        second.start()
        XCTAssertEqual(second.wm.counters.restoredOnLaunch, 1)
        XCTAssertTrue(second.journal.records().isEmpty)
    }

    /// R6 / spec 10.10: the panic chord ⌃⌥⌘⇧Esc (through the real matcher) restores every window
    /// and quits; afterwards no bind moves anything.
    func testR6PanicChordRestoresAllWindowsAndQuits() {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(b.windowID)
        h.press("4", Harness.lopt | Harness.shift)
        h.press("S", Harness.lopt)  // open the (empty) special too
        XCTAssertFalse(h.isOnScreen(b))

        let all = Harness.ctrl | Harness.lopt | Harness.lcmd | Harness.shift
        let fired = h.matcher.handle(.keyDown(code: 0x35, flags: all, isRepeat: false), now: 100).fired
        XCTAssertEqual(fired.map(\.bind.id), ["wm.panic"])
        h.wm.handle(fired: fired)

        XCTAssertEqual(h.quitCount, 1)
        XCTAssertFalse(h.wm.isManaging)
        XCTAssertTrue(h.isOnScreen(a))
        XCTAssertTrue(h.isOnScreen(b))
        XCTAssertTrue(h.journal.records().isEmpty)

        let writes = a.setFrameCount + b.setFrameCount
        h.press("2", Harness.lopt)
        XCTAssertEqual(a.setFrameCount + b.setFrameCount, writes)
    }

    /// R6: `wm.quit` and `wm.panic` over IPC restore every window before asking the daemon to exit.
    func testR6QuitAndPanicOverIPCRestoreEverything() {
        for command in [IPCCommand.wmQuit, .wmPanic] {
            let h = Harness()
            let a = h.system.existing("a")
            h.start()
            h.press("2", Harness.lopt)
            XCTAssertFalse(h.isOnScreen(a))
            let (response, quit) = h.wm.respond(to: IPCRequest(command))
            XCTAssertTrue(response.ok)
            XCTAssertTrue(quit, "\(command)")
            XCTAssertTrue(h.isOnScreen(a), "\(command)")
            XCTAssertTrue(h.journal.records().isEmpty, "\(command)")
        }
    }

    /// R6: if the journal cannot be written, the window is NOT parked (it stays visible).
    func testR6JournalWriteFailureNeverParks() {
        let h = Harness(journalURL: URL(fileURLWithPath: "/dev/null/caelestia-test/parked.json"))
        let a = h.system.existing("a")
        h.start()
        h.press("2", Harness.lopt)
        XCTAssertTrue(h.isOnScreen(a))
        XCTAssertFalse(h.wm.isParked(a.windowID))
        XCTAssertGreaterThan(h.wm.counters.journalWriteFailures, 0)
    }

    /// R6 "uninstall leaves zero windows off-screen": restoring (what uninstall triggers through
    /// `wm.quit`) also rescues a managed window that is off-screen without a journal record.
    func testR6RestoreLeavesZeroWindowsOffScreen() {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        let c = h.system.existing("c")
        h.start()
        h.wm.state.recordFocus(b.windowID)
        h.press("2", Harness.lopt | Harness.shift)
        c.frame = CGRect(x: 5000, y: 5000, width: 400, height: 300)  // lost by the app itself
        h.wm.shutdown()
        for w in [a, b, c] { XCTAssertTrue(h.isOnScreen(w), w.title) }
        XCTAssertTrue(h.journal.records().isEmpty)
    }
}
