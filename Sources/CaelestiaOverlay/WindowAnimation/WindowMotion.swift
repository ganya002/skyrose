import CaelestiaCore
import CoreGraphics
import Foundation

/// The drawable state of one window still at one instant.
public struct WindowMotionSample: Equatable, Sendable {
    public var id: CGWindowID
    public var displayID: CGDirectDisplayID
    public var frame: CGRect
    public var alpha: Double
    public var scale: Double
    public var isActive: Bool
    public var decorated: Bool
    public var isDragged: Bool
}

/// Pure motion model behind the snapshot animator: one item per window drawn on a cover, with
/// spring/bezier channels taken from the animation table (`windowsMove` for moves, `windowsIn`
/// pop-in, `windowsOut` shrink + fade). Retargeting mid-flight keeps the spring's velocity, so a
/// retile during a retile bends instead of restarting. Headless and clock-driven for tests.
public struct WindowMotionModel: Sendable {
    public enum Phase: Equatable, Sendable { case shown, leaving, dragging }

    public struct Item: Equatable, Sendable {
        public var id: CGWindowID
        public var displayID: CGDirectDisplayID
        public var isActive: Bool
        public var decorated: Bool
        public var phase: Phase
        /// Where the window ends up (its real final frame).
        public var target: CGRect
        var x, y, w, h, alpha, scale: AnimatedValue

        init(id: CGWindowID, displayID: CGDirectDisplayID, frame: CGRect, isActive: Bool, decorated: Bool) {
            self.id = id
            self.displayID = displayID
            self.isActive = isActive
            self.decorated = decorated
            phase = .shown
            target = frame
            x = AnimatedValue(frame.minX)
            y = AnimatedValue(frame.minY)
            w = AnimatedValue(frame.width)
            h = AnimatedValue(frame.height)
            alpha = AnimatedValue(1)
            scale = AnimatedValue(1)
        }

        mutating func move(to frame: CGRect, spec: AnimationSpec, at now: TimeInterval) {
            target = frame
            guard spec.enabled, spec.durationMs > 0 else { return snap(to: frame) }
            x.animate(to: frame.minX, spec: spec, at: now)
            y.animate(to: frame.minY, spec: spec, at: now)
            w.animate(to: frame.width, spec: spec, at: now)
            h.animate(to: frame.height, spec: spec, at: now)
        }

        mutating func snap(to frame: CGRect) {
            x.set(frame.minX)
            y.set(frame.minY)
            w.set(frame.width)
            h.set(frame.height)
        }

        func frame(at now: TimeInterval) -> CGRect {
            CGRect(x: x.value(at: now), y: y.value(at: now), width: max(1, w.value(at: now)), height: max(1, h.value(at: now)))
        }

        func isSettled(at now: TimeInterval) -> Bool {
            if phase == .dragging { return false }
            for v in [x, y, w, h] where !v.isDone(at: now) {
                if abs(v.value(at: now) - v.to) > WindowMotionModel.settleDistance { return false }
                if abs(v.currentVelocity(at: now)) > WindowMotionModel.settleSpeed { return false }
            }
            return alpha.isDone(at: now) && scale.isDone(at: now)
        }
    }

    /// A moving channel counts as arrived within half a point of its target...
    public static let settleDistance = 0.5
    /// ...while moving slower than this (pt/s), so an overshooting spring is not cut mid-swing.
    public static let settleSpeed = 40.0
    /// The dragged still is lifted slightly.
    public static let dragScale = 1.025

    public var table: AnimationTable
    public private(set) var items: [CGWindowID: Item] = [:]
    /// Back to front.
    public private(set) var order: [CGWindowID] = []

    public init(table: AnimationTable = .gabbySpringy) {
        self.table = table
    }

    public var isEmpty: Bool { items.isEmpty }
    public func contains(_ id: CGWindowID) -> Bool { items[id] != nil }

    /// Applies one layout pass. Known items are retargeted, new ones appear where the change
    /// says (moving from `from`, popping in, or still), closing/leaving ones start fading out.
    public mutating func apply(_ request: WindowAnimationRequest, at now: TimeInterval) {
        let changes = Dictionary(request.changes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let move = table[.windowsMove]
        let popIn = table[.windowsIn]
        var visible: Set<CGWindowID> = []
        for w in request.windows {
            visible.insert(w.id)
            if var item = items[w.id] {
                item.isActive = w.isActive
                item.displayID = w.displayID
                item.decorated = w.decorated
                if item.phase == .leaving {
                    item.phase = .shown
                    item.alpha.animate(to: 1, spec: BorderAnimator.fadeSpec(for: popIn), at: now)
                    item.scale.animate(to: 1, spec: popIn, at: now)
                }
                if item.phase == .dragging { item.target = w.frame } else { item.move(to: w.frame, spec: move, at: now) }
                items[w.id] = item
                continue
            }
            let change = changes[w.id]
            if change?.kind == .move, let from = change?.from, from != w.frame {
                var item = Item(id: w.id, displayID: w.displayID, frame: from, isActive: w.isActive, decorated: w.decorated)
                item.move(to: w.frame, spec: move, at: now)
                items[w.id] = item
            } else if change?.kind == .open || change?.kind == .move && change?.from == nil {
                var item = Item(id: w.id, displayID: w.displayID, frame: w.frame, isActive: w.isActive, decorated: w.decorated)
                if popIn.enabled, popIn.durationMs > 0 {
                    item.alpha = AnimatedValue(0)
                    item.scale = AnimatedValue(Self.popScale(popIn.style))
                    item.alpha.animate(to: 1, spec: BorderAnimator.fadeSpec(for: popIn), at: now)
                    item.scale.animate(to: 1, spec: popIn, at: now)
                }
                items[w.id] = item
            } else {
                items[w.id] = Item(id: w.id, displayID: w.displayID, frame: w.frame, isActive: w.isActive, decorated: w.decorated)
            }
        }
        let out = table[.windowsOut]
        var leaving: [CGWindowID] = []
        for c in request.changes where (c.kind == .close || c.kind == .leave) && !visible.contains(c.id) {
            var item: Item
            if let existing = items[c.id] {
                item = existing
            } else if c.kind == .leave, let from = c.from, let d = WindowAnimationRequest.display(for: from, in: request.displays) {
                // A window moved to another workspace is still on screen (it is parked in the
                // commit, under the cover). A closed one is not: macOS removed it before the WM
                // heard of it, and drawing its still again would flash it back for a frame (live
                // finding). Closes only animate when the still was put up before the close
                // (`prepareClose`, the WM's own close action).
                item = Item(id: c.id, displayID: d, frame: from, isActive: false, decorated: true)
            } else {
                continue
            }
            guard out.enabled, out.durationMs > 0 else { items[c.id] = nil; continue }
            if item.phase != .leaving {
                item.phase = .leaving
                item.alpha.animate(to: 0, spec: out, at: now)
                item.scale.animate(to: Self.popScale(out.style), spec: out, at: now)
            }
            items[c.id] = item
            leaving.append(c.id)
        }
        // Anything else that is no longer visible goes at once (a still of a window that is not
        // there must never linger).
        for id in Array(items.keys) where !visible.contains(id) && items[id]?.phase != .leaving { items[id] = nil }
        let stillLeaving = order.filter { items[$0]?.phase == .leaving && !leaving.contains($0) }
        order = request.windows.map(\.id) + stillLeaving + leaving
    }

    static func popScale(_ style: AnimationStyle) -> Double {
        switch style {
        case .popin(let s): return s > 0 ? s : 0.8
        case .fade: return 1
        default: return 0.8
        }
    }

    /// The WM is about to close `id`: its still must already be on the cover when the window goes.
    public mutating func prepareClose(_ id: CGWindowID, request: WindowAnimationRequest, at now: TimeInterval) {
        apply(WindowAnimationRequest(changes: [], windows: request.windows, displays: request.displays), at: now)
    }

    // MARK: Drag

    public mutating func beginDrag(_ id: CGWindowID, at now: TimeInterval) {
        guard var item = items[id] else { return }
        item.phase = .dragging
        item.scale.animate(to: Self.dragScale, spec: .bezier(.standard, milliseconds: 120), at: now)
        items[id] = item
        order.removeAll { $0 == id }
        order.append(id)
    }

    /// The dragged still follows the pointer 1:1 (no easing: `animate_mouse_windowdragging = false`).
    public mutating func drag(_ id: CGWindowID, to frame: CGRect) {
        guard var item = items[id], item.phase == .dragging else { return }
        item.snap(to: frame)
        items[id] = item
    }

    /// The drag ended: the still settles into its slot (the current `target`, which a following
    /// layout pass may still retarget).
    public mutating func endDrag(_ id: CGWindowID, at now: TimeInterval) {
        guard var item = items[id], item.phase == .dragging else { return }
        item.phase = .shown
        item.scale.animate(to: 1, spec: .bezier(.standard, milliseconds: 160), at: now)
        item.move(to: item.target, spec: table[.windowsMove], at: now)
        items[id] = item
    }

    // MARK: Sampling

    public func samples(at now: TimeInterval) -> [WindowMotionSample] {
        order.compactMap { id in
            guard let i = items[id] else { return nil }
            return WindowMotionSample(
                id: id, displayID: i.displayID, frame: i.frame(at: now),
                alpha: min(1, max(0, i.alpha.value(at: now))), scale: i.scale.value(at: now),
                isActive: i.isActive, decorated: i.decorated, isDragged: i.phase == .dragging
            )
        }
    }

    /// Every still is where its real window is (or gone): the cover can go.
    public func isSettled(at now: TimeInterval) -> Bool {
        items.values.allSatisfy { $0.isSettled(at: now) }
    }

    /// Drops finished fade-outs; returns their ids.
    @discardableResult
    public mutating func collectGone(at now: TimeInterval) -> [CGWindowID] {
        let gone = items.values.filter { $0.phase == .leaving && $0.alpha.isDone(at: now) && $0.scale.isDone(at: now) }.map(\.id)
        for id in gone { items[id] = nil }
        order.removeAll { gone.contains($0) }
        return gone
    }

    mutating func replace(_ item: Item) { items[item.id] = item }

    public mutating func removeAll() {
        items.removeAll()
        order.removeAll()
    }
}
