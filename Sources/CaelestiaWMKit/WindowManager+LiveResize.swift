import AppKit
import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
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
        if let previous = liveFrameStamp {
            liveFrameStep = min(0.05, max(0, now - previous))
        }
        liveFrameStamp = now
        let step = liveFrameStep
        for sample in liveResizeSchedule.samples(at: now) {
            guard handles[sample.id] != nil else {
                liveResizeSchedule.remove(sample.id)
                continue
            }
            // macOS draws a size change by scaling the old buffer until the app paints.
            // A step bigger than about 2pt shows up as a blurred frame (measured on this Mac:
            // 2pt/16ms stays sharp, 6pt/16ms does not). Follow the spring, but never faster
            // than that, and never catch up a late tick in one jump. Tests land on the final
            // frame in one call; they do not take this path.
            let shown = scheduling == .manual
                ? sample.frame
                : Self.slew(lastLiveFrame[sample.id], to: sample.frame, dt: step)
            if let last = lastLiveFrame[sample.id], last.approximatelyEquals(shown, tolerance: 0.25),
               !sample.frame.approximatelyEquals(shown, tolerance: 0.5) {
                continue
            }
            if let last = lastLiveFrame[sample.id],
               abs(shown.width - last.width) > 2.5 || abs(shown.height - last.height) > 2.5
                || abs(shown.minX - last.minX) > 2.5 || abs(shown.minY - last.minY) > 2.5 {
                Log.wm.notice("live jump #\(sample.id) \(Int(last.width))x\(Int(last.height)) -> \(Int(shown.width))x\(Int(shown.height))")
            }
            pushLiveFrame(sample.id, shown)
            lastLiveFrame[sample.id] = shown
            if let p = visiblePlacements[sample.id] {
                let border = Self.border(around: shown, matching: p)
                borderFrames[sample.id] = border
                decorations?.followLiveFrame(sample.id, border)
            }
            // A direct drag stays on the cursor until the button comes up. A spring ends on `to`.
            // The track stays while the slew has not reached the sample, so a fast spring
            // finishes sharp instead of jumping.
            guard sample.finished, shown.approximatelyEquals(sample.frame, tolerance: 0.5) else { continue }
            liveResizeSchedule.remove(sample.id)
            lastLiveFrame[sample.id] = nil
            liveGraceUntil[sample.id] = self.now().addingTimeInterval(0.4)
        }
        if liveResizeSchedule.isEmpty { stopLiveResizePump() }
    }

    /// Largest size or position change that stays sharp on this Mac's window server.
    static let sharpStep: Double = 2

    /// Moves `from` toward `to` by at most 2pt per 16ms, and never more than 2pt in one tick.
    static func slew(_ from: CGRect?, to: CGRect, dt: TimeInterval) -> CGRect {
        guard let from else { return to }
        let allowance = min(sharpStep, max(0.5, dt / 0.016 * sharpStep))
        func axis(_ value: Double, _ was: Double) -> Double {
            let d = value - was
            if abs(d) <= allowance { return value }
            return was + allowance * (d < 0 ? -1 : 1)
        }
        return CGRect(
            x: axis(to.minX, from.minX), y: axis(to.minY, from.minY),
            width: axis(to.width, from.width), height: axis(to.height, from.height)
        )
    }

    /// Real windows go out on a per-app queue. Test fakes are written here, on the caller.
    func pushLiveFrame(_ id: WindowID, _ frame: CGRect) {
        guard let handle = handles[id] else { return }
        if let ax = handle as? AXWindow {
            beginLiveFrames(ax)
            let element = ax.element
            frameWriter.submit(id: id, pid: ax.pid, frame: frame) { element.setFrameFast($0) }
        } else {
            let got = setFrame(handle, frame)
            if learnMinSize(id, target: frame, readBack: got) { setNeedsLayout() }
        }
    }

    /// One attribute write per app, queued ahead of the frames. Held off until shutdown.
    func beginLiveFrames(_ ax: AXWindow) {
        ax.holdSystemFrameAnimationOff()
        guard liveFrameApps.insert(ax.pid).inserted else { return }
        frameWriter.sync(pid: ax.pid) { ax.suppressSystemFrameAnimation() }
    }

    /// A read-back bigger than `target` is only a minimum if the app still reports it after it
    /// has had a chance to apply the frame. The immediate read during a resize is the old size.
    func confirmMinSizeLater(_ id: WindowID, target: CGRect, first: CGRect) {
        guard let ax = handles[id] as? AXWindow else { return }
        let element = ax.element
        frameWriter.later(pid: ax.pid, seconds: 0.25) { [weak self] in
            let got = element.rect() ?? .null
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    _ = self.learnMinSize(id, target: target, readBack: first)
                    guard self.learnMinSize(id, target: target, readBack: got) else { return }
                    self.setNeedsLayout()
                }
            }
        }
    }

    /// Quit puts the AppKit frame animation back. Synchronous: the process is about to exit.
    func restoreSystemFrameAnimations() {
        let pids = liveFrameApps
        liveFrameApps.removeAll()
        for pid in pids {
            guard let ax = handles.values.compactMap({ $0 as? AXWindow }).first(where: { $0.pid == pid }) else { continue }
            ax.releaseSystemFrameAnimationHold()
            ax.restoreSystemFrameAnimation()
        }
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
