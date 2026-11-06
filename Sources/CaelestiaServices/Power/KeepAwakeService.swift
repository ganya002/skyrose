import Foundation
import IOKit.pwr_mgt
import CaelestiaCore

/// One IOKit power assertion that prevents idle display sleep while held.
@MainActor
final class PowerAssertion {
    private var id: IOPMAssertionID = 0
    let name: String
    let type: String

    init(name: String, type: String = kIOPMAssertionTypePreventUserIdleDisplaySleep as String) {
        self.name = name
        self.type = type
    }

    var isHeld: Bool { id != 0 }

    /// Creates the assertion; returns `false` (and logs) if IOKit refused.
    func acquire() -> Bool {
        guard id == 0 else { return true }
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &newID)
        guard result == kIOReturnSuccess else {
            Log.services.error("IOPMAssertionCreateWithName(\(self.name, privacy: .public)) failed: \(result)")
            return false
        }
        id = newID
        return true
    }

    func release() {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }

    deinit {
        if id != 0 { IOPMAssertionRelease(id) }
    }
}

/// Sidebar "Keep awake" utility: `kIOPMAssertionTypePreventUserIdleDisplaySleep` named
/// "SkyRose keep awake", optionally for a limited time (`set(on:duration:)`); the assertion is
/// released when the timer ends. Status text mirrors Caelestia ("Normal power management" /
/// "Keeping awake") plus the time left.
@MainActor
public final class KeepAwakeService {
    public private(set) var isEnabled = false
    /// When a timed keep-awake ends; nil = until turned off.
    public private(set) var until: Date?
    /// The length the running timed keep-awake was started with (nil = off or unlimited).
    public private(set) var duration: TimeInterval?
    public var onChange: ((Bool) -> Void)?

    private let assertion = PowerAssertion(name: "SkyRose keep awake")
    private var timer: Timer?
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) { self.now = now }

    public var statusText: String { KeepAwakeTimer.status(enabled: isEnabled, until: until, now: now()) }

    /// Seconds left of a timed keep-awake (nil when off or unlimited).
    public var remaining: TimeInterval? { until.map { max(0, $0.timeIntervalSince(now())) } }

    /// Turns keep-awake on (for `duration` seconds, nil = until turned off) or off. Turning it on
    /// again replaces the previous timer.
    public func set(on: Bool, duration: TimeInterval? = nil) {
        timer?.invalidate()
        timer = nil
        if on {
            guard assertion.acquire() else { return }
            until = duration.map { now().addingTimeInterval($0) }
            self.duration = duration
            if let duration {
                let t = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.set(on: false) }
                }
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
        } else {
            assertion.release()
            until = nil
            self.duration = nil
        }
        let changed = on != isEnabled
        isEnabled = on
        // A new timer on an already-on keep-awake still changes the status line.
        if changed || on { onChange?(on) }
    }

    public func toggle() { set(on: !isEnabled) }
}

/// Separate assertion for the `game` window tag / game mode (Caelestia's idle inhibit), so turning
/// off game mode never releases a "Keep awake" the user set by hand, and vice versa.
@MainActor
public final class IdleInhibitor {
    public private(set) var isInhibited = false
    private let assertion = PowerAssertion(name: "SkyRose game mode idle inhibit")

    public init() {}

    public func set(inhibited: Bool) {
        if inhibited {
            guard assertion.acquire() else { return }
        } else {
            assertion.release()
        }
        isInhibited = inhibited
    }
}
