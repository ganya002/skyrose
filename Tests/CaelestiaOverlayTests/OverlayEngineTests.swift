import CaelestiaCore
import CoreGraphics
import XCTest

@testable import CaelestiaOverlay

final class OverlayEngineTests: XCTestCase {
    private let table = AnimationTable.gabbySpringy
    private let a = CGRect(x: 0, y: 0, width: 200, height: 100)
    private let b = CGRect(x: 300, y: 50, width: 400, height: 300)

    private func engine(_ table: AnimationTable = .gabbySpringy) -> OverlayEngine { OverlayEngine(table: table) }

    func testPopInStartsSmallTransparentAndSettles() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .popIn)]), at: 0)
        let s0 = e.samples(at: 0)[1]!
        XCTAssertEqual(s0.alpha, 0, accuracy: 1e-9)
        XCTAssertEqual(s0.scale, 0.8, accuracy: 1e-9)
        XCTAssertTrue(e.isAnimating(at: 0))

        let end = table[.windowsIn].duration + 0.001
        let s1 = e.samples(at: end)[1]!
        XCTAssertEqual(s1.alpha, 1)
        XCTAssertEqual(s1.scale, 1)
        XCTAssertFalse(e.isAnimating(at: end))
        XCTAssertTrue(e.borders[1]!.isIdle(at: end))
    }

    func testInstantAppearIsOpaqueAtOnce() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        let s = e.samples(at: 0)[1]!
        XCTAssertEqual(s.alpha, 1)
        XCTAssertEqual(s.scale, 1)
        XCTAssertFalse(e.isAnimating(at: 0))
    }

    func testAnimatedFrameChangeMovesSmoothlyAndEndsExactly() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant, motion: .animate)]), at: 1)
        let mid = e.samples(at: 1 + table[.windowsMove].duration / 3)[1]!.frame
        XCTAssertGreaterThan(mid.minX, a.minX)
        XCTAssertLessThan(mid.minX, b.minX)
        XCTAssertGreaterThan(mid.minY, a.minY)
        XCTAssertLessThan(mid.minY, b.minY)
        XCTAssertEqual(e.samples(at: 1 + table[.windowsMove].duration + 0.01)[1]!.frame, b)
    }

    func testSnapMotionJumpsImmediately() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant, motion: .snap)]), at: 1)
        XCTAssertEqual(e.samples(at: 1)[1]!.frame, b)
        XCTAssertFalse(e.isAnimating(at: 1))
    }

    func testActiveChangeBlendsOverBorderSpec() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, active: false, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, a, active: true, appear: .instant)]), at: 1)
        let d = table[.border].duration
        XCTAssertEqual(e.samples(at: 1)[1]!.activeMix, 0, accuracy: 1e-9)
        let mid = e.samples(at: 1 + d / 2)[1]!.activeMix
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
        XCTAssertEqual(e.samples(at: 1 + d + 0.001)[1]!.activeMix, 1)
    }

    func testFadeOutKeepsBorderUntilWindowsOutDuration() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        let removed = e.apply(OverlayScene(borders: [], vanish: [1: .fadeOut]), at: 1)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(e.borders[1]?.phase, .vanishing)
        XCTAssertTrue(e.shownIDs.isEmpty)
        let d = table[.windowsOut].duration
        XCTAssertTrue(e.collectGone(at: 1 + d / 2).isEmpty)
        XCTAssertEqual(e.collectGone(at: 1 + d + 0.001), [1])
        XCTAssertNil(e.borders[1])
    }

    func testInstantVanishReturnsRemovedAtOnce() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a), border(2, b)]), at: 0)
        let removed = e.apply(OverlayScene(borders: [border(2, b)], vanish: [1: .instant]), at: 0.1)
        XCTAssertEqual(removed, [1])
        XCTAssertNil(e.borders[1])
    }

    func testMissingVanishEntryDefaultsToFadeOut() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        XCTAssertTrue(e.apply(OverlayScene(), at: 1).isEmpty)
        XCTAssertEqual(e.borders[1]?.phase, .vanishing)
    }

    func testVanishingBorderReAddedComesBack() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(vanish: [1: .fadeOut]), at: 1)
        let mid = 1 + table[.windowsOut].duration / 2
        let fading = e.samples(at: mid)[1]!.alpha
        XCTAssertLessThan(fading, 1)
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: mid)
        XCTAssertEqual(e.borders[1]?.phase, .shown)
        XCTAssertEqual(e.shownIDs, [1])
        XCTAssertEqual(e.samples(at: mid)[1]!.alpha, fading, accuracy: 1e-9)
        XCTAssertEqual(e.samples(at: mid + 2)[1]!.alpha, 1)
        XCTAssertTrue(e.collectGone(at: mid + 2).isEmpty)
    }

    func testTableOffIsEntirelyInstant() {
        var e = engine(.off)
        e.apply(OverlayScene(borders: [border(1, a, active: false, appear: .popIn)]), at: 0)
        var s = e.samples(at: 0)[1]!
        XCTAssertEqual(s.alpha, 1)
        XCTAssertEqual(s.scale, 1)
        e.apply(OverlayScene(borders: [border(1, b, active: true, appear: .popIn)]), at: 1)
        s = e.samples(at: 1)[1]!
        XCTAssertEqual(s.frame, b)
        XCTAssertEqual(s.activeMix, 1)
        XCTAssertFalse(e.isAnimating(at: 1))
        let removed = e.apply(OverlayScene(vanish: [1: .fadeOut]), at: 2)
        XCTAssertEqual(removed, [1])
    }

    func testShownIDsEqualSceneIDs() {
        var e = engine()
        let scene = OverlayScene(borders: [border(3), border(5), border(9)])
        e.apply(scene, at: 0)
        XCTAssertEqual(e.shownIDs, scene.ids)
        e.apply(OverlayScene(borders: [border(5), border(11)]), at: 0.5)
        XCTAssertEqual(e.shownIDs, [5, 11])
    }

    func testTrackSnapsShownBorderAndIgnoresUnknown() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant)]), at: 1)
        let real = CGRect(x: 10, y: 20, width: 30, height: 40)
        e.track(1, frame: real)
        XCTAssertEqual(e.samples(at: 1.05)[1]!.frame, real)
        XCTAssertEqual(e.borders[1]?.target.frame, real)

        e.track(99, frame: real)
        XCTAssertNil(e.borders[99])
        XCTAssertEqual(e.borders.count, 1)
    }

    func testTrackIgnoresVanishingBorder() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(vanish: [1: .fadeOut]), at: 1)
        e.track(1, frame: b)
        XCTAssertEqual(e.borders[1]?.target.frame, a)
    }

    func testRemoveAllReturnsEverything() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1), border(2)]), at: 0)
        XCTAssertEqual(e.removeAll(), [1, 2])
        XCTAssertTrue(e.borders.isEmpty)
    }
}
