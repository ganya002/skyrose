import Foundation
import CoreGraphics
import CaelestiaCore

/// Orientation of a split node. Hyprland's `splitTop == false` is `.horizontal`.
public enum SplitDirection: String, Sendable, Hashable, Codable, CaseIterable {
    /// Children side by side: first = left, second = right.
    case horizontal
    /// Children stacked: first = top, second = bottom.
    case vertical

    public var toggled: SplitDirection { self == .horizontal ? .vertical : .horizontal }
}

/// Which child of a split a node is. `first` is left/top, `second` is right/bottom.
public enum SplitSide: String, Sendable, Hashable, Codable {
    case first, second

    public var opposite: SplitSide { self == .first ? .second : .first }
}

/// Hyprland's dwindle layout as a pure value: a binary tree whose leaves hold one window each (or
/// one tab group). The tree only stores structure, split directions and split ratios; every box
/// is recomputed from the usable area on demand, so `layout` is a pure function of
/// (tree, area, params) and calling it twice yields identical placements.
///
/// Node boxes partition the usable area with no gaps; gaps and borders are applied per leaf when
/// producing `Placement`s (see `layout`).
public struct DwindleTree: Sendable, Hashable, Codable {
    /// A leaf: one window, or an ordered tab group with one visible (active) member.
    public struct Leaf: Sendable, Hashable, Codable {
        public var windows: [WindowID]
        /// Index into `windows` of the visible member.
        public var activeIndex: Int
        /// True when this leaf is a Hyprland tab group (even with a single member).
        public var isGroup: Bool
        /// Locked groups refuse new members (`lockactivegroup`).
        public var isLocked: Bool

        public init(window: WindowID) {
            windows = [window]
            activeIndex = 0
            isGroup = false
            isLocked = false
        }

        public var activeWindow: WindowID { windows[clampedActiveIndex] }

        var clampedActiveIndex: Int { max(0, min(activeIndex, windows.count - 1)) }

        public func contains(_ window: WindowID) -> Bool { windows.contains(window) }
    }

    /// An inner node with exactly two children. The first child gets `ratio / 2` of the box
    /// along the split axis (Hyprland `splitRatio`, 0.1...1.9, 1.0 = 50/50).
    public struct Split: Sendable, Hashable, Codable {
        public var direction: SplitDirection
        public var ratio: Double
        public var first: Node
        public var second: Node

        public init(direction: SplitDirection, ratio: Double, first: Node, second: Node) {
            self.direction = direction
            self.ratio = ratio
            self.first = first
            self.second = second
        }

        public subscript(side: SplitSide) -> Node {
            get { side == .first ? first : second }
            set { if side == .first { first = newValue } else { second = newValue } }
        }
    }

    public indirect enum Node: Sendable, Hashable, Codable {
        case leaf(Leaf)
        case split(Split)

        public var leaf: Leaf? {
            if case .leaf(let l) = self { return l }
            return nil
        }

        public var split: Split? {
            if case .split(let s) = self { return s }
            return nil
        }
    }

    /// Position of a node: the sequence of sides taken from the root. The root's path is empty.
    public typealias Path = [SplitSide]

    public private(set) var root: Node?

    public init() {
        root = nil
    }

    public var isEmpty: Bool { root == nil }

    /// Number of leaves (= number of visible tiled windows).
    public var leafCount: Int { leafNodes.count }

    /// Every window in depth-first order, with group members expanded in group order.
    public var windows: [WindowID] { leafNodes.flatMap { $0.leaf.windows } }

    /// The visible window of every leaf in depth-first order.
    public var visibleWindows: [WindowID] { leafNodes.map { $0.leaf.activeWindow } }

    public func contains(_ window: WindowID) -> Bool { path(to: window) != nil }

    /// The leaf holding `window`, if it is tiled here.
    public func leaf(of window: WindowID) -> Leaf? {
        guard let p = path(to: window) else { return nil }
        return node(at: p)?.leaf
    }

    // MARK: Paths

    /// Path from the root to the leaf holding `window`.
    public func path(to window: WindowID) -> Path? {
        guard let root else { return nil }
        return Self.find(window, in: root, path: [])
    }

    /// The node at `path`, or nil if the path does not exist.
    public func node(at path: Path) -> Node? {
        guard var current = root else { return nil }
        for side in path {
            guard case .split(let s) = current else { return nil }
            current = s[side]
        }
        return current
    }

    private static func find(_ window: WindowID, in node: Node, path: Path) -> Path? {
        switch node {
        case .leaf(let l):
            return l.contains(window) ? path : nil
        case .split(let s):
            return find(window, in: s.first, path: path + [.first]) ?? find(window, in: s.second, path: path + [.second])
        }
    }

    var leafNodes: [(path: Path, leaf: Leaf)] {
        var out: [(Path, Leaf)] = []
        if let root { Self.collectLeaves(root, path: [], into: &out) }
        return out
    }

    private static func collectLeaves(_ node: Node, path: Path, into out: inout [(Path, Leaf)]) {
        switch node {
        case .leaf(let l): out.append((path, l))
        case .split(let s):
            collectLeaves(s.first, path: path + [.first], into: &out)
            collectLeaves(s.second, path: path + [.second], into: &out)
        }
    }

    mutating func update(at path: Path, _ body: (inout Node) -> Void) {
        guard var r = root else { return }
        Self.update(&r, path: path[...], body)
        root = r
    }

    private static func update(_ node: inout Node, path: ArraySlice<SplitSide>, _ body: (inout Node) -> Void) {
        guard let side = path.first else {
            body(&node)
            return
        }
        guard case .split(var s) = node else { return }
        switch side {
        case .first: update(&s.first, path: path.dropFirst(), body)
        case .second: update(&s.second, path: path.dropFirst(), body)
        }
        node = .split(s)
    }

    mutating func updateLeaf(at path: Path, _ body: (inout Leaf) -> Void) {
        update(at: path) { node in
            guard case .leaf(var l) = node else { return }
            body(&l)
            node = .leaf(l)
        }
    }

    mutating func updateSplit(at path: Path, _ body: (inout Split) -> Void) {
        update(at: path) { node in
            guard case .split(var s) = node else { return }
            body(&s)
            node = .split(s)
        }
    }

    // MARK: Geometry

    /// Box and effective direction of one node for a given usable area.
    struct NodeGeometry: Sendable {
        var path: Path
        var box: CGRect
        /// Effective direction for splits (stored, or re-evaluated from the aspect when
        /// `preserveSplit` and `smartSplit` are both off), nil for leaves.
        var direction: SplitDirection?
        var leaf: Leaf?
    }

    static func aspectDirection(of box: CGRect, config: DwindleConfig) -> SplitDirection {
        box.width > box.height * config.splitWidthMultiplier ? .horizontal : .vertical
    }

    static func effectiveDirection(of split: Split, box: CGRect, config: DwindleConfig) -> SplitDirection {
        if config.preserveSplit || config.smartSplit { return split.direction }
        return aspectDirection(of: box, config: config)
    }

    static func childBoxes(of box: CGRect, direction: SplitDirection, ratio: Double) -> (first: CGRect, second: CGRect) {
        switch direction {
        case .horizontal:
            let firstSize = box.width / 2 * ratio
            return (
                CGRect(x: box.minX, y: box.minY, width: max(0, firstSize), height: box.height),
                CGRect(x: box.minX + firstSize, y: box.minY, width: max(0, box.width - firstSize), height: box.height)
            )
        case .vertical:
            let firstSize = box.height / 2 * ratio
            return (
                CGRect(x: box.minX, y: box.minY, width: box.width, height: max(0, firstSize)),
                CGRect(x: box.minX, y: box.minY + firstSize, width: box.width, height: max(0, box.height - firstSize))
            )
        }
    }

    /// Geometry of every node in depth-first order (unrounded boxes).
    func geometries(in area: CGRect, config: DwindleConfig) -> [NodeGeometry] {
        var out: [NodeGeometry] = []
        if let root { Self.walk(root, path: [], box: area, config: config, into: &out) }
        return out
    }

    func leafGeometries(in area: CGRect, config: DwindleConfig) -> [NodeGeometry] {
        geometries(in: area, config: config).filter { $0.leaf != nil }
    }

    func geometryTable(in area: CGRect, config: DwindleConfig) -> [Path: NodeGeometry] {
        var table: [Path: NodeGeometry] = [:]
        for g in geometries(in: area, config: config) { table[g.path] = g }
        return table
    }

    private static func walk(_ node: Node, path: Path, box: CGRect, config: DwindleConfig, into out: inout [NodeGeometry]) {
        switch node {
        case .leaf(let l):
            out.append(NodeGeometry(path: path, box: box, direction: nil, leaf: l))
        case .split(let s):
            let direction = effectiveDirection(of: s, box: box, config: config)
            out.append(NodeGeometry(path: path, box: box, direction: direction, leaf: nil))
            let children = childBoxes(of: box, direction: direction, ratio: s.ratio)
            walk(s.first, path: path + [.first], box: children.first, config: config, into: &out)
            walk(s.second, path: path + [.second], box: children.second, config: config, into: &out)
        }
    }

    /// The node box (gap-free, rounded like Hyprland) of every visible window. Useful for debug
    /// output and for neighbour detection, which Hyprland performs on these boxes.
    public func boxes(in area: CGRect, config: DwindleConfig = DwindleConfig()) -> [WindowID: CGRect] {
        var out: [WindowID: CGRect] = [:]
        for g in leafGeometries(in: area, config: config) {
            if let l = g.leaf { out[l.activeWindow] = HyprGeometry.rounded(g.box) }
        }
        return out
    }

    static func clampRatio(_ ratio: Double, _ config: DwindleConfig) -> Double {
        let lo = min(config.minSplitRatio, config.maxSplitRatio)
        let hi = max(config.minSplitRatio, config.maxSplitRatio)
        return min(max(ratio, lo), hi)
    }

    // MARK: Structural operations

    /// Opens `window` by splitting the leaf of `focused` (Hyprland `use_active_for_splits`).
    /// Fallbacks: the leaf closest to `cursor` (the one under it when inside), then the last leaf,
    /// then the window becomes the root.
    ///
    /// The split direction follows the leaf's current box: side by side when
    /// `width > height · splitWidthMultiplier`, stacked otherwise. The new window goes right/bottom
    /// (`forceSplit` 0 or 2) or left/top (`forceSplit` 1); with `smartSplit` the cursor's quadrant
    /// of the leaf picks both the direction and the side like Hyprland. When `autoGroup` is set and
    /// the target leaf is an unlocked tab group, the window joins the group after the active tab
    /// instead (Hyprland `group:auto_group`).
    ///
    /// Returns false (no change) when the window is already in the tree.
    @discardableResult
    public mutating func insert(
        _ window: WindowID, relativeTo focused: WindowID? = nil, cursor: CGPoint? = nil, in area: CGRect,
        config: DwindleConfig = DwindleConfig(), autoGroup: Bool = true
    ) -> Bool {
        guard !contains(window) else { return false }
        guard root != nil else {
            root = .leaf(Leaf(window: window))
            return true
        }
        let leaves = leafGeometries(in: area, config: config)
        var target: NodeGeometry? = focused.flatMap { f in leaves.first { $0.leaf?.contains(f) == true } }
        if target == nil, let cursor {
            target = leaves.min { HyprGeometry.distanceSquared(from: cursor, to: $0.box) < HyprGeometry.distanceSquared(from: cursor, to: $1.box) }
        }
        if target == nil { target = leaves.last }
        guard let target, let leaf = target.leaf else { return false }

        if autoGroup, leaf.isGroup, !leaf.isLocked {
            updateLeaf(at: target.path) { l in
                let index = l.clampedActiveIndex + 1
                l.windows.insert(window, at: index)
                l.activeIndex = index
            }
            return true
        }

        let box = target.box
        var direction = Self.aspectDirection(of: box, config: config)
        var newGoesFirst = false
        if config.smartSplit, let cursor {
            // Hyprland smart_split: the leaf is cut into four triangles by its diagonals; the
            // cursor's triangle picks the side (and therefore the direction).
            let dx = cursor.x - box.midX
            let dy = cursor.y - box.midY
            let proportions = box.width > 0 ? box.height / box.width : Double.infinity
            let slope = dx != 0 ? abs(dy / dx) : Double.infinity
            if slope < proportions {
                direction = .horizontal
                newGoesFirst = dx <= 0
            } else {
                direction = .vertical
                newGoesFirst = dy <= 0
            }
        } else {
            newGoesFirst = config.forceSplit == 1
        }
        let ratio = Self.clampRatio(config.defaultSplitRatio, config)
        update(at: target.path) { node in
            let newLeaf = Node.leaf(Leaf(window: window))
            node = .split(Split(
                direction: direction, ratio: ratio,
                first: newGoesFirst ? newLeaf : node, second: newGoesFirst ? node : newLeaf
            ))
        }
        return true
    }

    /// Removes `window`. A member of a tab group just leaves the group (the next tab becomes
    /// active, wrapping around); a lone leaf collapses its parent so the sibling takes the parent's
    /// box. Returns false when the window is not in the tree.
    @discardableResult
    public mutating func remove(_ window: WindowID) -> Bool {
        guard let path = path(to: window), let leaf = node(at: path)?.leaf else { return false }
        if leaf.windows.count > 1 {
            updateLeaf(at: path) { l in
                guard let index = l.windows.firstIndex(of: window) else { return }
                let active = l.clampedActiveIndex
                l.windows.remove(at: index)
                if index < active {
                    l.activeIndex = active - 1
                } else if index == active {
                    l.activeIndex = index % l.windows.count
                } else {
                    l.activeIndex = active
                }
            }
            return true
        }
        guard let side = path.last else {
            root = nil
            return true
        }
        update(at: Array(path.dropLast())) { node in
            guard case .split(let s) = node else { return }
            node = s[side.opposite]
        }
        return true
    }

    /// Swaps the leaves holding `a` and `b` (a whole tab group moves as one unit, like Hyprland
    /// `swapwindow`). Returns false if either window is missing or both share a leaf.
    @discardableResult
    public mutating func swap(_ a: WindowID, _ b: WindowID) -> Bool {
        guard let pa = path(to: a), let pb = path(to: b), pa != pb,
            let la = node(at: pa)?.leaf, let lb = node(at: pb)?.leaf
        else { return false }
        update(at: pa) { $0 = .leaf(lb) }
        update(at: pb) { $0 = .leaf(la) }
        return true
    }

    /// The tiled window geometrically next to `window` in `direction` (Hyprland `movefocus` on
    /// node boxes): among leaves lying in that direction, the ones overlapping the source's
    /// projection win, then the closest edge, then the smallest perpendicular centre distance,
    /// then the most recently focused (`focusHistory`, most recent first).
    public func neighbor(
        of window: WindowID, direction: Direction, in area: CGRect, config: DwindleConfig = DwindleConfig(),
        focusHistory: [WindowID] = []
    ) -> WindowID? {
        let leaves = leafGeometries(in: area, config: config)
        guard let source = leaves.first(where: { $0.leaf?.contains(window) == true }) else { return nil }
        let candidates = leaves.filter { $0.path != source.path }.compactMap { g -> (WindowID, CGRect)? in
            guard let l = g.leaf else { return nil }
            return (l.activeWindow, g.box)
        }
        return FocusNavigation.neighbor(from: source.box, direction: direction, candidates: candidates, focusHistory: focusHistory)
    }

    /// Hyprland `movewindow` in dwindle: swaps `window` with its geometric neighbour in
    /// `direction`. Returns false when there is none (the WM then moves it to the next display).
    @discardableResult
    public mutating func move(
        _ window: WindowID, _ direction: Direction, in area: CGRect, config: DwindleConfig = DwindleConfig(),
        focusHistory: [WindowID] = []
    ) -> Bool {
        guard let other = neighbor(of: window, direction: direction, in: area, config: config, focusHistory: focusHistory) else {
            return false
        }
        return swap(window, other)
    }

    /// Hyprland `togglesplit`: flips the direction of the parent split of `window`. Only lasting
    /// with `preserveSplit` (or `smartSplit`) on; otherwise the aspect rule wins at layout time,
    /// exactly like Hyprland. Returns false for the root (no parent).
    @discardableResult
    public mutating func toggleSplit(_ window: WindowID) -> Bool {
        guard let path = path(to: window), !path.isEmpty else { return false }
        updateSplit(at: Array(path.dropLast())) { $0.direction = $0.direction.toggled }
        return true
    }

    /// Hyprland `splitratio` layoutmsg: sets (`exact`) or adjusts the parent split's ratio of
    /// `window`, clamped to `minSplitRatio...maxSplitRatio`. Returns false for the root.
    @discardableResult
    public mutating func setSplitRatio(_ window: WindowID, _ value: Double, exact: Bool = false, config: DwindleConfig = DwindleConfig()) -> Bool {
        guard let path = path(to: window), !path.isEmpty else { return false }
        updateSplit(at: Array(path.dropLast())) { s in
            s.ratio = Self.clampRatio(exact ? value : s.ratio + value, config)
        }
        return true
    }

    // MARK: Layout

    /// Pure layout: node boxes partition `area`; each leaf's window frame is its (rounded) box
    /// inset by `gapsOut` on sides touching the area edge and `gapsIn` elsewhere, then by
    /// `borderSize` on all sides. With exactly one leaf `gapsOutSingle` replaces `gapsOut`.
    ///
    /// Minimum sizes (`minSizes`, learned from apps that refuse to shrink): every split first
    /// gives each side at least what its subtree needs (`minimumBox`), moving the divider only as
    /// far as necessary; the stored ratios are not changed, so the layout stays a pure function
    /// and the extra room goes back when the window closes. When both sides cannot fit, the box is
    /// shared in proportion to the needs and the window that still does not fit gets its min
    /// size centred in its slot with `overflows = true` (the WM floats it). Inactive group members
    /// are returned with `hidden = true` and the group's frame.
    public func layout(area: CGRect, params: LayoutParams, minSizes: [WindowID: CGSize] = [:]) -> [Placement] {
        let relevant = minSizes.filter { contains($0.key) }
        let leaves = relevant.isEmpty
            ? leafGeometries(in: area, config: params.dwindle)
            : minimumAwareLeafGeometries(in: area, params: params, minSizes: relevant)
        let gapsOut = (leaves.count == 1 ? params.gapsOutSingle : nil) ?? params.gapsOut
        let border = params.borderSize
        var placements: [Placement] = []
        placements.reserveCapacity(windows.count)

        for g in leaves {
            guard let leaf = g.leaf else { continue }
            let box = HyprGeometry.rounded(g.box)
            let left = HyprGeometry.sticks(box.minX, area.minX) ? gapsOut : params.gapsIn
            let right = HyprGeometry.sticks(box.maxX, area.maxX) ? gapsOut : params.gapsIn
            let top = HyprGeometry.sticks(box.minY, area.minY) ? gapsOut : params.gapsIn
            let bottom = HyprGeometry.sticks(box.maxY, area.maxY) ? gapsOut : params.gapsIn
            let bar = leaf.isGroup ? max(0, params.groupBarHeight) : 0

            var frame = CGRect(
                x: box.minX + left + border,
                y: box.minY + top + border + bar,
                width: max(0, box.width - left - right - 2 * border),
                height: max(0, box.height - top - bottom - 2 * border - bar)
            )
            let active = leaf.activeWindow
            var overflows = false
            if let minimum = relevant[active] {
                // Half a point of rounding is not an overflow.
                overflows = minimum.width > frame.width + 0.5 || minimum.height > frame.height + 0.5
                frame = HyprGeometry.atLeast(frame, minimum)
            }
            let borderFrame = CGRect(
                x: frame.minX - border, y: frame.minY - bar - border,
                width: frame.width + 2 * border, height: frame.height + bar + 2 * border
            )
            placements.append(Placement(window: active, frame: frame, borderFrame: borderFrame, kind: .tiled, hidden: false, overflows: overflows))
            for member in leaf.windows where member != active {
                placements.append(Placement(window: member, frame: frame, borderFrame: borderFrame, kind: .tiled, hidden: true))
            }
        }
        return placements
    }

    // MARK: Minimum sizes

    /// The smallest box (gaps and border included) a subtree needs so every visible window gets
    /// at least its minimum size. Gaps are counted as the larger of `gapsIn` / `gapsOut` on both
    /// sides, so a box this size always fits whatever edge it ends up on.
    static func minimumBox(_ node: Node, box: CGRect, params: LayoutParams, minSizes: [WindowID: CGSize]) -> CGSize {
        switch node {
        case .leaf(let leaf):
            guard let m = minSizes[leaf.activeWindow] else { return .zero }
            let gap = max(params.gapsIn, params.gapsOut, params.gapsOutSingle ?? 0)
            let bar = leaf.isGroup ? max(0, params.groupBarHeight) : 0
            let pad = 2 * gap + 2 * params.borderSize
            return CGSize(width: m.width > 0 ? m.width + pad : 0, height: m.height > 0 ? m.height + pad + bar : 0)
        case .split(let s):
            let direction = effectiveDirection(of: s, box: box, config: params.dwindle)
            let children = childBoxes(of: box, direction: direction, ratio: s.ratio)
            let a = minimumBox(s.first, box: children.first, params: params, minSizes: minSizes)
            let b = minimumBox(s.second, box: children.second, params: params, minSizes: minSizes)
            switch direction {
            case .horizontal: return CGSize(width: a.width + b.width, height: max(a.height, b.height))
            case .vertical: return CGSize(width: max(a.width, b.width), height: a.height + b.height)
            }
        }
    }

    /// Size of the first child along the split axis after honouring minimum sizes: the stored
    /// ratio's size, clamped so each side gets at least what it needs; when both cannot fit,
    /// the space is shared in proportion to the needs. Pure (for tests).
    public static func minimumAwareFirstSize(total: Double, ratio: Double, firstNeeds: Double, secondNeeds: Double) -> Double {
        let wanted = total / 2 * ratio
        guard firstNeeds > 0 || secondNeeds > 0 else { return wanted }
        if firstNeeds + secondNeeds <= total {
            return min(max(wanted, firstNeeds), total - secondNeeds)
        }
        return total * firstNeeds / (firstNeeds + secondNeeds)
    }

    func minimumAwareLeafGeometries(in area: CGRect, params: LayoutParams, minSizes: [WindowID: CGSize]) -> [NodeGeometry] {
        var out: [NodeGeometry] = []
        if let root { Self.walkHonouringMinimums(root, path: [], box: area, params: params, minSizes: minSizes, into: &out) }
        return out
    }

    private static func walkHonouringMinimums(
        _ node: Node, path: Path, box: CGRect, params: LayoutParams, minSizes: [WindowID: CGSize], into out: inout [NodeGeometry]
    ) {
        switch node {
        case .leaf(let l):
            out.append(NodeGeometry(path: path, box: box, direction: nil, leaf: l))
        case .split(let s):
            let direction = effectiveDirection(of: s, box: box, config: params.dwindle)
            let plain = childBoxes(of: box, direction: direction, ratio: s.ratio)
            let a = minimumBox(s.first, box: plain.first, params: params, minSizes: minSizes)
            let b = minimumBox(s.second, box: plain.second, params: params, minSizes: minSizes)
            let total = direction == .horizontal ? box.width : box.height
            let first = minimumAwareFirstSize(
                total: total, ratio: s.ratio,
                firstNeeds: direction == .horizontal ? a.width : a.height,
                secondNeeds: direction == .horizontal ? b.width : b.height)
            let ratio = total > 0 ? first * 2 / total : s.ratio
            let children = childBoxes(of: box, direction: direction, ratio: ratio)
            walkHonouringMinimums(s.first, path: path + [.first], box: children.first, params: params, minSizes: minSizes, into: &out)
            walkHonouringMinimums(s.second, path: path + [.second], box: children.second, params: params, minSizes: minSizes, into: &out)
        }
    }
}
