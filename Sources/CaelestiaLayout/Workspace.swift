import Foundation
import CoreGraphics
import CaelestiaCore

/// One workspace: its dwindle tree, floating windows (bottom → top z-order), the fullscreen /
/// maximized window, pinned windows and the focus history. Lives on exactly one display.
public struct Workspace: Sendable, Hashable, Codable {
    public var id: WorkspaceID
    /// Stable display id (`DisplayInfo.id`).
    public var displayID: String
    public var tree: DwindleTree
    /// Stored frames of floating windows (CG/AX top-left space).
    public var floating: [WindowID: CGRect]
    /// Floating windows from bottom to top.
    public var floatingOrder: [WindowID]
    /// True fullscreen window (covers the whole display, no gaps, no bar).
    public var fullscreen: WindowID?
    /// Maximized window (fills the usable area with the single-window gaps).
    public var maximized: WindowID?
    /// Pinned (floating) windows; they follow the active workspace of their display.
    public var pinned: Set<WindowID>
    /// Most recently focused first.
    public var focusHistory: [WindowID]
    /// Windows in the order they arrived on the workspace (Hyprland `cyclenext` order).
    public var order: [WindowID]
    /// Pseudotiled windows (Hyprland `pseudo`) and the size each keeps, centred in its slot.
    public var pseudo: [WindowID: CGSize] = [:]

    public init(id: WorkspaceID, displayID: String) {
        self.id = id
        self.displayID = displayID
        tree = DwindleTree()
        floating = [:]
        floatingOrder = []
        fullscreen = nil
        maximized = nil
        pinned = []
        focusHistory = []
        order = []
    }

    public var isEmpty: Bool { tree.isEmpty && floating.isEmpty }

    /// Every window: tiled ones in tree order (groups expanded), then floating ones bottom → top.
    public var windows: [WindowID] { tree.windows + floatingOrder }

    /// Windows that are actually shown: the active tab of each group plus floating windows.
    public var visibleWindows: [WindowID] { tree.visibleWindows + floatingOrder }

    public func contains(_ window: WindowID) -> Bool {
        tree.contains(window) || floating[window] != nil
    }

    public func isFloating(_ window: WindowID) -> Bool { floating[window] != nil }

    /// The most recently focused window still on the workspace.
    public var lastFocused: WindowID? { focusHistory.first }

    /// The most recently focused tiled window (split origin for new windows).
    public var lastFocusedTiled: WindowID? { focusHistory.first { tree.contains($0) } }

    // MARK: Mutation helpers

    /// Removes the window from every structure. Returns false when it was not here.
    @discardableResult
    mutating func detach(_ window: WindowID) -> Bool {
        var found = tree.remove(window)
        if floating.removeValue(forKey: window) != nil { found = true }
        floatingOrder.removeAll { $0 == window }
        pinned.remove(window)
        if fullscreen == window { fullscreen = nil }
        if maximized == window { maximized = nil }
        pseudo[window] = nil
        focusHistory.removeAll { $0 == window }
        order.removeAll { $0 == window }
        return found
    }

    /// Tiles a new window next to the last focused tiled one. With `tilePadding` (gaps + border
    /// per axis) the dwindle minimum tile size is enforced: false when no tile has room left (the
    /// window was not added; `addTiledOrStack` then stacks it into a group).
    @discardableResult
    mutating func addTiled(_ window: WindowID, cursor: CGPoint?, area: CGRect, config: DwindleConfig, tilePadding: Double? = nil) -> Bool {
        tree.insert(window, relativeTo: lastFocusedTiled, cursor: cursor, in: area, config: config,
                    enforceMinTile: tilePadding != nil, tilePadding: tilePadding ?? 0)
        guard tree.contains(window) else { return false }
        if !order.contains(window) { order.append(window) }
        return true
    }

    /// Tiles `window`, and when no split can honour the minimum tile size stacks it into the
    /// focused leaf's group instead. Never floats. False only when the window is already here.
    @discardableResult
    mutating func addTiledOrStack(_ window: WindowID, cursor: CGPoint?, area: CGRect, config: DwindleConfig, tilePadding: Double?) -> Bool {
        if addTiled(window, cursor: cursor, area: area, config: config, tilePadding: tilePadding) { return true }
        guard tree.stack(window, onto: lastFocusedTiled) else { return false }
        if !order.contains(window) { order.append(window) }
        return true
    }

    mutating func addFloating(_ window: WindowID, frame: CGRect) {
        floating[window] = frame
        floatingOrder.removeAll { $0 == window }
        floatingOrder.append(window)
        if !order.contains(window) { order.append(window) }
    }

    mutating func pushFocus(_ window: WindowID) {
        focusHistory.removeAll { $0 == window }
        focusHistory.insert(window, at: 0)
    }

    mutating func raiseFloating(_ window: WindowID) {
        guard floating[window] != nil else { return }
        floatingOrder.removeAll { $0 == window }
        floatingOrder.append(window)
    }
}

/// What `WorkspaceState` operations need from the outside world: the config and the usable
/// area of every display (needed to pick split directions when windows are inserted).
public struct LayoutEnvironment: Sendable {
    public var config: WMConfig
    /// Usable area per display id (CG/AX top-left space).
    public var areas: [String: CGRect]

    public init(config: WMConfig = WMConfig(), areas: [String: CGRect] = [:]) {
        self.config = config
        self.areas = areas
    }

    /// Fallback when a display has no area yet: a 13" Air work area (1470×956 minus 10 per edge).
    public static let fallbackArea = CGRect(x: 10, y: 10, width: 1450, height: 936)

    public func area(forDisplay id: String) -> CGRect {
        if let a = areas[id] { return a }
        if let first = areas.keys.sorted().first, let a = areas[first] { return a }
        return Self.fallbackArea
    }
}

/// Outcome of a special-workspace toggle (Caelestia `fn.toggle`).
public struct SpecialToggleResult: Sendable, Hashable {
    /// Name of the special workspace that was opened, if any.
    public var opened: String?
    /// Name of the special workspace that was closed (or replaced), if any.
    public var closed: String?
    /// True when a named scratchpad was opened and the WM must spawn/move its configured app
    /// (`place_apps` in functions.lua).
    public var needsAppPlacement: Bool

    public init(opened: String? = nil, closed: String? = nil, needsAppPlacement: Bool = false) {
        self.opened = opened
        self.closed = closed
        self.needsAppPlacement = needsAppPlacement
    }
}

/// Order used by `cycleNext`/`cyclePrev`.
public enum CycleOrder: Sendable, Hashable {
    /// Most recently focused first (Hyprland `cyclenext hist`).
    case focusHistory
    /// Arrival order on the workspace (Hyprland `cyclenext` without arguments).
    case creation
}
