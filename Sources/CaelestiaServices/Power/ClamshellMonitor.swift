import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.ps
import CaelestiaCore

/// Lid state for the shell, read without root: IOPMrootDomain's `AppleClamshellState` /
/// `AppleClamshellCausesSleep`, the providing power source and the online external displays.
/// Refreshes on root-domain interest messages (lid open/close), power-source changes and display
/// reconfiguration; nothing polls.
///
/// With `keepAwakeWhenClosed` it holds its own `PreventUserIdleDisplaySleep` assertion while the
/// lid is closed. It only reads `SleepDisabled` (IOPMrootDomain); `LidSleepControl` sets it.
@MainActor
public final class ClamshellMonitor {
    public private(set) var facts = ClamshellFacts(hasLid: false, lidClosed: false, onAC: true, externalDisplays: 0)
    public var onChange: ((ClamshellFacts) -> Void)?
    /// `clamshell.keepAwake`.
    public var keepAwakeWhenClosed = false { didSet { applyAssertion() } }
    public var isHoldingKeepAwake: Bool { assertion.isHeld }

    private let assertion = PowerAssertion(name: "SkyRose clamshell keep awake")
    private var rootDomain: io_service_t = 0
    private var notifyPort: IONotificationPortRef?
    private var interest: io_object_t = 0
    private var powerSource: CFRunLoopSource?
    private var screenObserver: NSObjectProtocol?
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if rootDomain != 0, let port = IONotificationPortCreate(kIOMainPortDefault) {
            notifyPort = port
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
            let context = Unmanaged.passUnretained(self).toOpaque()
            // Any root-domain message (clamshell change, sleep/wake, power source) re-reads.
            IOServiceAddInterestNotification(port, rootDomain, kIOGeneralInterest, { context, _, _, _ in
                guard let context else { return }
                let monitor = Unmanaged<ClamshellMonitor>.fromOpaque(context).takeUnretainedValue()
                onMain { monitor.refresh() }
            }, context, &interest)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<ClamshellMonitor>.fromOpaque(context).takeUnretainedValue()
            onMain { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            onMain { self.refresh() }
        }
        refresh()
    }

    public func stop() {
        guard running else { return }
        running = false
        if interest != 0 { IOObjectRelease(interest); interest = 0 }
        if let port = notifyPort { IONotificationPortDestroy(port); notifyPort = nil }
        if rootDomain != 0 { IOObjectRelease(rootDomain); rootDomain = 0 }
        if let source = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode); powerSource = nil }
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        assertion.release()
    }

    public func refresh() {
        let new = Self.read(rootDomain: rootDomain)
        let changed = new != facts
        facts = new
        applyAssertion()
        if changed { onChange?(new) }
    }

    private func applyAssertion() {
        if Clamshell.holdsKeepAwake(facts, enabled: keepAwakeWhenClosed) {
            _ = assertion.acquire()
        } else {
            assertion.release()
        }
    }

    // MARK: Reading

    static func read(rootDomain: io_service_t) -> ClamshellFacts {
        let lid = rootDomain == 0 ? nil : boolProperty(rootDomain, "AppleClamshellState")
        let causesSleep = rootDomain == 0 ? nil : boolProperty(rootDomain, "AppleClamshellCausesSleep")
        // `pmset disablesleep` state, published by the root domain (same value as `pmset -g`).
        let sleepDisabled = rootDomain == 0 ? false : (boolProperty(rootDomain, "SleepDisabled") ?? false)
        return ClamshellFacts(hasLid: lid != nil, lidClosed: lid ?? false, closingCausesSleep: causesSleep,
                              onAC: onACPower(), externalDisplays: externalDisplayCount(), sleepDisabled: sleepDisabled)
    }

    private static func boolProperty(_ entry: io_registry_entry_t, _ key: String) -> Bool? {
        guard let v = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return (v as? Bool) ?? (v as? NSNumber)?.boolValue
    }

    private static func onACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPMACPowerKey
    }

    /// Online (not only active) displays, so a mirrored or asleep external still counts.
    private static func externalDisplayCount() -> Int {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return 0 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return 0 }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.count
    }
}
