import ApplicationServices
import CShims
import CaelestiaCore
import CoreGraphics
import Foundation

/// Swift mapping of `AXError`, plus two failures of our own (`unresponsive`, `typeMismatch`).
public enum AXFailure: Error, Equatable, Hashable, Sendable {
    case failure
    case illegalArgument
    case invalidElement
    case invalidObserver
    case cannotComplete
    case attributeUnsupported
    case actionUnsupported
    case notificationUnsupported
    case notImplemented
    case notificationAlreadyRegistered
    case notificationNotRegistered
    case apiDisabled
    case noValue
    case parameterizedAttributeUnsupported
    case notEnoughPrecision
    /// The owning process stopped answering AX messages; the call was skipped (see `AXResponsiveness`).
    case unresponsive
    /// The attribute exists but its value is not of the requested type.
    case typeMismatch
    case other(Int32)

    public init(_ error: AXError) {
        switch error {
        case .success, .failure: self = .failure
        case .illegalArgument: self = .illegalArgument
        case .invalidUIElement: self = .invalidElement
        case .invalidUIElementObserver: self = .invalidObserver
        case .cannotComplete: self = .cannotComplete
        case .attributeUnsupported: self = .attributeUnsupported
        case .actionUnsupported: self = .actionUnsupported
        case .notificationUnsupported: self = .notificationUnsupported
        case .notImplemented: self = .notImplemented
        case .notificationAlreadyRegistered: self = .notificationAlreadyRegistered
        case .notificationNotRegistered: self = .notificationNotRegistered
        case .apiDisabled: self = .apiDisabled
        case .noValue: self = .noValue
        case .parameterizedAttributeUnsupported: self = .parameterizedAttributeUnsupported
        case .notEnoughPrecision: self = .notEnoughPrecision
        @unknown default: self = .other(error.rawValue)
        }
    }

    /// `nil` for `.success`, otherwise the mapped failure.
    public static func from(_ error: AXError) -> AXFailure? {
        error == .success ? nil : AXFailure(error)
    }

    /// True when the element no longer exists (window closed, app quit).
    public var isElementGone: Bool { self == .invalidElement }

    /// True when the Accessibility permission is missing.
    public var isPermissionMissing: Bool { self == .apiDisabled }
}

/// Per-process circuit breaker for AX messaging. When an application stops answering (a call
/// hits the messaging timeout), further calls to its elements are short-circuited for a growing
/// backoff window (1 s, 2 s, 4 s, max 8 s) so a hung app cannot stall the main thread on every
/// layout pass. A successful call resets the strike count. Thread-safe.
public final class AXResponsiveness: @unchecked Sendable {
    public static let shared = AXResponsiveness()

    private struct State {
        var strikes: Int
        var trippedUntil: Date
    }

    private let lock = NSLock()
    private var states: [pid_t: State] = [:]

    public init() {}

    /// True when calls to `pid` are currently being skipped.
    public func isUnresponsive(_ pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let state = states[pid] else { return false }
        return state.trippedUntil > Date()
    }

    /// Clears the breaker for `pid` (e.g. after the app relaunches).
    public func reset(_ pid: pid_t) {
        lock.lock()
        states[pid] = nil
        lock.unlock()
    }

    func recordTimeout(_ pid: pid_t) {
        lock.lock()
        let strikes = (states[pid]?.strikes ?? 0) + 1
        let backoff = min(8.0, pow(2.0, Double(strikes - 1)))
        states[pid] = State(strikes: strikes, trippedUntil: Date().addingTimeInterval(backoff))
        lock.unlock()
        Log.ax.warning("pid \(pid) hit the AX messaging timeout (strike \(strikes)); backing off \(backoff, format: .fixed(precision: 1)) s")
    }

    func recordSuccess(_ pid: pid_t) {
        lock.lock()
        if states[pid] != nil { states[pid] = nil }
        lock.unlock()
    }
}

/// Thin value wrapper over `AXUIElement`.
///
/// Every element gets `AXUIElementSetMessagingTimeout(0.5 s)` on creation so a hung app can block
/// a call for at most half a second, and calls to apps that already timed out are skipped for a
/// backoff window (`AXResponsiveness`). All methods are synchronous IPC; call them from one thread
/// per element (in practice: the main thread).
public struct AXElement: Hashable, CustomStringConvertible {
    /// Messaging timeout applied to every element we create (seconds).
    public static let messagingTimeout: Float = 0.5

    /// Private attribute Chrome/Electron honour: when true the app animates/ignores AX resizes.
    public static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"
    /// Attribute exposing the native (green-button) fullscreen state of a window.
    public static let fullScreenAttribute = "AXFullScreen"

    public let ref: AXUIElement
    /// Owning process id (0 for the system-wide element).
    public let pid: pid_t

    public init(_ ref: AXUIElement) {
        self.ref = ref
        var pid: pid_t = 0
        if AXUIElementGetPid(ref, &pid) != .success { pid = 0 }
        self.pid = pid
        AXUIElementSetMessagingTimeout(ref, AXElement.messagingTimeout)
    }

    /// The application element for `pid`.
    public static func application(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    /// The system-wide element (focused application, focused element).
    public static var systemWide: AXElement {
        AXElement(AXUIElementCreateSystemWide())
    }

    public static func == (lhs: AXElement, rhs: AXElement) -> Bool {
        CFEqual(lhs.ref, rhs.ref)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(ref))
    }

    public var description: String { "AXElement(pid: \(pid), \(ref))" }

    // MARK: - Raw access

    /// Reads an attribute as an untyped CF value.
    public func copyAttribute(_ name: String) -> Result<CFTypeRef, AXFailure> {
        var value: CFTypeRef?
        if let failure = call({ AXUIElementCopyAttributeValue(ref, name as CFString, &value) }) {
            return .failure(failure)
        }
        guard let value else { return .failure(.noValue) }
        return .success(value)
    }

    /// Reads an attribute and bridges it to `T` (String, Bool, Int, Double, NSNumber, arrays…).
    /// Use `element(_:)` / `elements(_:)` for `AXUIElement` values and `point/size/rect` for `AXValue`s.
    public func attribute<T>(_ name: String) -> T? {
        guard case .success(let raw) = copyAttribute(name) else { return nil }
        return raw as? T
    }

    /// Typed variant that preserves the failure reason.
    public func attributeResult<T>(_ name: String, as type: T.Type = T.self) -> Result<T, AXFailure> {
        switch copyAttribute(name) {
        case .failure(let failure): return .failure(failure)
        case .success(let raw):
            guard let typed = raw as? T else { return .failure(.typeMismatch) }
            return .success(typed)
        }
    }

    /// Sets an attribute. Returns `nil` on success.
    @discardableResult
    public func setAttribute(_ name: String, _ value: CFTypeRef) -> AXFailure? {
        call { AXUIElementSetAttributeValue(ref, name as CFString, value) }
    }

    /// True when the attribute can be written (AX "settable" flag).
    public func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        guard call({ AXUIElementIsAttributeSettable(ref, name as CFString, &settable) }) == nil else { return false }
        return settable.boolValue
    }

    /// Performs an action such as `kAXRaiseAction` or `kAXPressAction`. Returns `nil` on success.
    @discardableResult
    public func perform(_ action: String) -> AXFailure? {
        call { AXUIElementPerformAction(ref, action as CFString) }
    }

    /// Names of the actions the element supports.
    public func actionNames() -> [String] {
        var names: CFArray?
        guard call({ AXUIElementCopyActionNames(ref, &names) }) == nil else { return [] }
        return (names as? [String]) ?? []
    }

    // MARK: - Typed convenience

    public var role: String? { string(kAXRoleAttribute) }
    public var subrole: String? { string(kAXSubroleAttribute) }
    public var title: String? { string(kAXTitleAttribute) }

    public func string(_ name: String) -> String? {
        guard case .success(let raw) = copyAttribute(name) else { return nil }
        if CFGetTypeID(raw) == CFStringGetTypeID() { return (raw as! CFString) as String }
        return raw as? String
    }

    public func bool(_ name: String) -> Bool? {
        guard case .success(let raw) = copyAttribute(name) else { return nil }
        if CFGetTypeID(raw) == CFBooleanGetTypeID() { return CFBooleanGetValue((raw as! CFBoolean)) }
        return (raw as? NSNumber)?.boolValue
    }

    public func number(_ name: String) -> NSNumber? {
        guard case .success(let raw) = copyAttribute(name) else { return nil }
        return raw as? NSNumber
    }

    /// Reads a child element attribute (`kAXFocusedWindowAttribute`, `kAXCloseButtonAttribute`, …).
    public func element(_ name: String) -> AXElement? {
        guard case .success(let raw) = copyAttribute(name), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return nil
        }
        return AXElement(raw as! AXUIElement)
    }

    /// Reads an element-array attribute (`kAXWindowsAttribute`, `kAXChildrenAttribute`, …).
    public func elements(_ name: String) -> [AXElement] {
        guard case .success(let raw) = copyAttribute(name), let array = raw as? [AnyObject] else { return [] }
        return array.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return AXElement(item as! AXUIElement)
        }
    }

    public func point(_ name: String) -> CGPoint? {
        guard case .success(let raw) = copyAttribute(name), let value = AXElement.axValue(raw) else { return nil }
        return value.cgPoint
    }

    public func size(_ name: String) -> CGSize? {
        guard case .success(let raw) = copyAttribute(name), let value = AXElement.axValue(raw) else { return nil }
        return value.cgSize
    }

    /// Reads a position + size attribute pair as a rect (AX uses global top-left coordinates).
    public func rect(position: String = kAXPositionAttribute, size: String = kAXSizeAttribute) -> CGRect? {
        guard let origin = point(position), let size = self.size(size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    public func rectResult(position: String = kAXPositionAttribute, size: String = kAXSizeAttribute) -> Result<CGRect, AXFailure> {
        let originResult = copyAttribute(position)
        guard case .success(let rawOrigin) = originResult else {
            if case .failure(let failure) = originResult { return .failure(failure) }
            return .failure(.failure)
        }
        guard let origin = AXElement.axValue(rawOrigin)?.cgPoint else { return .failure(.typeMismatch) }
        let sizeResult = copyAttribute(size)
        guard case .success(let rawSize) = sizeResult else {
            if case .failure(let failure) = sizeResult { return .failure(failure) }
            return .failure(.failure)
        }
        guard let size = AXElement.axValue(rawSize)?.cgSize else { return .failure(.typeMismatch) }
        return .success(CGRect(origin: origin, size: size))
    }

    @discardableResult
    public func setPoint(_ name: String, _ point: CGPoint) -> AXFailure? {
        setAttribute(name, AXValue.make(point))
    }

    @discardableResult
    public func setSize(_ name: String, _ size: CGSize) -> AXFailure? {
        setAttribute(name, AXValue.make(size))
    }

    /// One size write and one position write. No read-back and no enhanced-UI toggle: those
    /// belong on the animation clock's thread, and a slow read must not stall the other windows.
    public func setFrameFast(_ target: CGRect) {
        let target = target.integralPoints
        setSize(kAXSizeAttribute, target.size)
        setPoint(kAXPositionAttribute, target.origin)
    }

    @discardableResult
    public func setBool(_ name: String, _ value: Bool) -> AXFailure? {
        setAttribute(name, (value ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }

    /// True while the element still exists in its process. Only `.invalidElement` counts as dead;
    /// a timeout or missing permission keeps the benefit of the doubt.
    public var isValid: Bool {
        if case .failure(let failure) = copyAttribute(kAXRoleAttribute), failure.isElementGone { return false }
        return true
    }

    /// The CGWindowID of a window element, via the weak-linked `_AXUIElementGetWindow`.
    public var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return caelestia_ax_window_id(ref, &id) ? id : nil
    }

    // MARK: - Internals

    private static func axValue(_ raw: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        return (raw as! AXValue)
    }

    /// Runs one AX call through the responsiveness breaker and timeout bookkeeping.
    private func call(_ body: () -> AXError) -> AXFailure? {
        let breaker = AXResponsiveness.shared
        if pid > 0, breaker.isUnresponsive(pid) { return .unresponsive }
        let start = CFAbsoluteTimeGetCurrent()
        let error = body()
        if pid > 0 {
            if error == .cannotComplete, CFAbsoluteTimeGetCurrent() - start >= Double(AXElement.messagingTimeout) * 0.8 {
                breaker.recordTimeout(pid)
            } else if error == .success {
                breaker.recordSuccess(pid)
            }
        }
        return AXFailure.from(error)
    }
}

extension AXValue {
    /// Wraps a point in an `AXValue`.
    public static func make(_ point: CGPoint) -> AXValue {
        var value = point
        return AXValueCreate(.cgPoint, &value)!
    }

    /// Wraps a size in an `AXValue`.
    public static func make(_ size: CGSize) -> AXValue {
        var value = size
        return AXValueCreate(.cgSize, &value)!
    }

    /// Wraps a rect in an `AXValue`.
    public static func make(_ rect: CGRect) -> AXValue {
        var value = rect
        return AXValueCreate(.cgRect, &value)!
    }

    public var cgPoint: CGPoint? {
        guard AXValueGetType(self) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(self, .cgPoint, &point) ? point : nil
    }

    public var cgSize: CGSize? {
        guard AXValueGetType(self) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(self, .cgSize, &size) ? size : nil
    }

    public var cgRect: CGRect? {
        guard AXValueGetType(self) == .cgRect else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(self, .cgRect, &rect) ? rect : nil
    }
}
