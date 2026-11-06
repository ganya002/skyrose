import AppKit
import CaelestiaCore
import QuartzCore
import SwiftUI

/// Window levels of the shell (spec 5 / R5): the frame and the bar sit above normal windows and
/// floating panels but below the macOS menu bar (so a revealed menu bar is never covered);
/// drawers, OSDs and toasts sit above everything of ours.
public enum ShellLevel {
    public static let frame = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
    public static let bar = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
    public static let drawer = NSWindow.Level.popUpMenu
    public static let osd = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
}

/// Borderless, non-activating panel on every Space. Takes key focus only when `acceptsKey`
/// (launcher, session menu), so typing never activates our app and closing hands focus straight
/// back to the previous window.
public final class ShellPanel: NSPanel {
    public var acceptsKey = false
    /// Liquid surface: the drawer body (panel-local, y-down) SwiftUI last reported, the edge it
    /// slides from and its jelly amount (Caelestia `deformAmount`). Set by the controller.
    public var blobBody: CGRect? { didSet { if blobBody != oldValue { onBlobBodyChange?() } } }
    public var blobEdge: ShellEdge = .bottom
    public var blobDeformAmount: Double = 0.15
    public var onBlobBodyChange: (() -> Void)?
    /// Escape / arrows while key (launcher and session menu install one).
    public var onKeyDown: ((NSEvent) -> Bool)?

    public init(frame: CGRect, level: NSWindow.Level, clickThrough: Bool = false, name: String) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // isFloatingPanel resets the level to .floating: set it first.
        isFloatingPanel = true
        self.level = level
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = clickThrough
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        title = name
        setAccessibilityIdentifier("caelestia.\(name)")
    }

    /// Shell surfaces are laid out exactly (the frame covers an auto-hidden menu bar's strip and
    /// dips around the notch): AppKit must not push them below the menu bar. Live finding: the
    /// frame window was moved 32 pt down on the notched built-in while its drawers were not, so
    /// every drawer sat 32 pt off its band.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    public override var canBecomeKey: Bool { acceptsKey }
    public override var canBecomeMain: Bool { false }

    /// Bumped by every fade so a stale fade-out completion never orders out a re-shown panel.
    private var fadeGeneration = 0

    /// Orders the panel in (if needed) and fades it to full opacity. The window server animates
    /// the alpha; together with the SwiftUI slide this is the drawer's "slide + fade".
    public func fadeIn(duration: TimeInterval) {
        fadeGeneration += 1
        if !isVisible {
            alphaValue = 0
            if acceptsKey { makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
        } else if acceptsKey {
            makeKey()
        }
        guard duration > 0 else {
            alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// Fades the panel out and orders it out at the end (unless it was shown again meanwhile).
    public func fadeOut(duration: TimeInterval, completion: (() -> Void)? = nil) {
        fadeGeneration += 1
        let generation = fadeGeneration
        guard isVisible, duration > 0 else {
            orderOut(nil)
            alphaValue = 1
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fadeGeneration == generation else { return }
                self.orderOut(nil)
                self.alphaValue = 1
                completion?()
            }
        })
    }

    public override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    public override func cancelOperation(_ sender: Any?) {
        if let e = NSApp.currentEvent, onKeyDown?(e) == true { return }
    }
}

/// A drawer panel's content view: a transparent layer the liquid surface slides, squashes and
/// fades (its `sublayerTransform` / `opacity`), with the SwiftUI host inside.
public final class DrawerContentView: NSView {
    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    public override var isOpaque: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Transparent hosting view (no SwiftUI window background). Clicks outside `hitRegion` (view-local
/// points) fall through to whatever is below.
///
/// SwiftUI draws its controls without backing NSViews, so `NSHostingView.hitTest` returns the
/// hosting view itself for *every* point, buttons included; "pass through where the hit is the
/// hosting view" therefore dropped every click (live finding: no bar icon could be clicked with a
/// real pointer). Pass-through must be described as geometry instead.
public final class ShellHostingView<Content: View>: NSHostingView<Content> {
    public var hitRegion: ((CGPoint) -> Bool)?
    public required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isOpaque: Bool { false }

    /// The panels are never key or active: without this the first click on a control would only
    /// be swallowed.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hitRegion, hit != nil, !hitRegion(convert(point, from: superview)) { return nil }
        return hit
    }
}

/// Frosted backdrop (spec 1.4): a behind-window blur masked to a shape, under a fill of surface
/// at the base transparency, so panels read as glass in the scheme color, not stock vibrancy.
/// The blur is masked by a CAShapeLayer with the same path as the fill (a 9-slice `maskImage`
/// was ignored by the window server for the full-screen frame and blurred the whole display).
public final class FrostedView: NSView {
    private let blur = NSVisualEffectView()
    /// The fill lives in its own view above the blur (a sublayer of our layer would sit under
    /// the blur subview's layer and never show).
    private let fillView = NSView()
    private let fill = CAShapeLayer()
    private let blurMask = CAShapeLayer()
    /// Returns the shape path for a rect (y-down).
    public var shape: (CGRect) -> CGPath { didSet { needsLayout = true } }
    /// Kept for callers; unused since the mask is a shape layer.
    public var caps: NSEdgeInsets
    public var fillColor: NSColor { didSet { fill.fillColor = fillColor.cgColor } }
    public var blurEnabled = true { didSet { blur.isHidden = !blurEnabled } }

    public init(shape: @escaping (CGRect) -> CGPath, caps: NSEdgeInsets, fill fillColor: NSColor) {
        self.shape = shape
        self.caps = caps
        self.fillColor = fillColor
        super.init(frame: .zero)
        wantsLayer = true
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.autoresizingMask = [.width, .height]
        blur.wantsLayer = true
        addSubview(blur)
        for l in [fill, blurMask] {
            l.fillRule = .evenOdd
            l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull()]
        }
        fill.fillColor = fillColor.cgColor
        blurMask.fillColor = NSColor.black.cgColor
        fillView.wantsLayer = true
        fillView.autoresizingMask = [.width, .height]
        fillView.layer?.addSublayer(fill)
        addSubview(fillView, positioned: .above, relativeTo: blur)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shapes are y-down; the backing layers are y-up.
    private func layerPath() -> CGPath {
        var t = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        return shape(bounds).copy(using: &t) ?? shape(bounds)
    }

    public override func layout() {
        super.layout()
        blur.frame = bounds
        fillView.frame = bounds
        fill.frame = fillView.bounds
        refreshShape()
    }

    /// Redraws the fill and the blur mask now (call from an animation tick).
    public func refreshShape() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = layerPath()
        fill.path = path
        blurMask.frame = blur.bounds
        blurMask.path = path
        if blur.layer?.mask !== blurMask { blur.layer?.mask = blurMask }
        CATransaction.commit()
    }

    public func invalidateMask() { needsLayout = true }
}

/// A scalar eased over time on the display link (bar reveal: the frame band and the bar content
/// must move together frame by frame, which two independent SwiftUI animations cannot promise).
@MainActor
public final class ShellTween {
    public private(set) var value: Double
    private var from: Double
    private var to: Double
    private var start: CFTimeInterval = 0
    private var duration: Double = 0
    private var curve = ShellCurve.standard.bezier
    /// Set while a spring (not a Bézier) drives the tween; it keeps its velocity when retargeted.
    private var spring: CaelestiaCore.Spring?
    private var initialVelocity: Double = 0
    private var timer: Timer?
    public var onChange: ((Double) -> Void)?
    public var onFinish: ((Double) -> Void)?

    public init(_ value: Double) {
        self.value = value
        from = value
        to = value
    }

    public var target: Double { to }
    public var isRunning: Bool { timer != nil }

    public func animate(to target: Double, duration: Double, curve: ShellCurve) {
        guard target != to || isRunning else { return }
        guard duration > 0 else { return set(target) }
        from = value
        to = target
        start = CACurrentMediaTime()
        self.duration = duration
        self.curve = curve.bezier
        spring = nil
        startTimer()
    }

    /// Animates to `target` on `spring`, starting with the current velocity (so a reversal in
    /// mid-flight bends instead of jumping). Ends when the spring settles.
    public func animate(to target: Double, spring s: CaelestiaCore.Spring) {
        guard target != to || isRunning else { return }
        let now = CACurrentMediaTime()
        let v = currentVelocity(at: now)
        from = value
        to = target
        start = now
        spring = s
        initialVelocity = v
        duration = s.settlingTime(epsilon: AnimationSpec.springSettlingEpsilon) + (v == 0 ? 0 : 0.05)
        startTimer()
    }

    /// Velocity (units/s) of the running spring; 0 for Bézier tweens or when idle.
    private func currentVelocity(at now: CFTimeInterval) -> Double {
        guard isRunning, let s = spring else { return 0 }
        return s.velocity(at: now - start, from: from, to: to, initialVelocity: initialVelocity)
    }

    private func startTimer() {
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.step() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        step()
    }

    public func set(_ target: Double) {
        timer?.invalidate()
        timer = nil
        spring = nil
        from = target
        to = target
        value = target
        onChange?(target)
        onFinish?(target)
    }

    private func step() {
        let elapsed = CACurrentMediaTime() - start
        let t = min(1, elapsed / duration)
        if let s = spring {
            value = s.position(at: elapsed, from: from, to: to, initialVelocity: initialVelocity)
        } else {
            value = from + (to - from) * curve.value(at: t)
        }
        onChange?(value)
        if t >= 1 {
            value = to
            timer?.invalidate()
            timer = nil
            onFinish?(to)
        }
    }
}
