import AppKit
import CaelestiaCore
import QuartzCore

/// What the controller needs from one border's on-screen surface. The real one is an NSPanel;
/// tests use a fake so the R2 bookkeeping runs headless.
@MainActor
public protocol BorderSurface: AnyObject {
    /// The surface's own window number (CGWindowID), for `query overlays` and the R2 check.
    var windowNumber: Int { get }
    func render(_ sample: BorderSample, target: BorderTarget, style: OverlayStyle)
    /// Orders the surface directly above the managed window `id`.
    func order(above id: CGWindowID)
    func close()
}

/// Global AX/CG rect (top-left origin, y down) → Cocoa screen rect (bottom-left origin, y up).
@MainActor
public enum ScreenSpace {
    public static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    public static func cocoa(_ rect: CGRect, primaryHeight: CGFloat = ScreenSpace.primaryHeight) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func scale(for rect: CGRect) -> CGFloat {
        let c = cocoa(rect)
        return NSScreen.screens.first { $0.frame.intersects(c) }?.backingScaleFactor ?? 2
    }

    /// Snaps to the device-pixel grid so a 1 pt line never straddles pixels mid-animation.
    public static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        func r(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let x = r(rect.minX), y = r(rect.minY)
        return CGRect(x: x, y: y, width: r(rect.maxX) - x, height: r(rect.maxY) - y)
    }
}

/// One border: a borderless, click-through, non-activating panel sized to the border frame plus
/// a small margin (so the pop-in spring's overshoot is never clipped), holding one ring layer
/// and, for tab groups, the group bar tabs. All layer changes happen inside one CATransaction
/// with implicit animations disabled, and the ring is sized by autoresizing in the same pass as
/// the window, so a moving border never draws a frame of stale geometry (no flicker).
@MainActor
public final class BorderWindow: NSPanel, BorderSurface {
    /// Room around the ring for scale overshoot.
    static let margin: CGFloat = 12

    private let content = CALayer()
    private let ring = CALayer()
    /// The outline. A shape stroke, not `CALayer.borderWidth`: the layer border thins out along
    /// a long edge, so the right side faded while the top-left stayed solid.
    private let stroke = CAShapeLayer()
    private var tabLayers: [(bg: CALayer, text: CATextLayer)] = []
    private var lastGroup: GroupBar?
    private var lastSize: CGSize = .zero

    public init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canHide = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        level = .normal
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        title = "SkyRose border"

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layerContentsRedrawPolicy = .never
        contentView = root
        let rootLayer = root.layer!
        rootLayer.masksToBounds = false
        content.isGeometryFlipped = true
        content.masksToBounds = false
        ring.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        ring.cornerCurve = .circular
        stroke.fillColor = nil
        stroke.lineJoin = .round
        stroke.isGeometryFlipped = true
        content.addSublayer(ring)
        content.addSublayer(stroke)
        rootLayer.addSublayer(content)
        for l in [content, ring, stroke] { l.actions = Self.noActions }
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    static let noActions: [String: any CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "transform": NSNull(), "opacity": NSNull(),
        "borderColor": NSNull(), "borderWidth": NSNull(), "cornerRadius": NSNull(), "backgroundColor": NSNull(),
        "contents": NSNull(), "string": NSNull(), "hidden": NSNull(), "sublayers": NSNull(),
    ]

    /// The panel around a ring, on whole points. The WindowServer rounds a window's origin to a
    /// whole point, so a ring on a half point has to get that half point inside the panel.
    static func panelFrame(around ring: CGRect, margin: CGFloat) -> CGRect {
        let outer = ring.insetBy(dx: -margin, dy: -margin)
        let x = outer.minX.rounded(.down), y = outer.minY.rounded(.down)
        return CGRect(x: x, y: y, width: outer.maxX.rounded(.up) - x, height: outer.maxY.rounded(.up) - y)
    }

    public func render(_ sample: BorderSample, target: BorderTarget, style: OverlayStyle) {
        let scale = ScreenSpace.scale(for: sample.frame)
        let ringRect = ScreenSpace.pixelAligned(ScreenSpace.cocoa(sample.frame), scale: scale)
        let windowRect = Self.panelFrame(around: ringRect, margin: Self.margin)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frame != windowRect { setFrame(windowRect, display: false) }
        let bounds = CGRect(origin: .zero, size: windowRect.size)
        // bounds + position (never `frame`) because `content` carries the pop-in scale transform.
        let inner = CGRect(x: ringRect.minX - windowRect.minX, y: ringRect.minY - windowRect.minY,
                           width: ringRect.width, height: ringRect.height)
        content.bounds = CGRect(origin: .zero, size: inner.size)
        content.position = CGPoint(x: inner.midX, y: inner.midY)
        // A tab group's ring goes around the window only; its bar sits above, outside it.
        ring.frame = target.group == nil ? content.bounds : GroupBarGeometry.ring(in: content.bounds, style: style)
        ring.borderWidth = 0
        ring.cornerRadius = 0
        content.transform = sample.scale == 1 ? CATransform3DIdentity : CATransform3DMakeScale(sample.scale, sample.scale, 1)
        content.opacity = Float(sample.alpha)
        let line = CGFloat(style.borderWidth)
        let windowRadii = target.corners ?? CornerRadii(uniform: style.cornerRadius)
        // The ring is the window expanded by the border width. The stroke's inner edge sits on
        // the window; its centreline is half a border out, so the corner stays concentric.
        stroke.frame = ring.frame
        stroke.lineWidth = line
        stroke.strokeColor = Self.mix(style.inactive, style.active, sample.activeMix)
        stroke.contentsScale = scale
        let centreline = stroke.bounds.insetBy(dx: line / 2, dy: line / 2)
        stroke.path = windowRadii.outset(by: style.borderWidth / 2).path(in: centreline)
        for l in [content, ring, stroke] { l.contentsScale = scale }
        layoutGroupBar(target.group, size: ringRect.size, style: style, scale: scale)
        CATransaction.commit()
        // A new surface goes straight to its place in the stack (directly above its window),
        // never to the front first: no one-frame flash over other windows.
        if !isVisible { order(.above, relativeTo: Int(target.id)) }
    }

    public func order(above id: CGWindowID) {
        order(.above, relativeTo: Int(id))
    }

    // MARK: Group bar

    private func layoutGroupBar(_ group: GroupBar?, size: CGSize, style: OverlayStyle, scale: CGFloat) {
        guard let group, !group.titles.isEmpty else {
            for t in tabLayers { t.bg.removeFromSuperlayer() }
            tabLayers = []
            lastGroup = nil
            return
        }
        guard group != lastGroup || size != lastSize else { return }
        lastGroup = group
        lastSize = size
        while tabLayers.count < group.titles.count {
            let bg = CALayer()
            let text = CATextLayer()
            bg.actions = Self.noActions
            text.actions = Self.noActions
            text.alignmentMode = .center
            text.truncationMode = .end
            bg.addSublayer(text)
            content.addSublayer(bg)
            tabLayers.append((bg, text))
        }
        while tabLayers.count > group.titles.count {
            tabLayers.removeLast().bg.removeFromSuperlayer()
        }
        let font = Self.font(style)
        let rects = GroupBarGeometry.tabs(count: group.titles.count, in: CGRect(origin: .zero, size: size), style: style)
        for (i, rect) in rects.enumerated() {
            let (bg, text) = tabLayers[i]
            let active = i == group.activeIndex
            let color = group.isLocked
                ? (active ? style.groupLockedActive : style.groupLockedInactive)
                : (active ? style.groupActive : style.groupInactive)
            bg.frame = rect.insetBy(dx: 0, dy: 0)
            bg.cornerRadius = style.groupBarRounding
            bg.cornerCurve = .circular
            bg.backgroundColor = color.cgColor
            let lineHeight = ceil(font.ascender - font.descender)
            text.frame = CGRect(x: 6, y: (rect.height - lineHeight) / 2, width: max(0, rect.width - 12), height: lineHeight)
            text.font = font
            text.fontSize = style.groupBarFontSize
            text.foregroundColor = style.groupText.cgColor
            text.string = group.titles[i]
            text.contentsScale = scale
            bg.contentsScale = scale
        }
    }

    static func font(_ style: OverlayStyle) -> NSFont {
        for name in style.groupBarFont {
            if let f = NSFont(name: name, size: style.groupBarFontSize) { return f }
        }
        return .monospacedSystemFont(ofSize: style.groupBarFontSize, weight: .medium)
    }

    static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> CGColor {
        func l(_ x: Double, _ y: Double) -> CGFloat { CGFloat(x + (y - x) * t) }
        return CGColor(srgbRed: l(a.red, b.red), green: l(a.green, b.green), blue: l(a.blue, b.blue), alpha: l(a.alpha, b.alpha))
    }
}

extension RGBA {
    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
