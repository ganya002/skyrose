import AppKit
import CoreGraphics
import Foundation
import QuartzCore

extension WindowManager {
    /// Writes the real frames of every in-flight resize. One frame per window per call.
    /// A second call at the same time writes nothing new until a track finishes.
    /// Tests advance `now` and call this; the daemon's display link calls it each refresh.
    public func stepLiveResize(at time: Date? = nil) {
        guard isManaging, !liveResizeSchedule.isEmpty else {
            stopLiveResizePump()
            return
        }
        let now = (time ?? self.now()).timeIntervalSinceReferenceDate
        var learned = false
        for sample in liveResizeSchedule.samples(at: now) {
            guard let handle = handles[sample.id] else {
                liveResizeSchedule.remove(sample.id)
                continue
            }
            if let last = lastLiveFrame[sample.id], !sample.finished, !sample.snapped,
               last.approximatelyEquals(sample.frame, tolerance: 0.5) {
                continue
            }
            let got = setFrame(handle, sample.frame)
            lastLiveFrame[sample.id] = sample.frame
            let snap = liveResizeSchedule.noteReadBack(sample.id, requested: sample.frame, actual: got)
            guard sample.finished || snap else { continue }
            let final = liveResizeSchedule.tracks[sample.id]?.to ?? sample.frame
            let read = snap && !got.approximatelyEquals(final, tolerance: 2) ? setFrame(handle, final) : got
            if learnMinSize(sample.id, target: final, readBack: read) { learned = true }
            liveResizeSchedule.remove(sample.id)
            lastLiveFrame[sample.id] = nil
        }
        if learned { setNeedsLayout() }
        if liveResizeSchedule.isEmpty { stopLiveResizePump() }
    }

    func startLiveResizePump() {
        guard scheduling == .mainQueue else { return }
        if liveResizeLink == nil {
            let link = LiveResizeLink()
            link.onFrame = { [weak self] in self?.stepLiveResize() }
            liveResizeLink = link
        }
        liveResizeLink?.start()
    }

    func stopLiveResizePump() {
        liveResizeLink?.stop()
    }
}

/// Display-refresh clock for live resizes. 60–120 Hz, preferred 120 (ProMotion). Paused when
/// nothing is resizing; resuming ticks on the next frame.
final class LiveResizeLink: NSObject {
    var onFrame: (() -> Void)?
    private var link: CADisplayLink?
    private let target = LiveResizeLinkTarget()

    func start() {
        if link == nil {
            target.onFrame = { [weak self] in self?.onFrame?() }
            guard let screen = NSScreen.screens.first else { return }
            let displayLink = screen.displayLink(target: target, selector: #selector(LiveResizeLinkTarget.step(_:)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            displayLink.add(to: .main, forMode: .common)
            link = displayLink
        }
        link?.isPaused = false
    }

    func stop() {
        link?.isPaused = true
    }
}

private final class LiveResizeLinkTarget: NSObject {
    var onFrame: (() -> Void)?

    @objc func step(_ link: CADisplayLink) {
        let fire = onFrame
        MainActor.assumeIsolated { fire?() }
    }
}
