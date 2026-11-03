import AppKit
import ApplicationServices
import CaelestiaCore
import Foundation

/// Typed AX notification delivered by `AXApplication`, always on the main thread. Window-level
/// cases carry the raw element the app reported; `WindowDiscovery` resolves it to an `AXWindow`.
public enum AXApplicationEvent: Equatable {
    case windowCreated(AXElement)
    case focusedWindowChanged(AXElement)
    case mainWindowChanged(AXElement)
    case windowMoved(AXElement)
    case windowResized(AXElement)
    case titleChanged(AXElement)
    case windowMiniaturized(AXElement)
    case windowDeminiaturized(AXElement)
    case elementDestroyed(AXElement)
    case applicationHidden
    case applicationShown
    case applicationActivated
    case applicationDeactivated

    /// The AX notification names we subscribe to, in registration order.
    public static let notificationNames: [String] = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
        kAXApplicationActivatedNotification,
        kAXApplicationDeactivatedNotification,
    ]

    /// Maps a raw notification to an event; `nil` for notifications we did not subscribe to.
    public init?(notification: String, element: AXElement) {
        switch notification {
        case kAXWindowCreatedNotification: self = .windowCreated(element)
        case kAXFocusedWindowChangedNotification: self = .focusedWindowChanged(element)
        case kAXMainWindowChangedNotification: self = .mainWindowChanged(element)
        case kAXWindowMovedNotification: self = .windowMoved(element)
        case kAXWindowResizedNotification: self = .windowResized(element)
        case kAXTitleChangedNotification: self = .titleChanged(element)
        case kAXWindowMiniaturizedNotification: self = .windowMiniaturized(element)
        case kAXWindowDeminiaturizedNotification: self = .windowDeminiaturized(element)
        case kAXUIElementDestroyedNotification: self = .elementDestroyed(element)
        case kAXApplicationHiddenNotification: self = .applicationHidden
        case kAXApplicationShownNotification: self = .applicationShown
        case kAXApplicationActivatedNotification: self = .applicationActivated
        case kAXApplicationDeactivatedNotification: self = .applicationDeactivated
        default: return nil
        }
    }
}

/// Owns one `AXObserver`; its run loop source lives on the main run loop so callbacks arrive on
/// the main thread. `invalidate()` removes the source first, so no callback can run afterwards.
final class AXObserverHandle {
    let pid: pid_t
    let observer: AXObserver
    var handler: ((AXApplicationEvent) -> Void)?
    private(set) var registered: Set<String> = []
    private var scheduled = false

    init?(pid: pid_t) {
        var observer: AXObserver?
        let error = AXObserverCreate(pid, axObserverCallback, &observer)
        guard error == .success, let observer else { return nil }
        self.pid = pid
        self.observer = observer
    }

    deinit { invalidate() }

    func schedule() {
        guard !scheduled else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        scheduled = true
    }

    func add(_ notification: String, on element: AXElement) -> AXError {
        if registered.contains(notification) { return .success }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let error = AXObserverAddNotification(observer, element.ref, notification as CFString, refcon)
        if error == .success || error == .notificationAlreadyRegistered { registered.insert(notification) }
        return error
    }

    func invalidate() {
        if scheduled {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            scheduled = false
        }
        handler = nil
        if !registered.isEmpty {
            let app = AXUIElementCreateApplication(pid)
            for name in registered { AXObserverRemoveNotification(observer, app, name as CFString) }
            registered.removeAll()
        }
    }

    fileprivate func dispatch(_ notification: String, element: AXUIElement) {
        guard let handler, let event = AXApplicationEvent(notification: notification, element: AXElement(element)) else {
            return
        }
        handler(event)
    }
}

private func axObserverCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let handle = Unmanaged<AXObserverHandle>.fromOpaque(refcon).takeUnretainedValue()
    handle.dispatch(notification as String, element: element)
}

/// A running application seen through NSRunningApplication + its AX application element, with an
/// observer that delivers `AXApplicationEvent`s on the main thread.
///
/// Freshly launched apps (Electron especially) are not AX-ready for a while; registration is
/// retried with backoff for ~5 s, like AeroSpace does.
public final class AXApplication {
    public let pid: pid_t
    public let runningApplication: NSRunningApplication
    public let element: AXElement

    /// Backoff schedule for observer registration (sums to ≈4.75 s).
    public static let registrationBackoff: [TimeInterval] = [0.05, 0.1, 0.2, 0.4, 0.8, 1.6, 1.6]

    private var observerHandle: AXObserverHandle?
    private var handler: ((AXApplicationEvent) -> Void)?
    private var onRegistered: (() -> Void)?
    private let retryTask = DelayedMainTask()
    private var retryAttempt = 0

    public init(runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        self.pid = runningApplication.processIdentifier
        self.element = .application(pid: runningApplication.processIdentifier)
    }

    public convenience init?(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        self.init(runningApplication: app)
    }

    deinit { stopObserving() }

    public var bundleID: String { runningApplication.bundleIdentifier ?? "" }
    public var name: String { runningApplication.localizedName ?? "" }
    public var isHidden: Bool { runningApplication.isHidden }
    public var isActive: Bool { runningApplication.isActive }
    public var isTerminated: Bool { runningApplication.isTerminated }

    /// All AX windows that currently have a CG window id (menus, tooltips and not-yet-shown windows are skipped).
    public func windows() -> [AXWindow] {
        element.elements(kAXWindowsAttribute).compactMap { AXWindow(element: $0) }
    }

    /// The app's keyboard-focused window, if it has a window id.
    public var focusedWindow: AXWindow? {
        element.element(kAXFocusedWindowAttribute).flatMap { AXWindow(element: $0) }
    }

    /// The app's main window, if it has a window id.
    public var mainWindow: AXWindow? {
        element.element(kAXMainWindowAttribute).flatMap { AXWindow(element: $0) }
    }

    /// Chrome/Electron accessibility mode flag (see `AXWindow.setFrame`).
    public var enhancedUserInterface: Bool? { element.bool(AXElement.enhancedUserInterfaceAttribute) }

    @discardableResult
    public func activate(options: NSApplication.ActivationOptions = []) -> Bool {
        runningApplication.activate(options: options)
    }

    @discardableResult
    public func hide() -> Bool { runningApplication.hide() }

    @discardableResult
    public func unhide() -> Bool { runningApplication.unhide() }

    // MARK: - Observation

    public var isObserving: Bool { observerHandle != nil && observerHandle?.registered.isEmpty == false }

    /// Starts delivering AX events for this app on the main thread. Safe to call repeatedly.
    /// `onRegistered` runs once all notifications are registered (possibly after retries), which
    /// is the moment to enumerate windows created before the observer was listening.
    public func startObserving(_ handler: @escaping (AXApplicationEvent) -> Void, onRegistered: (() -> Void)? = nil) {
        self.handler = handler
        self.onRegistered = onRegistered
        observerHandle?.handler = handler
        retryAttempt = 0
        retryTask.cancel()
        attemptRegistration()
    }

    public func stopObserving() {
        retryTask.cancel()
        handler = nil
        onRegistered = nil
        observerHandle?.invalidate()
        observerHandle = nil
    }

    private enum RegistrationOutcome { case done, retry, failed(AXError) }

    private func attemptRegistration() {
        guard handler != nil, !runningApplication.isTerminated else { return }
        switch register() {
        case .done:
            retryAttempt = 0
            let callback = onRegistered
            onRegistered = nil
            callback?()
        case .failed(let error):
            Log.ax.error("AX observer registration failed for pid \(self.pid) (\(self.bundleID)): \(error.rawValue)")
        case .retry:
            guard retryAttempt < AXApplication.registrationBackoff.count else {
                Log.ax.warning("gave up registering AX observer for pid \(self.pid) (\(self.bundleID)) after \(self.retryAttempt) attempts")
                return
            }
            let delay = AXApplication.registrationBackoff[retryAttempt]
            retryAttempt += 1
            retryTask.schedule(after: delay) { [weak self] in self?.attemptRegistration() }
        }
    }

    private func register() -> RegistrationOutcome {
        guard let handler else { return .done }
        if observerHandle == nil {
            guard let handle = AXObserverHandle(pid: pid) else { return .retry }
            handle.handler = handler
            observerHandle = handle
        }
        guard let handle = observerHandle else { return .retry }
        handle.schedule()
        var needsRetry = false
        for name in AXApplicationEvent.notificationNames {
            switch handle.add(name, on: element) {
            case .success, .notificationAlreadyRegistered, .notificationUnsupported, .notImplemented:
                continue
            case .cannotComplete, .failure:
                needsRetry = true
            case .invalidUIElement:
                return .failed(.invalidUIElement)
            case .apiDisabled:
                return .failed(.apiDisabled)
            default:
                needsRetry = true
            }
        }
        return needsRetry ? .retry : .done
    }
}
