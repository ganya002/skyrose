import AppKit
import CaelestiaCore
import CaelestiaPlatform
import QuartzCore

/// Owns every border surface. Scenes from the WM go through the pure `OverlayEngine`; a display
/// link samples it while anything moves and stops when everything is idle (zero CPU at rest).
///
/// R2 (no ghost overlays): a surface exists only for an id the engine holds. Ids removed by a
/// scene close their surface in the same call; fade-outs close the moment they finish; a hard
/// sweep on every tick closes any surface the engine no longer knows. `removeAll()` (panic,
/// quit, game mode) closes everything synchronously.
@MainActor
public final class OverlayController {
    public enum Ticking {
        /// CADisplayLink on the main screen (the daemon).
        case displayLink
        /// Only when `tick(at:)` is called (tests).
        case manual
    }

    public var style: OverlayStyle {
        didSet { redrawAll() }
    }
    public var table: AnimationTable {
        get { engine.table }
        set { engine.table = newValue }
    }
    /// Game mode / borders off: nothing is drawn and every surface is closed.
    public var isEnabled = true {
        didSet { if !isEnabled { removeAll() } else if let lastScene { apply(lastScene) } }
    }

    /// How long a border follows its window's real frame after an external move notification.
    public static let trackingWindow: TimeInterval = 0.5

    public private(set) var engine = OverlayEngine()
    public private(set) var surfaces: [CGWindowID: any BorderSurface] = [:]
    private var trackUntil: [CGWindowID: TimeInterval] = [:]
    private var lastScene: OverlayScene?
    private var rendered: [CGWindowID: (sample: BorderSample, target: BorderTarget)] = [:]
    private let ticking: Ticking
    private let makeSurface: () -> any BorderSurface
    private let clock: () -> TimeInterval
    /// Real frame of a managed window (CG bounds), used while tracking a drag.
    public var realFrame: (CGWindowID) -> CGRect?
    /// Which of the given windows are on screen right now (CGWindowList). A managed window on
    /// another native Space is not: its border must not be drawn here (live R2 finding: ordering
    /// a new border above an off-Space window leaves it on the current Space as a ghost).
    public var onScreen: (Set<CGWindowID>) -> Set<CGWindowID>
    /// Targets whose window is on screen; only they have a surface.
    public private(set) var visibleTargets: Set<CGWindowID> = []
    private var spaceObserver: NSObjectProtocol?
    private var link: CADisplayLink?
    /// Counters for `query overlays` / the debug overlay.
    public private(set) var ticks = 0
    public private(set) var surfacesCreated = 0
    public private(set) var surfacesClosed = 0

    public init(
        style: OverlayStyle = .gabby, table: AnimationTable = .gabbySpringy, ticking: Ticking = .displayLink,
        makeSurface: @escaping () -> any BorderSurface = { BorderWindow() },
        clock: @escaping () -> TimeInterval = CACurrentMediaTime,
        realFrame: @escaping (CGWindowID) -> CGRect? = OverlayController.cgBounds,
        onScreen: @escaping (Set<CGWindowID>) -> Set<CGWindowID> = OverlayController.cgOnScreen
    ) {
        self.style = style
        self.ticking = ticking
        self.makeSurface = makeSurface
        self.clock = clock
        self.realFrame = realFrame
        self.onScreen = onScreen
        engine.table = table
        if ticking == .displayLink {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVisibility() }
            }
        }
    }

    /// Re-reads which targets are on screen: surfaces of off-screen targets close, on-screen ones
    /// without a surface get one (drawn at their current sample).
    public func refreshVisibility() {
        guard isEnabled else { return }
        visibleTargets = onScreen(Set(engine.borders.keys))
        for id in Array(surfaces.keys) where !visibleTargets.contains(id) { closeSurface(id) }
        render(at: clock())
    }

    // MARK: Scenes

    /// `moving`: one animation frame. When the set of windows is unchanged, the borders only move:
    /// no window-server query, no re-ordering (each costs milliseconds and dropped frames).
    public func apply(_ scene: OverlayScene, moving: Bool = false) {
        lastScene = scene
        guard isEnabled else { return }
        let now = clock()
        let before = Set(engine.borders.keys)
        let removed = engine.apply(scene, at: now)
        engine.advance(at: now)
        for id in removed { closeSurface(id) }
        for id in trackUntil.keys where !scene.ids.contains(id) { trackUntil[id] = nil }
        if moving, Set(engine.borders.keys) == before {
            render(at: now)
            scheduleTicks(at: now)
            return
        }
        visibleTargets = onScreen(Set(engine.borders.keys))
        for id in Array(surfaces.keys) where !visibleTargets.contains(id) { closeSurface(id) }
        render(at: now)
        for b in scene.borders { surfaces[b.id]?.order(above: b.id) }
        scheduleTicks(at: now)
        if ticking == .displayLink {
            // A window that was just created or unparked may reach the window server a moment
            // after the WM sees it: look again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refreshVisibility() }
        }
    }

    /// A frame SkyRose itself just wrote. The border is on that rect, fully visible, this refresh.
    public func followLiveFrame(_ id: CGWindowID, _ frame: CGRect) {
        guard isEnabled, engine.borders[id] != nil else { return }
        let now = clock()
        engine.snapVisible(id, frame: frame)
        if !visibleTargets.contains(id), onScreen([id]).contains(id) { visibleTargets.insert(id) }
        render(at: now)
    }

    /// The app or the user moved `id` (not us): follow its real frame 1:1 for a moment.
    public func noteExternalMove(_ id: CGWindowID) {
        guard isEnabled, engine.borders[id] != nil else { return }
        let now = clock()
        trackUntil[id] = now + Self.trackingWindow
        if !visibleTargets.contains(id), onScreen([id]).contains(id) { visibleTargets.insert(id) }
        trackRealFrames(at: now)
        render(at: now)
        scheduleTicks(at: now)
    }

    /// Closes every surface now.
    public func removeAll() {
        _ = engine.removeAll()
        for id in Array(surfaces.keys) { closeSurface(id) }
        trackUntil.removeAll()
        stopTicking()
    }

    // MARK: Ticks

    /// One frame: tracking, sampling, drawing, closing finished fade-outs.
    public func tick(at now: TimeInterval) {
        ticks += 1
        trackRealFrames(at: now)
        engine.advance(at: now)
        render(at: now)
        for id in engine.collectGone(at: now) { closeSurface(id) }
        // R2 sweep: a surface without an engine entry must not survive a frame.
        for id in surfaces.keys where engine.borders[id] == nil { closeSurface(id) }
        trackUntil = trackUntil.filter { $0.value > now }
        if !needsTicks(at: now) { stopTicking() }
    }

    public func needsTicks(at now: TimeInterval) -> Bool {
        engine.isAnimating(at: now) || !trackUntil.isEmpty
    }

    private func trackRealFrames(at now: TimeInterval) {
        for (id, until) in trackUntil where until > now {
            guard let real = realFrame(id), !real.isNull, let b = engine.borders[id] else { continue }
            let w = style.borderWidth
            var frame = real.insetBy(dx: -w, dy: -w)
            if b.target.group != nil {
                frame.origin.y -= style.groupBarReserved
                frame.size.height += style.groupBarReserved
            }
            engine.track(id, frame: frame, at: now)
        }
    }

    private func render(at now: TimeInterval, force: Bool = false) {
        for (id, sample) in engine.samples(at: now) {
            guard let b = engine.borders[id], visibleTargets.contains(id) else { continue }
            let surface: any BorderSurface
            if let s = surfaces[id] {
                surface = s
            } else {
                surface = makeSurface()
                surfaces[id] = surface
                surfacesCreated += 1
            }
            // Idle borders are not touched: only what changed reaches the window server.
            if !force, let last = rendered[id], last.sample == sample, last.target == b.target { continue }
            surface.render(sample, target: b.target, style: style)
            rendered[id] = (sample, b.target)
        }
    }

    private func redrawAll() {
        render(at: clock(), force: true)
    }

    private func closeSurface(_ id: CGWindowID) {
        rendered[id] = nil
        guard let s = surfaces.removeValue(forKey: id) else { return }
        s.close()
        surfacesClosed += 1
    }

    private func scheduleTicks(at now: TimeInterval) {
        guard ticking == .displayLink, needsTicks(at: now), link == nil else { return }
        let target = DisplayLinkTarget { [weak self] in
            guard let self else { return }
            self.tick(at: self.clock())
        }
        guard let screen = NSScreen.screens.first else { return }
        let l = screen.displayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopTicking() {
        link?.invalidate()
        link = nil
    }

    // MARK: Queries

    /// Every border surface: target window → overlay window number.
    public var windowNumbers: [CGWindowID: Int] { surfaces.mapValues(\.windowNumber) }

    /// On-screen windows among `ids` (current Space, not minimized).
    public nonisolated static func cgOnScreen(_ ids: Set<CGWindowID>) -> Set<CGWindowID> {
        guard !ids.isEmpty, let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return Set(CGWindowSnapshot.parse(infos).map(\.id)).intersection(ids)
    }

    /// Real CG bounds of a window (top-left space).
    public nonisolated static func cgBounds(_ id: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let snapshot = CGWindowSnapshot.parse(info).first(where: { $0.id == id }) else { return nil }
        return snapshot.bounds
    }
}

/// CADisplayLink needs an Objective-C target.
@MainActor
final class DisplayLinkTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func step(_ link: CADisplayLink) { action() }
}
