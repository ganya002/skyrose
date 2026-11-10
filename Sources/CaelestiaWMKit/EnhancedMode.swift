import CaelestiaCore
import CaelestiaOverlay
import CaelestiaPlatform
import CoreGraphics
import Foundation
import QuartzCore

/// SIP-off mode: talks to the scripting addition in the Dock (`SAClient`) when `[sipOff]
/// enabled` is on. Never required: while the SA is not loaded, answers another version, or a
/// command fails, `active` is false and the WM uses its SIP-on paths (snapshot animator, slide,
/// opaque windows). It re-probes every few seconds, so loading the SA later just switches over.
@MainActor
public final class EnhancedMode {
    public private(set) var active = false
    public private(set) var capabilities: SACapabilities = []
    public private(set) var config = SIPOffConfig()
    public private(set) var windowOpacity = 0.95
    /// Called when `active` (or what it may do) changes: the daemon swaps the window animator.
    public var onChange: (() -> Void)?
    public static let probeInterval: TimeInterval = 5
    /// How long windows stay transparent while a workspace switch moves them.
    public static let switchRestoreDelay: TimeInterval = 0.06

    let client: SAClient
    private var probeTimer: Timer?
    private var recordedUse = false
    /// Alpha SkyRose last set per window (absent = untouched, i.e. 1).
    private(set) var alphaSent: [CGWindowID: Double] = [:]
    private(set) var raisedLevel: Set<CGWindowID> = []
    private(set) var shadowOff: Set<CGWindowID> = []
    private var switchHidden: Set<CGWindowID> = []
    private var fullscreen: Set<CGWindowID> = []
    let manifest: RestoreManifest?
    /// Tests replace it.
    var applyMenuBar: (Bool) -> Void = { MenuBarOverride.set(hidden: $0) }
    private var menuBarHidden = false

    public private(set) lazy var animator = EnhancedWindowAnimator(mode: self)

    public init(client: SAClient = SAClient(), manifest: RestoreManifest? = RestoreManifest()) {
        self.client = client
        self.manifest = manifest
    }

    // MARK: What may be used now

    public var canAnimate: Bool { active && config.animations && capabilities.contains(.transform) && capabilities.contains(.alpha) }
    public var instantWorkspaces: Bool { active && config.instantWorkspaces && capabilities.contains(.alpha) }
    public var hidesMenuBar: Bool { active && config.hideMenuBar }
    public var status: String {
        if !config.enabled { return "off" }
        if !active { return "waiting for the scripting addition" }
        return "active (" + capabilities.names.joined(separator: ", ") + ")"
    }

    // MARK: Lifecycle

    public func apply(config c: Config) {
        let was = (config, windowOpacity)
        let wasActive = active
        config = c.sipOff
        windowOpacity = min(1, max(0.1, c.wm.windowOpacity))
        if !config.enabled {
            if active || client.isConnected { deactivate(reset: true) }
            probeTimer?.invalidate()
            probeTimer = nil
            syncMenuBar()
            return
        }
        if !active { probe() }
        if probeTimer == nil {
            let t = Timer(timeInterval: Self.probeInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if self?.active == false { self?.probe() } }
            }
            RunLoop.main.add(t, forMode: .common)
            probeTimer = t
        }
        if wasActive, active, was != (config, windowOpacity) {
            // Feature switches changed: undo everything, the next layout pass re-applies.
            _ = client.reset()
            forgetSent()
            onChange?()
        }
        syncMenuBar()
    }

    private func syncMenuBar() {
        guard hidesMenuBar != menuBarHidden else { return }
        menuBarHidden = hidesMenuBar
        applyMenuBar(menuBarHidden)
    }

    /// Tries the socket; switches on when the SA answers.
    public func probe() {
        guard config.enabled, !active, let hello = client.connect() else { return }
        active = true
        capabilities = hello.capabilities
        forgetSent()
        syncMenuBar()
        Log.wm.notice("SIP-off mode: scripting addition v\(hello.version, privacy: .public) loaded (\(hello.capabilities.names.joined(separator: ","), privacy: .public))")
        if !recordedUse {
            recordedUse = true
            // The SIP reminder at uninstall is shown only once this mode was really used.
            try? manifest?.recordModeUsed(.sipOff, note: "scripting addition v\(hello.version)")
        }
        onChange?()
    }

    /// Quit / panic: every change the SA made goes back, then the connection closes.
    public func shutdown() {
        probeTimer?.invalidate()
        probeTimer = nil
        animator.cancel()
        if client.isConnected { _ = client.reset() }
        deactivate(reset: false)
    }

    private func deactivate(reset: Bool) {
        if reset, client.isConnected { _ = client.reset() }
        client.close()
        let was = active
        active = false
        capabilities = []
        forgetSent()
        syncMenuBar()
        if was {
            Log.wm.notice("SIP-off mode: scripting addition gone, back to the SIP-on paths")
            onChange?()
        }
    }

    private func forgetSent() {
        alphaSent.removeAll()
        raisedLevel.removeAll()
        shadowOff.removeAll()
        switchHidden.removeAll()
    }

    /// Any failed command: the SA went away (Dock restarted, macOS update) → SIP-on paths.
    func check() {
        if active, !client.isConnected { deactivate(reset: false) }
    }

    // MARK: Per layout pass

    public struct WindowInfo: Equatable, Sendable {
        public var id: CGWindowID
        public var fullscreen: Bool
        public var pinned: Bool
        public init(id: CGWindowID, fullscreen: Bool, pinned: Bool) {
            self.id = id
            self.fullscreen = fullscreen
            self.pinned = pinned
        }
    }

    /// The alpha a visible window should have.
    public func targetAlpha(_ id: CGWindowID) -> Double {
        guard active, config.opacity, capabilities.contains(.alpha) else { return 1 }
        return fullscreen.contains(id) ? 1 : windowOpacity
    }

    /// After every layout pass: opacity, shadows and pinned levels of the visible windows.
    public func layoutApplied(_ windows: [WindowInfo]) {
        guard active else { return }
        fullscreen = Set(windows.filter(\.fullscreen).map(\.id))
        let ids = Set(windows.map(\.id))
        for w in windows where !switchHidden.contains(w.id) {
            // Alpha waits for a running animation (its last frame sets the target alpha); shadow
            // and level do not, or a window pinned mid-animation never got its level (live 3b).
            let a = targetAlpha(w.id)
            if capabilities.contains(.alpha), !animator.isCovering(w.id), alphaSent[w.id] != a, (alphaSent[w.id] != nil || a != 1) {
                if client.setAlpha(w.id, a) { alphaSent[w.id] = a }
            }
            if capabilities.contains(.shadow) {
                let off = !config.shadows && !w.fullscreen
                if off, !shadowOff.contains(w.id), client.setShadow(w.id, false) { shadowOff.insert(w.id) }
                if !off, shadowOff.contains(w.id), client.setShadow(w.id, true) { shadowOff.remove(w.id) }
            }
            if capabilities.contains(.level) {
                let top = config.pinOnTop && w.pinned
                // kCGFloatingWindowLevel: above normal windows, below SkyRose's shell panels.
                if top, !raisedLevel.contains(w.id), client.setLevel(w.id, Int(CGWindowLevelForKey(.floatingWindow))) { raisedLevel.insert(w.id) }
                if !top, raisedLevel.contains(w.id), client.resetLevel(w.id) { raisedLevel.remove(w.id) }
            }
        }
        // Windows that went away: forget them (the SA restores what it tracked on reset).
        for id in Array(alphaSent.keys) where !ids.contains(id) && !switchHidden.contains(id) { alphaSent[id] = nil }
        check()
    }

    // MARK: Instant workspace switches

    /// Makes windows invisible right before the WM moves them (parking / unparking), so a
    /// switch is a clean swap; `restoreAfterSwitch` brings their alpha back once they are moved.
    public func hideForSwitch(_ ids: [CGWindowID]) {
        guard instantWorkspaces, !ids.isEmpty else { return }
        for id in ids where client.setAlpha(id, 0) { switchHidden.insert(id) }
        check()
    }

    public func restoreAfterSwitch() {
        guard !switchHidden.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.switchRestoreDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let ids = self.switchHidden
                self.switchHidden.removeAll()
                guard self.active else { return }
                for id in ids {
                    let a = self.targetAlpha(id)
                    if self.client.setAlpha(id, a) { self.alphaSent[id] = a }
                }
                self.check()
            }
        }
    }
}

/// Real-window animations through the SA: the WM's frames are written at once (`commit`), then
/// each window's transform shows it travelling from its old rect to its new one on LiquidMotion
/// springs (open: pops from 80 % and fades in; move: ζ 0.72). Live content, no stills. A window
/// the SA cannot reach just ends up at its frame.
@MainActor
public final class EnhancedWindowAnimator: WindowAnimator {
    struct Track {
        var from: CGRect
        var to: CGRect
        var fromAlpha: Double
        var toAlpha: Double
        var start: CFTimeInterval
        var spring: Spring
        var duration: Double
        /// Last rect sent (where the window is drawn now).
        var current: CGRect
    }

    private weak var mode: EnhancedMode?
    private var tracks: [CGWindowID: Track] = [:]
    private var timer: Timer?
    public static let popScale = 0.8
    public static let closeSeconds = 0.18

    init(mode: EnhancedMode) { self.mode = mode }

    public var isAnimating: Bool { !tracks.isEmpty }
    public func isCovering(_ id: CGWindowID) -> Bool { tracks[id] != nil }

    /// `rect` scaled by `s` around its centre.
    public static func scaled(_ rect: CGRect, _ s: Double) -> CGRect {
        CGRect(x: rect.midX - rect.width * s / 2, y: rect.midY - rect.height * s / 2, width: rect.width * s, height: rect.height * s)
    }

    public static func lerp(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
               width: max(2, a.width + (b.width - a.width) * p), height: max(2, a.height + (b.height - a.height) * p))
    }

    public func animate(_ request: WindowAnimationRequest, commit: @escaping () -> Void) {
        guard let mode, mode.canAnimate else { commit(); return }
        let now = CACurrentMediaTime()
        var first: [SAProtocol.Visual] = []
        for c in request.changes {
            guard let to = c.to else { continue }
            let target = mode.targetAlpha(c.id)
            switch c.kind {
            case .move:
                guard let from = tracks[c.id]?.current ?? c.from, from != to, from.width > 1, from.height > 1 else { continue }
                tracks[c.id] = Track(from: from, to: to, fromAlpha: target, toAlpha: target, start: now, spring: LiquidMotion.windowMove,
                                     duration: LiquidMotion.settle, current: from)
                first.append(SAProtocol.Visual(id: c.id, rect: from))
            case .open:
                let from = Self.scaled(to, Self.popScale)
                tracks[c.id] = Track(from: from, to: to, fromAlpha: 0, toAlpha: target, start: now, spring: LiquidMotion.windowPop,
                                     duration: LiquidMotion.settle, current: from)
                first.append(SAProtocol.Visual(id: c.id, rect: from, alpha: 0))
            case .close, .leave, .reveal:
                continue
            }
        }
        guard !first.isEmpty else { commit(); return }
        // Frames and the first transforms land in one screen update (no frame at the new rect).
        _ = mode.client.command("freeze")
        commit()
        _ = mode.client.visual(first)
        _ = mode.client.command("thaw")
        mode.check()
        startTimer()
    }

    /// The WM's own close action: shrink + fade the real window, then close it. If it is still
    /// there afterwards (a "save changes?" sheet), it is shown again.
    public func closeAnimated(_ id: CGWindowID, frame: CGRect, close: @escaping () -> Void) -> Bool {
        guard let mode, mode.canAnimate else { return false }
        let now = CACurrentMediaTime()
        tracks[id] = Track(from: frame, to: Self.scaled(frame, Self.popScale), fromAlpha: mode.targetAlpha(id), toAlpha: 0, start: now,
                           spring: LiquidMotion.windowMove, duration: Self.closeSeconds, current: frame)
        startTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeSeconds) { [weak self] in
            MainActor.assumeIsolated {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated {
                        guard let self, let mode = self.mode, mode.active else { return }
                        self.tracks[id] = nil
                        _ = mode.client.visualReset([id])
                        _ = mode.client.setAlpha(id, mode.targetAlpha(id))
                    }
                }
            }
        }
        return true
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let mode, mode.active else { cancel(); return }
        let now = CACurrentMediaTime()
        var visuals: [SAProtocol.Visual] = []
        var finished: [CGWindowID] = []
        for (id, var tr) in tracks {
            let t = now - tr.start
            if t >= tr.duration {
                finished.append(id)
                continue
            }
            let p = tr.spring.position(at: t, from: 0, to: 1)
            let linear = min(1, t / tr.duration)
            tr.current = Self.lerp(tr.from, tr.to, p)
            tracks[id] = tr
            let alpha = tr.fromAlpha == tr.toAlpha ? nil : tr.fromAlpha + (tr.toAlpha - tr.fromAlpha) * min(1, linear * 1.6)
            visuals.append(SAProtocol.Visual(id: id, rect: tr.current, alpha: alpha))
        }
        if !visuals.isEmpty { _ = mode.client.visual(visuals) }
        if !finished.isEmpty {
            let ends = finished.compactMap { id -> (CGWindowID, Double)? in tracks.removeValue(forKey: id).map { (id, $0.toAlpha) } }
            _ = mode.client.visualReset(ends.map(\.0))
            for (id, a) in ends where a > 0 { _ = mode.client.setAlpha(id, a) }
        }
        mode.check()
        if tracks.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    public func prepareClose(_ id: CGWindowID, scene: WindowAnimationRequest) -> Bool { false }
    public func beginDrag(_ id: CGWindowID, pointer: CGPoint, scene: WindowAnimationRequest) -> Bool { false }
    public func updateDrag(pointer: CGPoint, dropTarget: CGRect?) {}
    public func endDrag() {}
    public func windowsChanged(visible: [AnimatedWindow]) {}

    public func frameApplied(_ id: CGWindowID, actual: CGRect) {
        tracks[id]?.to = actual
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
        let ids = Array(tracks.keys)
        let alphas = tracks.mapValues(\.toAlpha)
        tracks.removeAll()
        guard let mode, mode.client.isConnected, !ids.isEmpty else { return }
        _ = mode.client.visualReset(ids)
        for id in ids { _ = mode.client.setAlpha(id, max(alphas[id] ?? 1, mode.targetAlpha(id))) }
    }
}
