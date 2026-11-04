import AppKit
import CaelestiaCore
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit
import os

/// Errors from `EventTap.start()`.
public enum EventTapError: Error, Equatable, CustomStringConvertible {
    case alreadyRunning
    /// `CGEvent.tapCreate` returned nil: Input Monitoring / Accessibility is missing.
    case creationFailed
    case threadStartTimeout

    public var description: String {
        switch self {
        case .alreadyRunning: return "event tap already running"
        case .creationFailed: return "could not create the event tap (grant Input Monitoring and Accessibility)"
        case .threadStartTimeout: return "event tap thread did not start"
        }
    }
}

/// Permission state relevant to the tap, read without prompting.
public struct EventTapPermissions: Equatable, Sendable {
    /// `CGPreflightListenEventAccess`: needed to see keyboard events at all.
    public var inputMonitoring: Bool
    /// `AXIsProcessTrusted`: needed for an active (filtering) tap and window management.
    public var accessibility: Bool
    /// `CGPreflightPostEventAccess`: needed for `postKeystrokes` / `postMediaKey`.
    public var postEvents: Bool

    public var canRunTap: Bool { inputMonitoring || accessibility }
}

/// The capabilities media-key interception depends on, shared between the main thread (which
/// knows them) and the tap thread (which decides per event). Thread-safe.
public final class MediaKeyInterceptor: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _enabled = true
    private var _volume = false
    private var _brightness = false

    public init() {}

    /// Updates what Caelestia can do (config switch, output volume settable, brightness control).
    public func update(enabled: Bool? = nil, volumeControllable: Bool? = nil, brightnessControllable: Bool? = nil) {
        lock.lock()
        if let enabled { _enabled = enabled }
        if let volumeControllable { _volume = volumeControllable }
        if let brightnessControllable { _brightness = brightnessControllable }
        lock.unlock()
    }

    public func route(_ command: MediaKeyCommand?) -> MediaKeyRoute {
        lock.lock()
        defer { lock.unlock() }
        return MediaKeyRouting.route(command, intercept: _enabled, volumeControllable: _volume, brightnessControllable: _brightness)
    }
}

/// The `CGEventTap` that feeds a `ChordMatcher`, on its own thread with its own run loop.
///
/// The C callback converts each `CGEvent` into a `SyntheticEvent`, runs the matcher synchronously
/// (a dictionary lookup; well under a millisecond) and, for `.fire` / `.fireAndPass`, hands the
/// `Fired` list to `queue` through `onFired`. Nothing blocks on the tap thread.
///
/// Watchdog (spec 10.10): a tap disabled by timeout or user input is re-enabled from the callback
/// (`reEnableCount`), and a 2 s timer re-enables a silently disabled tap or re-creates an
/// invalidated one (`recreateCount`). Secure Event Input is polled at 1 Hz only while the tap is
/// running and mirrored into `ChordMatcher.secureInputActive`; `onSecureInputChanged` names the
/// app holding it so the WM can explain why hotkeys stopped.
///
/// `start()` triggers the Input Monitoring prompt when the permission is undetermined; call
/// `preflightPermissions()` first to drive onboarding, and never start a tap from unit tests.
public final class EventTap: @unchecked Sendable {
    public let matcher: ChordMatcher
    /// Where `onFired` and `onSecureInputChanged` run.
    public let queue: DispatchQueue

    private let lock = OSAllocatedUnfairLock()
    private var _onFired: (@Sendable ([Fired]) -> Void)?
    private var _onMediaKey: (@Sendable (MediaKeyEvent) -> Void)?
    private var _onLeftMouse: (@Sendable (_ down: Bool, _ location: CGPoint) -> Void)?
    /// Media keys Caelestia handles itself are swallowed here (before the matcher) and handed to
    /// `onMediaKey`; nil: every media key goes to the matcher and on to macOS.
    public let mediaKeys = MediaKeyInterceptor()
    private var _onSecureInputChanged: (@Sendable (_ active: Bool, _ appName: String?) -> Void)?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: CFRunLoopTimer?
    private var securePoll: CFRunLoopTimer?
    private var lastSecureInput = false
    private var _reEnableCount = 0
    private var _recreateCount = 0
    private let stopped = DispatchSemaphore(value: 0)

    /// Interval of the tap health check.
    public var watchdogInterval: TimeInterval = 2
    /// Interval of the `IsSecureEventInputEnabled` poll (only while running).
    public var secureInputPollInterval: TimeInterval = 1

    /// Tag stamped into `eventSourceUserData` of events we post, so the tap passes them untouched.
    static let ownEventTag: Int64 = 0x4341_454C
    /// `NX_SYSDEFINED`: media keys arrive with this CGEventType.
    static let systemDefinedEventType: UInt32 = 14
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
    static let auxControlSubtype = 8

    public init(matcher: ChordMatcher, queue: DispatchQueue = .main) {
        self.matcher = matcher
        self.queue = queue
    }

    deinit {
        stop()
    }

    // MARK: Callbacks

    /// Receives every fired bind, on `queue`. Set before `start()`.
    public var onFired: (@Sendable ([Fired]) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onFired }
        set { lock.lock(); defer { lock.unlock() }; _onFired = newValue }
    }

    /// A swallowed media key (volume / mute / brightness), on `queue`. Down, repeat and up events
    /// all arrive; act on downs.
    public var onMediaKey: (@Sendable (MediaKeyEvent) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onMediaKey }
        set { lock.lock(); defer { lock.unlock() }; _onMediaKey = newValue }
    }

    /// Every left button press / release (the WM tells the user's title-bar drags of tiled
    /// windows from apps moving their own windows), on `queue`. Never swallowed.
    public var onLeftMouse: (@Sendable (_ down: Bool, _ location: CGPoint) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onLeftMouse }
        set { lock.lock(); defer { lock.unlock() }; _onLeftMouse = newValue }
    }

    /// Secure Event Input went on or off, on `queue`, with the owning app's name when known.
    public var onSecureInputChanged: (@Sendable (_ active: Bool, _ appName: String?) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onSecureInputChanged }
        set { lock.lock(); defer { lock.unlock() }; _onSecureInputChanged = newValue }
    }

    // MARK: State

    /// Times the tap was re-enabled after macOS disabled it.
    public var reEnableCount: Int {
        lock.lock(); defer { lock.unlock() }; return _reEnableCount
    }

    /// Times the watchdog re-created an invalidated tap.
    public var recreateCount: Int {
        lock.lock(); defer { lock.unlock() }; return _recreateCount
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }; return thread != nil
    }

    /// Whether macOS currently delivers events to the tap.
    public var isEnabled: Bool {
        lock.lock(); let p = port; lock.unlock()
        guard let p, CFMachPortIsValid(p) else { return false }
        return CGEvent.tapIsEnabled(tap: p)
    }

    // MARK: Permissions

    /// Reads the relevant permissions without prompting.
    public static func preflightPermissions() -> EventTapPermissions {
        EventTapPermissions(
            inputMonitoring: CGPreflightListenEventAccess(),
            accessibility: AXIsProcessTrusted(),
            postEvents: CGPreflightPostEventAccess())
    }

    /// Asks macOS for Input Monitoring and event posting (shows the system prompts). Onboarding only.
    public static func requestPermissions() {
        _ = CGRequestListenEventAccess()
        _ = CGRequestPostEventAccess()
    }

    // MARK: Lifecycle

    /// Creates the tap on a dedicated thread and starts the watchdog and secure-input poll.
    public func start() throws {
        lock.lock()
        guard thread == nil else {
            lock.unlock()
            throw EventTapError.alreadyRunning
        }
        let ready = DispatchSemaphore(value: 0)
        let created = OSAllocatedUnfairLock(initialState: false)
        let t = Thread { [self] in
            let rl = CFRunLoopGetCurrent()
            lock.lock()
            runLoop = rl
            lock.unlock()
            let ok = createTap()
            created.withLock { $0 = ok }
            ready.signal()
            if ok {
                installTimers()
                CFRunLoopRun()
                removeTimers()
                destroyTap()
            }
            lock.lock()
            runLoop = nil
            thread = nil
            lock.unlock()
            stopped.signal()
        }
        t.name = "com.caelestia.mac.eventtap"
        t.qualityOfService = .userInteractive
        thread = t
        lock.unlock()
        t.start()

        guard ready.wait(timeout: .now() + 5) == .success else {
            lock.lock()
            thread = nil
            lock.unlock()
            throw EventTapError.threadStartTimeout
        }
        guard created.withLock({ $0 }) else {
            _ = stopped.wait(timeout: .now() + 2)
            throw EventTapError.creationFailed
        }
        Log.input.info("event tap started")
    }

    /// Stops the run loop, tears the tap down and waits (bounded) for the thread to finish.
    public func stop() {
        lock.lock()
        let rl = runLoop
        let running = thread != nil
        lock.unlock()
        guard running else { return }
        if let rl { CFRunLoopStop(rl) }
        _ = stopped.wait(timeout: .now() + 2)
        matcher.reset()
        Log.input.info("event tap stopped")
    }

    // MARK: Tap thread

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .scrollWheel,
        ]
        var mask: CGEventMask = 0
        for t in types { mask |= CGEventMask(1) << CGEventMask(t.rawValue) }
        mask |= CGEventMask(1) << CGEventMask(systemDefinedEventType)
        return mask
    }()

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return tap.handle(type: type, event: event)
    }

    /// Runs on the tap thread.
    private func createTap() -> Bool {
        guard let p = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.eventMask, callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Log.input.error("CGEvent.tapCreate failed; Input Monitoring or Accessibility is probably missing")
            return false
        }
        guard let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, p, 0) else {
            CFMachPortInvalidate(p)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), s, .commonModes)
        CGEvent.tapEnable(tap: p, enable: true)
        lock.lock()
        port = p
        source = s
        lock.unlock()
        return true
    }

    /// Runs on the tap thread.
    private func destroyTap() {
        lock.lock()
        let p = port
        let s = source
        port = nil
        source = nil
        lock.unlock()
        if let s { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes) }
        if let p {
            CGEvent.tapEnable(tap: p, enable: false)
            CFMachPortInvalidate(p)
        }
    }

    private func installTimers() {
        let rl = CFRunLoopGetCurrent()
        let wd = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + watchdogInterval, watchdogInterval, 0, 0
        ) { [weak self] _ in self?.checkTapHealth() }
        let sp = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + secureInputPollInterval, secureInputPollInterval, 0, 0
        ) { [weak self] _ in self?.pollSecureInput() }
        CFRunLoopAddTimer(rl, wd, .commonModes)
        CFRunLoopAddTimer(rl, sp, .commonModes)
        lock.lock()
        watchdog = wd
        securePoll = sp
        lock.unlock()
        pollSecureInput()
    }

    private func removeTimers() {
        lock.lock()
        let wd = watchdog
        let sp = securePoll
        watchdog = nil
        securePoll = nil
        lock.unlock()
        if let wd { CFRunLoopTimerInvalidate(wd) }
        if let sp { CFRunLoopTimerInvalidate(sp) }
    }

    /// Watchdog: re-enable a disabled tap, re-create an invalidated one.
    private func checkTapHealth() {
        lock.lock()
        let p = port
        lock.unlock()
        if let p, CFMachPortIsValid(p) {
            if !CGEvent.tapIsEnabled(tap: p) {
                CGEvent.tapEnable(tap: p, enable: true)
                bumpReEnable(reason: "watchdog found the tap disabled")
            }
            return
        }
        destroyTap()
        if createTap() {
            matcher.reset()
            lock.lock()
            _recreateCount += 1
            let n = _recreateCount
            lock.unlock()
            Log.input.warning("event tap re-created (\(n))")
        } else {
            Log.input.error("event tap invalid and could not be re-created; retrying in \(self.watchdogInterval) s")
        }
    }

    private func bumpReEnable(reason: String) {
        lock.lock()
        _reEnableCount += 1
        let n = _reEnableCount
        lock.unlock()
        Log.input.warning("event tap re-enabled (\(n)): \(reason)")
    }

    private func pollSecureInput() {
        let active = IsSecureEventInputEnabled()
        lock.lock()
        let changed = active != lastSecureInput
        lastSecureInput = active
        let cb = _onSecureInputChanged
        lock.unlock()
        guard changed else { return }
        matcher.secureInputActive = active
        let owner = active ? Self.secureInputOwner()?.name : nil
        Log.input.notice("secure event input \(active ? "on" : "off")\(owner.map { " (\($0))" } ?? "")")
        if let cb { queue.async { cb(active, owner) } }
    }

    /// The process holding Secure Event Input, from the IORegistry console-users record.
    public static func secureInputOwner() -> (pid: pid_t, name: String?)? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]]
        else { return nil }
        for user in users {
            guard let pid = (user["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 else { continue }
            return (pid, NSRunningApplication(processIdentifier: pid)?.localizedName)
        }
        return nil
    }

    // MARK: Event handling (tap thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let p = port
            lock.unlock()
            if let p { CGEvent.tapEnable(tap: p, enable: true) }
            bumpReEnable(reason: type == .tapDisabledByTimeout ? "timeout" : "user input")
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventTag { return pass }
        if type == .leftMouseDown || type == .leftMouseUp {
            lock.lock()
            let cb = _onLeftMouse
            lock.unlock()
            if let cb {
                let down = type == .leftMouseDown, location = event.location
                queue.async { cb(down, location) }
            }
        }
        if type.rawValue == Self.systemDefinedEventType, let media = Self.mediaKeyEvent(event),
           mediaKeys.route(media.command).swallow {
            lock.lock()
            let cb = _onMediaKey
            lock.unlock()
            if let cb {
                queue.async { cb(media) }
                return nil
            }
        }
        guard let synthetic = Self.convert(type: type, event: event) else { return pass }
        switch matcher.handle(synthetic, now: ProcessInfo.processInfo.systemUptime) {
        case .passThrough:
            return pass
        case .swallow:
            return nil
        case .fire(let fired):
            dispatch(fired)
            return nil
        case .fireAndPass(let fired):
            dispatch(fired)
            return pass
        }
    }

    private func dispatch(_ fired: [Fired]) {
        lock.lock()
        let cb = _onFired
        lock.unlock()
        guard let cb else { return }
        queue.async { cb(fired) }
    }

    /// Converts a `CGEvent` into the matcher's representation; `nil` for event types we ignore.
    static func convert(type: CGEventType, event: CGEvent) -> SyntheticEvent? {
        let flags = event.flags.rawValue
        func keyCode() -> UInt16 { UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)) }
        func otherButton() -> Int { MouseButtonCode.fromCGButtonNumber(Int(event.getIntegerValueField(.mouseEventButtonNumber))) }
        switch type {
        case .keyDown:
            return .keyDown(code: keyCode(), flags: flags, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp:
            return .keyUp(code: keyCode(), flags: flags)
        case .flagsChanged:
            return .flagsChanged(code: keyCode(), flags: flags)
        case .leftMouseDown:
            return .mouseDown(button: MouseButtonCode.left, flags: flags, location: event.location)
        case .rightMouseDown:
            return .mouseDown(button: MouseButtonCode.right, flags: flags, location: event.location)
        case .otherMouseDown:
            return .mouseDown(button: otherButton(), flags: flags, location: event.location)
        case .leftMouseUp:
            return .mouseUp(button: MouseButtonCode.left, flags: flags, location: event.location)
        case .rightMouseUp:
            return .mouseUp(button: MouseButtonCode.right, flags: flags, location: event.location)
        case .otherMouseUp:
            return .mouseUp(button: otherButton(), flags: flags, location: event.location)
        case .leftMouseDragged:
            return .mouseDragged(button: MouseButtonCode.left, flags: flags, location: event.location)
        case .rightMouseDragged:
            return .mouseDragged(button: MouseButtonCode.right, flags: flags, location: event.location)
        case .otherMouseDragged:
            return .mouseDragged(button: otherButton(), flags: flags, location: event.location)
        case .mouseMoved:
            return .mouseDragged(button: MouseButtonCode.none, flags: flags, location: event.location)
        case .scrollWheel:
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let dy: Double
            let dx: Double
            if continuous {
                dy = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
                dx = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            } else {
                dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
                dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            }
            let phase = scrollPhase(
                scroll: event.getIntegerValueField(.scrollWheelEventScrollPhase),
                momentum: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
            return .scroll(deltaY: dy, deltaX: dx, flags: flags, isContinuous: continuous, phase: phase)
        default:
            guard type.rawValue == systemDefinedEventType, let ns = NSEvent(cgEvent: event),
                ns.subtype.rawValue == auxControlSubtype
            else { return nil }
            let data1 = ns.data1
            let keyType = (data1 & 0xFFFF_0000) >> 16
            let keyState = (data1 & 0xFF00) >> 8
            return .systemDefined(nxKeyType: keyType, isDown: keyState == 0x0A, flags: flags)
        }
    }

    /// The aux-control media key in an `NX_SYSDEFINED` event, nil for anything else.
    static func mediaKeyEvent(_ event: CGEvent) -> MediaKeyEvent? {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == auxControlSubtype else { return nil }
        return MediaKeyEvent(data1: ns.data1, flags: event.flags.rawValue)
    }

    /// Maps `kCGScrollPhase*` / `kCGMomentumScrollPhase*` values.
    static func scrollPhase(scroll: Int64, momentum: Int64) -> ScrollPhase {
        switch momentum {
        case 1: return .momentumBegan
        case 2: return .momentumChanged
        case 3: return .momentumEnded
        default: break
        }
        switch scroll {
        case 1: return .began
        case 2: return .changed
        case 4: return .ended
        case 8: return .cancelled
        case 128: return .mayBegin
        default: return .none
        }
    }

    // MARK: Posting

    /// Types `text` as keyboard events carrying the Unicode string (for `clipboard.typeLatest`).
    /// Newlines and tabs are sent as Return / Tab key codes. Apps that read key codes instead of
    /// characters (some terminals, games) see key code 0 for other characters; this is a limit of
    /// the public API. Needs the event-posting permission (`EventTapPermissions.postEvents`).
    public func postKeystrokes(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for ch in text {
            if ch == "\n" || ch == "\r" || ch == "\r\n" {
                postKey(ChordMatcher.Key.return, source: source)
                continue
            }
            if ch == "\t" {
                postKey(ChordMatcher.Key.tab, source: source)
                continue
            }
            let units = Array(String(ch).utf16)
            for down in [true, false] {
                guard let ev = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                ev.flags = []
                units.withUnsafeBufferPointer { buf in
                    ev.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                ev.setIntegerValueField(.eventSourceUserData, value: Self.ownEventTag)
                ev.post(tap: .cgSessionEventTap)
            }
        }
    }

    private func postKey(_ code: UInt16, source: CGEventSource) {
        for down in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            ev.flags = []
            ev.setIntegerValueField(.eventSourceUserData, value: Self.ownEventTag)
            ev.post(tap: .cgSessionEventTap)
        }
    }

    /// Posts an `NX_SYSDEFINED` media key press (down + up) so macOS performs the action.
    /// Returns `false` for keys without an NX constant (`.micMute`).
    @discardableResult
    public func postMediaKey(_ key: MediaKey) -> Bool {
        let keyType = key.nxKeyType
        guard keyType >= 0 else { return false }
        func post(down: Bool) -> Bool {
            let modifier: UInt = down ? 0xA00 : 0xB00
            let data1 = (keyType << 16) | ((down ? 0xA : 0xB) << 8)
            guard let ns = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: modifier),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                subtype: Int16(Self.auxControlSubtype), data1: data1, data2: -1),
                let cg = ns.cgEvent
            else { return false }
            cg.setIntegerValueField(.eventSourceUserData, value: Self.ownEventTag)
            cg.post(tap: .cghidEventTap)
            return true
        }
        return post(down: true) && post(down: false)
    }
}
