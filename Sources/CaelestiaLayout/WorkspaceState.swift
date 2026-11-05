import Foundation
import CoreGraphics
import CaelestiaCore

/// The whole workspace model as one value: every workspace, which numbered workspace and which
/// special workspace is visible on each display, and the focused window. All operations are
/// mutating functions on this struct, so the WM can journal it (`Codable`), diff it and replay it
/// deterministically. Nothing here touches AppKit or AX.
///
/// Semantics follow Hyprland unless noted:
/// - A numbered workspace lives on one display; focusing a workspace that exists on another
///   display moves focus to that display.
/// - Special workspaces (scratchpads) open above the active numbered workspace of one display and
///   follow the focused display. Switching the numbered workspace underneath leaves them open; an
///   emptied special closes itself.
/// - Empty numbered workspaces that are not active on their display are dropped.
/// - Pinned windows follow the active numbered workspace of their display.
public struct WorkspaceState: Sendable, Hashable, Codable {
    public private(set) var workspaces: [WorkspaceID: Workspace]
    /// Registered display ids, in registration order.
    public private(set) var displays: [String]
    /// Active numbered workspace per display.
    public private(set) var activeNumbered: [String: Int]
    /// Open special workspace name per display.
    public private(set) var openSpecials: [String: String]
    public private(set) var focusedWindow: WindowID?
    public private(set) var focusedDisplay: String?
    /// Last floating frame of every window that has floated (Hyprland `m_lastFloatingSize`).
    public private(set) var lastFloatingFrames: [WindowID: CGRect]
    /// The size each window had when it was first managed (Hyprland's initial `m_lastFloatingSize`
    /// / pseudo size): used by float and pseudo for windows that never floated.
    public private(set) var naturalSizes: [WindowID: CGSize] = [:]

    public init() {
        workspaces = [:]
        displays = []
        activeNumbered = [:]
        openSpecials = [:]
        focusedWindow = nil
        focusedDisplay = nil
        lastFloatingFrames = [:]
    }

    // MARK: Queries

    public subscript(id: WorkspaceID) -> Workspace? { workspaces[id] }

    /// The active numbered workspace of a display (nil for an unregistered display).
    public func activeNumberedWorkspace(forDisplay display: String) -> Int? {
        activeNumbered[display]
    }

    /// The name of the special workspace open on a display, if any.
    public func openSpecial(onDisplay display: String) -> String? {
        openSpecials[display]
    }

    /// The workspace the user sees on a display: the open special, else the active numbered one.
    public func activeWorkspace(forDisplay display: String) -> WorkspaceID? {
        if let s = openSpecials[display] { return .special(s) }
        if let n = activeNumbered[display] { return .numbered(n) }
        return nil
    }

    /// The workspace of the focused display (what `wsaction` calls the active workspace).
    public var focusedWorkspace: WorkspaceID? {
        focusedDisplay.flatMap { activeWorkspace(forDisplay: $0) }
    }

    /// True when the workspace is the active numbered workspace or the open special of its display.
    public func isVisible(_ id: WorkspaceID) -> Bool {
        guard let ws = workspaces[id] else { return false }
        switch id {
        case .numbered(let n): return activeNumbered[ws.displayID] == n
        case .special(let name): return openSpecials[ws.displayID] == name
        }
    }

    public func workspace(of window: WindowID) -> WorkspaceID? {
        workspaces.values.first { $0.contains(window) }?.id
    }

    public func display(of window: WindowID) -> String? {
        workspace(of: window).flatMap { workspaces[$0]?.displayID }
    }

    public func windows(on id: WorkspaceID) -> [WindowID] {
        workspaces[id]?.windows ?? []
    }

    public func isPinned(_ window: WindowID) -> Bool {
        workspace(of: window).map { workspaces[$0]!.pinned.contains(window) } ?? false
    }

    /// Numbered workspaces the bar lists for a display: always 1...`shown`, plus every non-empty
    /// numbered workspace of the display and its active one, sorted.
    public func occupiedWorkspaces(display: String, shown: Int) -> [Int] {
        var set = Set<Int>()
        if shown >= 1 { set.formUnion(1...shown) }
        for (id, ws) in workspaces where ws.displayID == display {
            if case .numbered(let n) = id, !ws.isEmpty { set.insert(n) }
        }
        if let n = activeNumbered[display] { set.insert(n) }
        return set.sorted()
    }

    /// Numbered workspaces that exist (non-empty or active) across all displays, sorted.
    public var existingNumberedWorkspaces: [Int] {
        workspaces.keys.compactMap(\.number).sorted()
    }

    // MARK: Displays

    /// Registers a display. A new display gets the lowest workspace number that does not exist
    /// yet (Hyprland: new monitors get the next free workspace). Returns its active workspace.
    @discardableResult
    public mutating func ensureDisplay(_ id: String) -> Int {
        if let n = activeNumbered[id] { return n }
        if !displays.contains(id) { displays.append(id) }
        var n = 1
        while workspaces[.numbered(n)] != nil { n += 1 }
        workspaces[.numbered(n)] = Workspace(id: .numbered(n), displayID: id)
        activeNumbered[id] = n
        if focusedDisplay == nil { focusedDisplay = id }
        return n
    }

    /// Unplugging: every workspace of `id` moves to `other`, keeping its number. Its open special
    /// closes; focus moves to `other`.
    public mutating func removeDisplay(_ id: String, movingTo other: String) {
        guard id != other else { return }
        ensureDisplay(other)
        let moved = workspaces.keys.filter { workspaces[$0]!.displayID == id }
        for key in moved { workspaces[key]!.displayID = other }
        openSpecials[id] = nil
        activeNumbered[id] = nil
        displays.removeAll { $0 == id }
        if focusedDisplay == id { focusedDisplay = other }
        for key in moved { prune(key) }
    }

    /// This state as a restart sees it: windows not in `alive` are gone (their tree siblings take
    /// their place, as on close), displays not in `current` hand their workspaces to the first
    /// current display, and new displays get a workspace. Everything else (trees, split ratios,
    /// groups, floating frames, the visible workspace per display, focus) is kept.
    public func restored(keeping alive: Set<WindowID>, displays current: [String]) -> WorkspaceState {
        var s = self
        guard let first = current.first else { return s }
        for w in s.workspaces.values.flatMap(\.windows) where !alive.contains(w) { s.removeWindow(w) }
        for d in s.displays where !current.contains(d) { s.removeDisplay(d, movingTo: first) }
        for d in current { s.ensureDisplay(d) }
        s.displays = current
        s.lastFloatingFrames = s.lastFloatingFrames.filter { alive.contains($0.key) }
        s.naturalSizes = s.naturalSizes.filter { alive.contains($0.key) }
        if let f = s.focusedWindow, !alive.contains(f) { s.focusedWindow = nil }
        if let d = s.focusedDisplay, !current.contains(d) { s.focusedDisplay = first }
        return s
    }

    // MARK: Windows

    /// Adds a new window. `target` defaults to the visible workspace of the focused display; the
    /// workspace is created there if needed. Without `floating` the window is tiled next to the
    /// workspace's last focused tiled window (fallback: the leaf nearest `cursor`). With `focus`
    /// (Hyprland focuses new windows) it becomes the focused window when its workspace is visible,
    /// and that workspace's last focused window otherwise. Returns false if the window is already
    /// managed or no display is registered.
    ///
    /// `size` is the window's own size when it appeared (remembered for float and pseudo). When no
    /// tile has room for another split (dwindle `minTileWidth/Height`), the window floats centred
    /// at that size instead.
    @discardableResult
    public mutating func addWindow(
        _ id: WindowID, to target: WorkspaceID? = nil, floating frame: CGRect? = nil, cursor: CGPoint? = nil,
        size: CGSize? = nil, focus: Bool = true, env: LayoutEnvironment
    ) -> Bool {
        guard workspace(of: id) == nil, let display = focusedDisplay ?? displays.first else { return false }
        ensureDisplay(display)
        let wsID = target ?? activeWorkspace(forDisplay: display)!
        let wsDisplay = ensureWorkspace(wsID, preferredDisplay: display)
        if let size, size.width > 0, size.height > 0, naturalSizes[id] == nil { naturalSizes[id] = size }
        if let frame {
            workspaces[wsID]!.addFloating(id, frame: frame)
            lastFloatingFrames[id] = frame
        } else {
            let area = env.area(forDisplay: wsDisplay)
            if !workspaces[wsID]!.addTiled(id, cursor: cursor, area: area, config: env.config.dwindle, tilePadding: Self.tilePadding(env.config)) {
                let f = Self.centred(naturalSizes[id], in: area)
                workspaces[wsID]!.addFloating(id, frame: f)
                lastFloatingFrames[id] = f
            }
        }
        if focus {
            if isVisible(wsID) {
                recordFocus(id, unfullscreenOthers: env.config.unfullscreenOnFocus)
            } else {
                workspaces[wsID]!.pushFocus(id)
            }
        } else {
            workspaces[wsID]!.focusHistory.append(id)
        }
        return true
    }

    /// Forgets a window without any focus logic (e.g. the app quit while unmanaged). Returns the
    /// workspace it was on.
    @discardableResult
    public mutating func removeWindow(_ id: WindowID) -> WorkspaceID? {
        guard let wsID = workspace(of: id) else { return nil }
        workspaces[wsID]!.detach(id)
        lastFloatingFrames[id] = nil
        naturalSizes[id] = nil
        if focusedWindow == id { focusedWindow = nil }
        prune(wsID)
        return wsID
    }

    /// The window was closed. Returns the window that should receive focus per Hyprland
    /// `input.focus_on_close = 1`: `cursorWindow` (the managed window under the pointer) if given,
    /// else the next window in the focus history of the closed window's workspace, else the next
    /// one on the display's visible workspace (an emptied special closes). nil when nothing is
    /// left to focus.
    @discardableResult
    public mutating func closeWindow(_ id: WindowID, cursorWindow: WindowID? = nil) -> WindowID? {
        guard let wsID = workspace(of: id) else { return nil }
        let display = workspaces[wsID]!.displayID
        let wasFocused = focusedWindow == id
        workspaces[wsID]!.detach(id)
        lastFloatingFrames[id] = nil
        naturalSizes[id] = nil
        prune(wsID)

        var candidate: WindowID?
        if let cursorWindow, cursorWindow != id, workspace(of: cursorWindow) != nil {
            candidate = cursorWindow
        } else {
            candidate = workspaces[wsID]?.lastFocused
        }
        if candidate == nil, let visible = activeWorkspace(forDisplay: display) {
            candidate = workspaces[visible]?.lastFocused
        }
        if wasFocused { focusedWindow = candidate }
        return candidate
    }

    /// Hyprland `movetoworkspace` (`follow`) / `movetoworkspacesilent`. The target is created on
    /// the window's display when it does not exist. Following opens a special target (or activates
    /// a numbered one, moving focus to its display) and focuses the window; moving out of a
    /// special with `follow` closes that special. Fullscreen/maximized state is dropped. Pinned
    /// windows and same-workspace moves are refused (false).
    @discardableResult
    public mutating func moveWindow(
        _ id: WindowID, to target: WorkspaceID, follow: Bool, cursor: CGPoint? = nil, env: LayoutEnvironment
    ) -> Bool {
        guard let sourceID = workspace(of: id), sourceID != target else { return false }
        if case .numbered(let n) = target, n < 1 { return false }
        let source = workspaces[sourceID]!
        guard !source.pinned.contains(id) else { return false }
        let floatingFrame = source.floating[id]

        workspaces[sourceID]!.detach(id)
        let targetDisplay = ensureWorkspace(target, preferredDisplay: source.displayID)
        if let floatingFrame {
            workspaces[target]!.addFloating(id, frame: floatingFrame)
        } else {
            workspaces[target]!.addTiled(id, cursor: cursor, area: env.area(forDisplay: targetDisplay), config: env.config.dwindle)
        }

        if follow, case .special(let name) = sourceID, !target.isSpecial, openSpecials[source.displayID] == name {
            closeSpecial(on: source.displayID)
        }
        prune(sourceID)

        if follow {
            workspaces[target]!.pushFocus(id)
            switch target {
            case .numbered(let n): activateNumbered(n, on: targetDisplay)
            case .special(let name): openSpecial(name, on: targetDisplay)
            }
            focusedDisplay = targetDisplay
            focusedWindow = id
        } else {
            workspaces[target]!.focusHistory.append(id)
            if focusedWindow == id {
                focusedWindow = workspaces[sourceID]?.lastFocused
            }
        }
        return true
    }

    /// Caelestia `wsaction("move"/"move_silent", "", i)`: moves the window to slot `i` of the
    /// focused display's current workspace group.
    @discardableResult
    public mutating func moveWindow(_ id: WindowID, toIndex i: Int, follow: Bool, env: LayoutEnvironment) -> Bool {
        let n = WorkspaceMath.target(index: i, active: focusedWorkspace, perGroup: env.config.workspacesPerGroup)
        return moveWindow(id, to: .numbered(n), follow: follow, env: env)
    }

    /// Caelestia `wsaction("move", "group", g)`: moves the window to the same slot in group `g`.
    @discardableResult
    public mutating func moveWindow(_ id: WindowID, toGroup g: Int, follow: Bool, env: LayoutEnvironment) -> Bool {
        let n = WorkspaceMath.target(group: g, active: focusedWorkspace, perGroup: env.config.workspacesPerGroup)
        return moveWindow(id, to: .numbered(n), follow: follow, env: env)
    }

    /// `movetoworkspace special:<name>`: the special opens on the window's display and the window
    /// gets focus.
    @discardableResult
    public mutating func moveToSpecial(_ id: WindowID, name: String = "special", env: LayoutEnvironment) -> Bool {
        moveWindow(id, to: .special(name), follow: true, env: env)
    }

    /// `movetoworkspace e+0`: moves a window out of its special workspace to the active numbered
    /// workspace of that display, closing the special, and focuses it.
    @discardableResult
    public mutating func moveOutOfSpecial(_ id: WindowID, env: LayoutEnvironment) -> Bool {
        guard let wsID = workspace(of: id), wsID.isSpecial else { return false }
        let display = workspaces[wsID]!.displayID
        let n = ensureDisplay(display)
        return moveWindow(id, to: .numbered(n), follow: true, env: env)
    }

    /// Hyprland `movewindow <dir>` inside the window's workspace: swaps with the tiled neighbour.
    /// Returns false when there is none (the WM then moves the window to the next display).
    @discardableResult
    public mutating func moveWindow(_ id: WindowID, direction: Direction, env: LayoutEnvironment) -> Bool {
        guard let wsID = workspace(of: id) else { return false }
        let area = env.area(forDisplay: workspaces[wsID]!.displayID)
        let history = workspaces[wsID]!.focusHistory
        return workspaces[wsID]!.tree.move(id, direction, in: area, config: env.config.dwindle, focusHistory: history)
    }

    /// Hyprland `togglefloating`. Floating uses `frame`, else the window's last floating size (or
    /// its natural size, or 60%×70% of the area) centred on the centre of its tile, like Hyprland
    /// (ops10: a 1280×1410 float centred on its 1263×1398 slot), kept on-screen. Tiling inserts
    /// the window at the leaf under its centre and drops its pin. Fullscreen/maximized windows are
    /// refused (false).
    @discardableResult
    public mutating func setFloating(_ id: WindowID, _ floating: Bool, frame: CGRect? = nil, env: LayoutEnvironment) -> Bool {
        guard let wsID = workspace(of: id), var ws = workspaces[wsID] else { return false }
        guard ws.fullscreen != id, ws.maximized != id else { return false }
        let area = env.area(forDisplay: ws.displayID)
        if floating {
            guard ws.floating[id] == nil else { return false }
            var f: CGRect
            if let frame {
                f = frame
            } else {
                let size = lastFloatingFrames[id]?.size ?? naturalSizes[id] ?? Self.defaultFloatingFrame(in: area).size
                let params = LayoutParams(wm: env.config, singleWindowGaps: !wsID.isSpecial)
                let slot = ws.tree.layout(area: area, params: params).first { $0.window == id }?.frame
                let centre = slot.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: area.midX, y: area.midY)
                f = HyprGeometry.clamp(CGRect(x: (centre.x - size.width / 2).rounded(), y: (centre.y - size.height / 2).rounded(),
                                              width: size.width, height: size.height), to: area)
            }
            ws.pseudo[id] = nil
            ws.tree.remove(id)
            ws.addFloating(id, frame: f)
            lastFloatingFrames[id] = f
        } else {
            guard let f = ws.floating[id] else { return false }
            lastFloatingFrames[id] = f
            ws.floating[id] = nil
            ws.floatingOrder.removeAll { $0 == id }
            ws.pinned.remove(id)
            ws.tree.insert(id, relativeTo: nil, cursor: CGPoint(x: f.midX, y: f.midY), in: area, config: env.config.dwindle)
        }
        workspaces[wsID] = ws
        return true
    }

    @discardableResult
    public mutating func toggleFloating(_ id: WindowID, frame: CGRect? = nil, env: LayoutEnvironment) -> Bool {
        guard let wsID = workspace(of: id) else { return false }
        return setFloating(id, !workspaces[wsID]!.isFloating(id), frame: frame, env: env)
    }

    /// Records the frame of a floating window after the user moved/resized it.
    @discardableResult
    public mutating func setFloatingFrame(_ id: WindowID, _ frame: CGRect) -> Bool {
        guard let wsID = workspace(of: id), workspaces[wsID]!.floating[id] != nil else { return false }
        workspaces[wsID]!.floating[id] = frame
        lastFloatingFrames[id] = frame
        return true
    }

    /// Hyprland `fullscreen 0`: toggles true fullscreen. Only one window per workspace; a
    /// maximized window switches mode.
    @discardableResult
    public mutating func toggleFullscreen(_ id: WindowID) -> Bool {
        guard let wsID = workspace(of: id) else { return false }
        if workspaces[wsID]!.fullscreen == id {
            workspaces[wsID]!.fullscreen = nil
        } else {
            workspaces[wsID]!.fullscreen = id
            if workspaces[wsID]!.maximized == id { workspaces[wsID]!.maximized = nil }
        }
        return true
    }

    /// Hyprland `fullscreen 1` (maximize): fills the usable area with the single-window gaps.
    @discardableResult
    public mutating func toggleMaximize(_ id: WindowID) -> Bool {
        guard let wsID = workspace(of: id) else { return false }
        if workspaces[wsID]!.maximized == id {
            workspaces[wsID]!.maximized = nil
        } else {
            workspaces[wsID]!.maximized = id
            if workspaces[wsID]!.fullscreen == id { workspaces[wsID]!.fullscreen = nil }
        }
        return true
    }

    /// Hyprland `pseudo`: a tiled window keeps its own size (last floating size, else its natural
    /// size) centred in its slot, scaled down to fit. Toggles; refused for floating windows and
    /// windows whose size is unknown.
    @discardableResult
    public mutating func togglePseudo(_ id: WindowID) -> Bool {
        guard let wsID = workspace(of: id), var ws = workspaces[wsID], ws.tree.contains(id) else { return false }
        if ws.pseudo[id] != nil {
            ws.pseudo[id] = nil
        } else {
            guard let size = lastFloatingFrames[id]?.size ?? naturalSizes[id], size.width > 0, size.height > 0 else { return false }
            ws.pseudo[id] = size
        }
        workspaces[wsID] = ws
        return true
    }

    public func isPseudo(_ id: WindowID) -> Bool {
        workspace(of: id).flatMap { workspaces[$0]?.pseudo[id] } != nil
    }

    /// Hyprland `pin`: only floating, non-fullscreen windows can be pinned. The window moves to
    /// the active numbered workspace of its display (pinned windows live there and follow it).
    @discardableResult
    public mutating func setPinned(_ id: WindowID, _ pinned: Bool) -> Bool {
        guard let wsID = workspace(of: id), let ws = workspaces[wsID] else { return false }
        if !pinned {
            workspaces[wsID]!.pinned.remove(id)
            return true
        }
        guard let frame = ws.floating[id], ws.fullscreen != id, ws.maximized != id else { return false }
        let display = ws.displayID
        let active = WorkspaceID.numbered(ensureDisplay(display))
        if wsID != active {
            let wasFocused = focusedWindow == id
            workspaces[wsID]!.detach(id)
            ensureWorkspace(active, preferredDisplay: display)
            workspaces[active]!.addFloating(id, frame: frame)
            if wasFocused { workspaces[active]!.pushFocus(id) } else { workspaces[active]!.focusHistory.append(id) }
            prune(wsID)
        }
        workspaces[active]!.pinned.insert(id)
        return true
    }

    @discardableResult
    public mutating func togglePin(_ id: WindowID) -> Bool {
        setPinned(id, !isPinned(id))
    }

    /// The window got focus. Moves it to the front of its workspace's focus history, raises it if
    /// floating and makes its workspace visible (a numbered one becomes active; a special opens;
    /// focusing a window under an open special closes that special unless the window is pinned).
    /// `unfullscreenOthers` implements `on_focus_under_fullscreen = 2`: another fullscreen or
    /// maximized window on the workspace drops that state.
    public mutating func recordFocus(_ id: WindowID, unfullscreenOthers: Bool = false) {
        guard let wsID = workspace(of: id) else { return }
        let display = workspaces[wsID]!.displayID
        workspaces[wsID]!.pushFocus(id)
        workspaces[wsID]!.raiseFloating(id)
        if unfullscreenOthers {
            if let f = workspaces[wsID]!.fullscreen, f != id { workspaces[wsID]!.fullscreen = nil }
            if let m = workspaces[wsID]!.maximized, m != id { workspaces[wsID]!.maximized = nil }
        }
        switch wsID {
        case .numbered(let n):
            activateNumbered(n, on: display)
            if openSpecials[display] != nil, !workspaces[wsID]!.pinned.contains(id) {
                closeSpecial(on: display)
            }
        case .special(let name):
            if openSpecials[display] != name { openSpecial(name, on: display) }
        }
        focusedDisplay = display
        focusedWindow = id
    }

    /// Mutates the dwindle tree of the workspace holding `window` (resize, groups, toggleSplit...).
    public mutating func updateTree<T>(of window: WindowID, _ body: (inout DwindleTree) -> T) -> T? {
        guard let wsID = workspace(of: window) else { return nil }
        return body(&workspaces[wsID]!.tree)
    }

    /// Mutates one workspace in place.
    public mutating func updateWorkspace<T>(_ id: WorkspaceID, _ body: (inout Workspace) -> T) -> T? {
        guard workspaces[id] != nil else { return nil }
        return body(&workspaces[id]!)
    }

    // MARK: Workspace switching

    /// Hyprland `workspace <id>`: makes the workspace visible on its display (created on
    /// `display`, else the focused display, when new) and focuses that display. A numbered
    /// workspace becomes the active one underneath any open special (which stays open, keeping
    /// focus); a special opens on the focused display, replacing another open special.
    public mutating func focusWorkspace(_ id: WorkspaceID, display preferred: String? = nil) {
        guard let fallback = preferred ?? focusedDisplay ?? displays.first else { return }
        switch id {
        case .numbered(let n):
            guard n >= 1 else { return }
            let display = workspaces[id]?.displayID ?? fallback
            ensureDisplay(display)
            activateNumbered(n, on: display)
            focusedDisplay = display
            if openSpecials[display] == nil {
                focusedWindow = workspaces[id]?.lastFocused
            }
        case .special(let name):
            ensureDisplay(fallback)
            openSpecial(name, on: fallback)
            focusedDisplay = fallback
            focusedWindow = workspaces[id]?.lastFocused
        }
    }

    /// Caelestia `wsaction("focus", "", i)`: slot `i` of the focused display's current group.
    /// Returns the workspace number focused.
    @discardableResult
    public mutating func focusWorkspace(index i: Int, config: WMConfig) -> Int {
        let n = WorkspaceMath.target(index: i, active: focusedWorkspace, perGroup: config.workspacesPerGroup)
        focusWorkspace(.numbered(n))
        return n
    }

    /// Caelestia `wsaction("focus", "group", g)`: the current slot in group `g`.
    @discardableResult
    public mutating func focusWorkspaceGroup(_ g: Int, config: WMConfig) -> Int {
        let n = WorkspaceMath.target(group: g, active: focusedWorkspace, perGroup: config.workspacesPerGroup)
        focusWorkspace(.numbered(n))
        return n
    }

    /// Next numbered workspace of a display among the ones the bar shows (1...`workspacesShown`
    /// plus occupied ones); past the last one the next number is created (up to
    /// `workspaceGroups × workspacesPerGroup`). Returns the new workspace number, nil if unchanged.
    @discardableResult
    public mutating func nextWorkspace(display: String? = nil, config: WMConfig) -> Int? {
        guard let display = display ?? focusedDisplay, let current = activeNumbered[display] else { return nil }
        let list = occupiedWorkspaces(display: display, shown: config.workspacesShown)
        let target = list.first { $0 > current } ?? (current + 1)
        guard target <= Self.maxWorkspace(config), target != current else { return nil }
        focusWorkspace(.numbered(target), display: display)
        return target
    }

    /// Previous numbered workspace among the shown/occupied ones; stays on the first.
    @discardableResult
    public mutating func prevWorkspace(display: String? = nil, config: WMConfig) -> Int? {
        guard let display = display ?? focusedDisplay, let current = activeNumbered[display] else { return nil }
        let list = occupiedWorkspaces(display: display, shown: config.workspacesShown)
        guard let target = list.last(where: { $0 < current }) else { return nil }
        focusWorkspace(.numbered(target), display: display)
        return target
    }

    /// Hyprland `workspace +10`: the same slot in the next group (clamped to the last group).
    @discardableResult
    public mutating func nextGroup(display: String? = nil, config: WMConfig) -> Int? {
        shiftGroup(by: 1, display: display, config: config)
    }

    /// Hyprland `workspace -10`: the same slot in the previous group.
    @discardableResult
    public mutating func prevGroup(display: String? = nil, config: WMConfig) -> Int? {
        shiftGroup(by: -1, display: display, config: config)
    }

    /// Caelestia `fn.toggle`:
    /// - `generic` (SUPER+S): with `specialWsCloseAny` and ANY special open on the display, that
    ///   one closes; otherwise "special" toggles (open if closed, close if open, replacing another
    ///   open special).
    /// - named (sysmon/music/...): opens the special (replacing any other) and asks the WM to place
    ///   its app (`needsAppPlacement`); if it is the open one, closes it.
    /// Focus moves to the opened special's last focused window, or back to the numbered
    /// workspace's when one closes.
    @discardableResult
    public mutating func toggleSpecial(name: String = "special", generic: Bool = false, display: String? = nil, config: WMConfig)
        -> SpecialToggleResult
    {
        guard let display = display ?? focusedDisplay ?? displays.first else { return SpecialToggleResult() }
        ensureDisplay(display)
        let open = openSpecials[display]
        var result = SpecialToggleResult()
        if generic {
            if config.specialWsCloseAny, let open {
                closeSpecial(on: display)
                result.closed = open
            } else if open == "special" {
                closeSpecial(on: display)
                result.closed = "special"
            } else {
                result.closed = open
                openSpecial("special", on: display)
                result.opened = "special"
            }
        } else if open == name {
            closeSpecial(on: display)
            result.closed = name
        } else {
            result.closed = open
            openSpecial(name, on: display)
            result.opened = name
            result.needsAppPlacement = true
        }
        focusedDisplay = display
        focusedWindow = activeWorkspace(forDisplay: display).flatMap { workspaces[$0]?.lastFocused }
        return result
    }

    /// Hyprland `cyclenext`: the window after the focused one on the display's visible workspace
    /// (wrapping). `order` picks focus-history order (`cyclenext hist`) or arrival order. Hidden
    /// group tabs are skipped. Pure: the WM focuses the result and calls `recordFocus`.
    public func cycleNext(display: String? = nil, order: CycleOrder = .focusHistory) -> WindowID? {
        cycle(display: display, order: order, forward: true)
    }

    /// Hyprland `cyclenext prev`.
    public func cyclePrev(display: String? = nil, order: CycleOrder = .focusHistory) -> WindowID? {
        cycle(display: display, order: order, forward: false)
    }

    // MARK: - Internals

    static func maxWorkspace(_ config: WMConfig) -> Int {
        max(1, config.workspaceGroups) * max(1, config.workspacesPerGroup)
    }

    /// 60%×70% of the area, centred (first-time float without a remembered frame).
    /// Gaps and border a tile loses per axis (conservative: the larger gap on both sides).
    static func tilePadding(_ config: WMConfig) -> Double {
        config.gameMode ? 0 : 2 * max(config.gapsIn, config.gapsOut) + 2 * config.borderSize
    }

    /// `size` (else the default float size) centred in `area`, clamped to it.
    static func centred(_ size: CGSize?, in area: CGRect) -> CGRect {
        guard let size else { return defaultFloatingFrame(in: area) }
        let w = min(size.width, area.width), h = min(size.height, area.height)
        return CGRect(x: (area.midX - w / 2).rounded(), y: (area.midY - h / 2).rounded(), width: w, height: h)
    }

    static func defaultFloatingFrame(in area: CGRect) -> CGRect {
        let w = (area.width * 0.6).rounded()
        let h = (area.height * 0.7).rounded()
        return CGRect(x: (area.midX - w / 2).rounded(), y: (area.midY - h / 2).rounded(), width: w, height: h)
    }

    private func cycle(display: String?, order: CycleOrder, forward: Bool) -> WindowID? {
        guard let display = display ?? focusedDisplay, let wsID = activeWorkspace(forDisplay: display), let ws = workspaces[wsID]
        else { return nil }
        let visible = ws.visibleWindows
        guard !visible.isEmpty else { return nil }
        let list: [WindowID]
        switch order {
        case .creation:
            list = ws.order.filter(visible.contains) + visible.filter { !ws.order.contains($0) }
        case .focusHistory:
            list = ws.focusHistory.filter(visible.contains) + visible.filter { !ws.focusHistory.contains($0) }
        }
        guard let current = focusedWindow, let index = list.firstIndex(of: current) else { return list.first }
        return list[(index + (forward ? 1 : list.count - 1)) % list.count]
    }

    @discardableResult
    private mutating func ensureWorkspace(_ id: WorkspaceID, preferredDisplay: String) -> String {
        if let ws = workspaces[id] { return ws.displayID }
        workspaces[id] = Workspace(id: id, displayID: preferredDisplay)
        return preferredDisplay
    }

    /// Drops an empty workspace unless it is the active numbered one; an emptied special closes.
    private mutating func prune(_ id: WorkspaceID) {
        guard let ws = workspaces[id], ws.isEmpty else { return }
        switch id {
        case .numbered(let n):
            if activeNumbered[ws.displayID] != n { workspaces[id] = nil }
        case .special(let name):
            if openSpecials[ws.displayID] == name { openSpecials[ws.displayID] = nil }
            workspaces[id] = nil
        }
    }

    private mutating func activateNumbered(_ n: Int, on display: String) {
        let old = activeNumbered[display]
        guard old != n else { return }
        ensureWorkspace(.numbered(n), preferredDisplay: display)
        activeNumbered[display] = n
        guard let old, let oldWS = workspaces[.numbered(old)] else { return }
        for p in oldWS.floatingOrder where oldWS.pinned.contains(p) {
            guard let frame = oldWS.floating[p] else { continue }
            workspaces[.numbered(old)]!.detach(p)
            workspaces[.numbered(n)]!.addFloating(p, frame: frame)
            workspaces[.numbered(n)]!.pinned.insert(p)
            if focusedWindow == p {
                workspaces[.numbered(n)]!.pushFocus(p)
            } else {
                workspaces[.numbered(n)]!.focusHistory.append(p)
            }
        }
        prune(.numbered(old))
    }

    private mutating func openSpecial(_ name: String, on display: String) {
        let id = WorkspaceID.special(name)
        if let ws = workspaces[id], ws.displayID != display {
            if openSpecials[ws.displayID] == name { openSpecials[ws.displayID] = nil }
            workspaces[id]!.displayID = display
        }
        ensureWorkspace(id, preferredDisplay: display)
        openSpecials[display] = name
    }

    private mutating func closeSpecial(on display: String) {
        guard let name = openSpecials[display] else { return }
        openSpecials[display] = nil
        prune(.special(name))
    }

    private mutating func shiftGroup(by groups: Int, display: String?, config: WMConfig) -> Int? {
        guard let display = display ?? focusedDisplay, let current = activeNumbered[display] else { return nil }
        let target = current + groups * max(1, config.workspacesPerGroup)
        guard target >= 1, target <= Self.maxWorkspace(config), target != current else { return nil }
        focusWorkspace(.numbered(target), display: display)
        return target
    }
}
