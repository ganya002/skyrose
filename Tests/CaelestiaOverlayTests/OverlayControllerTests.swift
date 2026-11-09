import CaelestiaCore
import CoreGraphics
import XCTest

@testable import CaelestiaOverlay

@MainActor
final class OverlayControllerTests: XCTestCase {
    private let clock = TestClock()
    private var made: [FakeSurface] = []
    private var real: [CGWindowID: CGRect] = [:]
    /// Targets on another native Space (not on screen).
    private var offSpace: Set<CGWindowID> = []
    private let a = CGRect(x: 0, y: 0, width: 200, height: 100)

    private func makeController(table: AnimationTable = .gabbySpringy) -> OverlayController {
        OverlayController(
            style: .gabby, table: table, ticking: .manual,
            makeSurface: { [unowned self] in
                let s = FakeSurface()
                self.made.append(s)
                return s
            },
            clock: { [clock] in clock.now },
            realFrame: { [unowned self] id in self.real[id] },
            onScreen: { [unowned self] ids in ids.subtracting(self.offSpace) })
    }

    private func fake(_ c: OverlayController, _ id: CGWindowID) -> FakeSurface { c.surfaces[id] as! FakeSurface }

    func testOneRenderedOrderedSurfacePerSceneID() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1), border(2), border(3)]))
        XCTAssertEqual(Set(c.surfaces.keys), [1, 2, 3])
        XCTAssertEqual(made.count, 3)
        for id: CGWindowID in [1, 2, 3] {
            let s = fake(c, id)
            XCTAssertFalse(s.renders.isEmpty)
            XCTAssertEqual(Set(s.orderedAbove), [id])
        }
    }

    func testInstantRemovalClosesSurfaceInSameCall() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1), border(2)]))
        let gone = fake(c, 1)
        c.apply(OverlayScene(borders: [border(2)], vanish: [1: .instant]))
        XCTAssertEqual(gone.closeCount, 1)
        XCTAssertEqual(Set(c.surfaces.keys), [2])
    }

    func testFadeOutClosesOnlyAfterWindowsOutDuration() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1, appear: .instant)]))
        let s = fake(c, 1)
        clock.now = 1
        c.apply(OverlayScene(vanish: [1: .fadeOut]))
        XCTAssertEqual(s.closeCount, 0)
        let d = c.table[.windowsOut].duration
        c.tick(at: 1 + d / 2)
        XCTAssertEqual(s.closeCount, 0)
        XCTAssertNotNil(c.surfaces[1])
        c.tick(at: 1 + d + 0.001)
        XCTAssertEqual(s.closeCount, 1)
        XCTAssertTrue(c.surfaces.isEmpty)
    }

    func testRandomizedScenesNeverLeaveGhosts() {
        var rng = SeededGenerator(seed: 0xC0FFEE)
        let c = makeController()
        var live: Set<CGWindowID> = []
        var last = OverlayScene()
        var vanishInfo: [CGWindowID: Vanish] = [:]
        for step in 0..<300 {
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: live.insert(CGWindowID.random(in: 1...12, using: &rng))
            case 1: if let id = live.randomElement(using: &rng) { live.remove(id) }
            default: break
            }
            var borders: [BorderTarget] = []
            for id in live.sorted() {
                let frame = CGRect(x: Double.random(in: 0...500, using: &rng), y: Double.random(in: 0...500, using: &rng),
                                   width: Double.random(in: 50...400, using: &rng), height: Double.random(in: 50...400, using: &rng))
                borders.append(border(id, frame, active: Bool.random(using: &rng),
                                      appear: Bool.random(using: &rng) ? .popIn : .instant,
                                      motion: Bool.random(using: &rng) ? .animate : .snap))
            }
            for id in 1...12 where !live.contains(CGWindowID(id)) {
                vanishInfo[CGWindowID(id)] = Bool.random(using: &rng) ? .fadeOut : .instant
            }
            last = OverlayScene(borders: borders, vanish: vanishInfo)
            clock.now += Double.random(in: 0...0.3, using: &rng)
            c.apply(last)
            if Bool.random(using: &rng) { c.tick(at: clock.now + Double.random(in: 0...0.2, using: &rng)) }
            XCTAssertTrue(live.isSubset(of: Set(c.surfaces.keys)), "step \(step)")
            XCTAssertEqual(c.engine.shownIDs, live, "step \(step)")
        }
        c.tick(at: clock.now + 1)
        XCTAssertEqual(Set(c.surfaces.keys), c.engine.shownIDs)
        XCTAssertEqual(Set(c.surfaces.keys), last.ids)
        for s in made {
            XCTAssertEqual(s.rendersAfterClose, 0)
            XCTAssertLessThanOrEqual(s.closeCount, 1)
        }
        XCTAssertEqual(made.filter { $0.closeCount == 0 }.count, c.surfaces.count)
    }

    func testRemoveAllClosesEverything() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1), border(2)]))
        c.removeAll()
        XCTAssertTrue(c.surfaces.isEmpty)
        XCTAssertTrue(c.engine.borders.isEmpty)
        XCTAssertTrue(made.allSatisfy { $0.closeCount == 1 })
    }

    func testDisablingClosesAndReEnablingReappliesLastScene() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1), border(2)]))
        c.isEnabled = false
        XCTAssertTrue(c.surfaces.isEmpty)
        XCTAssertEqual(made.count, 2)
        XCTAssertTrue(made.allSatisfy { $0.closeCount == 1 })
        c.apply(OverlayScene(borders: [border(3)]))
        XCTAssertTrue(c.surfaces.isEmpty, "disabled controller draws nothing")
        c.isEnabled = true
        XCTAssertEqual(Set(c.surfaces.keys), [3])
    }

    func testExternalMoveFollowsRealFrameGrownByBorder() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1, a, appear: .instant)]))
        real[1] = CGRect(x: 100, y: 200, width: 300, height: 150)
        c.noteExternalMove(1)
        c.tick(at: clock.now + 0.1)
        let w = c.style.borderWidth
        let followed = real[1]!.insetBy(dx: -w, dy: -w)
        XCTAssertEqual(c.engine.borders[1]?.target.frame, followed)
        let drawn = fake(c, 1).renders.last!
        XCTAssertEqual(drawn.sample.frame, followed, "the border stays on the window while it moves")
        XCTAssertEqual(drawn.sample.alpha, 1, accuracy: 1e-9)
    }

    func testExternalMoveWithGroupBarGrowsUpward() {
        let c = makeController()
        let group = GroupBar(titles: ["a", "b"], activeIndex: 0)
        c.apply(OverlayScene(borders: [border(1, a, appear: .instant, group: group)]))
        real[1] = CGRect(x: 100, y: 200, width: 300, height: 150)
        c.noteExternalMove(1)
        c.tick(at: clock.now + 0.1)
        let w = c.style.borderWidth
        let r = c.style.groupBarReserved
        let expected = CGRect(x: 100 - w, y: 200 - w - r, width: 300 + 2 * w, height: 150 + 2 * w + r)
        XCTAssertEqual(c.engine.borders[1]?.target.frame, expected)
    }

    func testTrackingStopsAfterTrackingWindow() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1, a, appear: .instant)]))
        real[1] = CGRect(x: 100, y: 200, width: 300, height: 150)
        c.noteExternalMove(1)
        XCTAssertTrue(c.needsTicks(at: clock.now + 0.1))
        c.tick(at: clock.now + 0.3)  // reveal + fade-in done by `late`
        let late = clock.now + OverlayController.trackingWindow + 0.1
        c.tick(at: late)
        XCTAssertFalse(c.needsTicks(at: late))
    }

    func testIdleBordersAreNotRerendered() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1, appear: .instant), border(2, appear: .instant)]))
        XCTAssertFalse(c.needsTicks(at: 0))
        let counts = [1, 2].map { fake(c, CGWindowID($0)).renders.count }
        for i in 1...5 { c.tick(at: Double(i)) }
        XCTAssertEqual([1, 2].map { fake(c, CGWindowID($0)).renders.count }, counts)
    }

    func testPopInNeedsTicksThenGoesIdle() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1)]))
        XCTAssertTrue(c.needsTicks(at: 0))
        let end = c.table[.windowsIn].duration + 0.01
        c.tick(at: end)
        XCTAssertFalse(c.needsTicks(at: end))
        let s = fake(c, 1)
        let n = s.renders.count
        c.tick(at: end + 1)
        XCTAssertEqual(s.renders.count, n)
        XCTAssertEqual(s.renders.last?.sample.alpha, 1)
    }

    func testWindowNumbersMapIDsToSurfaces() {
        let c = makeController()
        c.apply(OverlayScene(borders: [border(1), border(2)]))
        XCTAssertEqual(c.windowNumbers[1], fake(c, 1).windowNumber)
        XCTAssertEqual(c.windowNumbers.count, 2)
    }

    // MARK: Native Spaces (live R2 finding)

    /// A managed window on another Space is in the scene but gets no surface; it gets one when
    /// it comes on screen and loses it again when it leaves.
    func testBordersOfOffScreenWindowsAreNeverDrawn() {
        let c = makeController(table: .off)
        offSpace = [2]
        c.apply(OverlayScene(borders: [border(1), border(2)]))
        XCTAssertEqual(Set(c.surfaces.keys), [1])
        XCTAssertEqual(c.engine.shownIDs, [1, 2], "still tracked, just not drawn")

        offSpace = []
        c.refreshVisibility()
        XCTAssertEqual(Set(c.surfaces.keys), [1, 2])
        XCTAssertFalse(fake(c, 2).renders.isEmpty)

        offSpace = [1]
        c.refreshVisibility()
        XCTAssertEqual(Set(c.surfaces.keys), [2])
        XCTAssertTrue(made.filter { $0.closeCount > 0 }.count == 1, "the surface of window 1 was closed")
    }
}
