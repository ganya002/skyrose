import CaelestiaCore
import CaelestiaLayout
import CaelestiaOverlay
import CoreGraphics
import XCTest

@testable import CaelestiaWMKit

/// A resize must not be handed to the snapshot animator. The real window walks to the new frame.
@MainActor
private final class ResizeRecordingAnimator: WindowAnimator {
    var sizeChanges = 0
    func animate(_ request: WindowAnimationRequest, commit: @escaping () -> Void) {
        for change in request.changes {
            if let from = change.from, let to = change.to,
               abs(from.width - to.width) > 1 || abs(from.height - to.height) > 1 {
                sizeChanges += 1
            }
        }
        commit()
    }
    func isCovering(_ id: CGWindowID) -> Bool { false }
    func prepareClose(_ id: CGWindowID, scene: WindowAnimationRequest) -> Bool { false }
    func beginDrag(_ id: CGWindowID, pointer: CGPoint, scene: WindowAnimationRequest) -> Bool { false }
    func updateDrag(pointer: CGPoint, dropTarget: CGRect?) {}
    func endDrag() {}
    func windowsChanged(visible: [AnimatedWindow]) {}
    func cancel() {}
}

@MainActor
final class LiveResizeWMTests: XCTestCase {
    func testAResizeIsNotCoveredAndTheRealWindowArrivesOnTheSpring() {
        let h = Harness()
        let recorder = ResizeRecordingAnimator()
        h.wm.windowAnimator = recorder
        let a = h.system.existing("a")
        h.system.existing("b")
        h.start()
        let before = a.frame
        let writes = a.setFrameCount
        XCTAssertTrue(h.wm.state.updateTree(of: a.windowID) { $0.setSplitRatio(a.windowID, 0.3, exact: true) } ?? false)
        h.wm.setNeedsLayout()
        h.settle()
        XCTAssertEqual(recorder.sizeChanges, 0, "the cover is not given a size change to scale")
        let target = h.wm.visiblePlacements[a.windowID]!.frame
        XCTAssertNotEqual(target, before)
        // Manual scheduling has no display link, so the pass lands on the final real frame.
        XCTAssertEqual(a.frame, target)
        XCTAssertFalse(WorkspaceLayout.overlaps(a.frame, h.wm.visiblePlacements[h.wm.managedWindowIDs.first { $0 != a.windowID }!]!.frame))
        let done = a.setFrameCount
        h.wm.stepLiveResize()
        h.settle()
        XCTAssertEqual(a.setFrameCount, done, "a finished resize does not keep writing")
        XCTAssertGreaterThan(done, writes)
    }

    func testTheRetileBudgetIsTheConfiguredDuration() {
        var config = Config()
        config.animations.windowDurationMs = 150
        let h = Harness(config: config)
        h.start()
        XCTAssertEqual(h.wm.liveResizeSchedule.spec.durationMs, 150, accuracy: 0.1)
        XCTAssertEqual(h.wm.currentLiveRetileSpec().durationMs, 150, accuracy: 0.1)
    }

    func testAFrameWriteIsTheWholeFrameAndResizesOnlyWhenTheSizeChanges() {
        let first = AsyncFrameWriter.plan(last: nil, next: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(first.resize)
        XCTAssertEqual(first.frame.width, 100)
        let slide = AsyncFrameWriter.plan(last: first.frame, next: CGRect(x: 400, y: 0, width: 100, height: 100))
        XCTAssertFalse(slide.resize, "a position ease must not write the size again")
        XCTAssertEqual(slide.frame.minX, 400)
        let grow = AsyncFrameWriter.plan(last: slide.frame, next: CGRect(x: 400, y: 0, width: 900, height: 100))
        XCTAssertTrue(grow.resize)
        XCTAssertEqual(grow.frame.width, 900, "a size change is written in full, not stepped 2 pt")
    }
}
