import AppKit
import CaelestiaCore
import CaelestiaServices
import CoreAudio
import SwiftUI

public enum PopoutKind: String, CaseIterable, Sendable {
    case audio, network, bluetooth, battery
    /// Hovering the bar's active-window column: the window's preview (Caelestia ActiveWindow popout).
    case activeWindow

    /// Body width (Caelestia popout sizes: active window 400, audio / network 320, battery 250).
    public var width: Double {
        switch self {
        case .activeWindow: return 400
        case .audio, .network: return 320
        case .bluetooth: return 300
        case .battery: return 250
        }
    }

    /// What hovering a bar item shows (nil: nothing). Ids as `BarModel.onHover` reports them.
    public static func forBarItem(_ id: String) -> PopoutKind? {
        id == "activeWindow" ? .activeWindow : forStatusIcon(id)
    }

    /// Which popout a bar status icon opens (nil: the icon has none).
    public static func forStatusIcon(_ id: String) -> PopoutKind? {
        switch id {
        case "audio", "microphone": return .audio
        case "network": return .network
        case "bluetooth": return .bluetooth
        case "battery": return .battery
        default: return nil
        }
    }
}

/// What the Wi-Fi panel is doing right now.
public enum WiFiJob: Equatable, Sendable {
    case idle
    case connecting(String)
    case disconnecting
    case forgetting(String)
    case joined(String)
    case failed(String, String)
}

@MainActor
public final class PopoutModel: ObservableObject {
    @Published public var shown = false
    @Published public var kind: PopoutKind = .audio
    @Published public var devices: [AudioDevice] = []
    @Published public var networks: [WiFiNetwork] = []
    @Published public var scanning = false
    @Published public var scanMessage: String?
    /// Opened by a click (the full Wi-Fi panel) rather than a hover (Caelestia's summary).
    @Published public var expanded = false
    @Published public var wifiJob: WiFiJob = .idle
    /// The network whose password field is open.
    @Published public var passwordFor: String?
    @Published public var locationMissing = false
    public var onConnect: (String, String?) -> Void = { _, _ in }
    public var onDisconnect: () -> Void = {}
    public var onForget: (String) -> Void = { _ in }
    public var onAllowLocation: () -> Void = {}
    /// The window the active-window popout shows, and its captured preview.
    @Published public var window: ActiveWindowInfo?
    @Published public var preview: CGImage?
    public var previewWindowID: UInt32 = 0
    public var onSetOutput: (AudioDeviceID) -> Void = { _ in }
    public var onVolume: (Double) -> Void = { _ in }
    public var onMute: () -> Void = {}
    public var onMicMute: () -> Void = {}
    public var onWifi: (Bool) -> Void = { _ in }
    public var onScan: () -> Void = {}
    public var onOpenSettings: (PopoutKind) -> Void = { _ in }
    public init() {}

    /// Body height per kind (rows are fixed height so the window can be sized before it shows).
    public func bodyHeight(for kind: PopoutKind) -> Double {
        switch kind {
        case .audio: return 150 + Double(min(devices.count, 6)) * 40
        case .network:
            guard expanded else { return 96 }
            return 222 + Double(min(networks.count, 6)) * 40 + (scanMessage == nil ? 0 : 44) + (locationMissing ? 34 : 0)
                + (passwordFor == nil ? 0 : 92) + (wifiJob == .idle ? 0 : 24)
        case .bluetooth: return 150
        case .battery: return 170
        case .activeWindow: return 74 + Self.previewHeight
        }
    }

    /// The preview's height inside a 400 pt popout (16:10 of the content width).
    public static let previewHeight: Double = ((PopoutKind.activeWindow.width - 16) * 10 / 16).rounded()
}

struct PopoutView: View {
    @ObservedObject var model: PopoutModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme
    let fillet: Double

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                DrawerBackground(edge: .left, fillet: fillet, radius: theme.frameRounding, shown: model.shown, depth: model.kind.width)
                Group {
                    switch model.kind {
                    case .audio: AudioPopout(model: model, state: state)
                    case .network: NetworkPopout(model: model, state: state)
                    case .bluetooth: BluetoothPopout(model: model, state: state)
                    case .battery: BatteryPopout(model: model, state: state)
                    case .activeWindow: ActiveWindowPopout(model: model)
                    }
                }
                // Moving between bar items morphs the one popout; its content cross-fades.
                .id(model.kind)
                .transition(.opacity)
                .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, fillet + 4)
                .liquidContent(edge: .left, shown: model.shown, depth: model.kind.width, theme: theme)
            }
            .frame(width: model.kind.width)
            .animation(theme.small, value: model.kind)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct PopHeader: View {
    var icon: String
    var title: String
    var subtitle: String
    @Environment(\.shellTheme) var theme
    var body: some View {
        HStack(spacing: 10) {
            MaterialIcon(icon, size: 16).foregroundStyle(theme[.onPrimaryContainer])
                .frame(width: 38, height: 38).background(Circle().fill(theme[.primaryContainer]))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onSurface])
                Text(subtitle).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsLink: View {
    var title: String
    var action: () -> Void
    @Environment(\.shellTheme) var theme
    var body: some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); MaterialIcon("arrow_outward", size: 12, weight: .medium) }
                .font(theme.sans(12, weight: .medium)).foregroundStyle(theme[.primary])
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme[.onSurface].opacity(0.07)))
        }.buttonStyle(.plain)
    }
}

/// The focused window: app icon, title, app name and a live capture of the window.
private struct ActiveWindowPopout: View {
    @ObservedObject var model: PopoutModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let w = model.window, let icon = AppIconCache.icon(bundleID: w.bundleID) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 38, height: 38)
                } else {
                    MaterialIcon("macwindow", size: 16).foregroundStyle(theme[.onPrimaryContainer])
                        .frame(width: 38, height: 38).background(Circle().fill(theme[.primaryContainer]))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.window.map { $0.title.isEmpty ? $0.appName : $0.title } ?? "No window")
                        .font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onSurface]).lineLimit(1)
                    Text(model.window?.appName ?? "Nothing is focused").font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous).fill(theme[.surfaceContainer].opacity(theme.layerAlpha + 0.3))
                if let image = model.preview {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(6)
                        .transition(.opacity)
                } else {
                    MaterialIcon("macwindow", size: 28).foregroundStyle(theme[.onSurfaceVariant].opacity(0.6))
                }
            }
            .frame(height: PopoutModel.previewHeight)
            .animation(theme.small, value: model.preview != nil)
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("popout.activeWindow")
    }
}

private struct AudioPopout: View {
    @ObservedObject var model: PopoutModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopHeader(icon: state.status.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: "Sound output",
                      subtitle: state.status.outputDeviceName.isEmpty ? "No output device" : state.status.outputDeviceName)
            HStack(spacing: 8) {
                HSlider(value: state.status.muted ? 0 : state.status.volume, icon: state.status.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", onSet: model.onVolume)
                RoundIconButton(symbol: state.status.muted ? "speaker.slash.fill" : "speaker.fill", size: 30, action: model.onMute)
            }
            if model.devices.isEmpty {
                Text("No output devices found").font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant])
            }
            ForEach(model.devices.prefix(6)) { d in
                Button { model.onSetOutput(d.id) } label: {
                    HStack {
                        MaterialIcon(d.isDefault ? "checkmark.circle.fill" : "circle", size: 13).foregroundStyle(d.isDefault ? theme[.primary] : theme[.onSurfaceVariant])
                        Text(d.name).font(theme.sans(13, weight: d.isDefault ? .semibold : .regular)).foregroundStyle(theme[.onSurface]).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme[.onSurface].opacity(d.isDefault ? 0.1 : 0.04)))
                }.buttonStyle(.plain).accessibilityIdentifier("popout.audio.device")
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("popout.audio")
    }
}

private struct NetworkPopout: View {
    @ObservedObject var model: PopoutModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        if model.expanded { NetworkPanel(model: model, state: state) } else { summary }
    }

    /// Caelestia's hover popout: three plain lines.
    private var summary: some View {
        let s = state.status
        return VStack(alignment: .leading, spacing: 12) {
            if s.ethernetConnected {
                line("Connected to: Ethernet")
            } else if !s.wifiAvailable {
                line("No Wi-Fi interface")
            } else if !s.wifiEnabled {
                line("Wi-Fi is off")
            } else if s.wifiConnected {
                line("Connected to: \(s.ssid ?? "")")
                line("Strength: \(s.wifiPercent)/100")
                line("Frequency: \(s.wifiFrequencyMHz.map { "\($0) MHz" } ?? "unknown")")
            } else {
                line("Not connected")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12).padding(.top, 4)
        .accessibilityIdentifier("popout.network")
    }

    private func line(_ text: String) -> some View {
        Text(text).font(theme.sans(14)).foregroundStyle(theme[.onSurface]).lineLimit(1)
    }
}

/// The full Wi-Fi panel (a click on the bar's network icon): power, scan, join, leave, forget.
private struct NetworkPanel: View {
    @ObservedObject var model: PopoutModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme
    @State private var password = ""
    @State private var reveal = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let s = state.status
        VStack(alignment: .leading, spacing: 10) {
            PopHeader(icon: s.ethernetConnected ? "cable.connector" : (s.wifiEnabled ? "wifi" : "wifi.slash"),
                      title: s.ethernetConnected ? "Ethernet" : "Wi-Fi",
                      subtitle: !s.wifiAvailable ? "No Wi-Fi interface" : (!s.wifiEnabled ? "Off" : (s.wifiConnected ? (s.ssid ?? "Connected") : "Not connected")))
            if s.wifiAvailable {
                HStack {
                    Text("Wi-Fi").font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurface])
                    Spacer()
                    Toggle("", isOn: Binding(get: { s.wifiEnabled }, set: { model.onWifi($0) })).toggleStyle(.switch).labelsHidden().tint(theme[.primary])
                        .accessibilityLabel("Wi-Fi")
                }
                Button(action: model.onScan) {
                    HStack { Text(model.scanning ? "Scanning…" : "Scan for networks"); Spacer(); MaterialIcon("refresh", size: 12, weight: .medium) }
                        .font(theme.sans(12, weight: .medium)).foregroundStyle(theme[.primary])
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme[.onSurface].opacity(0.07)))
                }.buttonStyle(.plain).disabled(model.scanning || !s.wifiEnabled)
                if let m = model.scanMessage {
                    Text(m).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                }
                if model.locationMissing {
                    Button("Allow Location", action: model.onAllowLocation)
                        .buttonStyle(.plain).font(theme.sans(12, weight: .semibold)).foregroundStyle(theme[.onPrimary])
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(theme[.primary]))
                }
                job
                ForEach(model.networks.prefix(6)) { n in row(n, connected: s.wifiConnected && n.isCurrent) }
                if let ssid = model.passwordFor { passwordField(ssid) }
            }
            Spacer(minLength: 0)
            SettingsLink(title: "Open Network settings") { model.onOpenSettings(.network) }
        }
        .animation(theme.small, value: model.passwordFor)
        .animation(theme.small, value: model.wifiJob)
        .accessibilityIdentifier("popout.network")
    }

    @ViewBuilder private var job: some View {
        switch model.wifiJob {
        case .idle: EmptyView()
        case .connecting(let n): status("Connecting to \(n)…", theme[.onSurfaceVariant])
        case .disconnecting: status("Disconnecting…", theme[.onSurfaceVariant])
        case .forgetting(let n): status("Forgetting \(n)…", theme[.onSurfaceVariant])
        case .joined(let n): status("Connected to \(n)", theme[.primary])
        case .failed(_, let m): status(m, theme[.error])
        }
    }

    private func status(_ text: String, _ color: Color) -> some View {
        Text(text).font(theme.sans(11.5, weight: .medium)).foregroundStyle(color).lineLimit(1).frame(height: 16)
            .accessibilityIdentifier("wifi.status")
    }

    private func busy(_ ssid: String) -> Bool {
        switch model.wifiJob {
        case .connecting(let n), .forgetting(let n): return n == ssid
        default: return false
        }
    }

    private func row(_ n: WiFiNetwork, connected: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                if connected { return }
                if n.secured, !n.known {
                    password = ""; reveal = false
                    model.passwordFor = n.ssid
                    fieldFocused = true
                } else {
                    model.passwordFor = nil
                    model.onConnect(n.ssid, nil)
                }
            } label: {
                HStack(spacing: 8) {
                    WifiBars(strength: n.strength).foregroundStyle(connected ? theme[.primary] : theme[.onSurfaceVariant])
                    Text(n.ssid).font(theme.sans(13, weight: connected ? .semibold : .regular)).foregroundStyle(theme[.onSurface]).lineLimit(1)
                    if n.secured { MaterialIcon("lock.fill", size: 10).foregroundStyle(theme[.onSurfaceVariant]) }
                    Spacer(minLength: 4)
                    if busy(n.ssid) {
                        ProgressView().controlSize(.small)
                    } else if connected {
                        Text("Connected").font(theme.sans(11)).foregroundStyle(theme[.primary])
                    } else if n.known {
                        Text("Known").font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant])
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(n.ssid), \(n.secured ? "secured" : "open"), \(connected ? "connected" : (n.known ? "known" : "new"))")
            if connected {
                iconButton("xmark", "Disconnect from \(n.ssid)", action: model.onDisconnect)
            }
            if n.known {
                iconButton("trash", "Forget \(n.ssid)") { model.onForget(n.ssid) }
            }
        }
        .frame(height: 32).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(connected ? theme[.primary].opacity(0.10) : .clear))
    }

    private func iconButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MaterialIcon(icon, size: 11, weight: .semibold).foregroundStyle(theme[.onSurfaceVariant])
                .frame(width: 24, height: 24).background(Circle().fill(theme[.onSurface].opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func passwordField(_ ssid: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password for \(ssid)").font(theme.sans(11.5, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
            HStack(spacing: 6) {
                Group {
                    if reveal { TextField("Password", text: $password) } else { SecureField("Password", text: $password) }
                }
                .textFieldStyle(.plain).font(theme.sans(13)).foregroundStyle(theme[.onSurface])
                .focused($fieldFocused)
                .onSubmit(join)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme[.onSurface].opacity(0.07)))
                .accessibilityIdentifier("wifi.password")
                iconButton(reveal ? "eye.slash" : "eye", reveal ? "Hide password" : "Show password") { reveal.toggle() }
            }
            HStack {
                Button("Cancel") { password = ""; model.passwordFor = nil }
                    .buttonStyle(.plain).font(theme.sans(12, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
                Spacer()
                Button("Join", action: join)
                    .buttonStyle(.plain).font(theme.sans(12, weight: .semibold)).foregroundStyle(theme[.onPrimary])
                    .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(theme[.primary]))
                    .disabled(password.isEmpty)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private func join() {
        guard let ssid = model.passwordFor, !password.isEmpty else { return }
        let secret = password
        password = ""
        model.onConnect(ssid, secret)
    }
}

/// Four signal bars, the lit ones by strength (0...4).
private struct WifiBars: View {
    var strength: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1).frame(width: 3, height: 4 + Double(i) * 3).opacity(i < strength ? 1 : 0.25)
            }
        }
        .frame(width: 18, height: 14, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct BluetoothPopout: View {
    @ObservedObject var model: PopoutModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        let s = state.status
        VStack(alignment: .leading, spacing: 10) {
            PopHeader(icon: "dot.radiowaves.left.and.right", title: "Bluetooth",
                      subtitle: !s.bluetoothAvailable ? "No Bluetooth controller" : (s.bluetoothOn ? "On" : "Off"))
            if s.bluetoothDevices.isEmpty {
                Text(s.bluetoothOn ? "No connected devices" : "Turn Bluetooth on in System Settings").font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant])
            }
            ForEach(s.bluetoothDevices.prefix(5), id: \.self) { d in
                HStack { MaterialIcon("checkmark.circle.fill", size: 13).foregroundStyle(theme[.primary]); Text(d).font(theme.sans(13)).foregroundStyle(theme[.onSurface]).lineLimit(1); Spacer() }
            }
            Spacer(minLength: 0)
            SettingsLink(title: "Open Bluetooth settings") { model.onOpenSettings(.bluetooth) }
        }
        .accessibilityIdentifier("popout.bluetooth")
    }
}

private struct BatteryPopout: View {
    @ObservedObject var model: PopoutModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        let s = state.status
        VStack(alignment: .leading, spacing: 10) {
            PopHeader(icon: s.batteryCharging ? "battery.100percent.bolt" : "battery.75percent", title: "Battery \(s.batteryPercent)%", subtitle: BatteryText.status(s))
            ZStack(alignment: .leading) {
                Capsule().fill(theme[.onSurface].opacity(0.1))
                GeometryReader { g in Capsule().fill(s.batteryPercent <= 15 && !s.batteryCharging ? theme[.error] : theme[.primary]).frame(width: g.size.width * Double(s.batteryPercent) / 100) }
            }.frame(height: 10)
            Spacer(minLength: 0)
            SettingsLink(title: "Open Battery settings") { model.onOpenSettings(.battery) }
        }
        .accessibilityIdentifier("popout.battery")
    }
}
