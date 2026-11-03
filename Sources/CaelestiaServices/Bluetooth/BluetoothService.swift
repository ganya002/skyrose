import AppKit
import Foundation
import IOBluetooth
import CaelestiaCore

/// Bluetooth radio state plus the names of connected devices (for the bar tooltip/popout).
public struct BluetoothState: Hashable, Sendable {
    public var poweredOn: Bool = false
    public var connectedDevices: [String] = []
    /// Set when this Mac has no Bluetooth controller.
    public var unavailableReason: String? = nil
    public init() {}
}

/// IOBluetooth status. Power changes arrive as `IOBluetoothHostControllerPoweredOn/Off`
/// notifications, connections through `IOBluetoothDevice.register(forConnectNotifications:)`;
/// nothing polls. There is no public API to toggle the radio, so the quick toggle opens the
/// Bluetooth pane of System Settings (`openSettings()`), as spec 5.5 asks.
@MainActor
public final class BluetoothService {
    /// Deep link to System Settings → Bluetooth.
    public static let settingsDeepLink = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!

    public private(set) var state = BluetoothState()
    public var onChange: ((BluetoothState) -> Void)?

    private var sink: BluetoothEventSink?
    private var observers: [NSObjectProtocol] = []
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        let sink = BluetoothEventSink { [weak self] in self?.refresh() }
        self.sink = sink
        sink.register()
        for name in [Notification.Name.IOBluetoothHostControllerPoweredOn, .IOBluetoothHostControllerPoweredOff] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                onMain { self.refresh() }
            })
        }
        refresh()
    }

    public func stop() {
        guard running else { return }
        running = false
        sink?.unregister()
        sink = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    /// Opens System Settings → Bluetooth (no private toggling).
    public func openSettings() {
        NSWorkspace.shared.open(Self.settingsDeepLink)
    }

    public func refresh() {
        var s = BluetoothState()
        if let controller = IOBluetoothHostController.default() {
            s.poweredOn = controller.powerState == kBluetoothHCIPowerStateON
            let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            s.connectedDevices = paired.filter { $0.isConnected() }.compactMap { $0.name }.sorted()
            sink?.watchDisconnects(of: paired.filter { $0.isConnected() })
        } else {
            s.unavailableReason = "No Bluetooth controller"
        }
        if s != state {
            state = s
            onChange?(s)
        }
    }
}

/// NSObject target for the selector-based IOBluetooth notifications.
private final class BluetoothEventSink: NSObject {
    private let changed: @MainActor @Sendable () -> Void
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    init(changed: @escaping @MainActor @Sendable () -> Void) { self.changed = changed }

    func register() {
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func unregister() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    func watchDisconnects(of devices: [IOBluetoothDevice]) {
        for device in devices {
            let key = device.addressString ?? device.name ?? ""
            guard disconnectNotifications[key] == nil else { continue }
            if let note = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
                disconnectNotifications[key] = note
            }
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        fire()
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let key = device.addressString ?? device.name ?? ""
        disconnectNotifications[key]?.unregister()
        disconnectNotifications[key] = nil
        fire()
    }

    private func fire() {
        let changed = self.changed
        onMain { changed() }
    }
}
