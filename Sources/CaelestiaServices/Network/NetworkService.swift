import CoreWLAN
import Foundation
import Network
import SecurityFoundation
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
    /// Channel centre frequency (MHz) while connected.
    public var frequencyMHz: Int? = nil
    public init() {}

    /// 0...100 like NetworkManager's strength: -100 dBm is 0, -50 dBm and above is 100.
    public static func percent(fromRSSI rssi: Int) -> Int {
        guard rssi != 0 else { return 0 }
        return min(100, max(0, (rssi + 100) * 2))
    }

    /// Centre frequency of a Wi-Fi channel. `band`: 2 (2.4 GHz), 5 or 6.
    public static func frequency(channel: Int, band: Int) -> Int? {
        guard channel > 0 else { return nil }
        switch band {
        case 2: return channel == 14 ? 2484 : 2407 + 5 * channel
        case 5: return 5000 + 5 * channel
        case 6: return 5950 + 5 * channel
        default: return nil
        }
    }

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
    /// In this Mac's known (preferred) networks: joins without a password.
    public var known: Bool
    public init(ssid: String, rssi: Int, strength: Int, secured: Bool, isCurrent: Bool, known: Bool = false) {
        self.ssid = ssid
        self.rssi = rssi
        self.strength = strength
        self.secured = secured
        self.isCurrent = isCurrent
        self.known = known
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
        monitor.start(queue: DispatchQueue(label: "com.skyrose.mac.services.network", qos: .utility))
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
        let known = knownSSIDs()
        for k in best.keys where known.contains(k) { best[k]?.known = true }
        return best.values.sorted { ($0.isCurrent ? 1 : 0, $0.rssi) > ($1.isCurrent ? 1 : 0, $1.rssi) }
    }

    /// The SSIDs of this Mac's known networks (System Settings › Wi-Fi › Known Networks).
    public func knownSSIDs() -> Set<String> {
        guard let profiles = client.interface()?.configuration()?.networkProfiles.array as? [CWNetworkProfile] else { return [] }
        return Set(profiles.compactMap(\.ssid))
    }

    /// Joins `ssid`. A known network joins with the password macOS keeps; a new secured one needs
    /// `password`, which goes straight to CoreWLAN (macOS stores it in its keychain as System
    /// Settings does). SkyRose never stores or logs it.
    public func connect(ssid: String, password: String?) async throws {
        guard let name = client.interface()?.interfaceName else { throw ServiceError.unavailable("No Wi-Fi interface") }
        let known = knownSSIDs().contains(ssid)
        try await Task.detached(priority: .userInitiated) {
            guard let iface = CWWiFiClient.shared().interface(withName: name) else { throw ServiceError.unavailable("No Wi-Fi interface") }
            // A full scan, matched by name: a scan for one name misses phone hotspots and some
            // non-ASCII names. Hotspots can take a moment to answer, so look twice.
            var network: CWNetwork?
            for _ in 0..<2 where network == nil {
                let found = (try? iface.scanForNetworks(withSSID: nil)) ?? []
                network = found.filter { $0.ssid == ssid }.max(by: { $0.rssiValue < $1.rssiValue })
            }
            guard let network else { throw ServiceError.failed("\(ssid) is not in range") }
            let open = network.supportsSecurity(.none) || network.supportsSecurity(.OWE)
            let secret = password
            // A known network joins with the password macOS already has. SkyRose never reads the
            // System keychain itself (that shows an administrator prompt).
            if secret == nil, !open, known {
                if (try? iface.associate(to: network, password: nil)) != nil { return }
                // CoreWLAN can't reuse a stored password; macOS's own tool can, without a prompt.
                if NetworkService.joinKnown(ssid, interface: name), iface.ssid() == ssid { return }
                throw ServiceError.failed(NetworkService.needsPassword)
            }
            if secret == nil, !open { throw ServiceError.failed(NetworkService.needsPassword) }
            do {
                try iface.associate(to: network, password: open ? nil : secret)
            } catch {
                throw ServiceError.failed(password != nil ? "Couldn't join \(ssid). Check the password." : "Couldn't join \(ssid).")
            }
        }.value
        refresh()
    }

    /// `networksetup -setairportnetwork <if> <ssid>`: joins a known network with the password
    /// macOS keeps. Waits for it (up to 20 s); true when it exited cleanly.
    nonisolated static func joinKnown(_ ssid: String, interface: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-setairportnetwork", interface, ssid]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return false }
        let deadline = Date().addingTimeInterval(20)
        while p.isRunning, Date() < deadline { usleep(100_000) }
        if p.isRunning { p.terminate(); return false }
        // It prints "Could not find network …" / "Failed to join …" but still exits 0.
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return p.terminationStatus == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The error `connect` throws when a secured network has no password yet.
    public static let needsPassword = "This network needs a password."

    /// Leaves the current network (Wi-Fi stays on; macOS may rejoin a known network later).
    public func disconnect() {
        client.interface()?.disassociate()
        refresh()
    }

    /// Removes `ssid` from the known networks. Changing them needs an administrator, so macOS shows
    /// its password prompt; SkyRose never sees that password.
    public func forget(ssid: String) async throws {
        guard let iface = client.interface(), let current = iface.configuration() else { throw ServiceError.unavailable("No Wi-Fi interface") }
        let config = CWMutableConfiguration(configuration: current)
        let profiles = (config.networkProfiles.array as? [CWNetworkProfile]) ?? []
        let kept = profiles.filter { $0.ssid != ssid }
        guard kept.count < profiles.count else { throw ServiceError.failed("\(ssid) is not a known network") }
        config.networkProfiles = NSOrderedSet(array: kept)
        let auth = SFAuthorization.authorization() as? SFAuthorization
        do {
            try auth?.obtain(withRight: "system.preferences", flags: [.extendRights, .interactionAllowed, .preAuthorize])
        } catch {
            throw ServiceError.failed("Not forgotten: macOS needs an administrator to change known networks.")
        }
        do {
            try iface.commitConfiguration(config, authorization: auth)
        } catch {
            throw ServiceError.failed("Couldn't forget \(ssid): \(error.localizedDescription)")
        }
        refresh()
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
                if let ch = interface.wlanChannel() {
                    let band = ch.channelBand == .band2GHz ? 2 : (ch.channelBand == .band5GHz ? 5 : (ch.channelBand.rawValue == 3 ? 6 : 0))
                    s.frequencyMHz = NetworkState.frequency(channel: ch.channelNumber, band: band)
                }
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
