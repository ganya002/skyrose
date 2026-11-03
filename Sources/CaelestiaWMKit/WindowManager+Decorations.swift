import CaelestiaCore
import CaelestiaLayout
import CaelestiaOverlay
import CoreGraphics
import Foundation

/// Where the WM sends what the overlay layer must draw. The daemon uses `OverlayDecorations`
/// (borders, group bars, workspace slide, debug overlay); tests record the calls.
@MainActor
public protocol WindowDecorations: AnyObject {
    /// The scene after a layout pass: one border per visible decorated window (R2 contract).
    func apply(_ scene: OverlayScene)
    /// The app or the user moved/resized `id` (not an echo of our own write).
    func externalMove(_ id: WindowID)
    /// Visible workspaces are about to change. Return true to hold the layout until `resume` is
    /// called (the slide puts its cover up first); `resume` may also be called synchronously.
    func workspaceWillChange(_ transitions: [WorkspaceTransition], resume: @escaping () -> Void) -> Bool
    /// The layout pass that applied the change has run.
    func workspaceDidChange()
    /// Quit / panic: every overlay window goes now.
    func removeAll()
    /// Debug overlay contents (nil hides it).
    func debug(_ snapshot: DebugSnapshot?)
    /// `query overlays`.
    func overlayEntries() -> [OverlayQueryEntry]
}

/// One border window as `caelestia query overlays` reports it.
public struct OverlayQueryEntry: Codable, Equatable, Sendable {
    /// The managed window the border belongs to.
    public var target: UInt32
    /// The overlay's own window number.
    public var overlay: Int
    public var at: [Int]
    public var size: [Int]
    public var alpha: Double
    public var active: Bool
    public var vanishing: Bool
    public var group: Bool

    public init(target: UInt32, overlay: Int, frame: CGRect, alpha: Double, active: Bool, vanishing: Bool, group: Bool) {
        self.target = target
        self.overlay = overlay
        at = [Int(frame.minX.rounded()), Int(frame.minY.rounded())]
        size = [Int(frame.width.rounded()), Int(frame.height.rounded())]
        self.alpha = alpha
        self.active = active
        self.vanishing = vanishing
        self.group = group
    }
}

extension WindowManager {
    /// Visible numbered and special workspace per display (for slide detection).
    struct VisibleWorkspaces: Equatable {
        var numbered: Int?
        var special: String?
    }

    func visibleWorkspacesByDisplay() -> [String: VisibleWorkspaces] {
        var result: [String: VisibleWorkspaces] = [:]
        for d in displays {
            var v = VisibleWorkspaces()
            if let n = state.activeNumberedWorkspace(forDisplay: d.id) { v.numbered = n }
            v.special = state.openSpecial(onDisplay: d.id)
            result[d.id] = v
        }
        return result
    }

    /// Displays whose visible workspace changed since the last applied layout.
    func workspaceTransitions(from old: [String: VisibleWorkspaces], to new: [String: VisibleWorkspaces]) -> [WorkspaceTransition] {
        var result: [WorkspaceTransition] = []
        for d in displays {
            guard let before = old[d.id], let after = new[d.id], before != after else { continue }
            let kind: WorkspaceTransition.Kind
            if before.special != after.special {
                kind = after.special != nil ? .specialIn : .specialOut
            } else if let a = before.numbered, let b = after.numbered, a != b {
                kind = .horizontal(forward: b > a)
            } else {
                continue
            }
            // Outgoing: what is on screen now (last applied pass). Incoming: what the new state
            // will put there. Same format, so a still taken when a workspace was left is reused
            // only if nothing on it changed since.
            let shown = visiblePlacements.values.filter { p in d.frame.intersects(p.frame) }
            let next = [after.numbered.map(WorkspaceID.numbered), after.special.map(WorkspaceID.special)].compactMap { $0 }
                .flatMap { placements(of: $0) }.filter { !$0.hidden }
            result.append(WorkspaceTransition(
                displayID: d.displayID, region: d.usableArea(reserved: .zero), kind: kind,
                outgoing: contentKey(d, before, shown, focus: focusShown), incoming: contentKey(d, after, next, focus: state.focusedWindow)
            ))
        }
        return result
    }

    /// "display|ws|special|focus|id@x,y,w,h;..." for the windows a workspace shows.
    func contentKey(_ d: DisplayInfo, _ v: VisibleWorkspaces, _ placements: [Placement], focus focused: WindowID?) -> String {
        let ids = Set(placements.map(\.window))
        let focus = focused.flatMap { ids.contains($0) ? $0 : nil }.map(String.init) ?? "-"
        let frames = placements.sorted { $0.window < $1.window }.map { p in
            "\(p.window)@\(Int(p.frame.minX)),\(Int(p.frame.minY)),\(Int(p.frame.width)),\(Int(p.frame.height))"
        }
        return "\(d.id)|\(v.numbered.map(String.init) ?? "-")|\(v.special ?? "-")|\(focus)|" + frames.joined(separator: ";")
    }

    /// The workspace-slide gate at the start of a layout pass. Returns true when the pass must
    /// wait (the overlay is putting the outgoing still up and will resume it). A hold never
    /// lasts longer than `maxTransitionHold`: after that the layout runs regardless.
    func holdForWorkspaceTransition() -> Bool {
        let visible = visibleWorkspacesByDisplay()
        guard let decorations, !lastVisibleWorkspaces.isEmpty else { return false }
        let transitions = workspaceTransitions(from: lastVisibleWorkspaces, to: visible)
        guard !transitions.isEmpty else { return false }
        if transitionReleased {
            transitionReleased = false
            return false
        }
        if let since = transitionHeldSince {
            if now().timeIntervalSince(since) < Self.maxTransitionHold { return true }
            transitionHeldSince = nil
            return false
        }
        transitionHeldSince = now()
        isInTransitionGate = true
        var resumedSynchronously = false
        let hold = decorations.workspaceWillChange(transitions) { [weak self] in
            guard let self else { return }
            if self.isInTransitionGate {
                resumedSynchronously = true
                return
            }
            guard self.transitionHeldSince != nil else { return }
            self.transitionHeldSince = nil
            self.transitionReleased = true
            self.needsLayout = true
            self.layoutIfNeeded()
        }
        isInTransitionGate = false
        if resumedSynchronously || !hold {
            transitionHeldSince = nil
            return false
        }
        return true
    }

    /// After a layout pass: hands the overlay its scene (and the debug snapshot).
    func publishDecorations(borders: [WindowID: CGRect]) {
        let visible = visibleWorkspacesByDisplay()
        let changed = !lastVisibleWorkspaces.isEmpty && !workspaceTransitions(from: lastVisibleWorkspaces, to: visible).isEmpty
        lastVisibleWorkspaces = visible
        focusShown = state.focusedWindow
        guard let decorations else { return }

        let focused = state.focusedWindow
        var targets: [BorderTarget] = []
        for id in borders.keys.sorted() {
            guard let frame = borders[id] else { continue }
            let group = groupBar(for: id)
            targets.append(BorderTarget(
                id: id, frame: frame, isActive: id == focused,
                appear: shownBefore.contains(id) || group != nil ? .instant : .popIn,
                motion: drag?.window == id ? .snap : .animate,
                group: group
            ))
        }
        var vanish: [CGWindowID: Vanish] = [:]
        for id in lastSceneIDs where borders[id] == nil {
            vanish[id] = fadeOutNext.contains(id) ? .fadeOut : .instant
        }
        shownBefore.formUnion(borders.keys)
        fadeOutNext.removeAll()
        lastSceneIDs = Set(borders.keys)
        decorations.apply(OverlayScene(borders: targets, vanish: vanish))
        if changed { decorations.workspaceDidChange() }
        if debugOverlayEnabled { decorations.debug(debugSnapshot()) }
    }

    /// Tabs of the group `id` is the visible member of, or nil.
    func groupBar(for id: WindowID) -> GroupBar? {
        guard let wsID = state.workspace(of: id), let ws = state[wsID], let leaf = ws.tree.leaf(of: id), leaf.isGroup,
              !leaf.windows.isEmpty else { return nil }
        let titles = leaf.windows.map { member -> String in
            let t = handles[member]?.title ?? descriptors[member]?.title ?? ""
            return t.isEmpty ? (descriptors[member]?.appName ?? "window") : t
        }
        return GroupBar(titles: titles, activeIndex: max(0, min(leaf.activeIndex, leaf.windows.count - 1)), isLocked: leaf.isLocked)
    }

    /// Strip reserved above grouped windows for the group bar (0 in game mode / without borders).
    func groupBarReserved(_ wm: WMConfig) -> Double {
        guard !wm.gameMode, wm.borderSize > 0 else { return 0 }
        return wm.groupBarHeight + wm.groupBarGaps
    }

    // MARK: Debug overlay

    public func setDebugOverlay(_ on: Bool) {
        debugOverlayEnabled = on
        decorations?.debug(on ? debugSnapshot() : nil)
    }

    func debugSnapshot() -> DebugSnapshot {
        let focused = state.focusedWindow
        let ds = displays.map { d -> DebugSnapshot.Display in
            let ws = state.activeNumberedWorkspace(forDisplay: d.id).map { "ws \($0)" } ?? "ws -"
            return DebugSnapshot.Display(frame: d.frame, usableArea: usableArea(of: d), label: "\(d.name) \(ws)")
        }
        let ws = visiblePlacements.keys.sorted().compactMap { id -> DebugSnapshot.Window? in
            guard let p = visiblePlacements[id] else { return nil }
            let title = (handles[id]?.title ?? "").prefix(24)
            let label = String(format: "0x%x %@ %@ %d×%d", id, p.kind.rawValue, String(title), Int(p.frame.width), Int(p.frame.height))
            return DebugSnapshot.Window(frame: p.frame, label: label, isFocused: id == focused)
        }
        let c = counters
        let lines = [
            "Caelestia debug",
            "managed \(managedWindowIDs.count)  parked \(parked.count)  borders \(borderFrames.count)",
            "layout passes \(c.layoutPasses)  setFrame \(c.setFrameCalls)",
            "park \(c.parkCalls)  raise \(c.raiseCalls)  focus \(c.focusCalls)",
            "overlays \(decorations?.overlayEntries().count ?? 0)",
        ]
        return DebugSnapshot(displays: ds, windows: ws, lines: lines)
    }
}
