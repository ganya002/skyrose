import CoreWLAN
import Foundation
import Network
import CaelestiaCore

/// Wi-Fi / Ethernet status for the bar icon and the network popout.
public struct NetworkState: Hashable, Sendable {
    public var wifiEnabled: Bool = false
    public var wifiConnected: Bool = false
    /// `nil` while connected means macOS hid it (see `ssidUnavailableReason`); the bar then shows "Connected".
    public var ssid: String? = nil
    /// "Location permission" when macOS 14+ withholds the SSID/BSSID until Location access is granted.
    public var ssidUnavailableReason: String? = nil
    /// 0...4 bars from RSSI (`NetworkState.strength(fromRSSI:)`).
    public var wifiStrength: Int = 0
    public var rssi: Int? = nil
    public var ethernetConnected: Bool = false
    public var wifiInterfaceName: String? = nil
    /// Set when this Mac has no Wi-Fi interface at all.
    public var unavailableReason: String? = nil
    public init() {}

    /// Maps dBm to 0...4 bars (the thresholds nmcli/iwd use for their 5-level icons).
    public static func strength(fromRSSI rssi: Int) -> Int {
        switch rssi {
        case 0: return 0
        case ..<(-80): return 1
        case ..<(-70): return 2
        case ..<(-60): return 3
        default: return 4
        }
    }
}

/// One scan result for the Wi-Fi popout.
public struct WiFiNetwork: Hashable, Sendable, Identifiable {
    public var id: String { ssid }
    public var ssid: String
    public var rssi: Int
    public var strength: Int
    public var secured: Bool
    public var isCurrent: Bool
    public init(ssid: String, rssi: Int, strength: Int, secured: Bool, isCurrent: Bool) {
        self.ssid = ssid
        self.rssi = rssi
        self.strength = strength
        self.secured = secured
        self.isCurrent = isCurrent
    }
}

/// CoreWLAN + NWPathMonitor network status. Wi-Fi events (power, SSID, link) come from
/// `CWEventDelegate`; reachability of Wi-Fi/Ethernet from `NWPathMonitor`; no polling.
///
/// Permission notes: on macOS 14+ `CWInterface.ssid()` returns `nil` unless the process has
/// Location permission. The state then carries `ssidUnavailableReason = "Location permission"`
/// and the shell shows "Connected" instead of a name (spec 5.2).
@MainActor
public final class NetworkService {
    public private(set) var state = NetworkState()
    public var onChange: ((NetworkState) -> Void)?

    private let client = CWWiFiClient.shared()
    private var pathMonitor: NWPathMonitor?
    private var eventSink: WiFiEventSink?
    private var lastPath: NWPath?
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        let sink = WiFiEventSink { [weak self] in self?.refresh() }
        eventSink = sink
        client.delegate = sink
        for event: CWEventType in [.powerDidChange, .ssidDidChange, .linkDidChange, .bssidDidChange] {
            do {
                try client.startMonitoringEvent(with: event)
            } catch {
                Log.services.debug("CoreWLAN event \(event.rawValue) not monitorable: \(error.localizedDescription, privacy: .public)")
            }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            onMain {
                self.lastPath = path
                self.refresh()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.caelestia.mac.services.network", qos: .utility))
        pathMonitor = monitor
        refresh()
    }

    public func stop() {
        guard running else { return }
        running = false
        pathMonitor?.cancel()
        pathMonitor = nil
        try? client.stopMonitoringAllEvents()
        client.delegate = nil
        eventSink = nil
    }

    /// Turns the Wi-Fi radio on/off (CoreWLAN `setPower`, no privileges needed).
    public func setWifi(on: Bool) throws {
        guard let interface = client.interface() else { throw ServiceError.unavailable("No Wi-Fi interface") }
        do {
            try interface.setPower(on)
        } catch {
            throw ServiceError.failed("Wi-Fi power change failed: \(error.localizedDescription)")
        }
        refresh()
    }

    /// Scans for networks (slow, 2–5 s; runs off the main thread). SSIDs are hidden without
    /// Location permission, in which case the result is empty and the error explains why.
    public func availableNetworks() async throws -> [WiFiNetwork] {
        guard let interface = client.interface() else { throw ServiceError.unavailable("No Wi-Fi interface") }
        let currentSSID = interface.ssid()
        let name = interface.interfaceName ?? ""
        let scanned: [(ssid: String?, rssi: Int, open: Bool)] = try await Task.detached(priority: .utility) {
            guard let iface = CWWiFiClient.shared().interface(withName: name) else { throw ServiceError.unavailable("No Wi-Fi interface") }
            let networks: Set<CWNetwork>
            do {
                networks = try iface.scanForNetworks(withSSID: nil)
            } catch {
                throw ServiceError.failed("Wi-Fi scan failed: \(error.localizedDescription)")
            }
            return networks.map { ($0.ssid, $0.rssiValue, $0.supportsSecurity(.none)) }
        }.value
        var best: [String: WiFiNetwork] = [:]
        var hidden = 0
        for entry in scanned {
            guard let ssid = entry.ssid, !ssid.isEmpty else { hidden += 1; continue }
            let candidate = WiFiNetwork(
                ssid: ssid, rssi: entry.rssi, strength: NetworkState.strength(fromRSSI: entry.rssi), secured: !entry.open,
                isCurrent: ssid == currentSSID)
            if let existing = best[ssid], existing.rssi >= candidate.rssi { continue }
            best[ssid] = candidate
        }
        if best.isEmpty, hidden > 0 {
            throw ServiceError.permissionMissing("Location")
        }
        return best.values.sorted { ($0.isCurrent ? 1 : 0, $0.rssi) > ($1.isCurrent ? 1 : 0, $1.rssi) }
    }

    /// Re-reads CoreWLAN and the last NWPath into `state`.
    public func refresh() {
        var s = NetworkState()
        if let path = lastPath {
            s.ethernetConnected = path.status == .satisfied && path.usesInterfaceType(.wiredEthernet)
        }
        if let interface = client.interface() {
            s.wifiInterfaceName = interface.interfaceName
            s.wifiEnabled = interface.powerOn()
            let ssid = interface.ssid()
            let rssi = interface.rssiValue()
            let pathSaysWifi = lastPath.map { $0.status == .satisfied && $0.usesInterfaceType(.wifi) } ?? false
            let associated = ssid != nil || (s.wifiEnabled && (rssi != 0 || interface.wlanChannel() != nil))
            s.wifiConnected = s.wifiEnabled && (pathSaysWifi || associated)
            if s.wifiConnected {
                s.ssid = ssid
                s.rssi = rssi
                s.wifiStrength = rssi == 0 ? 4 : NetworkState.strength(fromRSSI: rssi)
                if ssid == nil { s.ssidUnavailableReason = "Location permission" }
            }
        } else {
            s.unavailableReason = "No Wi-Fi interface"
        }
        if s != state {
            state = s
            onChange?(s)
        }
    }
}

/// NSObject shim for `CWEventDelegate` (ObjC protocol); forwards every event to the main actor.
private final class WiFiEventSink: NSObject, CWEventDelegate {
    private let changed: @MainActor @Sendable () -> Void
    init(changed: @escaping @MainActor @Sendable () -> Void) { self.changed = changed }

    private func fire() {
        let changed = self.changed
        onMain { changed() }
    }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { fire() }
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { fire() }
    func bssidDidChangeForWiFiInterface(withName interfaceName: String) { fire() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { fire() }
    func clientConnectionInterrupted() { fire() }
    func clientConnectionInvalidated() { fire() }
}
