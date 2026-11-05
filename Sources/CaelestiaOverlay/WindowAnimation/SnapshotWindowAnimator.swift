import AppKit
import CaelestiaCore
import QuartzCore

/// Standard-mode (SIP on) window animations, Hyprland style, with stills instead of the real
/// windows (spec 2.3 / 4.7):
///
/// 1. A layout pass hands over its changes *before* any AX write.
/// 2. If every still it needs is cached (window stills + the desktop still of each affected
///    display), a cover goes up over those displays showing exactly what is on screen now.
/// 3. On the next display refresh, once the cover is composited, the real windows are moved once
///    (`commit`) underneath it.
/// 4. The stills spring from the old to the new frames (`windowsMove`), new windows pop in
///    (`windowsIn`), closed / moved-away ones shrink and fade (`windowsOut`); border rings are
///    drawn with them. A retile during a retile retargets mid-flight.
/// 5. When everything has arrived the cover fades out (80 ms) over the real windows, which have
///    been at their final frames (and redrawn) for the whole animation.
///
/// Anything missing (no Screen Recording, a still not cached yet, animations off) makes the pass
/// an instant move with the border fade, exactly as before. Stills are refreshed in the
/// background whenever the layout has been quiet for `refreshDelay`.
@MainActor
public final class SnapshotWindowAnimator: WindowAnimator {
    public let cache: SnapshotCache
    public var style: OverlayStyle
    public var table: AnimationTable {
        didSet { model.table = table }
    }
    /// Off: every pass commits at once (config `animations.windows = "off"`, game mode).
    public var isEnabled = true {
        didSet { if !isEnabled { cancel() } }
    }

    /// Counters and timings (`skyrose query animations`, the debug overlay, logs).
    public private(set) var played = 0
    public private(set) var fallbacks = 0
    public private(set) var lastFallbackReason = ""
    /// Milliseconds from `animate` to the real frames being written (the extra latency the cover
    /// adds to a retile). 0 when the cover was already up.
    public private(set) var lastCommitLatencyMs: Double = 0
    public private(set) var maxCommitLatencyMs: Double = 0
    /// Duration of the last finished animation (cover up to cover gone), ms.
    public private(set) var lastAnimationMs: Double = 0
    public private(set) var drags = 0

    public static let coverFadeOut: TimeInterval = 0.08
    /// The cover never stays longer than this (a stuck animation must not hide windows).
    public static let hardTimeout: TimeInterval = 1.5
    /// Quiet time after the last change before stills are refreshed.
    public static let refreshDelay: TimeInterval = 0.35
    /// Every visible window's still is refreshed at least this often while idle.
    public static let periodicRefresh: TimeInterval = 4

    private var model: WindowMotionModel
    private var covers: [CGDirectDisplayID: SnapshotCover] = [:]
    private var pendingCommit: (() -> Void)?
    private var requestedAt: TimeInterval = 0
    private var coverSince: TimeInterval = 0
    /// Last new motion (a pass, a drop, a prepared close): the hard timeout counts from here, so
    /// a long drag never cuts the drop animation short (live finding).
    private var activeSince: TimeInterval = 0
    private var link: CADisplayLink?
    /// When the model last became settled (the fresh-capture grace counts from here).
    private var settledAt: TimeInterval?
    /// Longest a settled cover waits for a resized window's capture at its new size.
    public static let freshGrace: TimeInterval = 0.15
    private var dragging: (id: CGWindowID, offset: CGPoint, size: CGSize, display: CGDirectDisplayID)?
    private var lastVisible: [AnimatedWindow] = []
    private var refreshWork: DispatchWorkItem?
    private var timer: Timer?
    private var closing: [SnapshotCover] = []
    /// Windows shown live through a hole in the cover (opened without a correct-size still).
    private var uncovered: [CGWindowID: CGRect] = [:]
    /// Captures at a window's new size after a resize, and when each arrived (cross-fade start).
    private var fresh: [CGWindowID: (still: SnapshotCache.Still, at: TimeInterval)] = [:]
    /// Resized windows still waiting for a capture at their new size.
    private var wantFresh: [CGWindowID: CGSize] = [:]
    private var freshTask: Task<Void, Never>?
    /// Opens: popped in from a correct-size still / shown live because none existed in time.
    public private(set) var opensAnimated = 0
    public private(set) var opensLive = 0
    public static let freshCrossFade: TimeInterval = 0.12
    /// After a resize the app needs a moment to redraw at the new size: capture attempts (s
    /// after the commit) until one shows the whole window at its new size.
    public static let freshAttempts: [TimeInterval] = [0.04, 0.09, 0.16, 0.26, 0.4]
    private var idle: [CGDirectDisplayID: SnapshotCover] = [:]
    /// Closes the WM asked for, until their deadline: the cover waits for them.
    private var closingSoon: [CGWindowID: TimeInterval] = [:]
    /// Milliseconds to order the cover in and flush (part of the commit latency).
    public private(set) var lastShowMs: Double = 0

    public init(cache: SnapshotCache = SnapshotCache(), style: OverlayStyle = .gabby, table: AnimationTable = .gabbySpringy) {
        self.cache = cache
        self.style = style
        self.table = table
        model = WindowMotionModel(table: table)
    }

    public var isAnimating: Bool { !covers.isEmpty }

    /// Window motion is animated at all (off with game mode, Reduce Motion, the `off` preset).
    var motionEnabled: Bool {
        let move = table[.windowsMove]
        return isEnabled && move.enabled && move.durationMs > 0
    }

    // MARK: WindowAnimator

    public func animate(_ request: WindowAnimationRequest, commit: @escaping () -> Void) {
        let started = CACurrentMediaTime()
        guard motionEnabled else { return instant(commit, "off") }
        guard cache.canCapture() else { return instant(commit, "no Screen Recording") }
        let affected = request.affectedDisplays.union(covers.keys)
        guard !affected.isEmpty else {
            commit()
            return
        }
        let changes = Dictionary(request.changes.map { ($0.id, $0) }, uniquingKeysWith: { _, l in l })
        for d in affected where covers[d] == nil {
            guard cache.desktop(for: d) != nil else {
                cache.refreshDesktop(d)
                return instant(commit, "no desktop still for display \(d)")
            }
            for w in request.windows where w.displayID == d && changes[w.id]?.kind != .open && changes[w.id]?.kind != .reveal {
                guard cache.still(for: w.id) != nil else {
                    scheduleRefresh(after: 0.05)
                    return instant(commit, "no still for window \(w.id)")
                }
            }
        }

        for c in request.changes {
            Log.wm.debug("window animation: \(c.id) \(String(describing: c.kind), privacy: .public) \(String(describing: c.from), privacy: .public) -> \(String(describing: c.to), privacy: .public)")
        }
        // Opens pop in only from a still that shows the window at its final size; one capture
        // is tried with a deadline of one frame, else the real window is shown live through a
        // hole in the cover (a still of another size would be stretched: live finding).
        let frameTime = 1 / Double(max(30, frameRate(for: affected)))
        var modelRequest = request
        for c in request.changes where c.kind == .reveal {
            // Shown again (app switch / unhide) while a cover is up: live through a hole, never
            // from a still (an old still would be stale, and cancelling the cover would snap
            // every other window's animation to its end).
            if let to = c.to { uncovered[c.id] = to }
        }
        for c in request.changes where c.kind == .open {
            guard let to = c.to else { continue }
            let still = cache.still(for: c.id).flatMap { $0.fits(to.size) ? $0 : nil }
                ?? cache.captureNow(c.id, timeout: frameTime).flatMap { $0.fits(to.size) ? $0 : nil }
            if still != nil {
                opensAnimated += 1
            } else {
                opensLive += 1
                uncovered[c.id] = to
                Log.wm.debug("window animation: \(c.id) opens live (no still at \(Int(to.width))x\(Int(to.height)) within a frame)")
            }
        }
        if !uncovered.isEmpty {
            for w in request.windows where uncovered[w.id] != nil { uncovered[w.id] = w.frame }
            modelRequest.windows.removeAll { uncovered[$0.id] != nil }
            modelRequest.changes.removeAll { uncovered[$0.id] != nil }
        }
        model.apply(modelRequest, at: started)
        activeSince = started
        for c in request.changes where c.kind == .move {
            guard let from = c.from, let to = c.to, model.contains(c.id) else { continue }
            if abs(from.width - to.width) > 1 || abs(from.height - to.height) > 1 {
                wantFresh[c.id] = to.size
                fresh[c.id] = nil
            } else {
                wantFresh[c.id] = nil
            }
        }
        var newDisplays: Set<CGDirectDisplayID> = []
        for d in affected where covers[d] == nil {
            guard let region = request.displays[d] else { continue }
            covers[d] = makeCover(d, region: region)
            newDisplays.insert(d)
        }
        let newCovers = !newDisplays.isEmpty
        render(at: started)
        if newCovers {
            for c in covers.values where !c.window.isVisible { c.show() }
            CATransaction.flush()
            lastShowMs = (CACurrentMediaTime() - started) * 1000
            // The motion starts once the cover is on screen (ordered in, then composited on the
            // next refresh), so its first frames are seen instead of skipped.
            // Only on the new covers: a display whose cover was already up keeps moving.
            model.delayStarts(since: started, by: CACurrentMediaTime() - started + frameTime, on: newDisplays)
            render(at: CACurrentMediaTime())
            CATransaction.flush()
            for c in covers.values {
                Log.wm.debug("window animation: cover \(c.displayID) region \(String(describing: c.region), privacy: .public) window \(String(describing: c.window.frame), privacy: .public)")
            }
            coverSince = started
            played += 1
            // The real windows move one display refresh after the flush, once the cover is
            // composited: the WindowServer composites on its own, so waiting here (≤ one frame)
            // is enough. A timer or the display link fired only after the rest of the layout
            // pass (AX raise/focus), 20-70 ms late in live tests.
            pendingCommit = commit
            requestedAt = started
            let refresh = 1 / Double(max(30, frameRate(for: affected)))
            let wait = refresh - (CACurrentMediaTime() - started)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            runPendingCommit()
        } else {
            // The retargeted animations reach the render server before the AX writes block
            // the main thread (else they would start late and jump to where they should be).
            CATransaction.flush()
            lastCommitLatencyMs = 0
            commit()
            captureFresh()
        }
        startTicking()
    }

    public func isCovering(_ id: CGWindowID) -> Bool { !covers.isEmpty && model.contains(id) }

    public func frameApplied(_ id: CGWindowID, actual: CGRect) {
        guard !covers.isEmpty, model.contains(id) else { return }
        let now = CACurrentMediaTime()
        model.retarget(id, to: actual, at: now)
        if wantFresh[id] != nil { wantFresh[id] = actual.size }
        render(at: now)
        CATransaction.flush()
    }

    public func beginDrag(_ id: CGWindowID, pointer: CGPoint, scene: WindowAnimationRequest) -> Bool {
        guard motionEnabled, cache.canCapture(), let w = scene.windows.first(where: { $0.id == id }) else { return false }
        let d = w.displayID
        if covers[d] == nil {
            guard cache.desktop(for: d) != nil else {
                cache.refreshDesktop(d)
                return false
            }
            for other in scene.windows where other.displayID == d && cache.still(for: other.id) == nil {
                scheduleRefresh(after: 0.05)
                return false
            }
        }
        let now = CACurrentMediaTime()
        model.apply(WindowAnimationRequest(changes: [], windows: scene.windows, displays: scene.displays), at: now)
        model.beginDrag(id, at: now)
        dragging = (id, CGPoint(x: pointer.x - w.frame.minX, y: pointer.y - w.frame.minY), w.frame.size, d)
        if covers[d] == nil, let region = scene.displays[d] {
            let cover = makeCover(d, region: region)
            covers[d] = cover
            render(at: now)
            cover.show()
            coverSince = now
        }
        drags += 1
        startTicking()
        return true
    }

    /// How long a prepared close waits for the window to really go (an app may refuse: "save
    /// changes?"); then the cover just leaves.
    public static let closeWait: TimeInterval = 0.5

    public func prepareClose(_ id: CGWindowID, scene: WindowAnimationRequest) -> Bool {
        guard motionEnabled, cache.canCapture(), let w = scene.windows.first(where: { $0.id == id }),
              table[.windowsOut].enabled, table[.windowsOut].durationMs > 0 else { return false }
        let d = w.displayID
        if covers[d] == nil {
            guard cache.desktop(for: d) != nil else { return false }
            for other in scene.windows where other.displayID == d && cache.still(for: other.id) == nil { return false }
        }
        let now = CACurrentMediaTime()
        model.prepareClose(id, request: scene, at: now)
        activeSince = now
        closingSoon[id] = now + Self.closeWait
        if covers[d] == nil, let region = scene.displays[d] {
            let cover = makeCover(d, region: region)
            covers[d] = cover
            render(at: now)
            cover.show()
            CATransaction.flush()
            coverSince = now
            // Composited before the app gets the close.
            let wait = 1 / Double(max(30, frameRate(for: [d]))) - (CACurrentMediaTime() - now)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        startTicking()
        return true
    }

    public func updateDrag(pointer: CGPoint, dropTarget: CGRect?) {
        guard let d = dragging else { return }
        let frame = CGRect(x: pointer.x - d.offset.x, y: pointer.y - d.offset.y, width: d.size.width, height: d.size.height)
        model.drag(d.id, to: frame)
        covers[d.display]?.showPreview(dropTarget, style: style)
        render(at: CACurrentMediaTime())
        CATransaction.flush()
    }

    public func endDrag() {
        guard let d = dragging else { return }
        dragging = nil
        activeSince = CACurrentMediaTime()
        model.endDrag(d.id, at: activeSince)
        covers[d.display]?.showPreview(nil, style: style)
        render(at: activeSince)
        CATransaction.flush()
        startTicking()
    }

    public func windowsChanged(visible: [AnimatedWindow]) {
        lastVisible = visible
        var keep = Set(visible.map(\.id))
        keep.formUnion(model.items.keys)
        cache.retain(keep)
        scheduleRefresh(after: Self.refreshDelay)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: Self.periodicRefresh, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.periodic() }
            }
        }
    }

    public func cancel() {
        let commit = pendingCommit
        pendingCommit = nil
        commit?()
        dragging = nil
        model.removeAll()
        stopTicking()
        for c in Array(covers.values) + closing { park(c) }
        covers.removeAll()
        closing.removeAll()
        closingSoon.removeAll()
        resetPassState()
    }

    private func resetPassState() {
        settledAt = nil
        uncovered.removeAll()
        fresh.removeAll()
        wantFresh.removeAll()
        freshTask?.cancel()
        freshTask = nil
    }

    /// Space / display change: stills and covers are stale.
    public func invalidate() {
        cancel()
        for c in idle.values { c.close() }
        idle.removeAll()
        cache.invalidateAll()
    }

    /// A cover for `display`: the idle one when its region still matches (no new window or
    /// backing store on the critical path), else a new one.
    private func makeCover(_ display: CGDirectDisplayID, region: CGRect) -> SnapshotCover {
        let desktop = cache.desktop(for: display)?.image
        if let c = idle.removeValue(forKey: display) {
            if c.region == region {
                c.setDesktop(desktop)
                return c
            }
            c.close()
        }
        return SnapshotCover(displayID: display, region: region, desktop: desktop, style: style)
    }

    private func park(_ cover: SnapshotCover) {
        cover.reset()
        if let old = idle[cover.displayID], old !== cover { old.close() }
        idle[cover.displayID] = cover
    }

    // MARK: Ticks

    /// Highest refresh rate among `displays` (60 when unknown).
    private func frameRate(for displays: Set<CGDirectDisplayID>) -> Int {
        let rates = NSScreen.screens.compactMap { screen -> Int? in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            return id.map { displays.contains($0) } == true ? screen.maximumFramesPerSecond : nil
        }
        return rates.max() ?? 60
    }

    private func runPendingCommit() {
        guard let commit = pendingCommit else { return }
        pendingCommit = nil
        lastCommitLatencyMs = (CACurrentMediaTime() - requestedAt) * 1000
        maxCommitLatencyMs = max(maxCommitLatencyMs, lastCommitLatencyMs)
        commit()
        captureFresh()
    }

    private func startTicking() {
        if let link {
            link.isPaused = false
            return
        }
        let target = DisplayLinkTarget { [weak self] in self?.tick() }
        guard let screen = NSScreen.screens.first else { return }
        let l = screen.displayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// Paused, not invalidated: resuming a paused link ticks on the next frame.
    private func stopTicking() {
        link?.isPaused = true
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if pendingCommit != nil, (now - requestedAt) * 1000 >= 1000 / 60 { runPendingCommit() }
        model.collectGone(at: now)
        closingSoon = closingSoon.filter { $0.value > now && model.items[$0.key]?.phase != .leaving }
        render(at: now)
        let stuck = now - activeSince > Self.hardTimeout && dragging == nil
        if covers.isEmpty {
            if closing.isEmpty { stopTicking() }
            return
        }
        let settled = dragging == nil && closingSoon.isEmpty && model.isSettled(at: now)
        if settled, settledAt == nil { settledAt = now }
        if !settled { settledAt = nil }
        // A resized window that has not redrawn at its new size yet would be revealed stale:
        // the settled cover waits a little for its fresh capture (and its cross-fade).
        let waitingForFresh = settled && (!wantFresh.isEmpty || fresh.values.contains { now - $0.at < Self.freshCrossFade })
            && now - (settledAt ?? now) < Self.freshGrace
        if (settled && !waitingForFresh) || stuck {
            if stuck { Log.wm.notice("window animation: hard timeout") }
            finish(at: now)
        }
    }

    /// Mirrors the model on every cover (only changed channels are touched, so calling this
    /// every frame is cheap; the motion itself is played by the render server).
    private func render(at now: TimeInterval) {
        let items = model.order.compactMap { model.items[$0] }
        let holes = Array(uncovered.values)
        for c in covers.values {
            c.sync(items, now: now, image: { [cache] id in cache.still(for: id) }, holes: holes, style: style)
        }
    }

    /// Everything arrived: fade the covers out over the real windows, then close them.
    private func finish(at now: TimeInterval) {
        lastAnimationMs = (now - coverSince) * 1000
        let leaving = Array(covers.values)
        covers.removeAll()
        model.removeAll()
        resetPassState()
        closing.append(contentsOf: leaving)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.coverFadeOut)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1))
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                for c in leaving { self?.park(c) }
                self?.closing.removeAll { c in leaving.contains { $0 === c } }
            }
        }
        for c in leaving {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            c.root.add(fade, forKey: "fade")
            c.root.opacity = 0
        }
        CATransaction.commit()
        Log.wm.notice("window animation: done \(Int(self.lastAnimationMs)) ms, commit latency \(String(format: "%.1f", self.lastCommitLatencyMs), privacy: .public) ms (show \(String(format: "%.1f", self.lastShowMs), privacy: .public) ms)")
        scheduleRefresh(after: Self.refreshDelay)
    }

    private func instant(_ commit: () -> Void, _ reason: String) {
        if motionEnabled {
            fallbacks += 1
            lastFallbackReason = reason
            Log.wm.notice("window animation: instant (\(reason, privacy: .public))")
        }
        commit()
    }

    // MARK: Stills

    /// Windows whose size changed: capture them again once the app has redrawn at the new size
    /// and cross-fade to that capture (the old still is never stretched to the new aspect).
    private func captureFresh() {
        guard !wantFresh.isEmpty, freshTask == nil else { return }
        let start = CACurrentMediaTime()
        freshTask = Task { @MainActor in
            defer { self.freshTask = nil }
            for at in Self.freshAttempts {
                let delay = start + at - CACurrentMediaTime()
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                if Task.isCancelled || self.covers.isEmpty || self.wantFresh.isEmpty { return }
                for (id, size) in self.wantFresh {
                    guard await self.cache.captureWindow(id) != nil, let still = self.cache.still(for: id),
                          !Task.isCancelled, self.wantFresh[id] == size else { continue }
                    if still.fits(size) {
                        self.wantFresh[id] = nil
                        self.fresh[id] = (still, CACurrentMediaTime())
                        for c in self.covers.values { c.crossFadeFresh(id, still, duration: Self.freshCrossFade) }
                        CATransaction.flush()
                    }
                }
            }
        }
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refreshNow() {
        guard covers.isEmpty, dragging == nil else { return scheduleRefresh(after: Self.refreshDelay) }
        guard motionEnabled, cache.canCapture() else { return }
        // Front-most (active) first: it is the one most likely to move next.
        let ordered = lastVisible.sorted { ($0.isActive ? 0 : 1) < ($1.isActive ? 0 : 1) }
        cache.refresh(ordered.map(\.id))
        for d in Set(lastVisible.map(\.displayID)) { cache.refreshDesktop(d) }
    }

    private func periodic() {
        guard covers.isEmpty, dragging == nil, motionEnabled, cache.canCapture() else { return }
        let now = CACurrentMediaTime()
        let stale = lastVisible.filter { w in (cache.still(for: w.id).map { now - $0.capturedAt } ?? .infinity) > Self.periodicRefresh }
        cache.refresh(stale.map(\.id))
    }
}
