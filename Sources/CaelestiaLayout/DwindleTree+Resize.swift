import Foundation
import CoreGraphics
import CaelestiaCore

extension DwindleTree {
    /// Keyboard resize (Caelestia `kbWindowIncreaseWidth` & co.) by `delta` points along `axis`.
    ///
    /// With `smartResizing` (Gabby's setting) the window itself grows or shrinks by `delta`: the
    /// nearest ancestor split on that axis moves the edge between the window and its sibling
    /// subtree, so a left child grows to the right and a right child grows to the left, and the
    /// sibling loses exactly what the window gains. With `smartResizing` off this is the raw
    /// Hyprland dispatcher: the divider of the nearest matching split moves right/down by `delta`
    /// whichever side the window is on.
    ///
    /// Ratios are clamped to `minSplitRatio...maxSplitRatio`. Returns false when no ancestor splits
    /// on that axis (single window, or a full-width/height window).
    @discardableResult
    public mutating func resize(
        _ window: WindowID, axis: ResizeAxis, delta: Double, in area: CGRect, config: DwindleConfig = DwindleConfig()
    ) -> Bool {
        guard let path = path(to: window), !path.isEmpty else { return false }
        let wanted: SplitDirection = axis == .width ? .horizontal : .vertical
        let table = geometryTable(in: area, config: config)
        for depth in stride(from: path.count - 1, through: 0, by: -1) {
            let splitPath = Array(path[0..<depth])
            guard let geometry = table[splitPath], geometry.direction == wanted else { continue }
            let size = axis == .width ? geometry.box.width : geometry.box.height
            guard size > 0 else { return false }
            let signed = config.smartResizing ? (path[depth] == .first ? delta : -delta) : delta
            updateSplit(at: splitPath) { s in
                s.ratio = Self.clampRatio(s.ratio + signed * 2 / size, config)
            }
            return true
        }
        return false
    }

    /// Caelestia's resize binds are percentages of the window's current size
    /// (`resize_active_window(10, 0)` → `win.size.x · 10 / 100`). Converts `percent` of the
    /// window's current `frame` (from `placements`) into points and calls `resize`.
    /// Returns false when the window has no visible placement.
    @discardableResult
    public mutating func resizePercent(
        _ window: WindowID, axis: ResizeAxis, percent: Double, placements: [Placement], in area: CGRect,
        config: DwindleConfig = DwindleConfig()
    ) -> Bool {
        guard let placement = placements.first(where: { $0.window == window && !$0.hidden }) else { return false }
        let size = axis == .width ? placement.frame.width : placement.frame.height
        return resize(window, axis: axis, delta: size * percent / 100, in: area, config: config)
    }

    /// Mouse resize (Hyprland `resizeTarget` with `smart_resizing`): `edges` are the edges being
    /// dragged (the corner nearest the pointer at drag start, see `ResizeEdges.nearestCorner`) and
    /// `delta` the pointer movement. The dragged edges follow the pointer 1:1: for each axis the
    /// nearest ancestor split whose divider is that edge (the "outer" split) moves by the delta,
    /// and the split in between (the "inner" split, if any) is compensated so the opposite edge
    /// stays put. A window touching the usable-area edge on the dragged side moves its other edge
    /// instead; a window spanning the whole width/height ignores that axis.
    ///
    /// With `smartResizing` off this is Hyprland's positional variant: the parent split takes the
    /// delta on its axis and the first ancestor with the other axis takes the rest.
    /// Returns false when nothing could change.
    @discardableResult
    public mutating func resizeDrag(
        _ window: WindowID, edges: ResizeEdges, delta: CGPoint, in area: CGRect, config: DwindleConfig = DwindleConfig()
    ) -> Bool {
        guard let path = path(to: window), !path.isEmpty else { return false }
        var table = geometryTable(in: area, config: config)
        guard let leafBox = table[path]?.box else { return false }

        let displayLeft = HyprGeometry.sticks(leafBox.minX, area.minX)
        let displayRight = HyprGeometry.sticks(leafBox.maxX, area.maxX)
        let displayTop = HyprGeometry.sticks(leafBox.minY, area.minY)
        let displayBottom = HyprGeometry.sticks(leafBox.maxY, area.maxY)

        var allowed = delta
        if displayLeft && displayRight { allowed.x = 0 }
        if displayTop && displayBottom { allowed.y = 0 }

        if !config.smartResizing {
            return positionalResize(path: path, allowed: allowed, table: table, config: config)
        }

        let left = edges.contains(.left) || displayRight
        let top = edges.contains(.top) || displayBottom
        let right = edges.contains(.right) || displayLeft
        let bottom = edges.contains(.bottom) || displayTop
        let none = edges.isEmpty

        var vOuter: Int?
        var vInner: Int?
        var hOuter: Int?
        var hInner: Int?
        for depth in stride(from: path.count - 1, through: 0, by: -1) {
            guard let direction = table[Array(path[0..<depth])]?.direction else { continue }
            let side = path[depth]
            if direction == .vertical {
                if vOuter == nil, none || (top && side == .second) || (bottom && side == .first) {
                    vOuter = depth
                } else if vOuter == nil, vInner == nil {
                    vInner = depth
                }
            } else {
                if hOuter == nil, none || (left && side == .second) || (right && side == .first) {
                    hOuter = depth
                } else if hOuter == nil, hInner == nil {
                    hInner = depth
                }
            }
            if vOuter != nil, hOuter != nil { break }
        }

        var changed = false
        if let hOuter {
            changed = adjust(
                outer: hOuter, inner: hInner, path: path, delta: allowed.x, area: area, config: config, table: &table,
                size: { $0.width }
            ) || changed
        }
        if let vOuter {
            changed = adjust(
                outer: vOuter, inner: vInner, path: path, delta: allowed.y, area: area, config: config, table: &table,
                size: { $0.height }
            ) || changed
        }
        return changed
    }

    /// Hyprland's outer/inner ratio update for one axis. `outer`/`inner` are depths of the split
    /// nodes on `path`; `path[depth]` is the side our subtree occupies in that split.
    private mutating func adjust(
        outer: Int, inner: Int?, path: Path, delta: Double, area: CGRect, config: DwindleConfig,
        table: inout [Path: NodeGeometry], size: (CGRect) -> Double
    ) -> Bool {
        let outerPath = Array(path[0..<outer])
        guard let outerBox = table[outerPath]?.box, size(outerBox) > 0 else { return false }
        let original = inner.flatMap { table[Array(path[0...$0])].map { size($0.box) } }
        updateSplit(at: outerPath) { s in
            s.ratio = Self.clampRatio(s.ratio + delta * 2 / size(outerBox), config)
        }
        table = geometryTable(in: area, config: config)
        guard let inner, let original else { return true }
        let innerPath = Array(path[0..<inner])
        guard let innerBox = table[innerPath]?.box, size(innerBox) > 0 else { return true }
        let ratio: Double
        if path[inner] == .first {
            ratio = (original - delta) / size(innerBox) * 2
        } else {
            ratio = 2 - (original + delta) / size(innerBox) * 2
        }
        updateSplit(at: innerPath) { s in s.ratio = Self.clampRatio(ratio, config) }
        table = geometryTable(in: area, config: config)
        return true
    }

    /// Hyprland's `smart_resizing = false` branch.
    private mutating func positionalResize(path: Path, allowed: CGPoint, table: [Path: NodeGeometry], config: DwindleConfig) -> Bool {
        let parentPath = Array(path.dropLast())
        guard let parent = table[parentPath], let parentDirection = parent.direction else { return false }
        var otherPath: Path?
        for depth in stride(from: path.count - 2, through: 0, by: -1) {
            let p = Array(path[0..<depth])
            if let d = table[p]?.direction, d != parentDirection {
                otherPath = p
                break
            }
        }
        let sidePath = parentDirection == .horizontal ? parentPath : otherPath
        let topPath = parentDirection == .vertical ? parentPath : otherPath
        var changed = false
        if let sidePath, let box = table[sidePath]?.box, box.width > 0 {
            updateSplit(at: sidePath) { s in s.ratio = Self.clampRatio(s.ratio + allowed.x * 2 / box.width, config) }
            changed = true
        }
        if let topPath, let box = table[topPath]?.box, box.height > 0 {
            updateSplit(at: topPath) { s in s.ratio = Self.clampRatio(s.ratio + allowed.y * 2 / box.height, config) }
            changed = true
        }
        return changed
    }
}
