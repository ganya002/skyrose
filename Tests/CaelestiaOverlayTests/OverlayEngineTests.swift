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

    func testAnimatedFrameChangeFadesInPlaceAndRevealsAtTheFinalFrame() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant, motion: .animate)]), at: 1)
        // Hidden in place: frame still the old one, never interpolated.
        let mid = e.samples(at: 1 + BorderAnimator.moveFadeOut.duration / 2)[1]!
        XCTAssertEqual(mid.frame, a)
        XCTAssertLessThan(mid.alpha, 1)
        XCTAssertGreaterThan(mid.alpha, 0)
        e.advance(at: 1 + BorderAnimator.moveSettle + 0.001)
        XCTAssertEqual(e.samples(at: 1 + BorderAnimator.moveSettle + 0.001)[1]!.frame, b)
        let done = 1 + BorderAnimator.moveSettle + BorderAnimator.moveFadeIn.duration + 0.01
        e.advance(at: done)
        XCTAssertEqual(e.samples(at: done)[1]!.frame, b)
        XCTAssertEqual(e.samples(at: done)[1]!.alpha, 1, accuracy: 1e-9)
    }

    func testSnapMotionAlsoFadesInsteadOfJumping() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant, motion: .snap)]), at: 1)
        let s = e.samples(at: 1 + BorderAnimator.moveFadeOut.duration + 0.001)[1]!
        XCTAssertEqual(s.frame, a, "frame is not touched until the reveal")
        XCTAssertEqual(s.alpha, 0, accuracy: 1e-9)
        XCTAssertTrue(e.isAnimating(at: 1))
    }

    func testSnapMotionJumpsImmediatelyWhenMoveFadeIsOff() {
        var e = engine(.off)
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant, motion: .snap)]), at: 1)
        XCTAssertEqual(e.samples(at: 1)[1]!.frame, b)
        XCTAssertEqual(e.samples(at: 1)[1]!.alpha, 1)
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

    func testTrackHidesShownBorderAndRevealsWhenStillAndIgnoresUnknown() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        let real = CGRect(x: 10, y: 20, width: 30, height: 40)
        e.track(1, frame: real, at: 1)
        XCTAssertEqual(e.borders[1]?.target.frame, real)
        XCTAssertEqual(e.samples(at: 1.05)[1]!.frame, a, "not moved while hidden")
        e.advance(at: 1 + BorderAnimator.moveSettle + 0.001)
        XCTAssertEqual(e.samples(at: 1 + BorderAnimator.moveSettle + 0.001)[1]!.frame, real)

        e.track(99, frame: real, at: 2)
        XCTAssertNil(e.borders[99])
        XCTAssertEqual(e.borders.count, 1)
    }

    func testTrackSnapsWhenMoveFadeIsOff() {
        var e = engine(.off)
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        let real = CGRect(x: 10, y: 20, width: 30, height: 40)
        e.track(1, frame: real, at: 1)
        XCTAssertEqual(e.samples(at: 1)[1]!.frame, real)
        XCTAssertEqual(e.samples(at: 1)[1]!.alpha, 1)
        XCTAssertFalse(e.isAnimating(at: 1))
    }

    func testTrackIgnoresVanishingBorder() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(vanish: [1: .fadeOut]), at: 1)
        e.track(1, frame: b, at: 1.01)
        XCTAssertEqual(e.borders[1]?.target.frame, a)
        XCTAssertNil(e.borders[1]?.revealAt)
    }

    // MARK: Move fade

    private func moved(from old: CGRect, to new: CGRect, at t: TimeInterval = 1) -> OverlayEngine {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, old, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, new, appear: .instant)]), at: t)
        return e
    }

    func testNoSampleDuringARetileIsEverBetweenOldAndNewFrame() {
        var e = moved(from: a, to: b)
        var t = 1.0
        var sawNew = false
        while t < 2.0 {
            e.advance(at: t)
            let s = e.samples(at: t)[1]!
            XCTAssertTrue(s.frame == a || s.frame == b, "frame at \(t - 1)s is \(s.frame)")
            if s.frame == b {
                sawNew = true
                XCTAssertGreaterThanOrEqual(t - 1, BorderAnimator.moveSettle - 1e-9, "new frame only after the settle time")
            } else {
                XCTAssertLessThan(t - 1, BorderAnimator.moveSettle + 0.006)
            }
            // Visible only at a final frame: while at the old frame alpha must fall to 0 quickly.
            if s.frame == a, t - 1 >= BorderAnimator.moveFadeOut.duration + 1e-9 {
                XCTAssertEqual(s.alpha, 0, accuracy: 1e-9, "old frame must be invisible after the fade-out")
            }
            t += 0.005
        }
        XCTAssertTrue(sawNew)
    }

    func testAlphaReachesZeroWithinMoveFadeOut() {
        let e = moved(from: a, to: b)
        let d = BorderAnimator.moveFadeOut.duration
        XCTAssertEqual(d, 0.07, accuracy: 1e-9)
        XCTAssertEqual(e.samples(at: 1)[1]!.alpha, 1, accuracy: 1e-9)
        XCTAssertEqual(e.samples(at: 1 + d)[1]!.alpha, 0, accuracy: 1e-9)
        var prev = 1.0
        for i in 1...14 {
            let al = e.samples(at: 1 + Double(i) * 0.005)[1]!.alpha
            XCTAssertLessThanOrEqual(al, prev + 1e-12)
            prev = al
        }
    }

    func testRevealHappensMoveSettleAfterTheLastFrameChange() {
        var e = moved(from: a, to: b)
        let c = CGRect(x: 5, y: 5, width: 50, height: 60)
        // Retarget mid-hide, 0.1 s after the first change.
        e.apply(OverlayScene(borders: [border(1, c, appear: .instant)]), at: 1.1)
        XCTAssertEqual(e.borders[1]!.revealAt!, 1.1 + BorderAnimator.moveSettle, accuracy: 1e-9)
        e.advance(at: 1 + BorderAnimator.moveSettle + 0.01)  // the original reveal time has passed
        XCTAssertEqual(e.samples(at: 1.2)[1]!.frame, a, "reveal was pushed back")
        XCTAssertEqual(e.samples(at: 1.2)[1]!.alpha, 0, accuracy: 1e-9)
        e.advance(at: 1.1 + BorderAnimator.moveSettle - 0.001)
        XCTAssertEqual(e.samples(at: 1.2)[1]!.frame, a)
        e.advance(at: 1.1 + BorderAnimator.moveSettle)
        XCTAssertEqual(e.samples(at: 1.25)[1]!.frame, c)
        XCTAssertNil(e.borders[1]!.revealAt)
    }

    func testAfterRevealAlphaReturnsToOneAndEngineGoesIdle() {
        var e = moved(from: a, to: b)
        XCTAssertTrue(e.isAnimating(at: 1.0))
        XCTAssertTrue(e.isAnimating(at: 1.1), "reveal pending counts as animating")
        let reveal = 1 + BorderAnimator.moveSettle
        e.advance(at: reveal)
        XCTAssertTrue(e.isAnimating(at: reveal), "fading in")
        let end = reveal + BorderAnimator.moveFadeIn.duration + 0.001
        e.advance(at: end)
        XCTAssertEqual(e.samples(at: end)[1]!.alpha, 1, accuracy: 1e-9)
        XCTAssertEqual(e.samples(at: end)[1]!.frame, b)
        XCTAssertFalse(e.isAnimating(at: end))
        XCTAssertTrue(e.borders[1]!.isIdle(at: end))
    }

    func testAlphaIsPopInAlphaTimesMoveFade() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .popIn)]), at: 0)
        let popEnd = table[.windowsIn].duration + 0.01
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant)]), at: popEnd)
        XCTAssertEqual(e.samples(at: popEnd)[1]!.alpha, 1, accuracy: 1e-9)
        let mid = e.samples(at: popEnd + 0.035)[1]!.alpha
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
    }

    func testOffTableSnapsWithAlphaOne() {
        var e = engine(.off)
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant)]), at: 1)
        let s = e.samples(at: 1)[1]!
        XCTAssertEqual(s.frame, b)
        XCTAssertEqual(s.alpha, 1)
        XCTAssertNil(e.borders[1]!.revealAt)
        XCTAssertFalse(e.isAnimating(at: 1))
    }

    func testDragTrackingKeepsBorderHiddenUntilFrameIsStillForMoveSettle() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        var t = 1.0
        var frame = a
        for i in 0..<30 {  // 30 frames at 16 ms, the window moves every frame
            frame = frame.offsetBy(dx: 7, dy: 3)
            e.track(1, frame: frame, at: t)
            e.advance(at: t)
            let s = e.samples(at: t)[1]!
            XCTAssertEqual(s.frame, a, "hidden at the old place, never follows the drag (frame \(i))")
            if i >= 5 { XCTAssertEqual(s.alpha, 0, accuracy: 1e-9) }
            t += 0.016
        }
        let last = t - 0.016
        // Still, but not for long enough.
        e.track(1, frame: frame, at: last + 0.1)
        e.advance(at: last + BorderAnimator.moveSettle - 0.001)
        XCTAssertEqual(e.samples(at: last + 0.1)[1]!.frame, a)
        e.advance(at: last + BorderAnimator.moveSettle + 0.001)
        XCTAssertEqual(e.samples(at: last + BorderAnimator.moveSettle + 0.001)[1]!.frame, frame)
        let end = last + BorderAnimator.moveSettle + BorderAnimator.moveFadeIn.duration + 0.01
        e.advance(at: end)
        XCTAssertEqual(e.samples(at: end)[1]!.alpha, 1, accuracy: 1e-9)
        XCTAssertFalse(e.isAnimating(at: end))
    }

    func testTrackWithTheSameFrameDoesNotPushTheRevealBack() {
        var e = moved(from: a, to: b)
        let reveal = e.borders[1]!.revealAt!
        e.track(1, frame: b, at: 1.1)
        XCTAssertEqual(e.borders[1]!.revealAt!, reveal, accuracy: 1e-12)
    }

    func testVanishingBorderThatComesBackWithANewFrameSnaps() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1, a, appear: .instant)]), at: 0)
        e.apply(OverlayScene(vanish: [1: .fadeOut]), at: 1)
        e.apply(OverlayScene(borders: [border(1, b, appear: .instant)]), at: 1.02)
        XCTAssertEqual(e.samples(at: 1.02)[1]!.frame, b)
        XCTAssertNil(e.borders[1]!.revealAt)
    }

    func testShownIDsUnaffectedByHiddenMove() {
        var e = moved(from: a, to: b)
        XCTAssertEqual(e.shownIDs, [1])
        e.track(1, frame: CGRect(x: 1, y: 1, width: 9, height: 9), at: 1.05)
        XCTAssertEqual(e.shownIDs, [1])
        e.apply(OverlayScene(borders: [border(1, b), border(2, a)]), at: 1.06)
        XCTAssertEqual(e.shownIDs, [1, 2])
    }

    func testRemoveAllReturnsEverything() {
        var e = engine()
        e.apply(OverlayScene(borders: [border(1), border(2)]), at: 0)
        XCTAssertEqual(e.removeAll(), [1, 2])
        XCTAssertTrue(e.borders.isEmpty)
    }
}
