import CoreGraphics
import XCTest

@testable import CaelestiaCore

/// The resize scheduler never describes a cover: each sample is a real frame, the end sample is
/// exactly the target, and a window that cannot keep up is snapped instead of stretched.
/// Size is the final size from the first sample. Position eases out in a fixed time.
final class LiveResizeTests: XCTestCase {
    let from = CGRect(x: 10, y: 20, width: 400, height: 300)
    let to = CGRect(x: 30, y: 40, width: 700, height: 500)

    func testTheDefaultBudgetIs150msEaseOut() {
        let schedule = LiveResizeSchedule()
        XCTAssertEqual(schedule.spec.durationMs, 150, accuracy: 0.001)
        XCTAssertEqual(schedule.spec.curve, .bezier(.default))
        XCTAssertEqual(AnimationSpec.liveRetile(milliseconds: 0), .disabled)
    }

    func testSizeIsFinalImmediatelyAndTheEndIsExactlyTheTarget() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(1, from: from, to: to, at: 0)
        let start = schedule.samples(at: 0)[0]
        XCTAssertEqual(start.frame.size, to.size, "size is committed on the first sample")
        XCTAssertEqual(start.frame.origin, from.origin)
        XCTAssertFalse(start.finished)
        XCTAssertFalse(start.snapped)
        let end = schedule.samples(at: schedule.spec.duration)[0]
        XCTAssertEqual(end.frame, to)
        XCTAssertTrue(end.finished)
        XCTAssertFalse(end.snapped)
    }

    func testASampleIsOnlyAFrameAndEaseOutIsFrontLoaded() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(1, from: from, to: to, at: 0)
        let mid = schedule.samples(at: schedule.spec.duration / 2)[0]
        XCTAssertEqual(mid.frame.size, to.size)
        let halfway = Interpolation.lerp(from.origin.x, to.origin.x, 0.5)
        XCTAssertGreaterThan(mid.frame.minX, halfway, "Hyprland's default curve is an ease-out")
        XCTAssertLessThan(mid.frame.minX, to.minX)
        XCTAssertFalse(mid.finished)
    }

    func testDurationDoesNotScaleWithDistance() {
        func finished(distance: CGFloat) -> Bool {
            var schedule = LiveResizeSchedule()
            let start = CGRect(x: 0, y: 0, width: 200, height: 200)
            let end = CGRect(x: distance, y: 0, width: 800, height: 600)
            schedule.retarget(1, from: start, to: end, at: 0)
            let early = schedule.samples(at: 0.016)[0]
            XCTAssertGreaterThan(abs(early.frame.minX - start.minX), 2.5, "a frame is not capped at 2 pt")
            XCTAssertEqual(early.frame.size, end.size)
            XCTAssertFalse(schedule.samples(at: 0)[0].finished)
            if distance > 500 {
                XCTAssertFalse(schedule.samples(at: 0.05)[0].finished, "a long move is still going well before the budget")
            }
            return schedule.samples(at: 0.150)[0].finished
        }
        XCTAssertTrue(finished(distance: 40))
        XCTAssertTrue(finished(distance: 2000))
    }

    func testADirectTrackIsTheCursorFrame() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(1, from: from, to: to, at: 0, direct: true)
        let jumped = CGRect(x: 50, y: 60, width: 900, height: 400)
        schedule.retarget(1, from: from, to: jumped, at: 0.01, direct: true)
        let sample = schedule.samples(at: 0.5)[0]
        XCTAssertEqual(sample.frame, jumped)
        XCTAssertFalse(sample.finished)
        XCTAssertEqual(schedule.tracks.count, 1)
    }

    func testZeroDurationSnaps() {
        var schedule = LiveResizeSchedule(spec: .liveRetile(milliseconds: 0))
        schedule.retarget(1, from: from, to: to, at: 0)
        let sample = schedule.samples(at: 0)[0]
        XCTAssertEqual(sample.frame, to)
        XCTAssertTrue(sample.finished)
        XCTAssertTrue(sample.snapped)
    }

    func testASecondTargetBeforeTheNextTickReplacesTheFirst() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(1, from: from, to: to, at: 0)
        let later = CGRect(x: 0, y: 0, width: 200, height: 200)
        let now = CGRect(x: 12, y: 22, width: 410, height: 310)
        schedule.retarget(1, from: now, to: later, at: 0.05)
        XCTAssertEqual(schedule.tracks.count, 1)
        let sample = schedule.samples(at: 0.05)[0]
        XCTAssertEqual(sample.frame.size, later.size)
        XCTAssertEqual(sample.frame.origin, now.origin)
        let done = schedule.samples(at: 0.05 + schedule.spec.duration)[0]
        XCTAssertEqual(done.frame, later)
        XCTAssertTrue(done.finished)
    }

    func testTwoMissedReadBacksSnapToTheFinalFrame() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(7, from: from, to: to, at: 0)
        let asked = schedule.samples(at: 0.05)[0].frame
        XCTAssertFalse(schedule.noteReadBack(7, requested: asked, actual: CGRect(x: 0, y: 0, width: 10, height: 10)))
        XCTAssertTrue(schedule.noteReadBack(7, requested: asked, actual: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let snapped = schedule.samples(at: 0.05)[0]
        XCTAssertEqual(snapped.frame, to)
        XCTAssertTrue(snapped.finished)
        XCTAssertTrue(snapped.snapped)
    }

    func testAMatchingReadBackClearsTheMissCount() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(3, from: from, to: to, at: 0)
        let asked = schedule.samples(at: 0)[0].frame
        XCTAssertFalse(schedule.noteReadBack(3, requested: asked, actual: CGRect(x: 0, y: 0, width: 9, height: 9)))
        XCTAssertFalse(schedule.noteReadBack(3, requested: asked, actual: asked))
        XCTAssertFalse(schedule.noteReadBack(3, requested: asked, actual: CGRect(x: 1, y: 1, width: 8, height: 8)))
        XCTAssertFalse(schedule.samples(at: 0)[0].snapped)
    }

    func testWindowDurationMsIsTheBudgetAndZeroStaysZero() throws {
        XCTAssertEqual(Config().animations.windowDurationMs, 150)
        XCTAssertEqual(Config().animations.effectiveWindowDurationMs, 150)
        let zero = try ConfigLoader.parse(toml: "[animations]\nwindowDurationMs = 0\n")
        XCTAssertEqual(zero.animations.effectiveWindowDurationMs, 0)
        var fast = Config()
        fast.animations.speed = 2
        XCTAssertEqual(fast.animations.effectiveWindowDurationMs, 75)
        XCTAssertThrowsError(try ConfigLoader.parse(toml: "[animations]\nwindowDurationMs = -1\n"))
        XCTAssertEqual(try ConfigLoader.loadDefaultResource().animations.windowDurationMs, 150)
    }
}
