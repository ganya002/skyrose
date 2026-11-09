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
        for sample in liveResizeSchedule.samples(at: now) {
            guard handles[sample.id] != nil else {
                liveResizeSchedule.remove(sample.id)
                continue
            }
            // The sample is already the ease-out frame, or the cursor frame for a drag.
            // Do not cap the step: a 2 pt limit made the duration grow with the distance.
            let shown = sample.frame
            let unchanged = lastLiveFrame[sample.id]?.approximatelyEquals(shown, tolerance: 0.25) == true
            if !unchanged {
                pushLiveFrame(sample.id, shown)
                lastLiveFrame[sample.id] = shown
                if let p = visiblePlacements[sample.id] {
                    let border = Self.border(around: shown, matching: p)
                    borderFrames[sample.id] = border
                    decorations?.followLiveFrame(sample.id, border)
                }
            }
            guard sample.finished else { continue }
            if let track = liveResizeSchedule.tracks[sample.id] {
                let started = track.sampler.startTime
                let ms = max(0, Int(((now - started) * 1000).rounded()))
                let kind = sample.snapped ? "snap" : "ease"
                Log.wm.notice(
                    "live anim #\(sample.id, privacy: .public) \(ms, privacy: .public)ms \(kind, privacy: .public) \(Int(track.from.width), privacy: .public)x\(Int(track.from.height), privacy: .public) -> \(Int(track.to.width), privacy: .public)x\(Int(track.to.height), privacy: .public) budget \(Int(track.sampler.spec.durationMs.rounded()), privacy: .public)ms"
                )
            }
            liveResizeSchedule.remove(sample.id)
            lastLiveFrame[sample.id] = nil
            liveGraceUntil[sample.id] = self.now().addingTimeInterval(0.4)
        }
        if liveResizeSchedule.isEmpty { stopLiveResizePump() }
    }

    /// Ease-out budget for a keyboard resize or retile. Reduce Motion snaps.
    func currentLiveRetileSpec() -> AnimationSpec {
        let system = config.animations.respectReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if config.animations.reduceMotion || system { return .liveRetile(milliseconds: 0) }
        return .liveRetile(milliseconds: config.animations.effectiveWindowDurationMs)
    }

    /// Real windows go out on a per-app queue. Test fakes are written here, on the caller.
    func pushLiveFrame(_ id: WindowID, _ frame: CGRect) {
        guard let handle = handles[id] else { return }
        if let ax = handle as? AXWindow {
            beginLiveFrames(ax)
            let element = ax.element
            frameWriter.submit(id: id, pid: ax.pid, frame: frame) { element.setFrameFast($0, resize: $1) }
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
