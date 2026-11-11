import AppKit
import CaelestiaCore
import Metal
import QuartzCore

/// One display's liquid surface (Caelestia `ContentWindow` BlobGroup): a full-screen,
/// click-through layer that draws the screen frame and every open drawer's background as ONE
/// signed-distance shape in Metal (`BlobShader`), so drawers grow out of the band with concave
/// fillets and fuse with each other. A behind-window blur is masked to the same shape.
///
/// It is also the drawers' clock: each frame of its display link it advances every drawer's
/// `offsetScale` (0 open, 1 hidden; Caelestia's Wrapper Behavior, expressiveDefaultSpatial ×
/// scale), slides the blob out of / into its edge, runs the velocity jelly (`Jelly`) and applies
/// the same slide + squash + fade to the drawer's content window, so background and content
/// move as one piece. Drawer content stays in its own panel (key focus, clicks); only its layer
/// transform and opacity are driven from here.
@MainActor
public final class LiquidSurface: NSView {
    // MARK: Metal

    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private static var pipelineCache: MTLRenderPipelineState?
    private static var pipelineFailed = false
    private static var queue: MTLCommandQueue?

    /// Whether the GPU path is available (it is on every Apple Silicon Mac).
    public static var isSupported: Bool { pipeline != nil }

    static var pipeline: MTLRenderPipelineState? {
        if let p = pipelineCache { return p }
        guard !pipelineFailed, let device else { return nil }
        do {
            let lib = try device.makeLibrary(source: BlobShader.source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "blob_vertex")
            d.fragmentFunction = lib.makeFunction(name: "blob_fragment")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            let p = try device.makeRenderPipelineState(descriptor: d)
            pipelineCache = p
            queue = device.makeCommandQueue()
            return p
        } catch {
            pipelineFailed = true
            Log.shell.error("liquid surface: Metal pipeline failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Layers

    private let blur = NSVisualEffectView()
    private let fillHost = NSView()
    private let fillLayer = CAMetalLayer()
    private let maskLayer = CAMetalLayer()
    public var blurEnabled = true { didSet { blur.isHidden = !blurEnabled } }

    // MARK: Look

    public var fillColor: RGBA = RGBA(r: 13, g: 14, b: 18, alpha: 0.75) { didSet { setNeedsRender() } }
    public var shadowColor: RGBA = RGBA(r: 0, g: 0, b: 0, alpha: 0.4) { didSet { setNeedsRender() } }
    /// Shadow reach (Caelestia MultiEffect blurMax 15).
    public var shadowBlur: Double = 15 { didSet { setNeedsRender() } }
    public var smoothing: Double = BlobSDF.defaultSmoothing { didSet { setNeedsRender() } }
    public var reduceMotion = false
    /// Drawer motion (`offsetScale`): curve + seconds. Reduce Motion: a short standard fade.
    public var openCurve = CaelestiaTokens.Curve.defaultSpatial.bezier
    public var openSeconds: Double = 0.4
    public var closeCurve = CaelestiaTokens.Curve.defaultSpatial.bezier
    public var closeSeconds: Double = 0.4
    /// Size / position changes of an open drawer (tab switch, more launcher rows, popout morph).
    public var morphCurve = CaelestiaTokens.Curve.defaultSpatial.bezier
    public var morphSeconds: Double = 0.4
    public var deformScale: Double = CaelestiaTokens.deformScale

    // MARK: Frame geometry (surface-local, y-down)

    public private(set) var frameInner: CGRect = .zero
    public private(set) var frameRadii = BlobRadii.uniform(25)
    public private(set) var screenRadii = BlobRadii.uniform(0)
    public private(set) var dips: [CGRect] = []
    public var drawsFrame = true { didSet { setNeedsRender() } }

    public func setFrame(inner: CGRect, radii: BlobRadii, screenRadii: BlobRadii, dips: [CGRect]) {
        guard inner != frameInner || radii != frameRadii || screenRadii != self.screenRadii || dips != self.dips else { return }
        frameInner = inner
        frameRadii = radii
        self.screenRadii = screenRadii
        self.dips = dips
        setNeedsRender()
    }

    // MARK: Drawers

    final class Drawer {
        weak var panel: ShellPanel?
        var edge: ShellEdge
        var deformAmount: Double
        var shown = false
        /// Caelestia offsetScale: 0 open, 1 hidden (slid out by its depth).
        var offset: Double = 1
        var offsetFrom: Double = 1
        var offsetTo: Double = 1
        var offsetStart: CFTimeInterval = 0
        var offsetDuration: Double = 0
        var offsetCurve = CaelestiaTokens.Curve.defaultSpatial.bezier
        /// Rest rect (surface-local, y-down) as drawn, and its morph.
        var rect: CGRect?
        var rectFrom: CGRect = .zero
        var rectTo: CGRect = .zero
        var rectStart: CFTimeInterval = 0
        var rectDuration: Double = 0
        var jelly: Jelly
        var onHidden: (() -> Void)?
        var radii: BlobRadii?

        init(panel: ShellPanel, edge: ShellEdge, deformAmount: Double, deformScale: Double) {
            self.panel = panel
            self.edge = edge
            self.deformAmount = deformAmount
            jelly = Jelly(deformScale: Jelly.scale(deformAmount: deformAmount, appearanceScale: deformScale))
        }

        var offsetRunning: Bool { offset != offsetTo }
        var rectRunning: Bool { rect != nil && rect != rectTo }
    }

    private(set) var drawers: [Drawer] = []

    func drawer(for panel: ShellPanel) -> Drawer? { drawers.first { $0.panel === panel } }

    /// Whether `panel` is on this surface (open or still closing).
    public func contains(_ panel: ShellPanel) -> Bool { drawer(for: panel) != nil }

    /// Whether `panel` is shown or still animating out.
    public func isAnimating(_ panel: ShellPanel) -> Bool {
        guard let d = drawer(for: panel) else { return false }
        return d.offsetRunning || d.rectRunning || d.jelly.isActive
    }

    /// Whether `panel` is open (or opening), not closing or gone.
    public func isShown(_ panel: ShellPanel) -> Bool { drawer(for: panel)?.shown == true }

    /// Current offsetScale of `panel` (1 when not here). For tests and `query shell`.
    public func offsetScale(of panel: ShellPanel) -> Double { drawer(for: panel)?.offset ?? 1 }

    /// The blob rect of `panel` as drawn right now (surface-local, y-down, slid by offsetScale).
    public func drawnRect(of panel: ShellPanel) -> CGRect? {
        guard let d = drawer(for: panel), let r = d.rect else { return nil }
        return slid(r, edge: d.edge, offset: d.offset)
    }

    /// Opens `panel`'s drawer: ordered in at full alpha, its content hidden, then slid in.
    public func open(_ panel: ShellPanel, edge: ShellEdge, deformAmount: Double, seconds: Double? = nil) {
        let d: Drawer
        if let existing = drawer(for: panel) {
            d = existing
            d.edge = edge
            d.deformAmount = deformAmount
            d.jelly.deformScale = Jelly.scale(deformAmount: deformAmount, appearanceScale: deformScale)
        } else {
            d = Drawer(panel: panel, edge: edge, deformAmount: deformAmount, deformScale: deformScale)
            drawers.append(d)
            d.rect = bodyRect(of: panel)
            d.rectTo = d.rect ?? .zero
        }
        d.shown = true
        d.onHidden = nil
        // Drop a hide's deferred "back to full opacity" before this show, and put the content
        // off-screen at opacity 0 before the panel is ordered in. Otherwise the first frame is
        // the drawer at full size.
        panel.cancelHideRestore()
        applyContent(d)
        panel.alphaValue = 1
        if !panel.isVisible {
            if panel.acceptsKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        } else if panel.acceptsKey {
            panel.makeKey()
        }
        animateOffset(d, to: 0, curve: reduceMotion ? CaelestiaTokens.Curve.standard.bezier : openCurve,
                      seconds: reduceMotion ? 0.12 : seconds ?? openSeconds)
    }

    /// Slides `panel`'s drawer back into its edge; `completion` runs (and the panel is ordered
    /// out) once it is fully hidden, unless it was reopened meanwhile.
    public func close(_ panel: ShellPanel, seconds: Double? = nil, completion: (() -> Void)? = nil) {
        guard let d = drawer(for: panel) else {
            panel.orderOut(nil)
            completion?()
            return
        }
        d.shown = false
        d.onHidden = completion
        if panel.isKeyWindow { panel.resignKey() }
        animateOffset(d, to: 1, curve: reduceMotion ? CaelestiaTokens.Curve.standard.bezier : closeCurve,
                      seconds: reduceMotion ? 0.12 : seconds ?? closeSeconds)
    }

    /// Removes `panel` at once (rebuilds, teardown).
    public func remove(_ panel: ShellPanel) {
        guard let i = drawers.firstIndex(where: { $0.panel === panel }) else { return }
        let d = drawers.remove(at: i)
        resetContent(of: d.panel)
        setNeedsRender()
    }

    public func removeAll() {
        for d in drawers { resetContent(of: d.panel) }
        drawers.removeAll()
        setNeedsRender()
    }

    /// The drawer's body moved or resized (SwiftUI reported a new body, or the panel moved):
    /// an open drawer morphs to it on the spatial curve, a hidden one jumps.
    public func bodyChanged(_ panel: ShellPanel) {
        guard let d = drawer(for: panel), let target = bodyRect(of: panel) else { return }
        guard target != d.rectTo || d.rect == nil else { return }
        let now = CACurrentMediaTime()
        if let current = d.rect, d.offset < 0.999, !reduceMotion {
            d.rectFrom = current
            d.rectTo = target
            d.rectStart = now
            d.rectDuration = morphSeconds
        } else {
            d.rect = target
            d.rectFrom = target
            d.rectTo = target
            d.rectDuration = 0
        }
        startLink()
        setNeedsRender()
    }

    /// Per-corner radius override for `panel` (nil: Caelestia's 28 on every corner).
    public func setRadii(_ radii: BlobRadii?, for panel: ShellPanel) {
        guard let d = drawer(for: panel), d.radii != radii else { return }
        d.radii = radii
        setNeedsRender()
    }

    private func animateOffset(_ d: Drawer, to target: Double, curve: CubicBezier, seconds: Double) {
        guard seconds > 0 else {
            d.offset = target
            d.offsetTo = target
            finishIfHidden(d)
            applyContent(d)
            setNeedsRender()
            return
        }
        d.offsetFrom = d.offset
        d.offsetTo = target
        d.offsetStart = CACurrentMediaTime()
        d.offsetDuration = seconds
        d.offsetCurve = curve
        startLink()
    }

    // MARK: Geometry

    /// The panel's reported body (panel-local y-down) in this surface's space.
    func bodyRect(of panel: ShellPanel) -> CGRect? {
        guard let body = panel.blobBody, let window else { return nil }
        let pf = panel.frame, wf = window.frame
        return CGRect(x: pf.minX + body.minX - wf.minX, y: (wf.maxY - pf.maxY) + body.minY, width: body.width, height: body.height)
    }

    /// The rest rect pushed `offset` × its depth out through its edge (Caelestia anchors the
    /// wrapper at −size × offsetScale).
    func slid(_ r: CGRect, edge: ShellEdge, offset: Double) -> CGRect {
        switch edge {
        case .top: return r.offsetBy(dx: 0, dy: -r.height * offset)
        case .bottom: return r.offsetBy(dx: 0, dy: r.height * offset)
        case .left: return r.offsetBy(dx: -r.width * offset, dy: 0)
        case .right: return r.offsetBy(dx: r.width * offset, dy: 0)
        }
    }

    // MARK: Clock

    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var needsRender = true

    private func startLink() {
        if link == nil {
            let l = displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
            lastTick = CACurrentMediaTime()
        }
        link?.isPaused = false
    }

    public func setNeedsRender() {
        needsRender = true
        startLink()
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now
        var busy = false
        for d in drawers {
            if d.offsetRunning {
                let t = d.offsetDuration > 0 ? min(1, (now - d.offsetStart) / d.offsetDuration) : 1
                d.offset = t >= 1 ? d.offsetTo : d.offsetFrom + (d.offsetTo - d.offsetFrom) * d.offsetCurve.value(at: t)
                busy = true
            }
            if d.rectRunning, let _ = d.rect {
                let t = d.rectDuration > 0 ? min(1, (now - d.rectStart) / d.rectDuration) : 1
                d.rect = t >= 1 ? d.rectTo : Interpolation.lerp(d.rectFrom, d.rectTo, d.offsetCurveValue(morphCurve, t))
                busy = true
            }
            if let r = d.rect, !reduceMotion {
                let c = slid(r, edge: d.edge, offset: d.offset)
                if d.jelly.step(center: CGPoint(x: c.midX, y: c.midY), dt: dt) { busy = true }
            }
            applyContent(d)
        }
        for d in drawers where !d.shown && !d.offsetRunning && d.offset >= 1 { finishIfHidden(d) }
        if busy || needsRender {
            needsRender = false
            render()
        }
        if !busy { l.isPaused = true }
    }

    private func finishIfHidden(_ d: Drawer) {
        guard !d.shown, d.offset >= 1, let i = drawers.firstIndex(where: { $0 === d }) else { return }
        drawers.remove(at: i)
        // orderOut while the content is still slid away at opacity 0. Resetting the layer to
        // the rest pose first painted one full frame of the open drawer.
        d.panel?.orderOutSettled()
        let done = d.onHidden
        d.onHidden = nil
        done?()
        needsRender = true
    }

    // MARK: Content

    /// Slides, squashes and fades the drawer's content window with its blob.
    private func applyContent(_ d: Drawer) {
        guard let panel = d.panel, let host = panel.contentView, let layer = host.layer else { return }
        // `actual` is where the content really sits; `rest` is where the blob is drawn (it lags
        // behind while morphing between bodies, e.g. a popout moving from item to item), so the
        // content is carried along with the drawn body.
        let rest = d.rect ?? bodyRect(of: panel)
        let actual = d.rectRunning ? (d.rectTo == .zero ? rest : d.rectTo) : rest
        let opacity = Float(min(1, max(0, 1 - d.offset)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        if let rest, let actual, let body = panel.blobBody {
            let shown = slid(rest, edge: d.edge, offset: d.offset)
            // Panel-local, y-up (AppKit layer space): slide + jelly about the body's centre.
            let h = host.bounds.height
            let centre = CGPoint(x: body.midX, y: h - body.midY)
            // Along the edge normal the content stays with the attached edge, so a tab that
            // changes the drawer's depth does not push its content around.
            let dx = d.edge == .left ? shown.minX - actual.minX : d.edge == .right ? shown.maxX - actual.maxX : shown.midX - actual.midX
            let dy = -(d.edge == .top ? shown.minY - actual.minY : d.edge == .bottom ? shown.maxY - actual.maxY : shown.midY - actual.midY)
            let m = d.jelly.deform
            // y-up of a y-down symmetric matrix flips the off-diagonal term.
            var jm = CATransform3DIdentity
            jm.m11 = m.m00; jm.m12 = -m.m01; jm.m21 = -m.m01; jm.m22 = m.m11
            // Applied in order: to the body's centre, squash, back and slide.
            let t = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-centre.x, -centre.y, 0), jm),
                                        CATransform3DMakeTranslation(centre.x + dx, centre.y + dy, 0))
            // sublayerTransform is applied about the layer's anchor point.
            let a = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
            let s = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(a.x, a.y, 0), t), CATransform3DMakeTranslation(-a.x, -a.y, 0))
            layer.sublayerTransform = s
        }
        CATransaction.commit()
    }

    private func resetContent(of panel: ShellPanel?) {
        guard let layer = panel?.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = CATransform3DIdentity
        layer.opacity = 1
        CATransaction.commit()
    }

    // MARK: Scene

    /// The group as it is right now.
    public func scene() -> BlobScene {
        var rects: [BlobRect] = dips.map {
            // A dip around the notch hangs from above the screen into the band.
            let r = CGRect(x: $0.minX, y: -BlobFrame.outerMargin, width: $0.width, height: $0.maxY + BlobFrame.outerMargin)
            return BlobRect(rect: r, radii: .uniform(FramePath.cutoutCornerRadius))
        }
        for d in drawers {
            guard let r = d.rect, r.width > 1, r.height > 1 else { continue }
            let shown = slid(r, edge: d.edge, offset: d.offset)
            rects.append(BlobRect(rect: shown, radii: d.radii ?? .uniform(CaelestiaTokens.panelRadius), deform: reduceMotion ? .identity : d.jelly.deform))
            if rects.count >= BlobScene.maxRects { break }
        }
        var frame: BlobFrame?
        if drawsFrame, frameInner.width > 0, frameInner.height > 0 {
            let m = BlobFrame.outerMargin
            frame = BlobFrame(outer: bounds.insetBy(dx: -m, dy: -m), inner: frameInner, radii: frameRadii)
        }
        return BlobScene(rects: rects, frame: frame, smoothing: smoothing)
    }

    // MARK: Init / layout

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.autoresizingMask = [.width, .height]
        blur.wantsLayer = true
        addSubview(blur)
        fillHost.wantsLayer = true
        fillHost.autoresizingMask = [.width, .height]
        addSubview(fillHost, positioned: .above, relativeTo: blur)
        for l in [fillLayer, maskLayer] {
            l.device = Self.device
            l.pixelFormat = .bgra8Unorm
            l.isOpaque = false
            l.framebufferOnly = true
            l.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull(), "frame": NSNull()]
            l.presentsWithTransaction = true
        }
        // The mask only gates the blur: one sample per point is plenty.
        maskLayer.contentsScale = 1
        fillHost.layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        blur.frame = bounds
        fillHost.frame = bounds
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = fillHost.bounds
        fillLayer.contentsScale = scale
        fillLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        maskLayer.frame = blur.bounds
        maskLayer.drawableSize = CGSize(width: max(1, bounds.width), height: max(1, bounds.height))
        if blur.layer?.mask !== maskLayer { blur.layer?.mask = maskLayer }
        CATransaction.commit()
        setNeedsRender()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    // MARK: Render

    /// Renders count (for `query shell` / tests).
    public private(set) var renders = 0

    /// Shader inputs for `scene` (see `BlobShader`).
    func buffers(_ scene: BlobScene, viewSize: CGSize, scale: Float, mask: Bool) -> (u: [SIMD4<Float>], rd: [SIMD4<Float>]) {
        let radii = BlobSDF.effectiveRadii(scene)
        var rd: [SIMD4<Float>] = []
        rd.reserveCapacity(max(1, scene.rects.count) * 5)
        for (i, r) in scene.rects.enumerated() {
            let inv = r.deform.inverse, sh = r.screenHalf, er = radii[i]
            rd.append(SIMD4(Float(r.rect.midX), Float(r.rect.midY), Float(r.rect.width / 2), Float(r.rect.height / 2)))
            rd.append(SIMD4(Float(r.excludeMask), 0, 0, Float(r.deform.minEigenvalue)))
            rd.append(SIMD4(Float(inv.m00), Float(inv.m01), Float(inv.m01), Float(inv.m11)))
            rd.append(SIMD4(Float(sh.width), Float(sh.height), 0, 0))
            rd.append(SIMD4(Float(er.topRight), Float(er.bottomRight), Float(er.bottomLeft), Float(er.topLeft)))
        }
        if rd.isEmpty { rd = Array(repeating: SIMD4<Float>(0, 0, 0, 0), count: 5) }
        let f = scene.frame
        func box(_ r: CGRect?) -> SIMD4<Float> {
            guard let r else { return .zero }
            return SIMD4(Float(r.midX), Float(r.midY), Float(r.width / 2), Float(r.height / 2))
        }
        let fr = f?.radii ?? .uniform(0)
        let u: [SIMD4<Float>] = [
            SIMD4(Float(viewSize.width), Float(viewSize.height), scale, Float(scene.smoothing)),
            SIMD4(Float(scene.rects.count), f == nil ? 0 : 1, mask ? 1 : 0, 0),
            SIMD4(Float(fillColor.red), Float(fillColor.green), Float(fillColor.blue), Float(fillColor.alpha)),
            box(f?.outer), box(f?.inner),
            SIMD4(Float(shadowColor.red), Float(shadowColor.green), Float(shadowColor.blue), Float(shadowColor.alpha)),
            SIMD4(Float(screenRadii.topRight), Float(screenRadii.bottomRight), Float(screenRadii.bottomLeft), Float(screenRadii.topLeft)),
            SIMD4(Float(shadowBlur), 0, 0, 0),
            SIMD4(Float(fr.topRight), Float(fr.bottomRight), Float(fr.bottomLeft), Float(fr.topLeft)),
        ]
        return (u, rd)
    }

    private func encode(_ cmd: MTLCommandBuffer, target: MTLTexture, scene: BlobScene, viewSize: CGSize, scale: Float, mask: Bool) {
        guard let pipeline = Self.pipeline else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        let (u, rd) = buffers(scene, viewSize: viewSize, scale: scale, mask: mask)
        u.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        rd.withUnsafeBytes { raw in
            if raw.count <= 4096 {
                enc.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 1)
            } else if let buf = Self.device?.makeBuffer(bytes: raw.baseAddress!, length: raw.count) {
                enc.setFragmentBuffer(buf, offset: 0, index: 1)
            }
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    func render() {
        guard Self.pipeline != nil, let queue = Self.queue, bounds.width > 0, bounds.height > 0 else { return }
        let scene = scene()
        guard let cmd = queue.makeCommandBuffer() else { return }
        var drawables: [CAMetalDrawable] = []
        for (layer, mask) in [(fillLayer, false), (maskLayer, true)] where !(mask && blur.isHidden) {
            guard let drawable = layer.nextDrawable() else { continue }
            encode(cmd, target: drawable.texture, scene: scene, viewSize: bounds.size, scale: Float(layer.contentsScale), mask: mask)
            drawables.append(drawable)
        }
        cmd.commit()
        cmd.waitUntilScheduled()
        for d in drawables { d.present() }
        renders += 1
    }

    /// Renders `scene` at 1 px per point into BGRA8 bytes (tests: the GPU shape matches
    /// `BlobSDF`). Nil without Metal.
    public func renderOffscreen(_ scene: BlobScene, size: CGSize, mask: Bool = true) -> [UInt8]? {
        guard Self.pipeline != nil, let device = Self.device, let queue = Self.queue else { return nil }
        let w = Int(size.width), h = Int(size.height)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d), let cmd = queue.makeCommandBuffer() else { return nil }
        encode(cmd, target: tex, scene: scene, viewSize: size, scale: 1, mask: mask)
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }
}

extension LiquidSurface.Drawer {
    func offsetCurveValue(_ curve: CubicBezier, _ t: Double) -> Double { curve.value(at: t) }
}
