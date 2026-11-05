import AppKit
import CaelestiaCore
import QuartzCore
import ScreenCaptureKit

/// One display whose visible workspace changes.
public struct WorkspaceTransition: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Numbered workspaces: the new one comes in from the right when `forward`.
        case horizontal(forward: Bool)
        /// A special workspace opens on top (slidefadevert) or closes.
        case specialIn, specialOut
    }

    public var displayID: CGDirectDisplayID
    /// What slides, in global AX/CG coordinates: the display minus menu bar and Dock.
    public var region: CGRect
    public var kind: Kind
    /// Identity of the outgoing / incoming workspace content (workspace + window ids, frames
    /// and focus). A still cached under `incoming` shows exactly what will be revealed.
    public var outgoing: String
    public var incoming: String

    public init(displayID: CGDirectDisplayID, region: CGRect, kind: Kind, outgoing: String = "", incoming: String = "") {
        self.displayID = displayID
        self.region = region
        self.kind = kind
        self.outgoing = outgoing
        self.incoming = incoming
    }
}

/// Spec 4.7 workspace switch in Standard mode: real windows cannot be animated, so a cover window
/// shows a still of the outgoing workspace, the WM lays out the new one behind it, and the cover
/// slides the outgoing still out and the incoming still in (snappy, 320 ms, 20 pt gap) before it
/// goes and reveals the real windows already in place.
///
/// The incoming still is the one taken when that workspace was last left, used only if its
/// content key (window ids, frames, focus) is unchanged. A capture right after the layout cannot
/// be used: the apps redraw their un-parked windows a few frames later, so it shows an empty
/// desktop (live finding). Without a matching still, the outgoing still fades out over the real
/// windows instead.
///
/// Riko R1 rules: no snapshot is ever shown unless it was captured and is not black; the
/// outgoing capture has a short budget (else the switch happens with no effect); the cover has a
/// hard 600 ms timeout and goes on any key/mouse input. Without Screen Recording the cover is a
/// quick surface-colored cross-fade instead.
@MainActor
public final class WorkspaceSlide {
    /// Live: an SCK still of the Air display takes 66–90 ms.
    public static let outgoingBudget: TimeInterval = 0.12
    public static let hardTimeout: TimeInterval = 0.6

    public var style: OverlayStyle
    public var table: AnimationTable
    public var gap: Double
    public var canCapture: () -> Bool = { CGPreflightScreenCaptureAccess() }
    public private(set) var isActive = false
    /// Counters: effects played, skipped (capture late / black), fallbacks, aborted by input.
    public private(set) var played = 0
    public private(set) var skipped = 0
    public private(set) var fallbacks = 0
    public private(set) var aborted = 0

    private var token = 0
    private var covers: [Cover] = []
    private var proceed: (() -> Void)?
    private var waitingIncoming = false
    private var link: CADisplayLink?
    private var sampler: FrameSampler?
    private var inputMonitor: Any?
    private var content: SCShareableContent?
    /// The window animator's snapshot cache: when set, its shareable content is reused (one
    /// SCShareableContent fetch serves both).
    public var cache: SnapshotCache?
    /// Stills of workspaces as they were left, by content key (most recent last).
    private var stills: [(key: String, image: CGImage)] = []
    public static let maxStills = 4
    /// Milliseconds the last outgoing capture took (debug overlay / log).
    public private(set) var lastCaptureMs: Double = 0

    public init(style: OverlayStyle = .gabby, table: AnimationTable = .gabbySpringy, gap: Double = 20) {
        self.style = style
        self.table = table
        self.gap = gap
    }

    /// Display arrangement changed: shareable content must be fetched again.
    public func displaysChanged() {
        content = nil
        stills.removeAll()
    }

    /// Fetches the shareable content once so the first switch does not pay for it.
    public func prewarm() {
        guard canCapture(), content == nil else { return }
        Task { @MainActor in self.content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
    }

    // MARK: Protocol with the WM

    /// Called before the WM lays out a workspace change. Calls `resume` exactly once, soon
    /// (≤ `outgoingBudget` plus one run-loop turn), after the outgoing still is on screen.
    public func begin(_ transitions: [WorkspaceTransition], resume: @escaping () -> Void) {
        finish()
        token += 1
        let mine = token
        let spec = self.spec(for: transitions)
        guard !transitions.isEmpty, spec.enabled, spec.durationMs > 0 else { return resume() }
        proceed = resume
        isActive = true

        guard canCapture() else {
            fallbacks += 1
            return crossFade(transitions, mine: mine)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.outgoingBudget) { [weak self] in
            guard let self, self.token == mine, self.covers.isEmpty else { return }
            self.skipped += 1
            self.finish()
        }
        Task { @MainActor in
            let started = CACurrentMediaTime()
            var shots: [(WorkspaceTransition, CGImage)] = []
            for t in transitions {
                guard let image = await self.capture(t), self.token == mine else { break }
                shots.append((t, image))
            }
            self.lastCaptureMs = (CACurrentMediaTime() - started) * 1000
            Log.wm.notice("slide: outgoing capture \(Int(self.lastCaptureMs)) ms (\(shots.count)/\(transitions.count))")
            for (t, image) in shots where !t.outgoing.isEmpty { self.remember(image, as: t.outgoing) }
            guard self.token == mine, self.proceed != nil, shots.count == transitions.count else { return }
            self.covers = shots.map { Cover(transition: $0.0, outgoing: $0.1, style: self.style) }
            for c in self.covers { c.window.orderFrontRegardless() }
            CATransaction.flush()
            self.watchInput()
            self.armTimeout(mine)
            self.waitingIncoming = true
            DispatchQueue.main.async { self.releaseLayout() }
        }
    }

    /// Called by the WM right after the layout pass that applied the change.
    public func laidOut() {
        guard waitingIncoming else { return }
        waitingIncoming = false
        let mine = token
        let incoming = covers.map { c in stills.last(where: { $0.key == c.transition.incoming && !c.transition.incoming.isEmpty })?.image }
        guard !incoming.isEmpty, incoming.allSatisfy({ $0 != nil }) else {
            // Nothing trustworthy to slide in: fade the outgoing still away over the real windows,
            // after a few frames so the apps have redrawn them.
            Log.wm.notice("slide: no still for the incoming workspace, fading")
            fallbacks += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.fadeOutCovers(mine) }
            return
        }
        for (c, image) in zip(covers, incoming) { c.setIncoming(image!) }
        played += 1
        animate(spec: spec(for: covers.map(\.transition)), mine: mine)
    }

    private func remember(_ image: CGImage, as key: String) {
        stills.removeAll { $0.key == key }
        stills.append((key, image))
        if stills.count > Self.maxStills { stills.removeFirst(stills.count - Self.maxStills) }
    }

    /// Forgets every cached still (display change, scheme change).
    public func clearStills() { stills.removeAll() }

    /// Removes every cover now (input, timeout, a new switch, panic).
    public func finish() {
        token += 1
        stopLink()
        if let m = inputMonitor { NSEvent.removeMonitor(m) }
        inputMonitor = nil
        for c in covers { c.window.orderOut(nil); c.window.close() }
        covers = []
        waitingIncoming = false
        isActive = false
        releaseLayout()
    }

    // MARK: Internals

    private func spec(for transitions: [WorkspaceTransition]) -> AnimationSpec {
        let special = transitions.contains { $0.kind != .horizontal(forward: true) && $0.kind != .horizontal(forward: false) }
        return table[special ? .specialWorkspace : .workspaces]
    }

    private func releaseLayout() {
        let p = proceed
        proceed = nil
        p?()
    }

    private var timeoutWork: DispatchWorkItem?

    private func armTimeout(_ mine: Int) { rearmTimeout(mine, after: 0) }

    /// The cover never outlives the slide by much: `hardTimeout`, or the slide's own length
    /// (a slower `animations.speed`) plus a margin, from now.
    private func rearmTimeout(_ mine: Int, after duration: TimeInterval) {
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.token == mine else { return }
            self.finish()
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(Self.hardTimeout, duration + 0.25), execute: work)
    }

    private func watchInput() {
        // Clicks and scrolls end the cover at once (they are aimed at the real windows). Keys do
        // not: typing or the next shortcut during a ~280 ms slide cut it off mid-way (a snap).
        inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.aborted += 1
                self.finish()
            }
        }
    }

    /// The slide is played by Core Animation (render server, display rate), so a busy main thread
    /// cannot stall it half-way and make it jump; the link only notices the end.
    private func animate(spec: AnimationSpec, mine: Int) {
        let begin = CACurrentMediaTime()
        sampler = FrameSampler(spec: spec, startTime: begin)
        for c in covers { c.play(spec: spec, gap: gap, at: begin) }
        CATransaction.flush()
        rearmTimeout(mine, after: spec.duration)
        let target = DisplayLinkTarget { [weak self] in self?.step(mine) }
        guard let screen = NSScreen.screens.first else { return finish() }
        let l = screen.displayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func step(_ mine: Int) {
        guard token == mine, let sampler else { return }
        if sampler.isDone(at: CACurrentMediaTime()) { finish() }
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        sampler = nil
    }

    /// No Screen Recording: a surface-colored cover fades in, the switch happens under it, and it
    /// fades out (≈ 90 + 230 ms).
    private func crossFade(_ transitions: [WorkspaceTransition], mine: Int) {
        covers = transitions.map { Cover(transition: $0, outgoing: nil, style: style) }
        for c in covers {
            c.root.opacity = 0
            c.window.orderFrontRegardless()
        }
        watchInput()
        armTimeout(mine)
        fade(to: 1, duration: 0.09, mine: mine) { [weak self] in
            guard let self, self.token == mine else { return }
            self.releaseLayout()
            DispatchQueue.main.async { self.fadeOutCovers(mine) }
        }
    }

    private func fadeOutCovers(_ mine: Int) {
        fade(to: 0, duration: 0.23, mine: mine) { [weak self] in
            guard let self, self.token == mine else { return }
            self.finish()
        }
    }

    private func fade(to value: Float, duration: TimeInterval, mine: Int, done: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1))
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } }
        for c in covers { c.root.opacity = value }
        CATransaction.commit()
    }

    // MARK: Capture

    /// A still of `transition.region` without our own windows. Nil when capture fails, is late
    /// or comes back black (never shown then: R1).
    private func capture(_ t: WorkspaceTransition) async -> CGImage? {
        do {
            if let cache {
                content = try await cache.shareable(maxAge: 2)
            } else if content == nil {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }
            guard let content, let display = content.displays.first(where: { $0.displayID == t.displayID }) else { return nil }
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            config.sourceRect = t.region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            config.width = Int((t.region.width * scale).rounded())
            config.height = Int((t.region.height * scale).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return Self.isBlack(image) ? nil : image
        } catch {
            content = nil
            return nil
        }
    }

    /// True when an 8×8 downsample is pure #000000 (a failed capture, never a real desktop).
    nonisolated static func isBlack(_ image: CGImage) -> Bool {
        let n = 8
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] > 2 || pixels[i + 1] > 2 || pixels[i + 2] > 2 {
            return false
        }
        return true
    }
}

/// One display's cover: a click-through panel over the slide region with the outgoing still and,
/// once captured, the incoming still, on a surface-colored background (the 20 pt gap).
@MainActor
final class Cover {
    let transition: WorkspaceTransition
    let window: NSPanel
    let root: CALayer
    let outgoing = CALayer()
    let incoming = CALayer()

    init(transition: WorkspaceTransition, outgoing image: CGImage?, style: OverlayStyle) {
        self.transition = transition
        let frame = ScreenSpace.cocoa(transition.region)
        window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .stationary]
        window.title = "SkyRose workspace slide"
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        window.contentView = view
        root = view.layer!
        root.masksToBounds = true
        root.backgroundColor = style.surface.cgColor
        root.actions = BorderWindow.noActions
        for l in [outgoing, incoming] {
            l.actions = BorderWindow.noActions
            l.frame = CGRect(origin: .zero, size: frame.size)
            l.contentsGravity = .resize
            root.addSublayer(l)
        }
        outgoing.contents = image
        incoming.isHidden = true
        if image == nil { outgoing.isHidden = true }
    }

    func setIncoming(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incoming.contents = image
        incoming.isHidden = false
        switch transition.kind {
        case .specialIn:
            // The special workspace comes in over the normal one.
            root.insertSublayer(incoming, above: outgoing)
        case .specialOut, .horizontal:
            root.insertSublayer(outgoing, above: incoming)
        }
        CATransaction.commit()
        layout(progress: 0, gap: 0)
    }

    /// Plays the whole slide on the render server: both stills animate from progress 0 to 1 with
    /// the spec's curve (a spring as a `CASpringAnimation`, a Bézier as its timing function).
    func play(spec: AnimationSpec, gap: Double, at begin: TimeInterval) {
        let size = transition.region.size
        func frames(_ p: Double) -> (outgoing: CGRect, incoming: CGRect, outAlpha: Float, inAlpha: Float) {
            switch transition.kind {
            case .horizontal(let forward):
                let travel = (size.width + gap) * (forward ? -1 : 1)
                return (CGRect(x: travel * p, y: 0, width: size.width, height: size.height),
                        CGRect(x: travel * (p - 1), y: 0, width: size.width, height: size.height), 1, 1)
            case .specialIn:
                return (CGRect(origin: .zero, size: size),
                        CGRect(x: 0, y: -size.height * 0.15 * (1 - p), width: size.width, height: size.height), 1, Float(p))
            case .specialOut:
                return (CGRect(x: 0, y: -size.height * 0.15 * p, width: size.width, height: size.height),
                        CGRect(origin: .zero, size: size), Float(1 - p), 1)
            }
        }
        let a = frames(0), b = frames(1)
        func animation(_ keyPath: String, _ from: Any, _ to: Any) -> CAAnimation {
            let anim: CABasicAnimation
            switch spec.curve {
            case .spring(let s):
                let spring = CASpringAnimation(keyPath: keyPath)
                spring.mass = s.mass
                spring.stiffness = s.stiffness
                spring.damping = s.damping
                anim = spring
            case .bezier(let c):
                anim = CABasicAnimation(keyPath: keyPath)
                anim.timingFunction = CAMediaTimingFunction(controlPoints: Float(c.x1), Float(c.y1), Float(c.x2), Float(c.y2))
            }
            anim.fromValue = from
            anim.toValue = to
            anim.duration = spec.duration
            anim.beginTime = begin
            anim.fillMode = .backwards
            anim.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            return anim
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, from, to, fromAlpha, toAlpha) in [(outgoing, a.outgoing, b.outgoing, a.outAlpha, b.outAlpha),
                                                      (incoming, a.incoming, b.incoming, a.inAlpha, b.inAlpha)] {
            layer.frame = to
            layer.opacity = toAlpha
            if from != to {
                layer.add(animation("position", NSValue(point: CGPoint(x: from.midX, y: from.midY)), NSValue(point: CGPoint(x: to.midX, y: to.midY))), forKey: "slide")
            }
            if fromAlpha != toAlpha { layer.add(animation("opacity", fromAlpha, toAlpha), forKey: "fade") }
        }
        CATransaction.commit()
    }

    /// Positions both stills at eased progress `p` (may overshoot past 1).
    func layout(progress p: Double, gap: Double) {
        let size = transition.region.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch transition.kind {
        case .horizontal(let forward):
            let travel = (size.width + gap) * (forward ? -1 : 1)
            outgoing.frame = CGRect(x: travel * p, y: 0, width: size.width, height: size.height)
            incoming.frame = CGRect(x: travel * (p - 1), y: 0, width: size.width, height: size.height)
        case .specialIn:
            // slidefadevert 15 %: from 15 % below, fading in.
            outgoing.frame = CGRect(origin: .zero, size: size)
            incoming.frame = CGRect(x: 0, y: -size.height * 0.15 * (1 - p), width: size.width, height: size.height)
            incoming.opacity = Float(min(1, max(0, p)))
        case .specialOut:
            incoming.frame = CGRect(origin: .zero, size: size)
            outgoing.frame = CGRect(x: 0, y: -size.height * 0.15 * p, width: size.width, height: size.height)
            outgoing.opacity = Float(min(1, max(0, 1 - p)))
        }
        CATransaction.commit()
    }
}
