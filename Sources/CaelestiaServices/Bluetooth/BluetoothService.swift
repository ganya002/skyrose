import AppKit
import Foundation
import IOBluetooth
import CaelestiaCore

/// Bluetooth radio state plus the names of connected devices (for the bar tooltip/popout).
public struct BluetoothState: Hashable, Sendable {
    public var poweredOn: Bool = false
    public var connectedDevices: [String] = []
    /// Every paired device, connected first.
    public var paired: [BluetoothDevice] = []
    /// Set when this Mac has no Bluetooth controller.
    public var unavailableReason: String? = nil
    public init() {}
}

/// A paired (or, while scanning, a nearby) device.
public struct BluetoothDevice: Hashable, Sendable, Identifiable {
    public var id: String { address }
    public var address: String
    public var name: String
    public var connected: Bool
    /// "headphones", "keyboard", "mouse", "phone", "computer", "speaker" or "device".
    public var kind: String
    /// Battery %, when the device reports it (main, or left/right/case for earbuds).
    public var battery: [String: Int] = [:]
    public init(address: String, name: String, connected: Bool, kind: String, battery: [String: Int] = [:]) {
        self.address = address
        self.name = name
        self.connected = connected
        self.kind = kind
        self.battery = battery
    }

    /// Kind from the Bluetooth class of device (major / minor class).
    public static func kind(major: UInt32, minor: UInt32) -> String {
        switch major {
        case 0x01: return "computer"
        case 0x02: return "phone"
        case 0x04: return (minor == 0x01 || minor == 0x02 || minor == 0x06) ? "headphones" : "speaker"
        case 0x05:
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "mouse" }
            return "device"
        default: return "device"
        }
    }

    /// Battery levels from `system_profiler SPBluetoothDataType -json`, by address.
    public static func batteries(fromProfilerJSON data: Data) -> [String: [String: Int]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var out: [String: [String: Int]] = [:]
        let keys = ["device_batteryLevelMain": "main", "device_batteryLevel": "main", "device_batteryLevelLeft": "left",
                    "device_batteryLevelRight": "right", "device_batteryLevelCase": "case"]
        for item in items {
            for group in ["device_connected", "device_not_connected"] {
                for entry in (item[group] as? [[String: Any]]) ?? [] {
                    for (_, value) in entry {
                        guard let info = value as? [String: Any], let address = info["device_address"] as? String else { continue }
                        var levels: [String: Int] = [:]
                        for (k, name) in keys {
                            if let text = info[k] as? String, let n = Int(text.filter(\.isNumber)) { levels[name] = n }
                        }
                        if !levels.isEmpty { out[normalised(address)] = levels }
                    }
                }
            }
        }
        return out
    }

    /// "80%" / "L 80% R 75% Case 40%" / "" (no battery reported).
    public static func batteryText(_ d: BluetoothDevice) -> String {
        if let m = d.battery["main"] { return "\(m)%" }
        return [("L", "left"), ("R", "right"), ("Case", "case")].compactMap { l, k in d.battery[k].map { "\(l) \($0)%" } }.joined(separator: " ")
    }

    /// "AA:BB:…" upper case (IOBluetooth writes "aa-bb-…").
    public static func normalised(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }
}

/// What the Bluetooth panel is doing.
public enum BluetoothJob: Equatable, Sendable {
    case idle
    case connecting(String)
    case disconnecting(String)
    case pairing(String)
    /// The device shows this number: confirm it matches.
    case confirm(String, UInt32)
    /// The device wants a PIN typed here.
    case pin(String)
    case removing(String)
    case failed(String)
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
    private var batteries: [String: [String: Int]] = [:]
    private var batteriesReadAt: Date?
    private var pairing: BluetoothPairing?
    private var inquiry: BluetoothInquiry?
    /// Nearby, not yet paired devices while `scanning`.
    public private(set) var nearby: [BluetoothDevice] = []
    public private(set) var scanning = false
    public private(set) var job: BluetoothJob = .idle {
        didSet { onJob?(job) }
    }
    public var onJob: ((BluetoothJob) -> Void)?
    public var onNearby: (([BluetoothDevice], Bool) -> Void)?
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

    // MARK: Control

    /// Turns the radio on/off. There is no public API for this; IOBluetooth's own
    /// `IOBluetoothPreferenceSetControllerPowerState` (what blueutil uses) does it without root.
    public func setPower(_ on: Bool) throws {
        typealias SetPower = @convention(c) (Int32) -> Void
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW),
              let sym = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else {
            throw ServiceError.unavailable("This macOS has no Bluetooth power switch for apps")
        }
        unsafeBitCast(sym, to: SetPower.self)(on ? 1 : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    /// Reads battery levels (system_profiler, ~1 s, off the main thread), then refreshes. At most
    /// every 30 s unless `force` (after a connect), since hovering the bar asks each time.
    public func refreshBatteries(force: Bool = false) {
        if !force, let last = batteriesReadAt, Date().timeIntervalSince(last) < 30 { return }
        batteriesReadAt = Date()
        Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let levels = BluetoothDevice.batteries(fromProfilerJSON: data)
            await MainActor.run { [weak self] in
                guard let self, levels != self.batteries else { return }
                self.batteries = levels
                self.state = BluetoothState()
                self.refresh()
            }
        }
    }

    private func device(_ address: String) -> IOBluetoothDevice? {
        IOBluetoothDevice(addressString: address.replacingOccurrences(of: ":", with: "-"))
    }

    /// Connects a paired device (asynchronous; `job` follows it).
    public func connect(_ address: String) {
        guard let d = device(address) else { job = .failed("Unknown device"); return }
        let name = d.name ?? address
        job = .connecting(name)
        // The target comes back as an argument: capturing it here would be a retain cycle.
        let target = ConnectionTarget { [weak self] done, status in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in self?.connectionTargets.removeAll { $0 === done } }
            self.job = status == kIOReturnSuccess ? .idle : .failed("Couldn't connect \(name). Is it on and nearby?")
            self.refresh()
            self.refreshBatteries(force: true)
        }
        connectionTargets.append(target)
        let r = d.openConnection(target)
        if r != kIOReturnSuccess {
            connectionTargets.removeAll { $0 === target }
            job = .failed("Couldn't connect \(name).")
        }
    }
    private var connectionTargets: [ConnectionTarget] = []

    public func disconnect(_ address: String) {
        guard let d = device(address) else { return }
        job = .disconnecting(d.name ?? address)
        let r = d.closeConnection()
        job = r == kIOReturnSuccess ? .idle : .failed("Couldn't disconnect \(d.name ?? address).")
        refresh()
    }

    /// Removes a paired device. IOBluetooth has no public call; `-[IOBluetoothDevice remove]`
    /// is the one System Settings and blueutil use.
    public func forget(_ address: String) {
        guard let d = device(address) else { return }
        let name = d.name ?? address
        let sel = NSSelectorFromString("remove")
        guard d.responds(to: sel) else { job = .failed("This macOS can't remove devices from apps. Use Bluetooth settings."); return }
        job = .removing(name)
        if d.isConnected() { d.closeConnection() }
        _ = d.perform(sel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            // `remove` returns nothing useful: whether the device is still paired is the result.
            let stillPaired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
                .contains { BluetoothDevice.normalised($0.addressString ?? "") == BluetoothDevice.normalised(address) }
            self.job = stillPaired ? .failed("Couldn't forget \(name). Try Bluetooth settings.") : .idle
            self.refresh()
        }
    }

    /// Looks for nearby devices to pair (classic Bluetooth inquiry, up to 15 s).
    public func startScan() {
        guard inquiry == nil else { return }
        nearby = []
        scanning = true
        onNearby?(nearby, true)
        let pairedAddresses = Set(state.paired.map(\.address))
        let i = BluetoothInquiry(
            found: { [weak self] d in
                guard let self else { return }
                let address = BluetoothDevice.normalised(d.addressString ?? "")
                guard !address.isEmpty, !pairedAddresses.contains(address), !self.nearby.contains(where: { $0.address == address }) else { return }
                self.nearby.append(BluetoothDevice(address: address, name: d.name ?? address, connected: false,
                                                   kind: BluetoothDevice.kind(major: d.deviceClassMajor, minor: d.deviceClassMinor)))
                self.onNearby?(self.nearby, true)
            },
            done: { [weak self] in
                guard let self else { return }
                // Released on the next turn, never inside the inquiry's own callback.
                let finished = self.inquiry
                DispatchQueue.main.async { withExtendedLifetime(finished) {} }
                self.inquiry = nil
                self.scanning = false
                self.onNearby?(self.nearby, false)
            })
        inquiry = i
        if !i.start() { inquiry = nil; scanning = false; onNearby?(nearby, false); job = .failed("Couldn't scan. Is Bluetooth on?") }
    }

    public func stopScan() { inquiry?.stop() }

    /// Pairs a nearby device; PIN and number-confirm requests come back through `job`.
    public func pair(_ address: String) {
        guard let d = device(address) else { return }
        stopScan()
        let name = d.name ?? address
        job = .pairing(name)
        let p = BluetoothPairing(device: d, event: { [weak self] event in
            guard let self else { return }
            switch event {
            case .pin: self.job = .pin(name)
            case .confirm(let n): self.job = .confirm(name, n)
            case .finished(let ok):
                let finished = self.pairing
                DispatchQueue.main.async { withExtendedLifetime(finished) {} }
                self.pairing = nil
                self.job = ok ? .idle : .failed("Pairing with \(name) failed.")
                self.nearby.removeAll { $0.address == address }
                self.onNearby?(self.nearby, self.scanning)
                self.refresh()
                if ok { self.connect(address) }
            }
        })
        pairing = p
        if !p.start() { pairing = nil; job = .failed("Couldn't start pairing with \(name).") }
    }

    /// Answers the device's PIN request.
    public func sendPIN(_ pin: String) { pairing?.reply(pin: pin) }

    /// Answers "does this number match?".
    public func confirm(_ matches: Bool) { pairing?.reply(confirm: matches) }

    public func cancelPairing() {
        pairing?.cancel()
        pairing = nil
        job = .idle
    }

    public func refresh() {
        var s = BluetoothState()
        if let controller = IOBluetoothHostController.default() {
            s.poweredOn = controller.powerState == kBluetoothHCIPowerStateON
            let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            s.connectedDevices = paired.filter { $0.isConnected() }.compactMap { $0.name }.sorted()
            s.paired = paired.map { d in
                let address = BluetoothDevice.normalised(d.addressString ?? "")
                return BluetoothDevice(address: address, name: d.name ?? address, connected: d.isConnected(),
                                       kind: BluetoothDevice.kind(major: d.deviceClassMajor, minor: d.deviceClassMinor),
                                       battery: batteries[address] ?? [:])
            }
            .sorted { ($0.connected ? 0 : 1, $0.name.lowercased()) < ($1.connected ? 0 : 1, $1.name.lowercased()) }
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

/// `IOBluetoothDevice.openConnection(_:)` calls back on this object.
private final class ConnectionTarget: NSObject {
    private let done: @MainActor (ConnectionTarget, IOReturn) -> Void
    init(_ done: @escaping @MainActor (ConnectionTarget, IOReturn) -> Void) { self.done = done }
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        let done = self.done
        nonisolated(unsafe) let me = self
        onMain { MainActor.assumeIsolated { done(me, status) } }
    }
}

/// Classic Bluetooth inquiry (nearby devices in pairing mode).
private final class BluetoothInquiry: NSObject, IOBluetoothDeviceInquiryDelegate {
    private let found: @MainActor (IOBluetoothDevice) -> Void
    private let done: @MainActor () -> Void
    private var inquiry: IOBluetoothDeviceInquiry?

    init(found: @escaping @MainActor (IOBluetoothDevice) -> Void, done: @escaping @MainActor () -> Void) {
        self.found = found
        self.done = done
    }

    func start() -> Bool {
        guard let i = IOBluetoothDeviceInquiry(delegate: self) else { return false }
        i.inquiryLength = 15
        i.updateNewDeviceNames = true
        inquiry = i
        return i.start() == kIOReturnSuccess
    }

    func stop() { inquiry?.stop() }

    /// IOBluetoothDeviceInquiry keeps an unretained delegate and touches it in its dealloc: detach
    /// first, so freeing this object never leaves it pointing at freed memory.
    deinit {
        inquiry?.delegate = nil
        inquiry?.stop()
    }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let device else { return }
        let found = self.found
        onMain { MainActor.assumeIsolated { found(device) } }
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        deviceInquiryDeviceFound(sender, device: device)
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        sender?.delegate = nil
        let done = self.done
        onMain { MainActor.assumeIsolated { done() } }
    }
}

/// `IOBluetoothDevicePair` with its delegate: PIN entry and numeric comparison.
private final class BluetoothPairing: NSObject, IOBluetoothDevicePairDelegate {
    enum Event { case pin, confirm(UInt32), finished(Bool) }
    private let pair: IOBluetoothDevicePair?
    private let event: @MainActor (Event) -> Void

    init(device: IOBluetoothDevice, event: @escaping @MainActor (Event) -> Void) {
        pair = IOBluetoothDevicePair(device: device)
        self.event = event
        super.init()
        pair?.delegate = self
    }

    func start() -> Bool { pair?.start() == kIOReturnSuccess }
    func cancel() { pair?.stop() }

    deinit { pair?.delegate = nil }

    func reply(pin: String) {
        var code = BluetoothPINCode()
        let bytes = Array(pin.utf8.prefix(16))
        withUnsafeMutableBytes(of: &code) { raw in for (i, b) in bytes.enumerated() { raw[i] = b } }
        pair?.replyPINCode(bytes.count, pinCode: &code)
    }

    func reply(confirm: Bool) { pair?.replyUserConfirmation(confirm) }

    private func send(_ e: Event) {
        let event = self.event
        onMain { MainActor.assumeIsolated { event(e) } }
    }

    func devicePairingPINCodeRequest(_ sender: Any!) { send(.pin) }
    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) { send(.confirm(numericValue)) }
    func devicePairingFinished(_ sender: Any!, error: IOReturn) { send(.finished(error == kIOReturnSuccess)) }
}
