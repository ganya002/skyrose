import Foundation
import IOKit.ps
import CaelestiaCore

/// Internal battery status. `hasBattery == false` on desktops; the bar hides the icon then.
public struct BatteryState: Hashable, Sendable {
    public var hasBattery: Bool = false
    /// 0...100.
    public var percent: Int = 0
    public var isCharging: Bool = false
    /// On AC power (charging, or full and plugged in).
    public var isPluggedIn: Bool = false
    /// Minutes to empty (on battery) or to full (charging); `nil` while macOS is still estimating.
    public var timeRemainingMinutes: Int? = nil
    public var isLowPowerMode: Bool = false
    public init() {}

    /// Builds the state from the `IOPSGetPowerSourceDescription` dictionaries of all power sources,
    /// taking the first internal battery. Pure, so tests can feed synthetic dictionaries.
    public static func parse(powerSources: [[String: Any]], lowPowerMode: Bool) -> BatteryState {
        var state = BatteryState()
        state.isLowPowerMode = lowPowerMode
        guard let battery = powerSources.first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }) else {
            return state
        }
        state.hasBattery = true
        let current = battery[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = battery[kIOPSMaxCapacityKey] as? Int ?? 100
        state.percent = max > 0 ? clamp(Int((Double(current) / Double(max) * 100).rounded()), 0...100) : current
        state.isCharging = battery[kIOPSIsChargingKey] as? Bool ?? false
        state.isPluggedIn = (battery[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let key = state.isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        if let minutes = battery[key] as? Int, minutes >= 0 {
            state.timeRemainingMinutes = minutes
        }
        return state
    }
}

/// IOKit power-source watcher. `IOPSNotificationCreateRunLoopSource` fires on every change (plug,
/// unplug, percent, estimate), and `ProcessInfo` posts low-power-mode changes; nothing polls.
@MainActor
public final class BatteryService {
    public private(set) var state = BatteryState()
    public var onChange: ((BatteryState) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            onMain { service.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            onMain { self.refresh() }
        }
        refresh()
    }

    public func stop() {
        guard running else { return }
        running = false
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        if let observer = lowPowerObserver {
            NotificationCenter.default.removeObserver(observer)
            lowPowerObserver = nil
        }
    }

    /// Reads the power sources now.
    public func refresh() {
        let s = BatteryState.parse(powerSources: Self.powerSourceDescriptions(), lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if s != state {
            state = s
            onChange?(s)
        }
    }

    /// `IOPSGetPowerSourceDescription` for every power source.
    nonisolated static func powerSourceDescriptions() -> [[String: Any]] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return list.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
    }
}
