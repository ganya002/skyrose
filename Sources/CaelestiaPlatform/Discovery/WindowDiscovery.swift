import AppKit
import ApplicationServices
import CaelestiaCore
import CoreGraphics
import Foundation

/// Tracks every window of every regular application through NSWorkspace notifications + one
/// `AXObserver` per app, reconciled against `CGWindowListCopyWindowInfo`. Main thread only; all
/// events are delivered on the main thread through `onEvent`.
///
/// Guarantees:
/// - `created` is emitted at most once per `CGWindowID` while the window lives.
/// - AX move/resize storms are coalesced per window: the first notification opens a
///   `frameCoalescingInterval` (16 ms) window and exactly one `moved`/`resized` pair is emitted
///   when it closes, carrying the frame read at that moment.
/// - Notifications caused by our own `setFrame` calls are tagged `isEcho` when they match an
///   expected frame registered with `expectFrame` (automatically fed by every tracked `AXWindow`).
public final class WindowDiscovery: NSObject {
    public enum WindowEvent {
        case created(AXWindow)
        case destroyed(CGWindowID)
        case focused(AXWindow?)
        case moved(AXWindow, frame: CGRect, isEcho: Bool)
        case resized(AXWindow, frame: CGRect, isEcho: Bool)
        case titleChanged(AXWindow)
        case minimized(AXWindow)
        case deminiaturized(AXWindow)
        case appHidden(pid_t)
        case appShown(pid_t)
        case appTerminated(pid_t)
        case appActivated(pid_t)
    }

    /// System processes whose windows are never managed.
    public static let defaultIgnoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
    ]

    public var ignoredBundleIDs: Set<String> = WindowDiscovery.defaultIgnoredBundleIDs
    /// Only apps with one of these activation policies are tracked (default: regular apps).
    public var trackedActivationPolicies: Set<NSApplication.ActivationPolicy> = [.regular]
    /// Receives every event, on the main thread.
    public var onEvent: ((WindowEvent) -> Void)?
    /// Length of the per-window move/resize coalescing window.
    public var frameCoalescingInterval: TimeInterval = 0.016
    /// Echo detection state (tolerance 2 pt, lifetime 250 ms by default).
    public private(set) var echoFilter = FrameEchoFilter()
    /// How long a CG window with no AX counterpart is left alone before `reconcile` retries it.
    public var unresolvableRetryInterval: TimeInterval = 5

    public private(set) var windows: [CGWindowID: AXWindow] = [:]
    public private(set) var applications: [pid_t: AXApplication] = [:]
    public private(set) var isRunning = false
    public private(set) var focusedWindowID: CGWindowID?
    public let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier

    private struct PendingFrame {
        var moved = false
        var resized = false
    }

    private var elementIndex: [AXElement: CGWindowID] = [:]
    private var pendingFrames: [CGWindowID: PendingFrame] = [:]
    private var unresolvable: [CGWindowID: Date] = [:]
    private var hiddenPIDs: Set<pid_t> = []
    private var activePID: pid_t?
    private let reconcileTask = DelayedMainTask()

    public override init() {
        super.init()
    }

    deinit { stop() }

    // MARK: - Lifecycle

    /// Subscribes to NSWorkspace, tracks every running regular app and runs a first `reconcile()`.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appDidLaunch(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidTerminate(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidActivate(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidHide(_:)), name: NSWorkspace.didHideApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidUnhide(_:)), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(activeSpaceDidChange(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for app in NSWorkspace.shared.runningApplications where shouldTrack(app) {
            track(app)
        }
        reconcile()
        if let front = NSWorkspace.shared.frontmostApplication, let app = applications[front.processIdentifier],
           let focused = app.focusedWindow {
            setFocused(resolve(focused))
        }
    }

    /// Stops observing; the window table is cleared without emitting `destroyed` events.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        reconcileTask.cancel()
        for app in applications.values { app.stopObserving() }
        applications.removeAll()
        for window in windows.values { window.frameExpectationSink = nil }
        windows.removeAll()
        elementIndex.removeAll()
        pendingFrames.removeAll()
        unresolvable.removeAll()
        hiddenPIDs.removeAll()
        focusedWindowID = nil
        echoFilter = FrameEchoFilter(tolerance: echoFilter.tolerance, lifetime: echoFilter.lifetime)
    }

    // MARK: - Queries

    public func window(for id: CGWindowID) -> AXWindow? { windows[id] }

    /// The tracked window backing `element`, without creating one.
    public func window(for element: AXElement) -> AXWindow? {
        elementIndex[element].flatMap { windows[$0] }
    }

    public func windows(for pid: pid_t) -> [AXWindow] {
        windows.values.filter { $0.pid == pid }
    }

    public func application(for pid: pid_t) -> AXApplication? { applications[pid] }

    /// The keyboard-focused window of the frontmost app, falling back to the top-most tracked
    /// window in CG z-order.
    public func frontmostWindow() -> AXWindow? {
        if let front = NSWorkspace.shared.frontmostApplication,
           let app = applications[front.processIdentifier] ?? (shouldTrack(front) ? track(front) : nil),
           let focused = app.focusedWindow {
            return resolve(focused)
        }
        for snapshot in CGWindowSnapshot.onScreenNormalWindows() {
            if let window = windows[snapshot.id] { return window }
        }
        return nil
    }

    /// The tracked window whose CG bounds are top-most at `point` (CG top-left space). `nil` when
    /// the top-most window there belongs to an untracked app, so focus-follows-mouse never focuses
    /// a window that is visually covered.
    public func windowUnder(point: CGPoint) -> AXWindow? {
        for snapshot in CGWindowSnapshot.onScreenNormalWindows()
        where snapshot.pid != ownPID && snapshot.alpha > 0 && snapshot.bounds.contains(point) {
            if let window = windows[snapshot.id] { return window }
            guard let app = applications[snapshot.pid] else { return nil }
            if let found = app.windows().first(where: { $0.windowID == snapshot.id }) { return addWindow(found) }
            return nil
        }
        return nil
    }

    /// Whether `app` is a candidate for tracking (regular app, not us, not in the ignore set).
    public func shouldTrack(_ app: NSRunningApplication) -> Bool {
        WindowDiscovery.shouldTrack(
            pid: app.processIdentifier, bundleID: app.bundleIdentifier, activationPolicy: app.activationPolicy,
            isTerminated: app.isTerminated, ownPID: ownPID, ignoredBundleIDs: ignoredBundleIDs,
            trackedPolicies: trackedActivationPolicies
        )
    }

    /// Pure tracking policy.
    public static func shouldTrack(
        pid: pid_t, bundleID: String?, activationPolicy: NSApplication.ActivationPolicy, isTerminated: Bool,
        ownPID: pid_t, ignoredBundleIDs: Set<String>, trackedPolicies: Set<NSApplication.ActivationPolicy> = [.regular]
    ) -> Bool {
        guard pid > 0, pid != ownPID, !isTerminated, trackedPolicies.contains(activationPolicy) else { return false }
        if let bundleID, ignoredBundleIDs.contains(bundleID) { return false }
        return true
    }

    // MARK: - Echo filter

    /// Registers a frame the WM is about to apply (or just applied) to `id`, so the resulting
    /// AX notifications are tagged as echoes until `deadline` (default: 250 ms from now).
    public func expectFrame(_ id: CGWindowID, _ frame: CGRect, until deadline: Date? = nil) {
        echoFilter.expect(id, frame: frame, until: deadline ?? Date().addingTimeInterval(echoFilter.lifetime))
    }

    /// Changes the echo tolerance/lifetime (kept across `stop()`).
    public func configureEchoFilter(tolerance: Double, lifetime: TimeInterval) {
        echoFilter.tolerance = tolerance
        echoFilter.lifetime = lifetime
    }

    // MARK: - Reconciliation

    /// Compares the tracked state with the live process list and the CG window list: drops dead
    /// windows and terminated apps, tracks apps that launched without a notification, and adds
    /// on-screen layer-0 windows AX never announced.
    public func reconcile() {
        for (pid, app) in applications where app.isTerminated {
            untrack(pid, emitTerminated: true)
        }
        for app in NSWorkspace.shared.runningApplications
        where applications[app.processIdentifier] == nil && shouldTrack(app) {
            track(app)
        }

        let liveIDs = Set(CGWindowSnapshot.current(onScreenOnly: false).map(\.id))
        for (id, window) in windows where !liveIDs.contains(id) {
            if !window.isAlive { removeWindow(id) }
        }

        let now = Date()
        var missingByPID: [pid_t: Set<CGWindowID>] = [:]
        for snapshot in CGWindowSnapshot.onScreenNormalWindows()
        where windows[snapshot.id] == nil && applications[snapshot.pid] != nil {
            if let retryAt = unresolvable[snapshot.id], retryAt > now { continue }
            missingByPID[snapshot.pid, default: []].insert(snapshot.id)
        }
        for (pid, ids) in missingByPID {
            guard let app = applications[pid] else { continue }
            var found: Set<CGWindowID> = []
            for window in app.windows() {
                found.insert(window.windowID)
                if windows[window.windowID] == nil { addWindow(window) }
            }
            for id in ids.subtracting(found) {
                unresolvable[id] = now.addingTimeInterval(unresolvableRetryInterval)
            }
        }
        unresolvable = unresolvable.filter { $0.value > now }
    }

    /// Runs `reconcile()` once after `delay`, coalescing repeated requests.
    public func scheduleReconcile(after delay: TimeInterval) {
        reconcileTask.schedule(after: delay) { [weak self] in self?.reconcile() }
    }

    // MARK: - Tracking

    /// Starts tracking `app` (idempotent). Returns the wrapper.
    @discardableResult
    public func track(_ app: NSRunningApplication) -> AXApplication {
        let pid = app.processIdentifier
        if let existing = applications[pid] { return existing }
        let axApp = AXApplication(runningApplication: app)
        applications[pid] = axApp
        if app.isHidden { hiddenPIDs.insert(pid) }
        axApp.startObserving(
            { [weak self, weak axApp] event in
                guard let self, let axApp else { return }
                self.handle(event, from: axApp)
            },
            onRegistered: { [weak self, weak axApp] in
                guard let self, let axApp else { return }
                for window in axApp.windows() { self.addWindow(window) }
            }
        )
        for window in axApp.windows() { addWindow(window) }
        return axApp
    }

    private func untrack(_ pid: pid_t, emitTerminated: Bool) {
        guard let app = applications.removeValue(forKey: pid) else { return }
        app.stopObserving()
        for (id, window) in windows where window.pid == pid {
            removeWindow(id)
        }
        hiddenPIDs.remove(pid)
        AXResponsiveness.shared.reset(pid)
        if emitTerminated { emit(.appTerminated(pid)) }
    }

    @discardableResult
    private func addWindow(_ window: AXWindow) -> AXWindow {
        if let existing = windows[window.windowID] {
            if elementIndex[window.element] == nil { elementIndex[window.element] = window.windowID }
            return existing
        }
        windows[window.windowID] = window
        elementIndex[window.element] = window.windowID
        unresolvable[window.windowID] = nil
        window.frameExpectationSink = { [weak self] id, frame in self?.expectFrame(id, frame) }
        emit(.created(window))
        return window
    }

    private func removeWindow(_ id: CGWindowID) {
        guard let window = windows.removeValue(forKey: id) else { return }
        elementIndex = elementIndex.filter { $0.value != id }
        pendingFrames[id] = nil
        echoFilter.forget(id)
        window.frameExpectationSink = nil
        emit(.destroyed(id))
        if focusedWindowID == id {
            focusedWindowID = nil
            emit(.focused(nil))
        }
    }

    /// Maps an element to its tracked window, creating/announcing one when the element has a window id.
    @discardableResult
    private func resolve(_ element: AXElement) -> AXWindow? {
        if let window = window(for: element) { return window }
        guard let window = AXWindow(element: element) else { return nil }
        return addWindow(window)
    }

    private func resolve(_ window: AXWindow) -> AXWindow {
        windows[window.windowID] ?? addWindow(window)
    }

    // MARK: - AX events

    private func handle(_ event: AXApplicationEvent, from app: AXApplication) {
        switch event {
        case .windowCreated(let element):
            if resolve(element) == nil {
                // No CG window yet (some apps announce before showing); the CG list will have it soon.
                scheduleReconcile(after: 0.5)
            }
        case .focusedWindowChanged(let element):
            guard let window = resolve(element) else { return }
            if app.isActive || activePID == app.pid { setFocused(window) }
        case .mainWindowChanged(let element):
            resolve(element)
        case .windowMoved(let element):
            queueFrameEvent(element, moved: true, resized: false)
        case .windowResized(let element):
            queueFrameEvent(element, moved: false, resized: true)
        case .titleChanged(let element):
            if let window = window(for: element) {
                emit(.titleChanged(window))
            } else if element.role == kAXWindowRole, let window = resolve(element) {
                emit(.titleChanged(window))
            }
        case .windowMiniaturized(let element):
            if let window = resolve(element) { emit(.minimized(window)) }
        case .windowDeminiaturized(let element):
            if let window = resolve(element) { emit(.deminiaturized(window)) }
        case .elementDestroyed(let element):
            if let id = elementIndex[element] { removeWindow(id) }
        case .applicationHidden:
            setHidden(app.pid, true)
        case .applicationShown:
            setHidden(app.pid, false)
        case .applicationActivated:
            setActive(app.pid)
        case .applicationDeactivated:
            break
        }
    }

    private func queueFrameEvent(_ element: AXElement, moved: Bool, resized: Bool) {
        guard let window = resolve(element) else { return }
        let id = window.windowID
        if var pending = pendingFrames[id] {
            pending.moved = pending.moved || moved
            pending.resized = pending.resized || resized
            pendingFrames[id] = pending
            return
        }
        pendingFrames[id] = PendingFrame(moved: moved, resized: resized)
        onMainAfter(frameCoalescingInterval) { [weak self] in self?.flushFrameEvent(id) }
    }

    private func flushFrameEvent(_ id: CGWindowID) {
        guard let pending = pendingFrames.removeValue(forKey: id), let window = windows[id] else { return }
        let frame = window.frame
        guard !frame.isNull else { return }
        let isEcho = echoFilter.isEcho(id, frame: frame)
        if pending.moved { emit(.moved(window, frame: frame, isEcho: isEcho)) }
        if pending.resized { emit(.resized(window, frame: frame, isEcho: isEcho)) }
    }

    private func setFocused(_ window: AXWindow) {
        guard focusedWindowID != window.windowID else { return }
        focusedWindowID = window.windowID
        emit(.focused(window))
    }

    private func setActive(_ pid: pid_t) {
        guard activePID != pid else { return }
        activePID = pid
        guard let app = applications[pid] else { return }
        emit(.appActivated(pid))
        if let focused = app.focusedWindow { setFocused(resolve(focused)) }
    }

    private func setHidden(_ pid: pid_t, _ hidden: Bool) {
        guard applications[pid] != nil else { return }
        if hidden {
            guard hiddenPIDs.insert(pid).inserted else { return }
            emit(.appHidden(pid))
        } else {
            guard hiddenPIDs.remove(pid) != nil else { return }
            emit(.appShown(pid))
        }
    }

    private func emit(_ event: WindowEvent) {
        onEvent?(event)
    }

    // MARK: - NSWorkspace

    private func runningApplication(in notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = runningApplication(in: notification), shouldTrack(app) else { return }
        track(app)
        scheduleReconcile(after: 1.0)
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = runningApplication(in: notification) else { return }
        untrack(app.processIdentifier, emitTerminated: true)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = runningApplication(in: notification) else { return }
        if applications[app.processIdentifier] == nil, shouldTrack(app) { track(app) }
        setActive(app.processIdentifier)
    }

    @objc private func appDidHide(_ notification: Notification) {
        guard let app = runningApplication(in: notification) else { return }
        setHidden(app.processIdentifier, true)
    }

    @objc private func appDidUnhide(_ notification: Notification) {
        guard let app = runningApplication(in: notification) else { return }
        setHidden(app.processIdentifier, false)
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        scheduleReconcile(after: 0.1)
    }
}
