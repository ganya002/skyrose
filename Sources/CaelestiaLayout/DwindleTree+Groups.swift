import Foundation
import CoreGraphics
import CaelestiaCore

extension DwindleTree {
    /// Hyprland `togglegroup`: a lone window becomes a one-member tab group; a group is
    /// dissolved. Dissolving keeps the active member in the leaf and re-inserts the other members
    /// in group order as separate leaves, each splitting the previously placed one (so they end up
    /// next to each other). Returns false when the window is not tiled here.
    @discardableResult
    public mutating func groupToggle(_ window: WindowID, in area: CGRect, config: DwindleConfig = DwindleConfig()) -> Bool {
        guard let path = path(to: window), let leaf = node(at: path)?.leaf else { return false }
        if !leaf.isGroup {
            updateLeaf(at: path) { l in
                l.isGroup = true
                l.isLocked = false
            }
            return true
        }
        let active = leaf.activeWindow
        updateLeaf(at: path) { l in
            l = Leaf(window: active)
        }
        var previous = active
        for member in leaf.windows where member != active {
            insert(member, relativeTo: previous, cursor: nil, in: area, config: config, autoGroup: false)
            previous = member
        }
        return true
    }

    /// Adds `window` to the group holding `target` (Hyprland `moveintogroup` with
    /// `group:insert_after_current`): the window leaves its own leaf (or its own group), is inserted
    /// right after the target group's active tab and becomes the active tab. A non-group target
    /// leaf becomes a group. Refused (false) when either group is locked, when the two windows
    /// share a leaf, or when a window is missing.
    @discardableResult
    public mutating func groupAdd(_ window: WindowID, to target: WindowID) -> Bool {
        guard window != target, let sourcePath = path(to: window), let targetPath = path(to: target), sourcePath != targetPath,
            let source = node(at: sourcePath)?.leaf, let destination = node(at: targetPath)?.leaf
        else { return false }
        if destination.isGroup, destination.isLocked { return false }
        if source.isGroup, source.isLocked, source.windows.count > 1 { return false }
        remove(window)
        guard let newTargetPath = path(to: target) else { return false }
        updateLeaf(at: newTargetPath) { l in
            l.isGroup = true
            let index = l.clampedActiveIndex + 1
            l.windows.insert(window, at: index)
            l.activeIndex = index
        }
        return true
    }

    /// Hyprland `moveoutofgroup`: `window` leaves its tab group and becomes its own leaf, split
    /// from the group's leaf (the group's new active tab is the split origin). Returns false when
    /// the window is not in a group with at least two members.
    @discardableResult
    public mutating func groupMoveOut(_ window: WindowID, in area: CGRect, config: DwindleConfig = DwindleConfig()) -> Bool {
        guard let path = path(to: window), let leaf = node(at: path)?.leaf, leaf.isGroup, leaf.windows.count > 1 else {
            return false
        }
        remove(window)
        guard let remaining = node(at: path)?.leaf else { return false }
        return insert(window, relativeTo: remaining.activeWindow, cursor: nil, in: area, config: config, autoGroup: false)
    }

    /// Hyprland `changegroupactive f`: the next tab in the group of `window` becomes active
    /// (wrapping). Returns the new active window, or nil when the window is not grouped.
    @discardableResult
    public mutating func groupNext(in window: WindowID) -> WindowID? {
        cycleGroup(window, step: 1)
    }

    /// Hyprland `changegroupactive b`: the previous tab becomes active (wrapping).
    @discardableResult
    public mutating func groupPrev(in window: WindowID) -> WindowID? {
        cycleGroup(window, step: -1)
    }

    /// Makes `window` the active tab of its group. Returns false when it is not grouped.
    @discardableResult
    public mutating func groupActivate(_ window: WindowID) -> Bool {
        guard let path = path(to: window), let leaf = node(at: path)?.leaf, leaf.isGroup,
            let index = leaf.windows.firstIndex(of: window)
        else { return false }
        updateLeaf(at: path) { $0.activeIndex = index }
        return true
    }

    /// Hyprland `lockactivegroup`: locks (`true`), unlocks (`false`) or toggles (`nil`) the group
    /// of `window`. Locked groups refuse `groupAdd` and auto-grouping on insert. Returns false when
    /// the window is not grouped.
    @discardableResult
    public mutating func groupSetLocked(_ window: WindowID, _ locked: Bool? = nil) -> Bool {
        guard let path = path(to: window), let leaf = node(at: path)?.leaf, leaf.isGroup else { return false }
        updateLeaf(at: path) { l in l.isLocked = locked ?? !l.isLocked }
        return true
    }

    public func isGrouped(_ window: WindowID) -> Bool {
        leaf(of: window)?.isGroup ?? false
    }

    public func isGroupLocked(_ window: WindowID) -> Bool {
        guard let l = leaf(of: window), l.isGroup else { return false }
        return l.isLocked
    }

    /// The members of the group holding `window` in tab order (just `[window]` for an ungrouped
    /// tiled window, empty when it is not tiled here).
    public func groupMembers(of window: WindowID) -> [WindowID] {
        leaf(of: window)?.windows ?? []
    }

    /// The visible tab of the leaf holding `window`.
    public func groupActiveWindow(of window: WindowID) -> WindowID? {
        leaf(of: window)?.activeWindow
    }

    private mutating func cycleGroup(_ window: WindowID, step: Int) -> WindowID? {
        guard let path = path(to: window), let leaf = node(at: path)?.leaf, leaf.isGroup else { return nil }
        let count = leaf.windows.count
        let next = ((leaf.clampedActiveIndex + step) % count + count) % count
        updateLeaf(at: path) { $0.activeIndex = next }
        return leaf.windows[next]
    }
}
