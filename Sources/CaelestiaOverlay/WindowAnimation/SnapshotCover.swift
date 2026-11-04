import AppKit
import CaelestiaCore
import QuartzCore

/// One display's animation cover: a click-through panel over the whole display (below the shell's
/// frame and bar, above normal windows) holding the desktop still and one tile per window (its
/// still plus its border ring). While it is up the real windows underneath get their final frames.
@MainActor
final class SnapshotCover {
    @MainActor final class Tile {
        let container = CALayer()
        let image = CALayer()
        let ring = CALayer()
        var hasImage = false

        init() {
            for l in [container, image, ring] { l.actions = BorderWindow.noActions }
            image.contentsGravity = .resize
            image.minificationFilter = .trilinear
            ring.cornerCurve = .circular
            container.addSublayer(image)
            container.addSublayer(ring)
        }
    }

    let displayID: CGDirectDisplayID
    /// Display frame, global top-left.
    let region: CGRect
    let window: NSPanel
    let root: CALayer
    let background = CALayer()
    let preview = CALayer()
    private(set) var tiles: [CGWindowID: Tile] = [:]
    private let scale: CGFloat

    init(displayID: CGDirectDisplayID, region: CGRect, desktop: CGImage?, style: OverlayStyle) {
        self.displayID = displayID
        self.region = region
        let frame = ScreenSpace.cocoa(region)
        scale = ScreenSpace.scale(for: region)
        window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .stationary, .canJoinAllSpaces]
        window.title = "Caelestia window animation"
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .never
        window.contentView = view
        root = view.layer!
        root.isGeometryFlipped = true
        root.masksToBounds = true
        root.actions = BorderWindow.noActions
        root.backgroundColor = style.surface.cgColor
        background.actions = BorderWindow.noActions
        background.frame = CGRect(origin: .zero, size: frame.size)
        background.contentsGravity = .resize
        background.contents = desktop
        root.addSublayer(background)
        preview.actions = BorderWindow.noActions
        preview.isHidden = true
        preview.cornerCurve = .circular
        preview.zPosition = 10_000
        root.addSublayer(preview)
    }

    func setDesktop(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.contents = image
        CATransaction.commit()
    }

    /// Draws `samples` (back to front) with the stills `image(id)` returns.
    func render(_ samples: [WindowMotionSample], image: (CGWindowID) -> SnapshotCache.Still?, style: OverlayStyle) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var seen: Set<CGWindowID> = []
        for (z, s) in samples.enumerated() where s.displayID == displayID {
            seen.insert(s.id)
            let tile: Tile
            if let t = tiles[s.id] { tile = t } else {
                tile = Tile()
                tiles[s.id] = tile
                root.addSublayer(tile.container)
            }
            if !tile.hasImage, let still = image(s.id) {
                tile.image.contents = still.image
                tile.image.contentsRect = still.contentRect
                tile.hasImage = true
            }
            let bw = s.decorated ? style.borderWidth : 0
            let local = s.frame.offsetBy(dx: -region.minX, dy: -region.minY)
            let ringRect = ScreenSpace.pixelAligned(local.insetBy(dx: -bw, dy: -bw), scale: scale)
            tile.container.bounds = CGRect(origin: .zero, size: ringRect.size)
            tile.container.position = CGPoint(x: ringRect.midX, y: ringRect.midY)
            tile.container.transform = s.scale == 1 ? CATransform3DIdentity : CATransform3DMakeScale(s.scale, s.scale, 1)
            // A tile without a still (a window that just opened, still being captured) stays
            // invisible; the real window shows when the cover goes.
            tile.container.opacity = tile.hasImage ? Float(s.alpha) : 0
            tile.container.zPosition = CGFloat(z + 1)
            tile.image.frame = CGRect(origin: .zero, size: ringRect.size).insetBy(dx: bw, dy: bw)
            tile.ring.frame = CGRect(origin: .zero, size: ringRect.size)
            tile.ring.isHidden = bw == 0
            tile.ring.borderWidth = bw
            tile.ring.cornerRadius = style.cornerRadius + bw
            tile.ring.borderColor = (s.isActive ? style.active : style.inactive).cgColor
            if s.isDragged {
                tile.container.shadowOpacity = 0.35
                tile.container.shadowRadius = 18
                tile.container.shadowOffset = CGSize(width: 0, height: 8)
                tile.container.shadowPath = CGPath(roundedRect: tile.container.bounds, cornerWidth: style.cornerRadius, cornerHeight: style.cornerRadius, transform: nil)
            } else if tile.container.shadowOpacity != 0 {
                tile.container.shadowOpacity = 0
            }
            for l in [tile.container, tile.image, tile.ring] { l.contentsScale = scale }
        }
        for (id, t) in tiles where !seen.contains(id) {
            t.container.removeFromSuperlayer()
            tiles[id] = nil
        }
        CATransaction.commit()
    }

    /// The slot a dragged window would drop into (nil hides it).
    func showPreview(_ rect: CGRect?, style: OverlayStyle) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect {
            let local = rect.offsetBy(dx: -region.minX, dy: -region.minY)
            preview.frame = ScreenSpace.pixelAligned(local, scale: scale)
            preview.cornerRadius = style.cornerRadius
            preview.backgroundColor = style.active.withAlpha(0.18).cgColor
            preview.borderColor = style.active.withAlpha(0.9).cgColor
            preview.borderWidth = max(2, style.borderWidth)
            preview.isHidden = false
        } else {
            preview.isHidden = true
        }
        CATransaction.commit()
    }

    func show() {
        window.orderFrontRegardless()
    }

    /// Back to idle (kept for the next animation so showing it costs no new backing store).
    func reset() {
        window.orderOut(nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for t in tiles.values { t.container.removeFromSuperlayer() }
        tiles.removeAll()
        root.removeAllAnimations()
        root.opacity = 1
        preview.isHidden = true
        CATransaction.commit()
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

extension RGBA {
    func withAlpha(_ a: Double) -> RGBA {
        var c = self
        c.alpha = a
        return c
    }
}
