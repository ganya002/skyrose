import AppKit
import CaelestiaCore
import QuartzCore

/// One display's animation cover: a click-through panel over the whole display (below the shell's
/// frame and bar, above normal windows) holding the desktop still and one tile per window (its
/// still plus its border ring). While it is up the real windows underneath get their final frames.
@MainActor
final class SnapshotCover {
    /// One window: `clip` (the window's rounded shape, filled with the still's average colour)
    /// holds the still at its own size, anchored top-left, never scaled to another aspect; while
    /// the tile is bigger than the still the fill shows, while it is smaller the still is cut off,
    /// like a window being resized live. `fresh` (a capture at the new size) cross-fades over it.
    @MainActor final class Tile {
        let container = CALayer()
        let clip = CALayer()
        let image = CALayer()
        let fresh = CALayer()
        let ring = CALayer()
        var hasImage = false
        var stillSize: CGSize = .zero
        var freshSize: CGSize = .zero
        var hasFresh = false

        init() {
            for l in [container, clip, image, fresh, ring] { l.actions = BorderWindow.noActions }
            for l in [image, fresh] {
                l.contentsGravity = .resize
                l.minificationFilter = .trilinear
                l.anchorPoint = .zero
            }
            fresh.opacity = 0
            clip.masksToBounds = true
            clip.cornerCurve = .circular
            ring.cornerCurve = .circular
            clip.addSublayer(image)
            clip.addSublayer(fresh)
            container.addSublayer(clip)
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
    private var surfaceColor: CGColor?

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
        // Our own root under the view's backing layer: AppKit owns the backing layer's
        // `isGeometryFlipped` (it follows the view), so setting it there did not stick and every
        // tile was drawn upside down in position (live finding: stacked windows swapped places
        // while a cover was up).
        root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        view.layer!.addSublayer(root)
        root.isGeometryFlipped = true
        root.masksToBounds = true
        root.actions = BorderWindow.noActions
        surfaceColor = style.surface.cgColor
        root.backgroundColor = surfaceColor
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

    /// Draws `samples` (back to front) with the stills `image(id)` returns; `fresh(id)` is a
    /// capture at the window's new size and its cross-fade progress (0...1). `holes` (global)
    /// are cut out of the desktop backdrop so real windows shown live (an open without a
    /// correct-size still) are visible through the cover.
    func render(_ samples: [WindowMotionSample], image: (CGWindowID) -> SnapshotCache.Still?,
                fresh: (CGWindowID) -> (SnapshotCache.Still, Double)? = { _ in nil },
                holes: [CGRect] = [], style: OverlayStyle) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setHoles(holes)
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
                tile.stillSize = still.contentSize
                tile.clip.backgroundColor = still.fill ?? style.surface.cgColor
                tile.hasImage = true
            }
            if let (f, progress) = fresh(s.id) {
                if !tile.hasFresh {
                    tile.fresh.contents = f.image
                    tile.fresh.contentsRect = f.contentRect
                    tile.freshSize = f.contentSize
                    tile.hasFresh = true
                }
                tile.fresh.opacity = Float(min(1, max(0, progress)))
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
            tile.clip.frame = CGRect(origin: .zero, size: ringRect.size).insetBy(dx: bw, dy: bw)
            tile.clip.cornerRadius = style.cornerRadius
            // 1:1 in points, top-left: a still is never stretched to the tile's aspect.
            tile.image.frame = CGRect(origin: .zero, size: tile.stillSize)
            tile.fresh.frame = CGRect(origin: .zero, size: tile.freshSize)
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
            for l in [tile.container, tile.clip, tile.image, tile.fresh, tile.ring] { l.contentsScale = scale }
        }
        for (id, t) in tiles where !seen.contains(id) {
            t.container.removeFromSuperlayer()
            tiles[id] = nil
        }
        CATransaction.commit()
    }

    private var holeRects: [CGRect] = []

    /// Cuts `holes` (global top-left) out of the desktop backdrop.
    private func setHoles(_ holes: [CGRect]) {
        let local = holes.map { $0.offsetBy(dx: -region.minX, dy: -region.minY) }.filter { $0.intersects(root.bounds) }
        guard local != holeRects else { return }
        holeRects = local
        guard !local.isEmpty else {
            background.mask = nil
            root.backgroundColor = surfaceColor
            return
        }
        let mask = CAShapeLayer()
        mask.actions = BorderWindow.noActions
        mask.frame = background.bounds
        mask.fillRule = .evenOdd
        let path = CGMutablePath()
        path.addRect(background.bounds)
        // Plain rects: what shows through is the real screen (the window and, at its rounded
        // corners, the real desktop), identical to the backdrop around it.
        for r in local { path.addRect(r) }
        mask.path = path
        background.mask = mask
        // The root's fill would cover the hole too.
        root.backgroundColor = nil
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
        setHoles([])
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
