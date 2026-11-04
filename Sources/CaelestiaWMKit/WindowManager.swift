import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaOverlay
import CaelestiaPlatform
import CoreGraphics
import Foundation

/// The tiling window manager (spec 4.1 Standard mode, 4.3–4.6): owns the `WorkspaceState`, turns
/// window-system events and actions into state changes, and runs ONE coalesced layout pass that
/// applies frames over AX and parks windows of hidden workspaces off-screen.
///
/// Riko rules this class enforces (spec 0.5 / 12.2):
/// - R3: a frame is only written when its target changed (or the window was parked); our own AX
///   echoes are ignored; a min size learned from a read-back converges the layout in ≤ 3 passes;
///   an app that keeps snapping back is re-applied at most `maxSnapBackRetries` times per target.
/// - R6: the parking journal is written BEFORE a window moves off-screen (a failed write leaves
///   the window visible), the journal is replayed on start, and quit/panic restore every window.
///
/// Main actor only. Nothing here touches AppKit directly; the window system, displays and clock
/// are injected so the Riko suite runs headless.
@MainActor
public final class WindowManager {
    /// Debug counters (`caelestia query state`), used by the Riko suite.
    public struct Counters: Equatable, Sendable {
        public var layoutPasses = 0
        public var setFrameCalls = 0
        public var parkCalls = 0
        public var focusCalls = 0
        public var raiseCalls = 0
        public var restoredOnLaunch = 0
        public var journalWriteFailures = 0

        public var dictionary: [String: Int] {
            [
                "layoutPasses": layoutPasses, "setFrameCalls": setFrameCalls, "parkCalls": parkCalls,
                "focusCalls": focusCalls, "raiseCalls": raiseCalls, "restoredOnLaunch": restoredOnLaunch,
                "journalWriteFailures": journalWriteFailures,
            ]
        }
    }

    /// How layout passes get scheduled after a change.
    public enum LayoutScheduling: Sendable {
        /// Once per main run-loop turn (the daemon).
        case mainQueue
        /// Only when `layoutIfNeeded()` is called (tests).
        case manual
    }

    struct DragState {
        enum Kind { case move, resize }
        var window: WindowID
        var kind: Kind
        var edges: ResizeEdges
        var location: CGPoint
    }

    /// Re-applies allowed per window and target when an app moves a tiled window back by itself.
    public static let maxSnapBackRetries = 2
    /// Focus events for a parked window this soon after we switched workspaces are ignored (macOS
    /// hands focus to another window of the app being parked; following it would switch back).
    public static let focusGuardInterval: TimeInterval = 0.5

    public let windowSystem: any WindowSystem
    public let displayProvider: any DisplayProvider
    public let journal: ParkingJournal

    public internal(set) var state = WorkspaceState()
    public internal(set) var config: Config
    public internal(set) var rules: RuleSet
    public internal(set) var keymap: Keymap?
    /// Displays, primary first.
    public internal(set) var displays: [DisplayInfo] = []
    public internal(set) var counters = Counters()
    /// False before `start()` and after quit/panic: no layout, no event handling.
    public internal(set) var isManaging = false
    /// Border overlay frames for every visible decorated window: exactly what the overlay layer
    /// must draw (R2 contract: one entry per visible managed window, nothing else).
    public internal(set) var borderFrames: [WindowID: CGRect] = [:]
    /// Visible placements from the last layout pass.
    public internal(set) var visiblePlacements: [WindowID: Placement] = [:]

    /// Borders, group bars, workspace slide and debug overlay (nil: headless, nothing drawn).
    public var decorations: (any WindowDecorations)?
    /// Animates real windows between layout passes (snapshot covers in Standard mode). Nil:
    /// every frame is written at once (tests, animations off).
    public var windowAnimator: (any WindowAnimator)?
    /// A workspace-change layout is held at most this long for the slide's outgoing still.
    public static let maxTransitionHold: TimeInterval = 0.3

    /// Called after quit/panic restored every window (the daemon exits).
    public var onQuit: (() -> Void)?
    /// Actions the WM does not own (shell, apps, capture, media); the daemon logs or forwards them.
    public var onUnhandledAction: ((Action) -> Void)?
    /// `config.reload` / `rules.reload` from IPC; return warnings.
    public var onConfigReload: (() -> [String])?
    public var onRulesReload: (() -> [String])?
    /// After every applied layout pass (the shell refreshes workspaces / the active window).
    public var onLayoutApplied: (() -> Void)?
    /// Shell IPC (`shell.*`, drawers, toasts). Returns nil for commands the shell does not own.
    public var shellResponder: ((IPCRequest, IPCCommand) -> IPCResponse?)?
    /// Displays whose auto-hidden bar is currently revealed (it reserves its width).
    public internal(set) var barRevealed: Set<String> = []

    var handles: [WindowID: any WindowHandle] = [:]
    var descriptors: [WindowID: WindowDescriptor] = [:]
    var effects: [WindowID: RuleEffects] = [:]
    /// Last target frame sent for each window.
    var applied: [WindowID: CGRect] = [:]
    /// Parked windows and the display they are parked on.
    var parked: [WindowID: String] = [:]
    /// Minimum sizes learned from read-backs (AX does not expose them).
    var minSizes: [WindowID: CGSize] = [:]
    /// Minimized windows / windows of hidden apps, with the workspace to return to.
    var suspended: [WindowID: WorkspaceID] = [:]
    var snapBacks: [WindowID: Int] = [:]
    var forceApply: Set<WindowID> = []
    /// Parked windows whose parking corner must be recomputed (the display arrangement changed,
    /// so the old corner may now be visible on a neighbour).
    var staleParking: Set<WindowID> = []
    /// Floating/special windows raised since they became visible.
    var raised: Set<WindowID> = []
    /// What macOS last reported (or we last requested) as focused.
    var systemFocus: WindowID?
    /// Most recently focused first, across workspaces (`focusHistoryID`).
    var focusOrder: [WindowID] = []
    var lastWorkspaceChange = Date.distantPast
    var drag: DragState?
    /// The animator shows the current tiled-window drag live.
    var dragIsLive = false
    var needsLayout = false
    var layoutScheduled = false
    var isDiscovering = false
    // Decorations bookkeeping (WindowManager+Decorations).
    /// Windows whose border has been shown: coming back (workspace switch) is instant, not a pop-in.
    var shownBefore: Set<WindowID> = []
    /// Borders that must fade out (closed / minimized / hidden app) rather than vanish at once.
    var fadeOutNext: Set<WindowID> = []
    var lastSceneIDs: Set<WindowID> = []
    var lastVisibleWorkspaces: [String: VisibleWorkspaces] = [:]
    var transitionHeldSince: Date?
    var transitionReleased = false
    var isInTransitionGate = false
    var debugOverlayEnabled = false
    /// The focused window as of the last applied layout pass (what the screen shows).
    var focusShown: WindowID?
    let scheduling: LayoutScheduling
    let now: () -> Date
    let startDate: Date

    public init(
        windowSystem: any WindowSystem, displayProvider: any DisplayProvider, journal: ParkingJournal = ParkingJournal(),
        config: Config = Config(), rules: RuleSet = .defaults, keymap: Keymap? = nil,
        scheduling: LayoutScheduling = .mainQueue, now: @escaping () -> Date = Date.init
    ) {
        self.windowSystem = windowSystem
        self.displayProvider = displayProvider
        self.journal = journal
        self.config = config
        self.rules = rules
        self.keymap = keymap
        self.scheduling = scheduling
        self.now = now
        startDate = now()
    }

    // MARK: - Lifecycle

    /// Registers displays, replays the parking journal (crash restore), then starts discovery and
    /// tiles every existing window onto the visible workspace of the display it is on.
    public func start() {
        guard !isManaging else { return }
        displayProvider.onChange = { [weak self] in self?.displaysChanged($0) }
        displayProvider.start()
        displaysChanged(displayProvider.displays)
        counters.restoredOnLaunch = restoreJournal()
        if counters.restoredOnLaunch > 0 {
            Log.wm.notice("restored \(self.counters.restoredOnLaunch) parked window(s) from the journal")
        }

        isManaging = true
        windowSystem.onEvent = { [weak self] in self?.handle($0) }
        isDiscovering = true
        windowSystem.start()
        isDiscovering = false
        systemFocus = windowSystem.focusedWindowID
        if let f = systemFocus, isManaged(f) { state.recordFocus(f) }
        setNeedsLayout()
    }

    /// Restores every window (journal + off-screen rescue), stops discovery and calls `onQuit`.
    /// Used by the panic chord, `wm.quit`/`wm.panic` and SIGTERM.
    @discardableResult
    public func shutdown() -> Int {
        let restored = restoreEverything()
        windowSystem.onEvent = nil
        windowSystem.stop()
        displayProvider.onChange = nil
        displayProvider.stop()
        onQuit?()
        return restored
    }

    /// The panic chord (⌃⌥⌘⇧Esc): same as quit; it must work in any state.
    public func panic() {
        Log.wm.notice("panic: restoring every window and quitting")
        shutdown()
    }

    public func apply(config: Config) {
        self.config = config
        setNeedsLayout()
    }

    /// New rules apply to windows as they appear; existing windows keep their tiling state.
    public func apply(rules: RuleSet) {
        self.rules = rules
        for (id, d) in descriptors { effects[id] = rules.resolve(for: d).effects }
        setNeedsLayout()
    }

    public func apply(keymap: Keymap) {
        self.keymap = keymap
    }

    // MARK: - Queries

    public func isManaged(_ id: WindowID) -> Bool { handles[id] != nil && state.workspace(of: id) != nil }
    public func isParked(_ id: WindowID) -> Bool { parked[id] != nil }
    public var managedWindowIDs: [WindowID] { handles.keys.filter { state.workspace(of: $0) != nil }.sorted() }
    public func handle(for id: WindowID) -> (any WindowHandle)? { handles[id] }
    public func learnedMinSize(_ id: WindowID) -> CGSize? { minSizes[id] }

    public var environment: LayoutEnvironment {
        LayoutEnvironment(config: config.wm, areas: Dictionary(uniqueKeysWithValues: displays.map { ($0.id, usableArea(of: $0)) }))
    }

    /// Frame − menu bar − Dock − screen frame − bar (spec 4.6), with per-display overrides. The
    /// bar reserves its width while it is persistent or revealed (Caelestia: the exclusive zone
    /// follows the bar's visibility). It replaces the frame band on its edge, so that edge
    /// reserves max(frame, bar), not their sum.
    public func usableArea(of display: DisplayInfo) -> CGRect {
        let c = config.resolved(forDisplay: display.id)
        let frame = c.wm.screenFrame ? c.wm.screenFrameInset : 0
        var reserved = Insets.uniform(frame)
        if c.bar.enabled, c.bar.persistent || barRevealed.contains(display.id) {
            let bar = max(frame, c.bar.width)
            switch c.bar.edge {
            case .left: reserved.left = bar
            case .right: reserved.right = bar
            case .top: reserved.top = bar
            case .bottom: reserved.bottom = bar
            }
        }
        return display.usableArea(reserved: reserved)
    }

    /// The shell revealed / hid an auto-hidden bar on `display`: retile around it.
    public func setBarRevealed(_ revealed: Bool, display: String) {
        let changed = revealed ? barRevealed.insert(display).inserted : barRevealed.remove(display) != nil
        guard changed else { return }
        if !config.resolved(forDisplay: display).bar.persistent { setNeedsLayout() }
    }

    public func display(id: String?) -> DisplayInfo? {
        guard let id else { return nil }
        return displays.first { $0.id == id }
    }

    /// Placements of one workspace with the current config, areas and learned min sizes.
    ///
    /// A tiled window whose minimum size is bigger than its slot comes back from the layout
    /// centred on the slot, which can push it past the usable area (live test: Finder at x = −44).
    /// Such frames are shifted back inside the area, keeping their size.
    public func placements(of id: WorkspaceID) -> [Placement] {
        guard let ws = state[id], let d = display(id: ws.displayID) else { return [] }
        let area = usableArea(of: d)
        let wm = config.resolved(forDisplay: d.id).wm
        return WorkspaceLayout.compute(
            ws, area: area, fullFrame: d.frame, config: wm, minSizes: minSizes, groupBarHeight: groupBarReserved(wm)
        ).map { p in
            guard p.kind == .tiled, !area.contains(p.frame) else { return p }
            let x = p.frame.width > area.width ? area.minX : min(max(p.frame.minX, area.minX), area.maxX - p.frame.width)
            let y = p.frame.height > area.height ? area.minY : min(max(p.frame.minY, area.minY), area.maxY - p.frame.height)
            var shifted = p
            shifted.frame.origin = CGPoint(x: x, y: y)
            shifted.borderFrame = p.borderFrame.offsetBy(dx: x - p.frame.minX, dy: y - p.frame.minY)
            return shifted
        }
    }

    // MARK: - Layout

    public func setNeedsLayout() {
        needsLayout = true
        guard scheduling == .mainQueue, !layoutScheduled else { return }
        layoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.layoutScheduled = false
                self?.layoutIfNeeded()
            }
        }
    }

    /// One layout pass: visible windows get their frame (only when it changed), hidden ones are
    /// parked, newly visible floating/special windows are raised, and focus is synced.
    public func layoutIfNeeded() {
        guard needsLayout, isManaging else { return }
        if holdForWorkspaceTransition() { return }
        needsLayout = false
        counters.layoutPasses += 1

        var visible: [WindowID: Placement] = [:]
        var raiseOrder: [WindowID] = []
        for d in displays {
            var ids: [WorkspaceID] = []
            if let n = state.activeNumberedWorkspace(forDisplay: d.id) { ids.append(.numbered(n)) }
            if let s = state.openSpecial(onDisplay: d.id) { ids.append(.special(s)) }
            for wsID in ids {
                for p in placements(of: wsID) where !p.hidden {
                    visible[p.window] = p
                    if wsID.isSpecial || p.kind != .tiled { raiseOrder.append(p.window) }
                }
            }
        }

        let previous = visiblePlacements
        // Workspace switches are the slide's job; mouse resizes track 1:1 (spec 2.3).
        let animated = windowAnimator != nil && drag?.kind != .resize
            && (lastVisibleWorkspaces.isEmpty || workspaceTransitions(from: lastVisibleWorkspaces, to: visibleWorkspacesByDisplay()).isEmpty)
        var writes: [() -> Bool] = []
        var changes: [WindowFrameChange] = []
        var borders: [WindowID: CGRect] = [:]
        for id in handles.keys.sorted() {
            guard let handle = handles[id], let wsID = state.workspace(of: id) else { continue }
            if let p = visible[id] {
                if p.kind != .fullscreen, p.borderFrame != p.frame, decorated(id) { borders[id] = p.borderFrame }
                let wasParked = parked[id] != nil
                if applied[id] != p.frame { snapBacks[id] = 0 }
                guard wasParked || forceApply.contains(id) || applied[id] != p.frame else { continue }
                forceApply.remove(id)
                let old = previous[id]?.frame ?? (wasParked ? nil : applied[id])
                applied[id] = p.frame
                if wasParked {
                    parked[id] = nil
                    try? journal.remove(id)
                }
                changes.append(WindowFrameChange(id: id, kind: previous[id] == nil ? .open : .move, from: old, to: p.frame))
                writes.append { [weak self] in
                    guard let self else { return false }
                    let got = self.setFrame(handle, p.frame)
                    guard p.kind == .tiled, !got.isNull, got.width > p.frame.width + 1 || got.height > p.frame.height + 1 else { return false }
                    let known = self.minSizes[id] ?? .zero
                    self.minSizes[id] = CGSize(width: max(known.width, got.width.rounded()), height: max(known.height, got.height.rounded()))
                    return self.minSizes[id] != known
                }
            } else if let ws = state[wsID] {
                if animated, let was = previous[id] {
                    changes.append(WindowFrameChange(id: id, kind: .leave, from: was.frame, to: nil))
                    let display = ws.displayID
                    writes.append { [weak self] in
                        self?.park(id, handle, on: display)
                        return false
                    }
                } else {
                    park(id, handle, on: ws.displayID)
                }
            }
        }
        // Closed or minimized since the last pass: their stills shrink and fade.
        for (id, p) in previous where visible[id] == nil && (handles[id] == nil || state.workspace(of: id) == nil) {
            changes.append(WindowFrameChange(id: id, kind: .close, from: p.frame, to: nil))
        }
        let commit = { [weak self] in
            var learned = false
            for w in writes where w() { learned = true }
            if learned { self?.setNeedsLayout() }
        }
        let scene = animationScene(visible, raiseOrder: raiseOrder)
        if animated, let animator = windowAnimator, !changes.isEmpty {
            animator.animate(WindowAnimationRequest(changes: changes, windows: scene, displays: displayFrames), commit: commit)
        } else {
            commit()
        }
        borderFrames = borders
        visiblePlacements = visible
        publishDecorations(borders: borders)
        windowAnimator?.windowsChanged(visible: scene)

        let visibleRaised = Set(raiseOrder)
        for id in raiseOrder where !raised.contains(id) {
            handles[id]?.raise()
            counters.raiseCalls += 1
        }
        raised = visibleRaised
        syncFocus()
        onLayoutApplied?()
    }

    /// Display frames by CGDirectDisplayID (for the window animator).
    var displayFrames: [CGDirectDisplayID: CGRect] {
        Dictionary(displays.map { ($0.displayID, $0.frame) }, uniquingKeysWith: { a, _ in a })
    }

    /// Visible windows back to front (tiled, then floating/special in raise order) as the
    /// window animator draws them.
    func animationScene(_ visible: [WindowID: Placement], raiseOrder: [WindowID]) -> [AnimatedWindow] {
        let raisedIndex = Dictionary(raiseOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let focused = state.focusedWindow
        let ids = visible.keys.sorted { a, b in
            let ra = raisedIndex[a] ?? -1, rb = raisedIndex[b] ?? -1
            if ra != rb { return ra < rb }
            if (a == focused) != (b == focused) { return b == focused }
            return a < b
        }
        return ids.compactMap { id in
            guard let p = visible[id], let d = DisplayGeometry.display(for: p.frame, in: displays) else { return nil }
            return AnimatedWindow(id: id, frame: p.frame, displayID: d.displayID, isActive: id == focused,
                                  decorated: p.kind != .fullscreen && decorated(id))
        }
    }

    private func decorated(_ id: WindowID) -> Bool {
        if effects[id]?.noBorder == true { return false }
        return descriptors[id]?.isStandardWindow ?? true
    }

    private func setFrame(_ handle: any WindowHandle, _ frame: CGRect) -> CGRect {
        counters.setFrameCalls += 1
        return handle.setFrame(frame)
    }

    /// Moves a window of a hidden workspace off-screen. The journal record goes to disk first; if
    /// that fails the window stays where it is (never risk a lost window).
    private func park(_ id: WindowID, _ handle: any WindowHandle, on displayID: String) {
        guard parked[id] != displayID || staleParking.contains(id), let d = display(id: displayID) else { return }
        staleParking.remove(id)
        let current = handle.frame
        if parked[id] == nil {
            let restore = applied[id] ?? current
            guard !restore.isNull else { return }
            let record = ParkedWindowRecord(
                windowID: id, pid: handle.pid, bundleID: handle.bundleID, title: handle.title,
                restoreFrame: restore, displayID: displayID, parkedAt: now()
            )
            do {
                try journal.upsert(record)
            } catch {
                counters.journalWriteFailures += 1
                Log.wm.error("not parking #\(id): journal write failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        let size = current.isNull ? (applied[id]?.size ?? .zero) : current.size
        let others = displays.filter { $0.id != displayID }.map(\.frame)
        let target = ParkingPlanner.parkedFrame(size: size, on: d.frame, others: others)
        handle.setPosition(target.origin)
        counters.parkCalls += 1
        parked[id] = displayID
        lastWorkspaceChange = now()
    }

    private func syncFocus() {
        guard let f = state.focusedWindow else { return }
        if focusOrder.first != f {
            focusOrder.removeAll { $0 == f }
            focusOrder.insert(f, at: 0)
        }
        guard f != systemFocus, effects[f]?.noFocus != true, let handle = handles[f] else { return }
        systemFocus = f
        handle.focus()
        counters.focusCalls += 1
    }

    // MARK: - Displays

    func displaysChanged(_ list: [DisplayInfo]) {
        // An empty list happens transiently (clamshell, sleep); keep the old layout.
        guard !list.isEmpty else { return }
        let sorted = list.filter(\.isPrimary) + list.filter { !$0.isPrimary }
        let newIDs = Set(sorted.map(\.id))
        for d in sorted { state.ensureDisplay(d.id) }
        for old in displays where !newIDs.contains(old.id) {
            state.removeDisplay(old.id, movingTo: sorted[0].id)
        }
        if sorted.map(\.frame) != displays.map(\.frame) { staleParking = Set(parked.keys) }
        displays = sorted
        setNeedsLayout()
    }

    // MARK: - Window-system events

    func handle(_ event: WindowSystemEvent) {
        guard isManaging else { return }
        switch event {
        case .created(let handle):
            manage(handle)
        case .destroyed(let id):
            unmanage(id)
        case .focused(let id):
            systemFocusChanged(id)
        case .frameChanged(let id, let frame, let isEcho):
            frameChanged(id, frame, isEcho: isEcho)
        case .minimized(let id):
            suspend(id)
        case .deminiaturized(let id):
            resume(id)
        case .appHidden(let pid):
            for (id, h) in handles where h.pid == pid { suspend(id) }
        case .appShown(let pid):
            for (id, h) in handles.sorted(by: { $0.key < $1.key }) where h.pid == pid { resume(id) }
        case .appTerminated(let pid):
            for (id, h) in handles where h.pid == pid { unmanage(id) }
        }
    }

    /// Windows that are never managed: anything that is not an AXWindow (sheets, popovers, menus),
    /// minimized windows and windows in native fullscreen.
    static func shouldManage(_ d: WindowDescriptor) -> Bool {
        d.role == "AXWindow" && !d.isMinimized && !d.isNativeFullscreen
    }

    func manage(_ handle: any WindowHandle) {
        let id = handle.windowID
        guard handles[id] == nil else { return }
        let d = handle.descriptor()
        guard Self.shouldManage(d) else { return }
        let effects = rules.resolve(for: d).effects
        let frame = handle.frame

        // Existing windows (discovery at start) stay on the display they are on; new ones open on
        // the focused display, like Hyprland.
        let displayID: String?
        if isDiscovering, !frame.isNull {
            displayID = DisplayGeometry.display(for: frame, in: displays)?.id
        } else {
            displayID = state.focusedDisplay ?? displays.first?.id
        }
        guard let displayID, let area = display(id: displayID).map(usableArea(of:)) else { return }
        var target = effects.workspace.flatMap(WorkspaceID.init(parsing:))
        if target == nil { target = state.activeWorkspace(forDisplay: displayID) }

        var floating: CGRect?
        let isFloating = effects.float == true || d.isDialogLike || d.isFixedSize || !d.isStandardWindow
        if isFloating {
            let size = frame.isNull ? CGSize(width: area.width * 0.6, height: area.height * 0.7) : frame.size
            if isDiscovering, !frame.isNull, area.intersects(frame) {
                floating = frame
            } else {
                floating = resolvedFloatingFrame(effects: effects, in: area, windowSize: size)
                    ?? CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
            }
            floating = floating.map { Self.clamp($0, to: area).integralPoints }
        }

        handles[id] = handle
        descriptors[id] = d
        self.effects[id] = effects
        if let m = d.minSize { minSizes[id] = m }
        let focus = !isDiscovering && effects.noInitialFocus != true && effects.noFocus != true && d.isStandardWindow
        guard state.addWindow(id, to: target, floating: floating, cursor: windowSystem.cursorLocation, focus: focus, env: environment) else {
            forget(id)
            return
        }
        if effects.pin == true { state.setPinned(id, true) }
        setNeedsLayout()
    }

    func unmanage(_ id: WindowID) {
        guard handles[id] != nil else { return }
        if state.workspace(of: id) != nil {
            var cursorWindow: WindowID?
            if config.wm.focusOnCloseUnderCursor, let under = windowSystem.windowUnderCursor(), under != id,
               visiblePlacements[under] != nil {
                cursorWindow = under
            }
            state.closeWindow(id, cursorWindow: cursorWindow)
        }
        fadeOutNext.insert(id)
        shownBefore.remove(id)
        forget(id)
        setNeedsLayout()
    }

    private func forget(_ id: WindowID) {
        if parked[id] != nil { try? journal.remove(id) }
        handles[id] = nil
        descriptors[id] = nil
        effects[id] = nil
        applied[id] = nil
        parked[id] = nil
        minSizes[id] = nil
        suspended[id] = nil
        snapBacks[id] = nil
        forceApply.remove(id)
        staleParking.remove(id)
        raised.remove(id)
        focusOrder.removeAll { $0 == id }
        if systemFocus == id { systemFocus = nil }
        if drag?.window == id { drag = nil }
    }

    private func suspend(_ id: WindowID) {
        guard handles[id] != nil, let ws = state.workspace(of: id) else { return }
        suspended[id] = ws
        state.closeWindow(id)
        fadeOutNext.insert(id)
        shownBefore.remove(id)
        applied[id] = nil
        raised.remove(id)
        setNeedsLayout()
    }

    private func resume(_ id: WindowID) {
        if handles[id] == nil {
            // Minimized before the WM started (never managed): manage it now.
            if let handle = windowSystem.allWindows.first(where: { $0.windowID == id }) { manage(handle) }
            return
        }
        guard let ws = suspended.removeValue(forKey: id) else { return }
        let frame = handles[id]!.frame
        let floating = effects[id]?.float == true || descriptors[id].map { $0.isDialogLike || $0.isFixedSize || !$0.isStandardWindow } == true
        // A special that closed while the window was away is reopened only by focusing it.
        state.addWindow(id, to: ws, floating: floating && !frame.isNull ? frame : nil, focus: true, env: environment)
        setNeedsLayout()
    }

    private func systemFocusChanged(_ id: WindowID?) {
        systemFocus = id
        guard let id, isManaged(id), id != state.focusedWindow else { return }
        if parked[id] != nil, now().timeIntervalSince(lastWorkspaceChange) < Self.focusGuardInterval { return }
        if parked[id] != nil, !config.wm.focusOnActivate { return }
        state.recordFocus(id, unfullscreenOthers: config.wm.unfullscreenOnFocus)
        setNeedsLayout()
    }

    private func frameChanged(_ id: WindowID, _ frame: CGRect, isEcho: Bool) {
        guard !isEcho, !frame.isNull, parked[id] == nil, drag == nil, let wsID = state.workspace(of: id),
              let ws = state[wsID] else { return }
        if ws.isFloating(id) {
            // The user moved/resized a floating window: remember it, don't fight it.
            state.setFloatingFrame(id, frame)
            applied[id] = frame
            decorations?.externalMove(id)
            setNeedsLayout()  // the border follows (no setFrame: the target equals the frame)
            return
        }
        decorations?.externalMove(id)
        guard let target = applied[id], !frame.approximatelyEquals(target, tolerance: 2) else { return }
        let tries = snapBacks[id, default: 0]
        guard tries < Self.maxSnapBackRetries else { return }
        snapBacks[id] = tries + 1
        forceApply.insert(id)
        setNeedsLayout()
    }

    // MARK: - Helpers

    static func clamp(_ frame: CGRect, to area: CGRect) -> CGRect {
        let w = min(frame.width, area.width)
        let h = min(frame.height, area.height)
        let x = min(max(frame.minX, area.minX), area.maxX - w)
        let y = min(max(frame.minY, area.minY), area.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
