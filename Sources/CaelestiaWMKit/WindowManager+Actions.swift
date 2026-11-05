import CaelestiaCore
import CaelestiaLayout
import CaelestiaOverlay
import CaelestiaPlatform
import CoreGraphics
import Foundation

/// Keymap actions (spec 3.4, 4.3, 4.4). Binds arrive as `Fired` values from the hotkey engine;
/// IPC goes through `perform(_:)` directly.
extension WindowManager {
    /// Runs the binds the event tap fired.
    public func handle(fired: [Fired]) {
        for f in fired {
            switch f.phase {
            case .press, .release, .repeatTick, .scrollStep:
                perform(f.bind.action, location: f.location)
            case .dragBegin:
                beginDrag(f.bind.action.kind, at: f.location ?? windowSystem.cursorLocation)
            case .dragMove(let delta):
                moveDrag(by: delta)
            case .dragEnd:
                endDrag(at: f.location ?? windowSystem.cursorLocation)
            }
        }
    }

    /// Performs one action. Returns false when it did nothing (no focused window, refused move...)
    /// or is not a WM action (then `onUnhandledAction` gets it).
    @discardableResult
    public func perform(_ action: Action, location: CGPoint? = nil) -> Bool {
        if action.kind == .wmPanic {
            panic()
            return true
        }
        guard isManaging else { return false }
        let env = environment
        let wm = config.wm
        let focused = state.focusedWindow
        var done = true

        switch action.kind {
        // MARK: Workspaces
        case .workspaceFocus:
            guard let i = action.index else { return false }
            state.focusWorkspace(index: i, config: wm)
        case .workspaceMove, .workspaceMoveSilent:
            guard let i = action.index, let f = focused else { return false }
            done = state.moveWindow(f, toIndex: i, follow: action.kind == .workspaceMove, env: env)
        case .workspaceFocusGroup:
            guard let g = action.group else { return false }
            state.focusWorkspaceGroup(g, config: wm)
        case .workspaceMoveGroup:
            guard let g = action.group, let f = focused else { return false }
            done = state.moveWindow(f, toGroup: g, follow: true, env: env)
        case .workspaceNext:
            done = state.nextWorkspace(config: wm) != nil
        case .workspacePrev:
            done = state.prevWorkspace(config: wm) != nil
        case .workspaceNextGroup:
            done = state.nextGroup(config: wm) != nil
        case .workspacePrevGroup:
            done = state.prevGroup(config: wm) != nil
        case .workspaceMoveToNext, .workspaceMoveToPrev:
            guard let f = focused, let display = state.display(of: f),
                  let n = state.activeNumberedWorkspace(forDisplay: display) else { return false }
            let target = n + (action.kind == .workspaceMoveToNext ? 1 : -1)
            guard target >= 1, target <= max(1, wm.workspaceGroups) * max(1, wm.workspacesPerGroup) else { return false }
            done = state.moveWindow(f, to: .numbered(target), follow: true, env: env)
        case .workspaceMoveToSpecial:
            guard let f = focused else { return false }
            done = state.moveToSpecial(f, name: action.name ?? "special", env: env)
        case .workspaceMoveOutOfSpecial:
            guard let f = focused else { return false }
            done = state.moveOutOfSpecial(f, env: env)
        case .specialToggle:
            let name = action.name ?? "special"
            state.toggleSpecial(name: name, generic: name == "special", config: wm)

        // MARK: Focus and cycling
        case .windowFocus:
            guard let dir = action.direction else { return false }
            done = focus(direction: dir)
        case .windowCycleNext, .windowCyclePrev:
            let next = action.kind == .windowCycleNext ? state.cycleNext() : state.cyclePrev()
            guard let next else { return false }
            state.recordFocus(next, unfullscreenOthers: wm.unfullscreenOnFocus)

        // MARK: Moving and resizing
        case .windowSwap:
            guard let dir = action.direction, let f = focused else { return false }
            done = swap(f, direction: dir)
        case .windowResize:
            guard let f = focused, let axis = action.axis, let delta = action.delta else { return false }
            done = resize(f, axis: axis, percent: delta)
        case .windowDrag, .windowResizeDrag:
            // Only meaningful as a mouse/drag bind (handled by `handle(fired:)`).
            return false

        // MARK: Window state
        case .windowToggleFloat:
            guard let f = focused else { return false }
            done = state.toggleFloating(f, env: env)
        case .windowFullscreen:
            guard let f = focused else { return false }
            done = state.toggleFullscreen(f)
        case .windowMaximize:
            guard let f = focused else { return false }
            done = state.toggleMaximize(f)
        case .windowPin:
            guard let f = focused else { return false }
            if !isFloating(f) { state.setFloating(f, true, env: env) }
            done = state.togglePin(f)
        case .windowCenter:
            guard let f = focused, let frame = floatingFrame(f), let area = area(of: f) else { return false }
            done = state.setFloatingFrame(f, centered(frame.size, in: area))
        case .windowPseudo:
            guard let f = focused else { return false }
            done = state.togglePseudo(f)
        case .layoutToggleSplit:
            guard let f = focused else { return false }
            done = state.updateTree(of: f) { $0.toggleSplit(f) } ?? false
        case .layoutSwapSplit:
            guard let f = focused else { return false }
            done = state.updateTree(of: f) { $0.swapSplit(f) } ?? false
        case .windowNormalize:
            guard let f = focused, let area = area(of: f) else { return false }
            let size = CGSize(width: floor(area.width * 0.55), height: floor(area.height * 0.7))
            if !isFloating(f) { state.setFloating(f, true, env: env) }
            done = state.setFloatingFrame(f, centered(size, in: area))
        case .windowPip:
            guard let f = focused, let area = area(of: f) else { return false }
            if !isFloating(f) { state.setFloating(f, true, env: env) }
            guard let frame = floatingFrame(f) else { return false }
            let pip = resolvedFloatingFrame(effects: RuleEffects(move: "pip"), in: area, windowSize: frame.size) ?? frame
            state.setFloatingFrame(f, pip.integralPoints)
            if !state.isPinned(f) { state.setPinned(f, true) }
        case .windowClose:
            guard let f = focused, let handle = handles[f] else { return false }
            // The window goes away through the window system's `destroyed` event (the app may
            // also refuse, e.g. "save changes?"). The animator puts the stills up first so the
            // close can shrink and fade a window that never vanished.
            if let animator = windowAnimator, visiblePlacements[f] != nil {
                let scene = animationScene(visiblePlacements, raiseOrder: Array(raised))
                _ = animator.prepareClose(f, scene: WindowAnimationRequest(changes: [], windows: scene, displays: displayFrames))
            }
            return handle.close()

        // MARK: Groups
        case .groupToggle:
            guard let f = focused, let area = area(of: f) else { return false }
            done = state.updateTree(of: f) { $0.groupToggle(f, in: area, config: wm.dwindle) } ?? false
        case .groupMoveOut:
            guard let f = focused, let area = area(of: f) else { return false }
            done = state.updateTree(of: f) { $0.groupMoveOut(f, in: area, config: wm.dwindle) } ?? false
        case .groupLock:
            guard let f = focused else { return false }
            done = state.updateTree(of: f) { $0.groupSetLocked(f) } ?? false
        case .groupNext, .groupPrev:
            guard let f = focused else { return false }
            let next = state.updateTree(of: f) { action.kind == .groupNext ? $0.groupNext(in: f) : $0.groupPrev(in: f) }
            guard let n = next ?? nil else { return false }
            state.recordFocus(n)

        default:
            onUnhandledAction?(action)
            return false
        }
        setNeedsLayout()
        return done
    }

    // MARK: - Helpers

    func isFloating(_ id: WindowID) -> Bool {
        state.workspace(of: id).flatMap { state[$0] }?.isFloating(id) ?? false
    }

    func floatingFrame(_ id: WindowID) -> CGRect? {
        state.workspace(of: id).flatMap { state[$0] }?.floating[id]
    }

    func area(of id: WindowID) -> CGRect? {
        display(id: state.display(of: id)).map(usableArea(of:))
    }

    func centered(_ size: CGSize, in area: CGRect) -> CGRect {
        CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// Hyprland `movefocus`: the neighbour on the visible workspace of the focused display, else
    /// the last focused window of the neighbouring display in that direction.
    func focus(direction: Direction) -> Bool {
        guard let displayID = state.focusedDisplay, let source = display(id: displayID) else { return false }
        if let f = state.focusedWindow, let wsID = state.activeWorkspace(forDisplay: displayID), let ws = state[wsID] {
            let list = placements(of: wsID)
            if let n = FocusNavigation.neighbor(of: f, direction: direction, placements: list, focusHistory: ws.focusHistory) {
                state.recordFocus(n, unfullscreenOthers: config.wm.unfullscreenOnFocus)
                return true
            }
        }
        guard let other = DisplayGeometry.neighbor(of: source, direction: direction, in: displays) else { return false }
        if let wsID = state.activeWorkspace(forDisplay: other.id), let w = state[wsID]?.lastFocused {
            state.recordFocus(w, unfullscreenOthers: config.wm.unfullscreenOnFocus)
        } else if let n = state.activeNumberedWorkspace(forDisplay: other.id) {
            state.focusWorkspace(.numbered(n), display: other.id)
        }
        return true
    }

    /// Hyprland `movewindow`: swap with the tiled neighbour, else move to the neighbouring
    /// display's visible workspace.
    func swap(_ id: WindowID, direction: Direction) -> Bool {
        if state.moveWindow(id, direction: direction, env: environment) { return true }
        guard let source = display(id: state.display(of: id)),
              let other = DisplayGeometry.neighbor(of: source, direction: direction, in: displays),
              let n = state.activeNumberedWorkspace(forDisplay: other.id) else { return false }
        return state.moveWindow(id, to: .numbered(n), follow: true, env: environment)
    }

    /// Caelestia's resize binds: `percent` of the window's current size. Tiled windows move their
    /// split (smart_resizing); floating windows grow from their top-left corner.
    func resize(_ id: WindowID, axis: ResizeAxis, percent: Double) -> Bool {
        guard let wsID = state.workspace(of: id), let area = area(of: id) else { return false }
        if let frame = floatingFrame(id) {
            var f = frame
            if axis == .width { f.size.width = max(50, (f.width * (1 + percent / 100)).rounded()) }
            else { f.size.height = max(50, (f.height * (1 + percent / 100)).rounded()) }
            return state.setFloatingFrame(id, Self.clamp(f, to: area))
        }
        let list = placements(of: wsID)
        let dwindle = config.wm.dwindle
        return state.updateTree(of: id) { $0.resizePercent(id, axis: axis, percent: percent, placements: list, in: area, config: dwindle) } ?? false
    }

    // MARK: - Mouse drag (⌥L+drag / ⌥L+right-drag, or Z/X held)

    func beginDrag(_ kind: ActionKind, at location: CGPoint?) {
        guard isManaging, let location else { return }
        let hit = visiblePlacements.values
            .filter { $0.frame.contains(location) }
            .sorted { ($0.kind == .tiled ? 0 : 1, $0.window) > ($1.kind == .tiled ? 0 : 1, $1.window) }
            .first
        guard let p = hit ?? state.focusedWindow.flatMap({ visiblePlacements[$0] }) else { return }
        drag = DragState(
            window: p.window, kind: kind == .windowResizeDrag ? .resize : .move,
            edges: ResizeEdges.nearestCorner(to: location, in: p.frame), location: location
        )
        state.recordFocus(p.window, unfullscreenOthers: config.wm.unfullscreenOnFocus)
        // A tiled window dragged with the mouse: its still follows the pointer on the animator's
        // cover and a preview shows the slot it would swap into; the real window stays put.
        if kind != .windowResizeDrag, p.kind == .tiled, let animator = windowAnimator {
            var scene = animationScene(visiblePlacements, raiseOrder: Array(raised))
            for i in scene.indices { scene[i].isActive = scene[i].id == p.window }
            dragIsLive = animator.beginDrag(p.window, pointer: location, scene: WindowAnimationRequest(changes: [], windows: scene, displays: displayFrames))
        }
        setNeedsLayout()
    }

    /// The tiled window a dragged window would swap with at `point` (same workspace).
    func dropTarget(for window: WindowID, at point: CGPoint) -> Placement? {
        visiblePlacements.values.first { $0.window != window && $0.kind == .tiled && $0.frame.contains(point) }
            .flatMap { state.workspace(of: $0.window) == state.workspace(of: window) ? $0 : nil }
    }

    func moveDrag(by delta: CGPoint) {
        guard let d = drag, let area = area(of: d.window) else { return }
        drag?.location.x += delta.x
        drag?.location.y += delta.y
        if var f = floatingFrame(d.window) {
            switch d.kind {
            case .move:
                f = f.offsetBy(dx: delta.x, dy: delta.y)
            case .resize:
                if d.edges.contains(.left) { f.origin.x += delta.x; f.size.width -= delta.x }
                if d.edges.contains(.right) { f.size.width += delta.x }
                if d.edges.contains(.top) { f.origin.y += delta.y; f.size.height -= delta.y }
                if d.edges.contains(.bottom) { f.size.height += delta.y }
                f.size.width = max(50, f.width)
                f.size.height = max(50, f.height)
            }
            state.setFloatingFrame(d.window, f)
        } else if d.kind == .resize {
            let dwindle = config.wm.dwindle
            _ = state.updateTree(of: d.window) { $0.resizeDrag(d.window, edges: d.edges, delta: delta, in: area, config: dwindle) }
        } else {
            if dragIsLive, let location = drag?.location {
                windowAnimator?.updateDrag(pointer: location, dropTarget: dropTarget(for: d.window, at: location)?.frame)
            }
            return
        }
        setNeedsLayout()
    }

    /// A tiled window dropped on another tiled window of the same workspace swaps with it.
    func endDrag(at location: CGPoint?) {
        guard let d = drag else { return }
        drag = nil
        if dragIsLive {
            dragIsLive = false
            windowAnimator?.endDrag()
        }
        guard d.kind == .move, !isFloating(d.window) else { return }
        let point = location ?? d.location
        guard let target = dropTarget(for: d.window, at: point) else { return }
        _ = state.updateTree(of: d.window) { $0.swap(d.window, target.window) }
        setNeedsLayout()
    }
}
