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
    /// Debug counters (`skyrose query state`), used by the Riko suite.
    public struct Counters: Equatable, Sendable {
        public var layoutPasses = 0
        public var setFrameCalls = 0
        public var parkCalls = 0
        public var focusCalls = 0
        public var raiseCalls = 0
        public var restoredOnLaunch = 0
        public var journalWriteFailures = 0
        public var restoredFromSession = 0
        /// Re-applies after an app moved/resized a tiled window by itself.
        public var snapBacks = 0
        /// Kept at 0. Windows are no longer floated because they could not fit or fought their slot.
        public var autoFloats = 0
        /// Title-bar drags / edge resizes of tiled windows finished by the user.
        public var nativeDrops = 0
        public var nativeResizes = 0
        /// Minimum sizes confirmed by a second read-back.
        public var minSizesLearned = 0
        /// Reconcile passes that put a drifted window back on its tile.
        public var reconciles = 0
        /// Workspaces whose split direction was flipped so minimum sizes could fit.
        public var splitFlips = 0
        /// Workspaces stacked (one visible tile) because minimum sizes could not sit side by side.
        public var monocleLayouts = 0

        public var dictionary: [String: Int] {
            [
                "layoutPasses": layoutPasses, "setFrameCalls": setFrameCalls, "parkCalls": parkCalls,
                "focusCalls": focusCalls, "raiseCalls": raiseCalls, "restoredOnLaunch": restoredOnLaunch,
                "restoredFromSession": restoredFromSession,
                "journalWriteFailures": journalWriteFailures, "snapBacks": snapBacks, "autoFloats": autoFloats,
                "nativeDrops": nativeDrops, "nativeResizes": nativeResizes, "minSizesLearned": minSizesLearned,
                "reconciles": reconciles, "splitFlips": splitFlips, "monocleLayouts": monocleLayouts,
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

    /// A tiled window the user is dragging by its title bar or resizing by an edge (the left
    /// button is down while its frame changes). Nothing is written to it until the button is
    /// released; then it goes back to its slot, swaps with the window it was dropped on, moves to
    /// the display it was dropped on, or (resized) its splits take the new size.
    struct NativeDrag {
        /// The window's slot when the drag started.
        var slot: CGRect
        var latest: CGRect
        /// The workspace's tree when the drag started: a live resize is always re-derived from
        /// it, so the ratios never drift.
        var startTree: DwindleTree?
        var lastLiveUpdate: Date = .distantPast

        var isResize: Bool { abs(latest.width - slot.width) > 2 || abs(latest.height - slot.height) > 2 }
    }

    /// Re-applies allowed per window and target when an app moves a tiled window by itself.
    /// After that the window stays tiled; the reconcile pass puts it back, it is not floated.
    public static let maxSnapBackRetries = 2
    /// How often the reconcile pass re-checks tiles that drifted (event-driven first; this is the fallback).
    public static let reconcileInterval: TimeInterval = 1
    /// After a native drag ends, late AX notifications from the drag are re-applied without
    /// counting as the app fighting its slot.
    public static let nativeDragGrace: TimeInterval = 0.6
    /// A mouse-edge resize updates the layout on every event. The display link writes the
    /// frames; this is not a throttle (a throttle is lag).
    public static let liveResizeInterval: TimeInterval = 0
    /// How often the button state is polled while a native drag is open (the event tap's
    /// mouse-up normally ends it first).
    public static let pointerPollInterval: TimeInterval = 1.0 / 30
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
    /// SIP-off mode (nil or inactive: every SIP-on path as before).
    public var enhanced: EnhancedMode?
    /// A workspace-change layout is held at most this long for the slide's outgoing still.
    public static let maxTransitionHold: TimeInterval = 0.3

    /// Called after quit/panic restored every window (the daemon exits).
    public var onQuit: (() -> Void)?
    /// Saves a per-app rule (the daemon writes config.toml `[appRules]`; nil: memory only).
    public var appRulePersister: ((String, AppLayoutMode) throws -> Void)?
    /// Running regular apps (bundle id, name) for the rules API; the daemon reads NSWorkspace.
    public var runningApps: () -> [(bundleID: String, name: String)] = { [] }
    /// Actions the WM does not own (shell, apps, capture, media); the daemon logs or forwards them.
    public var onUnhandledAction: ((Action) -> Void)?
    /// `config.reload` / `rules.reload` from IPC; return warnings.
    public var onConfigReload: (() -> [String])?
    /// `keys.pause` (the daemon forwards it to the event tap).
    public var onPauseHotkeys: ((TimeInterval) -> Void)?
    /// The user's config.toml (the config API's target; tests point it at a temporary file).
    public var configFileURL: URL = Paths.configFile
    /// Simulated missing permissions (`SKYROSE_SIMULATE_MISSING`, tests and screenshots only).
    public var simulatedMissingPermissions: Set<SkyRosePermission> =
        PermissionSnapshot.parseSimulated(ProcessInfo.processInfo.environment["SKYROSE_SIMULATE_MISSING"])
    public var onRulesReload: (() -> [String])?
    /// After every applied layout pass (the shell refreshes workspaces / the active window).
    public var onLayoutApplied: (() -> Void)?
    /// Shell IPC (`shell.*`, drawers, toasts). Returns nil for commands the shell does not own.
    public var shellResponder: ((IPCRequest, IPCCommand) -> IPCResponse?)?
    /// Panic (chord or `wm panic`), before windows are restored: the shell puts power settings back.
    public var onPanic: (() -> Void)?
    /// Displays whose auto-hidden bar is currently revealed (it overlays windows, reserves nothing).
    public internal(set) var barRevealed: Set<String> = []
    /// Every window id managed in this session (CGWindowIDs are never reused while a window
    /// lives). A window managed again (its app was unhidden or activated, it was unminimized) is
    /// not a new window: its pass never animates.
    var everManaged: Set<WindowID> = []
    /// Windows managed again (or discovered at start) since the last layout pass.
    var reappeared: Set<WindowID> = []
    /// An app was hidden / unhidden or a window minimized / restored since the last pass (app
    /// switching): the next pass moves windows instantly.
    var suspendChangedSinceLayout = false

    var handles: [WindowID: any WindowHandle] = [:]
    var descriptors: [WindowID: WindowDescriptor] = [:]
    var effects: [WindowID: RuleEffects] = [:]
    /// Last target frame sent for each window.
    var applied: [WindowID: CGRect] = [:]
    /// Parked windows and the display they are parked on.
    var parked: [WindowID: String] = [:]
    /// Minimum sizes learned from read-backs (AX does not expose them: no app checked here
    /// publishes an AXMinimumSize attribute). An axis that is 0 is unknown.
    var minSizes: [WindowID: CGSize] = [:]
    /// A read-back bigger than the slot, waiting for a second write to confirm it (an app that
    /// applies sizes asynchronously, e.g. Electron, reads back its old size once).
    var pendingMinSizes: [WindowID: CGSize] = [:]
    /// Confirmed minimum sizes by bundle id: a new window of the same app is laid out with it
    /// from its first pass (no visible clamp-and-retile).
    var appMinSizes: [String: CGSize] = [:]
    /// Windows whose `minSizes` entry is only their app's hint (another window of the app was
    /// seen to need it). A hint gives the split room up front but never floats a window: windows
    /// of one app can differ (live finding: an 800 pt minimum of one window floated every new
    /// window of the app).
    var minSizeHinted: Set<WindowID> = []
    /// Tiled windows being dragged / resized by the user right now.
    var nativeDrags: [WindowID: NativeDrag] = [:]
    /// Keyboard and layout resizes, sampled onto the real window (no snapshot cover).
    var liveResizeSchedule = LiveResizeSchedule()
    var liveResizeLink: LiveResizeLink?
    /// Per-app AX writes. The display link enqueues a frame and returns.
    let frameWriter = AsyncFrameWriter()
    /// Apps whose `AXEnhancedUserInterface` SkyRose turned off so frame changes are not scaled.
    /// Restored in `shutdown`.
    var liveFrameApps: Set<Int32> = []
    /// Echoes of a live write that arrive just after the track ends are not the app fighting its tile.
    var liveGraceUntil: [WindowID: Date] = [:]
    /// Last real frame written for a live resize, so a tick that has not moved skips AX.
    var lastLiveFrame: [WindowID: CGRect] = [:]
    /// Until when late notifications of a finished native drag are re-applied silently.
    var nativeGrace: [WindowID: Date] = [:]
    /// Where a window really is before the next pass (dropped after a native drag): the pass
    /// animates it from there.
    var displaced: [WindowID: CGRect] = [:]
    /// Last left-button press (from the event tap): a frame change only counts as the user's drag
    /// when the press was on that window.
    var lastPointerPress: CGPoint?
    /// `wm.closeQuitsApp`: windows whose red close button was just pressed, and when. A window
    /// destroyed within `closeClickWindow` of that press was closed by the red button (a
    /// "save changes?" sheet may sit in between).
    var closeButtonPresses: [WindowID: Date] = [:]
    static let closeClickWindow: TimeInterval = 60
    /// How long after the last window goes before the app's own window list is checked (the
    /// closed window can still be listed for a moment).
    static let closeQuitCheckDelay: TimeInterval = 0.3
    public var appTerminator: AppTerminator = SystemAppTerminator()
    /// Apps the red button quit (pid → bundle id), for `query state` and tests.
    public private(set) var closeQuitApps: [String] = []
    var pointerPoll: Timer?
    /// Plain-language tiling events for `query state` and `skyrose doctor` (capped).
    public internal(set) var tilingNotes: [String] = []
    /// User float / tile choices, keyed by app + window identity. Nil URL keeps them in memory.
    public var userFloatLedgerURL: URL?
    var userFloats = UserFloatLedger()
    /// Until when a window that keeps leaving its tile is left alone (the reconcile pass retries then).
    var resistedUntil: [WindowID: Date] = [:]
    /// Last fit strategy per workspace, so a note is written once when it changes.
    var workspaceFit: [WorkspaceID: String] = [:]
    var reconcileTimer: Timer?
    /// Order in which windows were managed (the newest overflowing window floats first).
    var manageSerial: [WindowID: Int] = [:]
    var nextManageSerial = 0
    /// Minimized windows / windows of hidden apps, with the workspace to return to.
    var suspended: [WindowID: WorkspaceID] = [:]
    /// Session snapshot (`Paths.sessionSnapshot` in the daemon; nil: not saved or restored).
    public var sessionStore: SessionSnapshotStore?
    var lastSavedSession: WorkspaceState?
    var lastSavedSuspended: [WindowID: WorkspaceID] = [:]
    var sessionSaveScheduled = false
    static let sessionSaveDelay: TimeInterval = 0.5
    /// Windows the snapshot placed that were minimized / hidden at start: where they come back.
    var restoreTargets: [WindowID: WorkspaceID] = [:]
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
    /// When a key drawer (launcher, session menu) last closed without launching anything: macOS
    /// then hands focus back to the previously active app, which is not a request to go to its
    /// workspace (seen: closing the launcher on an empty ws 3 jumped to kitty on ws 4).
    var lastKeyDrawerClose = Date.distantPast
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
    /// Last pointer position inside each window, for `cursorWarpMode = last`.
    var lastPointerInWindow: [WindowID: CGPoint] = [:]
    /// A warp just happened. Focus and hover caused by that synthetic move are ignored until then.
    var ignorePointerFocusUntil = Date.distantPast
    /// Focus follows the pointer. The candidate and when the pointer arrived.
    var hoverFocus = HoverFocus()
    var hoverTimer: Timer?
    /// Hover asked to focus this window without bringing it forward. Cleared once focus is applied.
    var hoverFocusWithoutRaise: WindowID?
    /// Windows we raised back into place after a no-raise focus. Their focus echoes are ignored.
    var orderRestoreEcho: Set<WindowID> = []
    var orderRestoreEchoUntil = Date.distantPast
    /// Secure Event Input is on (a password field). Hover must not steal focus.
    var secureInputActive = false
    /// SkyRose drawers, the launcher, or a bar popout are open.
    var shellBlocksPointerFocus: () -> Bool = { false }
    /// Moves the pointer. Tests replace it; the real one disconnects the hardware mouse first so
    /// the warp is not a hover and the next physical move is not stuck.
    public var warpCursor: (CGPoint) -> Void = { point in
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
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

        if let url = userFloatLedgerURL { userFloats = UserFloatLedger.load(from: url) }
        isManaging = true
        windowSystem.onEvent = { [weak self] in self?.handle($0) }
        isDiscovering = true
        windowSystem.start()
        isDiscovering = false
        counters.restoredFromSession = restoreSession()
        enforceUserFloatLedger()
        systemFocus = windowSystem.focusedWindowID
        // A restored session keeps the workspace each display showed; the app focus only counts
        // when it is on one of those.
        if let f = systemFocus, isManaged(f), counters.restoredFromSession == 0 || state.workspace(of: f).map(state.isVisible) == true {
            state.recordFocus(f)
        }
        startReconcileTimer()
        setNeedsLayout()
    }

    /// Restores every window (journal + off-screen rescue), stops discovery and calls `onQuit`.
    /// Used by the panic chord, `wm.quit`/`wm.panic` and SIGTERM.
    @discardableResult
    public func shutdown() -> Int {
        stopReconcileTimer()
        stopLiveResizePump()
        liveResizeSchedule = LiveResizeSchedule()
        restoreSystemFrameAnimations()
        // SIP-off mode: every alpha / level / transform / shadow goes back first.
        enhanced?.shutdown()
        if isManaging { saveSessionIfChanged(immediately: true) }
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
        onPanic?()
        shutdown()
    }

    public func apply(config: Config) {
        let oldRules = self.config.appRuleBook
        self.config = config
        reapplyAppRules(from: oldRules)
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

    /// Frame − menu bar − Dock − screen frame − bar (spec 4.6), with per-display overrides. Only a
    /// *persistent* bar reserves its width (it replaces the frame band on its edge, so that edge
    /// reserves max(frame, bar), not their sum). An auto-hidden bar and every drawer overlay the
    /// windows: a pointer reveal must never retile (live finding: revealing the bar resized the
    /// tiles, and dwindle flipped the split so windows jumped up and down).
    public func usableArea(of display: DisplayInfo) -> CGRect {
        let c = config.resolved(forDisplay: display.id)
        let frame = c.wm.screenFrame ? c.wm.screenFrameInset : 0
        var reserved = Insets.uniform(frame)
        if c.bar.enabled, c.bar.persistent {
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

    /// The shell revealed / hid an auto-hidden bar on `display`. Recorded only (`query`, tests):
    /// the bar overlays windows, so this never schedules a layout.
    public func setBarRevealed(_ revealed: Bool, display: String) {
        if revealed { barRevealed.insert(display) } else { barRevealed.remove(display) }
    }

    public func display(id: String?) -> DisplayInfo? {
        guard let id else { return nil }
        return displays.first { $0.id == id }
    }

    /// Placements of one workspace with the current config, areas and learned min sizes.
    ///
    /// A tiled frame that would stick out of the usable area is pulled back inside it (live test:
    /// Finder at x = −44). The size is shrunk when it is larger than the area, so it never covers
    /// a neighbour.
    public func placements(of id: WorkspaceID) -> [Placement] {
        guard let ws = state[id] else { return [] }
        return placements(for: ws)
    }

    func placements(for ws: Workspace, forcing direction: SplitDirection? = nil) -> [Placement] {
        guard let d = display(id: ws.displayID) else { return [] }
        let area = usableArea(of: d)
        var wm = config.resolved(forDisplay: d.id).wm
        var workspace = ws
        if let direction {
            // Honour this direction even when the aspect rule would pick the other one.
            workspace.tree = ws.tree.withSplitDirection(direction)
            wm.dwindle.preserveSplit = true
        }
        return WorkspaceLayout.compute(
            workspace, area: area, fullFrame: d.frame, config: wm, minSizes: minSizes, groupBarHeight: groupBarReserved(wm)
        ).map { p in
            guard p.kind == .tiled else { return p }
            var frame = p.frame
            if frame.width > area.width { frame.size.width = area.width }
            if frame.height > area.height { frame.size.height = area.height }
            let x = min(max(frame.minX, area.minX), max(area.minX, area.maxX - frame.width))
            let y = min(max(frame.minY, area.minY), max(area.minY, area.maxY - frame.height))
            frame.origin = CGPoint(x: x, y: y)
            guard frame != p.frame else { return p }
            var shifted = p
            let dx = frame.minX - p.frame.minX
            let dy = frame.minY - p.frame.minY
            shifted.frame = frame
            shifted.borderFrame = p.borderFrame.offsetBy(dx: dx, dy: dy)
            shifted.borderFrame.size.width += frame.width - p.frame.width
            shifted.borderFrame.size.height += frame.height - p.frame.height
            return shifted
        }
    }

    func placements(of id: WorkspaceID, forcing direction: SplitDirection) -> [Placement] {
        guard let ws = state[id] else { return [] }
        return placements(for: ws, forcing: direction)
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
        adoptStrays()
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
                for p in placementsKeepingTiled(of: wsID) where !p.hidden {
                    visible[p.window] = p
                    if wsID.isSpecial || p.kind != .tiled { raiseOrder.append(p.window) }
                }
            }
        }

        let previous = visiblePlacements
        // Workspace switches are the slide's job; mouse resizes track 1:1 (spec 2.3). A pass that
        // shows a window again (app switch / unhide / unminimize) is never animated: focusing or
        // switching apps must not put stills up (live finding: stretched windows for ~1 s).
        let revealed = Set(visible.keys.filter { reappeared.contains($0) && previous[$0] == nil })
        let suspendChanged = suspendChangedSinceLayout
        reappeared.removeAll()
        suspendChangedSinceLayout = false
        let liveResize = nativeDrags.values.contains(where: \.isResize)
        // While an animation is in flight, a pass that shows windows again retargets it (those
        // windows are revealed live, the rest keep moving): cancelling it snapped every moving
        // window to its end (live finding, round 4).
        let busy = windowAnimator?.isAnimating == true
        let showsReappeared = suspendChanged || (!revealed.isEmpty && !busy)
        let workspaceSlide = !lastVisibleWorkspaces.isEmpty
            && !workspaceTransitions(from: lastVisibleWorkspaces, to: visibleWorkspacesByDisplay()).isEmpty
        // Glide (a snapshot cover) only when the user turned it on. The default moves the real windows.
        let glide = config.animations.windows == .snapshot && windowAnimator != nil && drag?.kind != .resize
            && !liveResize && !showsReappeared && !workspaceSlide
        let live = config.animations.windows == .live && !showsReappeared && !workspaceSlide
        if live || glide { liveResizeSchedule.spec = currentLiveRetileSpec() }
        if suspendChanged { windowAnimator?.cancel() }
        var writes: [() -> Bool] = []
        var changes: [WindowFrameChange] = []
        let instantSwitch = !glide && enhanced?.instantWorkspaces == true
        var unparking: [WindowID] = []
        var borders: [WindowID: CGRect] = [:]
        for id in handles.keys.sorted() {
            guard let handle = handles[id], let wsID = state.workspace(of: id) else { continue }
            if let p = visible[id] {
                if p.kind != .fullscreen, p.borderFrame != p.frame, decorated(id) { borders[id] = p.borderFrame }
                let wasParked = parked[id] != nil
                if applied[id] != p.frame { snapBacks[id] = 0 }
                // A title-bar move waits for the drop. A resize is written every event, including
                // the window under the cursor, so macOS never leaves a stretched proxy on screen.
                if let drag = nativeDrags[id], !drag.isResize { continue }
                guard wasParked || forceApply.contains(id) || applied[id] != p.frame else { continue }
                forceApply.remove(id)
                let old = displaced.removeValue(forKey: id) ?? previous[id]?.frame ?? (wasParked ? nil : applied[id])
                applied[id] = p.frame
                if wasParked {
                    parked[id] = nil
                    try? journal.remove(id)
                    unparking.append(id)
                }
                // A frame written again unchanged (snap-back after an app moved it, a forced
                // re-apply on focus) is not a change to animate.
                if revealed.contains(id) {
                    changes.append(WindowFrameChange(id: id, kind: .reveal, from: old, to: p.frame))
                } else if previous[id] == nil || old != p.frame {
                    changes.append(WindowFrameChange(id: id, kind: previous[id] == nil ? .open : .move, from: old, to: p.frame))
                }
                writes.append { [weak self] in
                    guard let self else { return false }
                    // The live driver owns this window. The display link writes it; this pass must
                    // not block on AX.
                    if self.liveResizeSchedule.contains(id) { return false }
                    let got = self.setFrame(handle, p.frame)
                    // The app chose its own frame (a minimum, a refused resize): the animation
                    // ends where the window really is, not on the slot (else the cover would
                    // fade onto a different frame). An unchanged read-back may be an app that
                    // applies the size later, so it does not count.
                    if !got.isNull, !got.approximatelyEquals(p.frame, tolerance: 2), old.map({ !got.approximatelyEquals($0, tolerance: 2) }) ?? false {
                        self.windowAnimator?.frameApplied(id, actual: got)
                    }
                    guard p.kind == .tiled else { return false }
                    if handle is AXWindow {
                        // The immediate read is often the frame we just left. Confirm once the
                        // app has had a turn, or a live resize stacks the workspace on a stale size.
                        if got.width > p.frame.width + 1 || got.height > p.frame.height + 1 {
                            self.confirmMinSizeLater(id, target: p.frame, first: got)
                        }
                        return false
                    }
                    return self.learnMinSize(id, target: p.frame, readBack: got)
                }
            } else if let ws = state[wsID] {
                if glide, let was = previous[id] {
                    changes.append(WindowFrameChange(id: id, kind: .leave, from: was.frame, to: nil))
                    let display = ws.displayID
                    writes.append { [weak self] in
                        self?.park(id, handle, on: display)
                        return false
                    }
                } else {
                    // SIP-off instant switch: invisible while it is moved off screen.
                    if instantSwitch, previous[id] != nil, parked[id] == nil { enhanced?.hideForSwitch([id]) }
                    park(id, handle, on: ws.displayID)
                }
            }
        }
        if instantSwitch, !unparking.isEmpty { enhanced?.hideForSwitch(unparking) }
        // Closed or minimized since the last pass: their stills shrink and fade.
        for (id, p) in previous where visible[id] == nil && (handles[id] == nil || state.workspace(of: id) == nil) {
            changes.append(WindowFrameChange(id: id, kind: .close, from: p.frame, to: nil))
        }
        displaced.removeAll()
        if live {
            // Every move and resize is the real window. Nothing is handed to a snapshot cover.
            let clock = now().timeIntervalSinceReferenceDate
            let direct = liveResize || drag?.kind == .resize
            for change in changes where change.kind == .move || change.kind == .open {
                guard let to = change.to else { continue }
                let layoutFrom = change.from ?? to
                let visual = lastLiveFrame[change.id] ?? layoutFrom
                guard !visual.approximatelyEquals(to, tolerance: 0.5) else {
                    liveResizeSchedule.remove(change.id)
                    lastLiveFrame[change.id] = nil
                    continue
                }
                if lastLiveFrame[change.id] == nil { lastLiveFrame[change.id] = layoutFrom }
                liveResizeSchedule.retarget(change.id, from: visual, to: to, at: clock, direct: direct)
            }
            changes = []
            // Manual scheduling writes the final frame in this pass. Borders must match that
            // write, not the pose at t = 0.
            let sampleAt = scheduling == .manual ? clock + liveResizeSchedule.spec.duration + 0.05 : clock
            let samples = liveResizeSchedule.samples(at: sampleAt)
            for sample in samples {
                guard let p = visible[sample.id] else { continue }
                borders[sample.id] = Self.border(around: sample.frame, matching: p)
            }
        } else if glide {
            // Opt-in glide: a size change is still the real window. Scaling a still is the blur.
            changes = changes.filter { change in
                guard change.kind == .move, let from = change.from, let to = change.to else { return true }
                guard abs(from.width - to.width) > 1 || abs(from.height - to.height) > 1 else { return true }
                let clock = now().timeIntervalSinceReferenceDate
                let visual = liveResizeSchedule.samples(at: clock).first { $0.id == change.id }?.frame ?? from
                liveResizeSchedule.retarget(change.id, from: visual, to: to, at: clock)
                return false
            }
        }
        visiblePlacements = visible
        let commit = { [weak self] in
            guard let self else { return }
            var learned = false
            for w in writes where w() { learned = true }
            if learned { self.setNeedsLayout() }
            guard !self.liveResizeSchedule.isEmpty else { return }
            if self.scheduling == .manual {
                // No display link in tests: land on the final frame in this pass.
                let end = self.now().addingTimeInterval(self.liveResizeSchedule.spec.duration + 0.05)
                self.stepLiveResize(at: end)
            } else {
                self.stepLiveResize()
                self.startLiveResizePump()
            }
        }
        let scene = animationScene(visible, raiseOrder: raiseOrder)
        if glide, let animator = windowAnimator, !changes.isEmpty {
            animator.animate(WindowAnimationRequest(changes: changes, windows: scene, displays: displayFrames), commit: commit)
        } else {
            commit()
        }
        if instantSwitch { enhanced?.restoreAfterSwitch() }
        if let enhanced, enhanced.active {
            enhanced.layoutApplied(visible.map { id, p in
                EnhancedMode.WindowInfo(id: id, fullscreen: p.kind == .fullscreen, pinned: state.isPinned(id))
            })
        }
        borderFrames = borders
        publishDecorations(borders: borders)
        windowAnimator?.windowsChanged(visible: scene)

        let visibleRaised = Set(raiseOrder)
        for id in raiseOrder where !raised.contains(id) {
            handles[id]?.raise()
            counters.raiseCalls += 1
        }
        raised = visibleRaised
        syncFocus()
        saveSessionIfChanged()
        onLayoutApplied?()
    }

    /// The border rect for a window that is visually at `window` while its slot is `p.frame`.
    static func border(around window: CGRect, matching p: Placement) -> CGRect {
        CGRect(
            x: window.minX + (p.borderFrame.minX - p.frame.minX),
            y: window.minY + (p.borderFrame.minY - p.frame.minY),
            width: window.width + (p.borderFrame.width - p.frame.width),
            height: window.height + (p.borderFrame.height - p.frame.height)
        )
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

    func setFrame(_ handle: any WindowHandle, _ frame: CGRect) -> CGRect {
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
        let keepOrder = hoverFocusWithoutRaise == f
        hoverFocusWithoutRaise = nil
        if keepOrder { focusWithoutRaising(f, handle: handle) } else { handle.focus(raise: true) }
        counters.focusCalls += 1
        warpCursorToFocus()
    }

    /// macOS raises a window when it becomes focused. Put the windows that were already in front
    /// back, front-most last, so hover focus does not change the stack.
    func focusWithoutRaising(_ id: WindowID, handle: any WindowHandle) {
        let order = CGWindowSnapshot.current(onScreenOnly: true)
            .filter { $0.alpha >= 0.05 && handles[$0.id] != nil }
            .map(\.id)
        handle.focus(raise: false)
        guard let index = order.firstIndex(of: id), index > 0 else { return }
        let above = Array(order[..<index])
        orderRestoreEcho = Set(above)
        orderRestoreEchoUntil = now().addingTimeInterval(0.2)
        for other in above.reversed() {
            handles[other]?.raise()
        }
    }

    /// Keyboard, workspace, close and launcher focus move the pointer. A click, a drag, a held
    /// button, or a window on a display the user cannot see does not.
    func warpCursorToFocus() {
        guard config.wm.cursorFollowsFocus, drag == nil, nativeDrags.isEmpty else { return }
        guard !windowSystem.isLeftMouseDown, now() >= ignorePointerFocusUntil else { return }
        guard let id = state.focusedWindow else { return }
        let frame = visiblePlacements[id]?.frame ?? handles[id]?.frame ?? .null
        let cursor = windowSystem.cursorLocation
        if let cursor { rememberPointer(cursor) }
        guard let point = CursorWarp.destination(
            frame: frame, mode: config.wm.cursorWarpMode, lastInside: lastPointerInWindow[id],
            cursor: cursor, mouseDown: false, dragging: false,
            enabled: true, onVisibleDisplay: displays.contains { $0.frame.intersects(frame) }
        ) else { return }
        ignorePointerFocusUntil = now().addingTimeInterval(0.08)
        lastPointerInWindow[id] = point
        warpCursor(point)
        Log.wm.notice("cursor warp #\(id, privacy: .public) \(Int(point.x), privacy: .public),\(Int(point.y), privacy: .public)")
    }

    /// The pointer moved. Focus follows it after `focusFollowsMouseDelayMs`, unless something else
    /// owns the pointer. Does not raise a floating window unless `raiseOnHover` is on.
    public func pointerMoved(at point: CGPoint) {
        guard isManaging, config.wm.focusFollowsMouse else { return }
        rememberPointer(point)
        let delay = TimeInterval(config.wm.focusFollowsMouseDelayMs) / 1000
        let over = window(at: point)
        let blocked = hoverBlock(at: point, over: over)
        let now = self.now().timeIntervalSinceReferenceDate
        guard let id = hoverFocus.update(over: over, at: now, delay: delay, blocked: blocked) else {
            armHoverTimer(delay: delay)
            return
        }
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard id != state.focusedWindow else { return }
        let raise = config.wm.raiseOnHover && isFloating(id)
        hoverFocusWithoutRaise = raise ? nil : id
        state.recordFocus(id, raise: raise)
        setNeedsLayout()
        Log.wm.notice("hover focus #\(id, privacy: .public) raise \(raise, privacy: .public)")
    }

    /// Fully transparent windows (Hex's invisible system dialogs sit on top of the whole
    /// screen at alpha 0) are not what the pointer is over. A visible sheet still is, and
    /// `hoverBlock` refuses to focus it.
    private var invisibleHoverCache: (at: TimeInterval, ids: Set<WindowID>)?

    func window(at point: CGPoint) -> WindowID? {
        Self.hoverTarget(at: point, placements: visiblePlacements, skipping: invisibleHoverIDs())
    }

    func invisibleHoverIDs() -> Set<WindowID> {
        let t = now().timeIntervalSinceReferenceDate
        if let cache = invisibleHoverCache, t - cache.at < 0.25 { return cache.ids }
        let ids = Set(CGWindowSnapshot.current(onScreenOnly: true).filter { $0.alpha < 0.05 }.map(\.id))
        invisibleHoverCache = (t, ids)
        return ids
    }

    static func hoverTarget(
        at point: CGPoint, placements: [WindowID: Placement], skipping: Set<WindowID>
    ) -> WindowID? {
        placements.filter { !$0.value.hidden && $0.value.frame.contains(point) && !skipping.contains($0.key) }
            .max { a, b in
                let rank: (Placement.Kind) -> Int = { $0 == .tiled ? 0 : 1 }
                let ar = rank(a.value.kind), br = rank(b.value.kind)
                if ar != br { return ar < br }
                return a.key < b.key
            }?.key
    }

    func hoverBlock(at point: CGPoint, over: WindowID?) -> HoverFocus.Block? {
        if drag != nil || !nativeDrags.isEmpty { return .drag }
        if windowSystem.isLeftMouseDown { return .button }
        if now() < ignorePointerFocusUntil { return .warp }
        if secureInputActive { return .password }
        if shellBlocksPointerFocus() { return .drawer }
        if let display = displays.first(where: { $0.frame.contains(point) }),
           point.y <= display.frame.minY + display.menuBarHeight + 1 { return .menuBar }
        if let over, let desc = descriptors[over] {
            if desc.subrole.contains("Menu") || desc.role == "AXMenu" { return .menu }
            if desc.isDialogLike { return .sheet }
            if desc.bundleID == "com.skyrose.mac" || desc.bundleID == "com.apple.Spotlight" { return .launcher }
        }
        if let focused = state.focusedWindow, focused != over {
            if let desc = descriptors[focused], desc.isDialogLike || desc.bundleID == "com.apple.Spotlight"
                || desc.bundleID == "com.skyrose.mac" || desc.subrole.contains("Menu") {
                return .sheet
            }
            if let ws = state.workspace(of: focused),
               state[ws]?.fullscreen == focused || descriptors[focused]?.isNativeFullscreen == true,
               state.workspace(of: over ?? 0) != ws {
                return .otherSpaceFullscreen
            }
        }
        return nil
    }

    func armHoverTimer(delay: TimeInterval) {
        guard scheduling == .mainQueue, let since = hoverFocus.since else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            return
        }
        let remain = delay - (now().timeIntervalSinceReferenceDate - since)
        guard remain > 0 else { return }
        hoverTimer?.invalidate()
        let wait = max(0.01, remain)
        let t = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let point = self.windowSystem.cursorLocation else { return }
                self.pointerMoved(at: point)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    /// Remembers where the pointer is, for the next `last` warp. A point from our own warp does not count.
    func rememberPointer(_ point: CGPoint) {
        guard now() >= ignorePointerFocusUntil else { return }
        guard let id = visiblePlacements.first(where: { $0.value.frame.contains(point) })?.key else { return }
        lastPointerInWindow[id] = point
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
            let quit = closeQuitCandidate(id)
            unmanage(id)
            if let quit { quitIfLastWindow(pid: quit.pid, bundleID: quit.bundleID) }
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
        // A window the session snapshot placed (minimized or hidden at start) goes back there.
        var target = restoreTargets.removeValue(forKey: id) ?? effects.workspace.flatMap(WorkspaceID.init(parsing:))
        if target == nil { target = state.activeWorkspace(forDisplay: displayID) }

        var floating: CGRect?
        let isFloating = wantsFloat(d, ruleFloat: effects.float)
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
        if everManaged.contains(id) || isDiscovering { reappeared.insert(id) }
        everManaged.insert(id)
        if let m = d.minSize {
            minSizes[id] = m
        } else if let hint = appMinSizes[d.bundleID] {
            minSizes[id] = hint
            minSizeHinted.insert(id)
        }
        if manageSerial[id] == nil {
            manageSerial[id] = nextManageSerial
            nextManageSerial += 1
        }
        let focus = !isDiscovering && effects.noInitialFocus != true && effects.noFocus != true && d.isStandardWindow
        guard state.addWindow(id, to: target, floating: floating, cursor: windowSystem.cursorLocation,
                              size: frame.isNull ? nil : frame.size, focus: focus, env: environment) else {
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
        minSizeHinted.remove(id)
        pendingMinSizes[id] = nil
        nativeDrags[id] = nil
        nativeGrace[id] = nil
        displaced[id] = nil
        manageSerial[id] = nil
        resistedUntil[id] = nil
        liveResizeSchedule.remove(id)
        lastLiveFrame[id] = nil
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
        suspendChangedSinceLayout = true
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
        suspendChangedSinceLayout = true
        let frame = handles[id]!.frame
        let floating = descriptors[id].map { wantsFloat($0, ruleFloat: effects[id]?.float) } ?? false
        // A special that closed while the window was away is reopened only by focusing it.
        state.addWindow(id, to: ws, floating: floating && !frame.isNull ? frame : nil, focus: true, env: environment)
        setNeedsLayout()
    }

    /// The shell closed a key drawer; `launched` is true when it opened an app (follow that one).
    public func keyDrawerClosed(launched: Bool) {
        lastKeyDrawerClose = launched ? .distantPast : now()
    }

    private func systemFocusChanged(_ id: WindowID?) {
        // A warp can deliver a move. It must not focus whatever that move landed on.
        if let id, now() < ignorePointerFocusUntil, id != state.focusedWindow { return }
        if let id, now() < orderRestoreEchoUntil, orderRestoreEcho.contains(id) { return }
        // Our own focus() echoes back. The pointer move, if any, already happened in syncFocus.
        if let id, id == state.focusedWindow {
            systemFocus = id
            return
        }
        if let id { adoptIfManageable(id) }
        guard let id, isManaged(id), id != state.focusedWindow else { return }
        if parked[id] != nil, now().timeIntervalSince(lastWorkspaceChange) < Self.focusGuardInterval { return }
        if parked[id] != nil, now().timeIntervalSince(lastKeyDrawerClose) < Self.focusGuardInterval { return }
        if parked[id] != nil, !config.wm.focusOnActivate { return }
        state.recordFocus(id, unfullscreenOthers: config.wm.unfullscreenOnFocus)
        setNeedsLayout()
    }

    private func frameChanged(_ id: WindowID, _ frame: CGRect, isEcho: Bool) {
        if handles[id] == nil { adoptIfManageable(id) }
        guard !isEcho, !frame.isNull, parked[id] == nil, drag == nil, let wsID = state.workspace(of: id),
              let ws = state[wsID] else { return }
        // A frame we are writing ourselves is not the app moving, and it must not fade the border
        // or be learned as a minimum (the spring is still larger than the slot on purpose).
        if liveResizeSchedule.contains(id) { return }
        if ws.isFloating(id) {
            // The user moved/resized a floating window: remember it, don't fight it.
            state.setFloatingFrame(id, frame)
            applied[id] = frame
            decorations?.externalMove(id)
            setNeedsLayout()  // the border follows (no setFrame: the target equals the frame)
            return
        }
        decorations?.externalMove(id)
        guard let target = applied[id] else { return }
        // The user holds the button on this window: a title-bar drag or an edge resize. Nothing is
        // written until the release (`pointerReleased`); a resize moves the neighbours live.
        if windowSystem.isLeftMouseDown, pressWasOn(id, slot: target) || nativeDrags[id] != nil {
            trackNativeDrag(id, frame: frame, slot: nativeDrags[id]?.slot ?? target)
            return
        }
        // Released before this notification arrived (a quick drag): finish it now.
        if nativeDrags[id] != nil {
            finishNativeDrag(id, at: windowSystem.cursorLocation)
            return
        }
        guard !frame.approximatelyEquals(target, tolerance: 2) else { return }
        if let until = liveGraceUntil[id], now() < until, frame.approximatelyEquals(applied[id] ?? frame, tolerance: 2) {
            return
        }
        // Late notifications from a drag that just ended: put it back, it is not the app.
        if let until = nativeGrace[id], now() < until {
            forceApply.insert(id)
            setNeedsLayout()
            return
        }
        // The app moved or resized its own tiled window: back to the slot a few times. After that
        // it stays tiled; the reconcile pass puts it back. It is never floated for fighting.
        let tries = snapBacks[id, default: 0]
        guard tries < Self.maxSnapBackRetries else {
            if resistedUntil[id] == nil || now() >= resistedUntil[id]! {
                resistedUntil[id] = now().addingTimeInterval(Self.reconcileInterval)
                noteTiling("#\(id) keeps leaving its tile; it stays tiled and is put back on the next reconcile")
            }
            return
        }
        snapBacks[id] = tries + 1
        counters.snapBacks += 1
        forceApply.insert(id)
        setNeedsLayout()
    }

    /// The press that started the current button-down was on `id` (its slot, plus a margin for
    /// the resize handles just outside the frame). Unknown press: assume it was.
    private func pressWasOn(_ id: WindowID, slot: CGRect) -> Bool {
        guard let p = lastPointerPress else { return true }
        return slot.insetBy(dx: -12, dy: -12).contains(p)
    }

    // MARK: - Min sizes

    /// Called with the frame read back after writing `target` to a tiled window. A read-back
    /// bigger than the target is the app's minimum size, but only once a second write reads the
    /// same back (the first may be an app that applies sizes later). Returns true when the layout
    /// must run again (to retry, or because a min size was confirmed).
    func learnMinSize(_ id: WindowID, target: CGRect, readBack got: CGRect) -> Bool {
        guard !got.isNull else { return false }
        let grewW = got.width > target.width + 1
        let grewH = got.height > target.height + 1
        guard grewW || grewH else {
            pendingMinSizes[id] = nil
            return false
        }
        let candidate = CGSize(width: grewW ? got.width.rounded() : 0, height: grewH ? got.height.rounded() : 0)
        guard let pending = pendingMinSizes[id], abs(pending.width - candidate.width) <= 2, abs(pending.height - candidate.height) <= 2 else {
            pendingMinSizes[id] = candidate
            forceApply.insert(id)
            return true
        }
        pendingMinSizes[id] = nil
        let known = minSizeHinted.remove(id) != nil ? .zero : (minSizes[id] ?? .zero)
        let merged = CGSize(width: max(known.width, candidate.width), height: max(known.height, candidate.height))
        guard merged != known else { return false }
        minSizes[id] = merged
        counters.minSizesLearned += 1
        if let bundle = handles[id]?.bundleID, !bundle.isEmpty {
            let app = appMinSizes[bundle] ?? .zero
            appMinSizes[bundle] = CGSize(width: max(app.width, merged.width), height: max(app.height, merged.height))
        }
        Log.wm.notice("learned min size \(Int(merged.width))x\(Int(merged.height)) for #\(id)")
        return true
    }

    /// Placements that keep every non-rule window tiled. Hints that cannot fit are dropped.
    /// Confirmed minimums that still do not fit flip the split direction when that helps, and
    /// otherwise stack the workspace (one visible tile). Frames never overlap.
    func placementsKeepingTiled(of wsID: WorkspaceID) -> [Placement] {
        var list = placements(of: wsID)
        for _ in 0..<8 {
            let hinted = list.filter { $0.kind == .tiled && $0.overflows && !$0.hidden && minSizeHinted.contains($0.window) }
            if hinted.isEmpty { break }
            for p in hinted {
                minSizeHinted.remove(p.window)
                minSizes[p.window] = nil
            }
            list = placements(of: wsID)
        }
        let before = Self.overflowCount(list)
        if before == 0 {
            rememberFit(wsID, "dwindle", nil)
            return list
        }
        // The other split direction, forced (the aspect rule would otherwise keep the one that
        // does not fit). The stored tree is left alone; the choice is recomputed every pass.
        var bestDirection: SplitDirection?
        var bestList = list
        var bestCount = before
        for direction in SplitDirection.allCases {
            let candidate = placements(of: wsID, forcing: direction)
            let count = Self.overflowCount(candidate)
            if count < bestCount {
                bestDirection = direction
                bestList = candidate
                bestCount = count
            }
        }
        if bestDirection != nil {
            rememberFit(wsID, "flipped", "split direction changed so minimum sizes fit")
            if bestCount == 0 { return bestList }
            list = bestList
        }
        let visibleTiled = list.filter { $0.kind == .tiled && !$0.hidden }
        if visibleTiled.count >= 2, Self.overflowCount(list) > 0, let shown = focusedTiled(in: wsID, among: visibleTiled.map(\.window)) {
            guard let ws = state[wsID], let d = display(id: ws.displayID) else { return list }
            let area = usableArea(of: d)
            let wm = config.resolved(forDisplay: d.id).wm
            let grouped = ws.tree.leaf(of: shown)?.isGroup == true
            guard let tile = WorkspaceLayout.fullTile(
                in: area, config: wm, singleWindowGaps: !wsID.isSpecial,
                groupBarHeight: grouped ? groupBarReserved(wm) : 0
            ) else { return list }
            rememberFit(wsID, "monocle", "minimum sizes do not fit side by side; stacked so nothing overlaps")
            return WorkspaceLayout.monocle(list, showing: shown, tile: tile, minSizes: minSizes)
        }
        rememberFit(wsID, "squeezed", "a window is larger than its screen; it stays tiled to the full area")
        return list
    }

    static func overflowCount(_ list: [Placement]) -> Int {
        list.filter { $0.kind == .tiled && !$0.hidden && $0.overflows }.count
    }

    func focusedTiled(in wsID: WorkspaceID, among ids: [WindowID]) -> WindowID? {
        if let focused = state.focusedWindow, ids.contains(focused) { return focused }
        if let history = state[wsID]?.focusHistory.first(where: { ids.contains($0) }) { return history }
        return ids.first
    }

    func rememberFit(_ wsID: WorkspaceID, _ strategy: String, _ message: String?) {
        guard workspaceFit[wsID] != strategy else { return }
        workspaceFit[wsID] = strategy
        guard let message else { return }
        switch strategy {
        case "flipped": counters.splitFlips += 1
        case "monocle": counters.monocleLayouts += 1
        default: break
        }
        noteTiling(message)
    }

    func noteTiling(_ message: String) {
        guard tilingNotes.last != message else { return }
        tilingNotes.append(message)
        if tilingNotes.count > 24 { tilingNotes.removeFirst(tilingNotes.count - 24) }
        Log.wm.notice("tiling: \(message, privacy: .public)")
    }

    /// The user's explicit choice, if they have floated or tiled this window before.
    func userFloatChoice(_ d: WindowDescriptor) -> Bool? {
        switch userFloats.choice(bundleID: d.bundleID, subrole: d.subrole, title: d.title) {
        case .floating: return true
        case .tiled: return false
        case nil: return nil
        }
    }

    /// User choice wins. Otherwise the float rule, including dialogs, sheets and panels.
    func wantsFloat(_ d: WindowDescriptor, ruleFloat: Bool?) -> Bool {
        if let choice = userFloatChoice(d) { return choice }
        return config.appRuleBook.floats(d, ruleFloat: ruleFloat)
    }

    func rememberUserFloat(_ id: WindowID) {
        guard let d = descriptors[id] else { return }
        userFloats.set(isFloating(id) ? .floating : .tiled, bundleID: d.bundleID, subrole: d.subrole, title: d.title)
        guard let url = userFloatLedgerURL else { return }
        do {
            try userFloats.save(to: url)
        } catch {
            Log.wm.error("user float ledger not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies explicit user choices on top of a restored session (the ledger is the intent; the
    /// snapshot can be one save behind).
    func enforceUserFloatLedger() {
        for id in managedWindowIDs {
            guard let d = descriptors[id], let want = userFloatChoice(d), want != isFloating(id) else { continue }
            if want {
                let area = area(of: id) ?? .zero
                let current = handles[id]?.frame ?? .null
                let size = current.isNull ? CGSize(width: max(area.width * 0.6, 1), height: max(area.height * 0.7, 1)) : current.size
                let frame = current.isNull ? centered(size, in: area) : Self.clamp(current, to: area).integralPoints
                _ = state.setFloating(id, true, frame: frame, env: environment)
            } else {
                _ = state.setFloating(id, false, env: environment)
            }
            forceApply.insert(id)
        }
    }

    /// Manages a window that was skipped earlier (native fullscreen, not yet in the AX tree) now
    /// that it can be tiled.
    func adoptIfManageable(_ id: WindowID) {
        guard handles[id] == nil, let handle = windowSystem.allWindows.first(where: { $0.windowID == id }) else { return }
        manage(handle)
    }

    /// Picks up every tracked window that should be tiled and is not.
    func adoptStrays() {
        for handle in windowSystem.allWindows where handles[handle.windowID] == nil {
            manage(handle)
        }
    }

    /// Wake, space change, or a display coming back: adopt anything missed and re-apply tiles
    /// that drifted. Idempotent when everything is already in place.
    public func noteSessionEvent(_ reason: String) {
        guard isManaging else { return }
        let before = managedWindowIDs.count
        adoptStrays()
        var drifted: [WindowID] = []
        for id in managedWindowIDs where !isFloating(id) && nativeDrags[id] == nil && parked[id] == nil {
            guard let target = applied[id], let frame = handles[id]?.frame, !frame.isNull,
                  !frame.approximatelyEquals(target, tolerance: 2) else { continue }
            drifted.append(id)
        }
        guard managedWindowIDs.count != before || !drifted.isEmpty else { return }
        for id in drifted {
            forceApply.insert(id)
            snapBacks[id] = 0
            resistedUntil[id] = nil
        }
        counters.reconciles += 1
        noteTiling("re-tiled after \(reason)")
        setNeedsLayout()
    }

    /// Event-driven callers and the timer fallback. Puts drifted tiled windows back on their
    /// slots and adopts windows that appeared without an event. A second call with nothing
    /// drifted writes nothing.
    public func reconcileTiling() {
        guard isManaging else { return }
        let before = managedWindowIDs.count
        adoptStrays()
        let moment = now()
        var drifted: [WindowID] = []
        for id in managedWindowIDs where !isFloating(id) && nativeDrags[id] == nil && parked[id] == nil {
            if let until = resistedUntil[id], moment < until { continue }
            guard let target = applied[id] ?? visiblePlacements[id]?.frame else { continue }
            guard let frame = handles[id]?.frame, !frame.isNull else {
                drifted.append(id)
                continue
            }
            guard !frame.approximatelyEquals(target, tolerance: 2) else { continue }
            drifted.append(id)
        }
        adoptFloatingFrames()
        reparkDriftedWindows(at: moment)
        let tiled = visiblePlacements.values.filter { $0.kind == .tiled }
        let tiledList = Array(tiled)
        var overlap = false
        if tiledList.count > 1 {
            for i in tiledList.indices {
                for j in tiledList.indices where j > i && WorkspaceLayout.overlaps(tiledList[i].frame, tiledList[j].frame) {
                    overlap = true
                }
            }
        }
        if overlap {
            noteTiling("tiled windows overlapped; laying them out again")
            setNeedsLayout()
        }
        if managedWindowIDs.count != before {
            noteTiling("picked up a window that was not tiled yet")
            setNeedsLayout()
        }
        guard !drifted.isEmpty else { return }
        for id in drifted {
            forceApply.insert(id)
            snapBacks[id] = 0
            resistedUntil[id] = moment.addingTimeInterval(Self.reconcileInterval)
        }
        counters.reconciles += 1
        noteTiling("put \(drifted.count) window(s) back on their tiles")
        setNeedsLayout()
    }

    /// Frame events are ignored while a window is parked, so one that came back on screen by
    /// itself (an app restoring its own frame) stayed over the visible workspace for good.
    private func reparkDriftedWindows(at moment: Date) {
        guard moment.timeIntervalSince(lastWorkspaceChange) >= Self.focusGuardInterval else { return }
        for id in parked.keys where !staleParking.contains(id) {
            guard let frame = handles[id]?.frame, !frame.isNull else { continue }
            // A parked window keeps a sliver on the display, so only real overlap counts.
            let onScreen = displays.contains { d in
                let overlap = d.frame.intersection(frame)
                return !overlap.isNull && overlap.width > 8 && overlap.height > 8
            }
            guard onScreen else { continue }
            staleParking.insert(id)
            noteTiling("put a hidden window back off screen")
            setNeedsLayout()
        }
    }

    /// A window that resizes itself right after it appears (before the WM is observing it) sends
    /// no event, so its float frame, and the border drawn from it, keeps the size it was first seen at.
    private func adoptFloatingFrames() {
        guard drag == nil else { return }
        for id in managedWindowIDs where isFloating(id) && parked[id] == nil && nativeDrags[id] == nil
            && !liveResizeSchedule.contains(id) && windowAnimator?.isCovering(id) != true {
            guard let frame = handles[id]?.frame, !frame.isNull, let known = floatingFrame(id),
                  !frame.approximatelyEquals(known, tolerance: 2) else { continue }
            state.setFloatingFrame(id, frame)
            applied[id] = frame
            setNeedsLayout()
        }
    }

    func startReconcileTimer() {
        guard scheduling == .mainQueue, reconcileTimer == nil else { return }
        let timer = Timer(timeInterval: Self.reconcileInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileTiling() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reconcileTimer = timer
    }

    func stopReconcileTimer() {
        reconcileTimer?.invalidate()
        reconcileTimer = nil
    }

    // MARK: - Native drags (title bar / window edge)

    /// The left button went down at `location` (event tap, main thread).
    public func pointerPressed(at location: CGPoint?) {
        lastPointerPress = location
        if let location { rememberPointer(location) }
        if config.wm.closeQuitsApp, let location { noteCloseButtonPress(at: location) }
    }

    // MARK: Red close button quits the app (wm.closeQuitsApp)

    /// Records a press on a window's red close button. Only the top strip of the window under
    /// the pointer costs an AX read (the button's frame); everything else returns at once.
    func noteCloseButtonPress(at p: CGPoint) {
        let cutoff = now().addingTimeInterval(-Self.closeClickWindow)
        closeButtonPresses = closeButtonPresses.filter { $0.value > cutoff && handles[$0.key] != nil }
        let under = windowSystem.windowUnderCursor().flatMap { handles[$0] != nil ? $0 : nil }
            ?? handles.first { $0.value.frame.contains(p) }?.key
        guard let id = under, let handle = handles[id] else { return }
        let f = handle.frame
        guard !f.isNull, f.contains(p), p.y - f.minY <= 60 else { return }
        guard let button = handle.closeButtonFrame(), button.insetBy(dx: -2, dy: -2).contains(p) else { return }
        closeButtonPresses[id] = now()
    }

    /// The app of a window closed by its red button, when `closeQuitsApp` may quit it.
    func closeQuitCandidate(_ id: WindowID) -> (pid: pid_t, bundleID: String)? {
        guard config.wm.closeQuitsApp, let pressed = closeButtonPresses.removeValue(forKey: id),
              now().timeIntervalSince(pressed) <= Self.closeClickWindow, let h = handles[id] else { return nil }
        let bundle = descriptors[id]?.bundleID ?? h.bundleID
        guard !Self.neverQuits(bundle, exceptions: config.wm.closeQuitsAppExceptions) else { return nil }
        return (h.pid, bundle)
    }

    /// SkyRose's own apps and the user's exceptions are never quit.
    static func neverQuits(_ bundleID: String, exceptions: [String]) -> Bool {
        bundleID.isEmpty || ownApps.contains(bundleID) || exceptions.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// The WM and Settings. TestWindows is deliberately not here: it stands in for any app.
    static let ownApps: Set<String> = ["com.skyrose.mac", "com.skyrose.mac.settings"]

    /// Quits the app (normally) once it has no window left: none tracked (minimized and parked
    /// ones count) and none in its own AX list. Background / menu-bar apps are never quit.
    func quitIfLastWindow(pid: pid_t, bundleID: String) {
        let check: @MainActor () -> Void = { [weak self] in
            guard let self, self.config.wm.closeQuitsApp else { return }
            guard !self.handles.values.contains(where: { $0.pid == pid }) else { return }
            if let listed = self.windowSystem.appWindowCount(pid: pid), listed > 0 { return }
            guard self.appTerminator.isRegularApp(pid: pid) else { return }
            Log.wm.notice("red close button on the last window: quitting \(bundleID, privacy: .public)")
            if self.appTerminator.terminate(pid: pid) { self.closeQuitApps.append(bundleID) }
        }
        if scheduling == .mainQueue {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeQuitCheckDelay) { MainActor.assumeIsolated { check() } }
        } else {
            check()
        }
    }

    /// The left button was released: every native drag of a tiled window ends.
    public func pointerReleased(at location: CGPoint?) {
        if let location { rememberPointer(location) }
        guard !nativeDrags.isEmpty else { return }
        for id in nativeDrags.keys.sorted() { finishNativeDrag(id, at: location) }
    }

    private func trackNativeDrag(_ id: WindowID, frame: CGRect, slot: CGRect) {
        var d = nativeDrags[id] ?? NativeDrag(slot: slot, latest: frame, startTree: state.workspace(of: id).flatMap { state[$0]?.tree })
        d.latest = frame
        if d.isResize, now().timeIntervalSince(d.lastLiveUpdate) >= Self.liveResizeInterval {
            d.lastLiveUpdate = now()
            applyNativeResize(id, d)
            setNeedsLayout()
            // Same turn as the mouse event: the edge is on the cursor before this returns.
            layoutIfNeeded()
        }
        nativeDrags[id] = d
        startPointerPoll()
    }

    /// The drag is over: decide what it meant and put the window where it belongs.
    func finishNativeDrag(_ id: WindowID, at location: CGPoint?) {
        guard let d = nativeDrags.removeValue(forKey: id) else { return }
        if nativeDrags.isEmpty { stopPointerPoll() }
        guard let handle = handles[id], state.workspace(of: id) != nil, !isFloating(id) else { return }
        let read = handle.frame
        var drop = d
        drop.latest = read.isNull ? d.latest : read
        nativeGrace[id] = now().addingTimeInterval(Self.nativeDragGrace)
        snapBacks[id] = 0
        if drop.isResize {
            applyNativeResize(id, drop)
            counters.nativeResizes += 1
            Log.wm.notice("live drag #\(id, privacy: .public) 1:1")
        } else if !drop.latest.approximatelyEquals(drop.slot, tolerance: 2) {
            let point = location ?? windowSystem.cursorLocation ?? CGPoint(x: drop.latest.midX, y: drop.latest.minY + 12)
            if let target = dropTarget(for: id, at: point) {
                _ = state.updateTree(of: id) { $0.swap(id, target.window) }
            } else if let here = state.display(of: id), let there = DisplayGeometry.display(containing: point, in: displays), there.id != here,
                      let n = state.activeNumberedWorkspace(forDisplay: there.id) {
                state.moveWindow(id, to: .numbered(n), follow: true, env: environment)
            }
            counters.nativeDrops += 1
        }
        displaced[id] = drop.latest
        forceApply.insert(id)
        setNeedsLayout()
    }

    /// Re-derives the splits from the tree at drag start plus the edges the user moved, so the
    /// window's slot takes its new size (smart resizing: the dragged edge follows, the opposite
    /// edge stays).
    private func applyNativeResize(_ id: WindowID, _ d: NativeDrag) {
        guard let area = area(of: id) else { return }
        let dl = d.latest.minX - d.slot.minX, dr = d.latest.maxX - d.slot.maxX
        let dt = d.latest.minY - d.slot.minY, db = d.latest.maxY - d.slot.maxY
        var edges: ResizeEdges = []
        var delta = CGPoint.zero
        if abs(dr) > 1 || abs(dl) > 1 {
            if abs(dr) >= abs(dl) { edges.insert(.right); delta.x = dr } else { edges.insert(.left); delta.x = dl }
        }
        if abs(db) > 1 || abs(dt) > 1 {
            if abs(db) >= abs(dt) { edges.insert(.bottom); delta.y = db } else { edges.insert(.top); delta.y = dt }
        }
        let dwindle = config.wm.dwindle
        _ = state.updateTree(of: id) { tree in
            // From the tree at drag start, unless windows came or went meanwhile (restoring it
            // then would drop or resurrect them).
            if let start = d.startTree, start.contains(id), Set(start.windows) == Set(tree.windows) { tree = start }
            return tree.resizeDrag(id, edges: edges, delta: delta, in: area, config: dwindle)
        }
    }

    private func startPointerPoll() {
        guard scheduling == .mainQueue, pointerPoll == nil else { return }
        let t = Timer(timeInterval: Self.pointerPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.windowSystem.isLeftMouseDown else { return }
                self.pointerReleased(at: self.windowSystem.cursorLocation)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        pointerPoll = t
    }

    private func stopPointerPoll() {
        pointerPoll?.invalidate()
        pointerPoll = nil
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
