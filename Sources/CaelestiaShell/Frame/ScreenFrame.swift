import AppKit
import CaelestiaCore

/// One display's screen frame (spec 5.1): a click-through window drawing the 10 pt band in
/// surface at the base transparency, inner radius 25. When the bar is revealed the left band
/// widens to the bar width (Caelestia: the bar *is* the left edge of the frame). On a display
/// with a notch the top band stays 10 pt and dips around the notch (`FramePath`).
@MainActor
public final class ScreenFrameWindow {
    public let displayID: String
    public private(set) var layout: DisplayLayout
    public let panel: ShellPanel
    private let view: FrostedView
    private var theme: ShellTheme
    public private(set) var barReveal: Double = 0

    public init(displayID: String, layout: DisplayLayout, theme: ShellTheme) {
        self.displayID = displayID
        self.layout = layout
        self.theme = theme
        panel = ShellPanel(frame: layout.area, level: ShellLevel.frame, clickThrough: true, name: "frame")
        view = FrostedView(shape: { _ in CGMutablePath() }, caps: NSEdgeInsets(), fill: theme.panelFill)
        view.frame = CGRect(origin: .zero, size: layout.area.size)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        configureShape()
    }

    public func update(layout: DisplayLayout, theme: ShellTheme) {
        let themeChanged = theme != self.theme
        self.layout = layout
        self.theme = theme
        if panel.frame != layout.area { panel.setFrame(layout.area, display: true) }
        if themeChanged { view.fillColor = theme.panelFill }
        configureShape()
    }

    public func setBarReveal(_ reveal: Double) {
        guard reveal != barReveal else { return }
        barReveal = reveal
        configureShape()
    }

    private func configureShape() {
        let insets = layout.frameInsets(barReveal: barReveal, swell: true)
        let r = theme.frameRounding
        let cutouts = layout.localCutouts
        let thickness = layout.thickness
        let outerRadii = layout.outerRadii
        let innerRadii = layout.innerRadii(base: r)
        view.shape = { rect in
            FramePath.path(outer: rect, insets: insets, outerRadii: outerRadii, innerRadii: innerRadii, cutouts: cutouts, thickness: thickness)
        }
        view.caps = NSEdgeInsets(top: insets.top + r, left: insets.left + r, bottom: insets.bottom + r, right: insets.right + r)
        view.refreshShape()
    }

    public func show() { panel.orderFrontRegardless() }
    public func close() { panel.orderOut(nil); panel.close() }
}
