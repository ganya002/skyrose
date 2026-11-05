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
        /// The channel segments the layers currently play (only changed ones are re-added).
        var synced: [String: AnimatedValue] = [:]
        private var syncedBorder: CGFloat = -1
        private var syncedDragged: Bool?

        init(scale: CGFloat = 2) {
            for l in [container, clip, image, fresh, ring] {
                l.actions = BorderWindow.noActions
                l.contentsScale = scale
            }
            for l in [image, fresh] {
                l.contentsGravity = .resize
                l.minificationFilter = .trilinear
                l.anchorPoint = .zero
            }
            fresh.opacity = 0
            clip.masksToBounds = true
            clip.cornerCurve = .circular
            // Clip and ring hang from the container's top-left corner, so only their sizes move.
            clip.anchorPoint = .zero
            ring.anchorPoint = .zero
            ring.position = .zero
            ring.cornerCurve = .circular
            clip.addSublayer(image)
            clip.addSublayer(fresh)
            container.addSublayer(clip)
            container.addSublayer(ring)
        }

        func setFresh(_ f: SnapshotCache.Still) {
            guard !hasFresh else { return }
            fresh.contents = f.image
            fresh.contentsRect = f.contentRect
            freshSize = f.contentSize
            fresh.frame = CGRect(origin: .zero, size: f.contentSize)
            hasFresh = true
        }

        /// One layer property fed by one channel: value = channel × `factor` + `offset`.
        /// Position is the sum of two channels (x + w/2), so its parts are additive animations
        /// of the offset from their final value; everything else has one channel and animates
        /// its absolute value.
        private struct Binding {
            var layer: CALayer
            var keyPath: String
            var factor: Double
            var offset: Double
            var additive: Bool
        }

        func update(_ item: WindowMotionModel.Item, bw: CGFloat, origin: CGPoint, style: OverlayStyle, now: TimeInterval) {
            let b = Double(bw)
            if b != Double(syncedBorder) {
                syncedBorder = bw
                synced["w"] = nil
                synced["h"] = nil
                clip.position = CGPoint(x: bw, y: bw)
                ring.isHidden = bw == 0
                ring.borderWidth = bw
            }
            clip.cornerRadius = style.cornerRadius
            ring.cornerRadius = style.cornerRadius + bw
            ring.borderColor = (item.isActive ? style.active : style.inactive).cgColor

            let channels: [(String, AnimatedValue, [Binding])] = [
                ("x", item.x, [Binding(layer: container, keyPath: "position.x", factor: 1, offset: -origin.x, additive: true)]),
                ("y", item.y, [Binding(layer: container, keyPath: "position.y", factor: 1, offset: -origin.y, additive: true)]),
                ("w", item.w, [Binding(layer: container, keyPath: "position.x", factor: 0.5, offset: 0, additive: true),
                               Binding(layer: container, keyPath: "bounds.size.width", factor: 1, offset: 2 * b, additive: false),
                               Binding(layer: clip, keyPath: "bounds.size.width", factor: 1, offset: 0, additive: false),
                               Binding(layer: ring, keyPath: "bounds.size.width", factor: 1, offset: 2 * b, additive: false)]),
                ("h", item.h, [Binding(layer: container, keyPath: "position.y", factor: 0.5, offset: 0, additive: true),
                               Binding(layer: container, keyPath: "bounds.size.height", factor: 1, offset: 2 * b, additive: false),
                               Binding(layer: clip, keyPath: "bounds.size.height", factor: 1, offset: 0, additive: false),
                               Binding(layer: ring, keyPath: "bounds.size.height", factor: 1, offset: 2 * b, additive: false)]),
                // A tile without a still stays invisible (the real window shows when the cover goes).
                ("alpha", hasImage ? item.alpha : AnimatedValue(0), [Binding(layer: container, keyPath: "opacity", factor: 1, offset: 0, additive: false)]),
                ("scale", item.scale, [Binding(layer: container, keyPath: "transform.scale", factor: 1, offset: 0, additive: false)]),
            ]
            var changed = false
            for (name, value, bindings) in channels where synced[name] != value {
                synced[name] = value
                changed = true
                for binding in bindings {
                    let key = "\(name).\(binding.keyPath)"
                    if let a = Self.animation(value, binding, now: now) {
                        binding.layer.add(a, forKey: key)
                    } else {
                        binding.layer.removeAnimation(forKey: key)
                    }
                }
            }
            if changed {
                // Model values: where everything ends up (what shows once the animations end).
                let w = max(1, item.w.to), h = max(1, item.h.to)
                container.position = CGPoint(x: item.x.to + w / 2 - origin.x, y: item.y.to + h / 2 - origin.y)
                container.bounds = CGRect(x: 0, y: 0, width: w + 2 * b, height: h + 2 * b)
                clip.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                ring.bounds = container.bounds
                container.opacity = hasImage ? Float(min(1, max(0, item.alpha.to))) : 0
                container.setValue(item.scale.to, forKeyPath: "transform.scale")
            }
            let dragged = item.phase == .dragging
            if dragged != syncedDragged || (dragged && changed) {
                syncedDragged = dragged
                if dragged {
                    container.shadowOpacity = 0.35
                    container.shadowRadius = 18
                    container.shadowOffset = CGSize(width: 0, height: 8)
                    container.shadowPath = CGPath(roundedRect: container.bounds, cornerWidth: style.cornerRadius, cornerHeight: style.cornerRadius, transform: nil)
                } else {
                    container.shadowOpacity = 0
                    container.shadowPath = nil
                }
            }
        }

        /// The Core Animation twin of one `AnimatedValue` segment, or nil when it is at rest.
        private static func animation(_ v: AnimatedValue, _ b: Binding, now: TimeInterval) -> CAAnimation? {
            guard !v.isDone(at: now), v.spec.enabled, v.spec.durationMs > 0 else { return nil }
            let distance = v.to - v.from
            let fromValue = b.additive ? (v.from - v.to) * b.factor : v.from * b.factor + b.offset
            let toValue = b.additive ? 0 : v.to * b.factor + b.offset
            let a: CABasicAnimation
            switch v.spec.curve {
            case .spring(let s):
                // A velocity with no distance to cover cannot be expressed (CA normalises it by the
                // distance); such a segment is a few points of drift at most, so it just ends.
                guard abs(distance) > 1e-9 else { return nil }
                let spring = CASpringAnimation(keyPath: b.keyPath)
                spring.mass = s.mass
                spring.stiffness = s.stiffness
                spring.damping = s.damping
                // CA's initial velocity is in distances per second, positive towards the target.
                spring.initialVelocity = v.velocity / distance
                a = spring
            case .bezier(let c):
                a = CABasicAnimation(keyPath: b.keyPath)
                a.timingFunction = CAMediaTimingFunction(controlPoints: Float(c.x1), Float(c.y1), Float(c.x2), Float(c.y2))
            }
            a.fromValue = fromValue
            a.toValue = toValue
            a.isAdditive = b.additive
            a.duration = v.spec.duration
            // On the media clock the model uses: a segment that started before this sync (a busy
            // main thread) joins mid-flight instead of starting over late.
            a.beginTime = b.layer.convertTime(v.start, from: nil)
            a.fillMode = .backwards
            a.isRemovedOnCompletion = true
            a.preferredFrameRateRange = SnapshotCover.frameRates
            return a
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
        window.title = "SkyRose window animation"
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

    /// Draws `samples` (back to front) as they are, with no motion: a static frame (tests, a
    /// cover shown for one instant). `fresh(id)` is a capture at the window's new size and its
    /// cross-fade progress (0...1). `holes` (global) are cut out of the desktop backdrop so real
    /// windows shown live are visible through the cover.
    func render(_ samples: [WindowMotionSample], image: (CGWindowID) -> SnapshotCache.Still?,
                fresh: (CGWindowID) -> (SnapshotCache.Still, Double)? = { _ in nil },
                holes: [CGRect] = [], style: OverlayStyle) {
        let items = samples.map { s -> WindowMotionModel.Item in
            var item = WindowMotionModel.Item(id: s.id, displayID: s.displayID, frame: s.frame, isActive: s.isActive, decorated: s.decorated)
            item.alpha = AnimatedValue(s.alpha)
            item.scale = AnimatedValue(s.scale)
            if s.isDragged { item.phase = .dragging }
            return item
        }
        sync(items, now: CACurrentMediaTime(), image: image, holes: holes, style: style)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for s in samples {
            guard let tile = tiles[s.id], let (f, progress) = fresh(s.id) else { continue }
            tile.setFresh(f)
            tile.fresh.opacity = Float(min(1, max(0, progress)))
        }
        CATransaction.commit()
    }

    /// Mirrors the motion model on the layers (back to front). Every channel segment (from, to,
    /// start, velocity, curve) becomes a Core Animation animation with the same curve and
    /// `beginTime = start`, so the render server plays it at the display's rate on its own: a
    /// main thread busy with AX writes, focus or captures can no longer freeze a tile mid-flight
    /// and make it jump to the end once the thread is back (the "plays half, then snaps" bug).
    /// Only channels whose segment changed are touched; a retarget replaces the channel's
    /// animation with one starting from the current value and velocity (the model's own
    /// restart rule), so interruptions bend the motion instead of restarting it.
    func sync(_ items: [WindowMotionModel.Item], now: TimeInterval, image: (CGWindowID) -> SnapshotCache.Still?,
              holes: [CGRect] = [], style: OverlayStyle) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setHoles(holes)
        var seen: Set<CGWindowID> = []
        for (z, item) in items.enumerated() where item.displayID == displayID {
            seen.insert(item.id)
            let tile: Tile
            if let t = tiles[item.id] { tile = t } else {
                tile = Tile(scale: scale)
                tiles[item.id] = tile
                root.addSublayer(tile.container)
            }
            if !tile.hasImage, let still = image(item.id) {
                tile.image.contents = still.image
                tile.image.contentsRect = still.contentRect
                tile.stillSize = still.contentSize
                tile.image.frame = CGRect(origin: .zero, size: still.contentSize)
                tile.clip.backgroundColor = still.fill ?? style.surface.cgColor
                tile.hasImage = true
                tile.synced["alpha"] = nil
            }
            tile.update(item, bw: item.decorated ? style.borderWidth : 0, origin: region.origin, style: style, now: now)
            tile.container.zPosition = CGFloat(z + 1)
        }
        for (id, t) in tiles where !seen.contains(id) {
            t.container.removeFromSuperlayer()
            tiles[id] = nil
        }
        CATransaction.commit()
    }

    /// A capture at the window's new size arrived: cross-fade it in over `duration`.
    func crossFadeFresh(_ id: CGWindowID, _ still: SnapshotCache.Still, duration: TimeInterval) {
        guard let tile = tiles[id], !tile.hasFresh else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tile.setFresh(still)
        tile.fresh.opacity = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.preferredFrameRateRange = Self.frameRates
        tile.fresh.add(fade, forKey: "fresh")
        CATransaction.commit()
    }

    static let frameRates = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

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
