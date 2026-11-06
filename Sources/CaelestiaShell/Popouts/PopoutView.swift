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

@MainActor
public final class PopoutModel: ObservableObject {
    @Published public var shown = false
    @Published public var kind: PopoutKind = .audio
    @Published public var devices: [AudioDevice] = []
    @Published public var networks: [WiFiNetwork] = []
    @Published public var scanning = false
    @Published public var scanMessage: String?
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
        case .network: return 190 + Double(min(networks.count, 6)) * 38 + (scanMessage == nil ? 0 : 40)
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
                }
                Button(action: model.onScan) {
                    HStack { Text(model.scanning ? "Scanning..." : "Scan for networks"); Spacer(); MaterialIcon("refresh", size: 12, weight: .medium) }
                        .font(theme.sans(12, weight: .medium)).foregroundStyle(theme[.primary])
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme[.onSurface].opacity(0.07)))
                }.buttonStyle(.plain).disabled(model.scanning || !s.wifiEnabled)
                if let m = model.scanMessage {
                    Text(m).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.networks.prefix(6)) { n in
                    HStack {
                        MaterialIcon("wifi", size: 13).foregroundStyle(n.isCurrent ? theme[.primary] : theme[.onSurfaceVariant])
                        Text(n.ssid).font(theme.sans(13, weight: n.isCurrent ? .semibold : .regular)).foregroundStyle(theme[.onSurface]).lineLimit(1)
                        Spacer()
                        if n.secured { MaterialIcon("lock.fill", size: 10).foregroundStyle(theme[.onSurfaceVariant]) }
                    }.frame(height: 30).padding(.horizontal, 6)
                }
            }
            Spacer(minLength: 0)
            SettingsLink(title: "Open Network settings") { model.onOpenSettings(.network) }
        }
        .accessibilityIdentifier("popout.network")
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
