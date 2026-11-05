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
/// "Caelestia keep awake". Status text mirrors Caelestia ("Normal power management" /
/// "Keeping awake").
@MainActor
public final class KeepAwakeService {
    public private(set) var isEnabled = false
    public var onChange: ((Bool) -> Void)?

    private let assertion = PowerAssertion(name: "SkyRose keep awake")

    public init() {}

    public var statusText: String { isEnabled ? "Keeping awake" : "Normal power management" }

    public func set(on: Bool) {
        if on {
            guard assertion.acquire() else { return }
        } else {
            assertion.release()
        }
        if on != isEnabled {
            isEnabled = on
            onChange?(on)
        }
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
