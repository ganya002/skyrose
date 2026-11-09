import CoreGraphics
import XCTest

@testable import CaelestiaCore

/// The resize scheduler never describes a cover: each sample is a real frame, the end sample is
/// exactly the target, and a window that cannot keep up is snapped instead of stretched.
final class LiveResizeTests: XCTestCase {
    let from = CGRect(x: 10, y: 20, width: 400, height: 300)
    let to = CGRect(x: 30, y: 40, width: 700, height: 500)

    func testStartIsTheCurrentFrameAndTheEndIsExactlyTheTarget() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(1, from: from, to: to, at: 0)
        let start = schedule.samples(at: 0)[0]
        XCTAssertEqual(start.frame, from)
        XCTAssertFalse(start.finished)
        XCTAssertFalse(start.snapped)
        let end = schedule.samples(at: schedule.spec.duration + 0.001)[0]
        XCTAssertEqual(end.frame, to)
        XCTAssertTrue(end.finished)
        XCTAssertFalse(end.snapped)
    }

    func testASampleIsOnlyAFrame() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(1, from: from, to: to, at: 0)
        let mid = schedule.samples(at: schedule.spec.duration / 2)[0]
        XCTAssertGreaterThan(mid.frame.width, from.width)
        XCTAssertLessThan(mid.frame.width, to.width + to.width * 0.05)
        XCTAssertFalse(mid.finished)
    }

    func testASecondTargetBeforeTheNextTickReplacesTheFirst() {
        var schedule = LiveResizeSchedule()
        schedule.retarget(1, from: from, to: to, at: 0)
        let later = CGRect(x: 0, y: 0, width: 200, height: 200)
        let now = CGRect(x: 12, y: 22, width: 410, height: 310)
        schedule.retarget(1, from: now, to: later, at: 0.05)
        XCTAssertEqual(schedule.tracks.count, 1)
        let sample = schedule.samples(at: 0.05)[0]
        XCTAssertEqual(sample.frame, now)
        let done = schedule.samples(at: 0.05 + schedule.spec.duration)[0]
        XCTAssertEqual(done.frame, later)
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
        let asked = from
        XCTAssertFalse(schedule.noteReadBack(3, requested: asked, actual: CGRect(x: 0, y: 0, width: 9, height: 9)))
        XCTAssertFalse(schedule.noteReadBack(3, requested: asked, actual: asked))
        XCTAssertFalse(schedule.noteReadBack(3, requested: asked, actual: CGRect(x: 1, y: 1, width: 8, height: 8)))
        XCTAssertFalse(schedule.samples(at: 0)[0].snapped)
    }
}
