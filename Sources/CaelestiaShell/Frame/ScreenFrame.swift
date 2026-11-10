import AppKit
import CaelestiaCore

/// One display's screen frame (spec 5.1): a click-through window drawing the 10 pt band in
/// surface at the base transparency, inner radius 25. When the bar is revealed the left band
/// widens to the bar width (Caelestia: the bar *is* the left edge of the frame). On a display
/// with a notch the top band stays 10 pt and dips around the notch (`FramePath`).
///
/// With `theme.liquidSurface` the band is drawn by a `LiquidSurface`: the same SDF group also
/// carries every open drawer's background (Caelestia's single BlobGroup), so drawers grow out of
/// the band with fillets and merge with each other. Otherwise a `FrostedView` draws the band alone.
@MainActor
public final class ScreenFrameWindow {
    public let displayID: String
    public private(set) var layout: DisplayLayout
    public let panel: ShellPanel
    private let frosted: FrostedView?
    /// The liquid surface (nil when Metal is unavailable or the theme turned it off).
    public let surface: LiquidSurface?
    private var theme: ShellTheme
    public private(set) var barReveal: Double = 0

    public init(displayID: String, layout: DisplayLayout, theme: ShellTheme) {
        self.displayID = displayID
        self.layout = layout
        self.theme = theme
        panel = ShellPanel(frame: layout.area, level: ShellLevel.frame, clickThrough: true, name: "frame")
        if theme.liquidSurface, LiquidSurface.isSupported {
            let s = LiquidSurface(frame: CGRect(origin: .zero, size: layout.area.size))
            s.autoresizingMask = [.width, .height]
            panel.contentView = s
            surface = s
            frosted = nil
        } else {
            let v = FrostedView(shape: { _ in CGMutablePath() }, caps: NSEdgeInsets(), fill: theme.panelFill)
            v.frame = CGRect(origin: .zero, size: layout.area.size)
            v.autoresizingMask = [.width, .height]
            panel.contentView = v
            frosted = v
            surface = nil
        }
        applyTheme()
        configureShape()
    }

    public func update(layout: DisplayLayout, theme: ShellTheme) {
        let themeChanged = theme != self.theme
        self.layout = layout
        self.theme = theme
        if panel.frame != layout.area { panel.setFrame(layout.area, display: true) }
        if themeChanged { applyTheme() }
        configureShape()
    }

    public func setBarReveal(_ reveal: Double) {
        guard reveal != barReveal else { return }
        barReveal = reveal
        configureShape()
    }

    private func applyTheme() {
        frosted?.fillColor = theme.panelFill
        guard let s = surface else { return }
        s.fillColor = theme.scheme[.surface].withAlpha(theme.baseAlpha)
        s.shadowColor = RGBA(r: 0, g: 0, b: 0, alpha: theme.baseAlpha < 1 ? 0.35 : 0.5)
        s.reduceMotion = theme.reduceMotion
        s.openSeconds = theme.tokenSeconds(CaelestiaTokens.Duration.defaultSpatial)
        s.closeSeconds = theme.tokenSeconds(CaelestiaTokens.DrawerMs.other.close)
        s.morphSeconds = theme.tokenSeconds(CaelestiaTokens.Duration.defaultSpatial)
    }

    private func configureShape() {
        let insets = layout.frameInsets(barReveal: barReveal, swell: true)
        let r = theme.frameRounding
        let cutouts = layout.localCutouts
        let thickness = layout.thickness
        let outerRadii = layout.outerRadii
        let innerRadii = layout.innerRadii(base: r)
        if let s = surface {
            let outer = CGRect(origin: .zero, size: layout.area.size)
            let inner = FramePath.inner(of: outer, insets: insets)
            s.drawsFrame = thickness > 0 || barReveal > 0
            s.setFrame(inner: inner, radii: Self.blob(innerRadii), screenRadii: Self.blob(outerRadii),
                       dips: FramePath.dips(cutouts: cutouts, inner: inner, thickness: thickness))
            return
        }
        guard let view = frosted else { return }
        view.shape = { rect in
            FramePath.path(outer: rect, insets: insets, outerRadii: outerRadii, innerRadii: innerRadii, cutouts: cutouts, thickness: thickness)
        }
        view.caps = NSEdgeInsets(top: insets.top + r, left: insets.left + r, bottom: insets.bottom + r, right: insets.right + r)
        view.refreshShape()
    }

    static func blob(_ c: CornerRadii) -> BlobRadii {
        BlobRadii(topRight: c.topRight, bottomRight: c.bottomRight, bottomLeft: c.bottomLeft, topLeft: c.topLeft)
    }

    public func show() { panel.orderFrontRegardless() }
    public func close() {
        surface?.removeAll()
        panel.orderOut(nil)
        panel.close()
    }
}
