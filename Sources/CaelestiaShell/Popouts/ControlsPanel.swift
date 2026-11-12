import AppKit
import CaelestiaServices
import CoreAudio
import SwiftUI

/// What the Controls panel needs beyond `ShellState`: lists read when it opens, and its actions.
@MainActor
public final class ControlsModel: ObservableObject {
    @Published public var inputDevices: [AudioDevice] = []
    @Published public var inputSources: [InputSource] = []
    @Published public var extras: [MenuExtra] = []
    @Published public var extrasLoading = false
    /// nil: this Mac has no Night Shift.
    @Published public var nightShift: Bool?
    @Published public var brightnessAvailable = true
    @Published public var lowPowerBusy = false
    public var onSetInput: (AudioDeviceID) -> Void = { _ in }
    public var onInputSource: (String) -> Void = { _ in }
    public var onNightShift: (Bool) -> Void = { _ in }
    public var onLowPower: (Bool) -> Void = { _ in }
    public var onDND: (Bool) -> Void = { _ in }
    public var onFocusSettings: () -> Void = {}
    public var onAirDrop: () -> Void = {}
    public var onBrightness: (Double) -> Void = { _ in }
    public var onPlayPause: () -> Void = {}
    public var onNext: () -> Void = {}
    public var onPrevious: () -> Void = {}
    public var onRaisePlayer: () -> Void = {}
    public var onExtra: (MenuExtra) -> Void = { _ in }
    public var onShowMenuBar: () -> Void = {}
    /// Morphs the popout into another one (the full Wi-Fi / Bluetooth / sound panels).
    public var onOpen: (PopoutKind) -> Void = { _ in }
    public init() {}

    /// Rows of menu-bar app icons (seven per row).
    var extraRows: Int { max(1, (extras.count + 6) / 7) }
}

/// Control Center for a Mac whose menu bar is hidden: the toggles, sound, brightness, input
/// source, now playing and the other apps' menu-bar items.
struct ControlsPanel: View {
    @ObservedObject var model: PopoutModel
    @ObservedObject var controls: ControlsModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    /// Body height (fixed rows, so the window is sized before it shows).
    @MainActor static func height(_ c: ControlsModel, _ state: ShellState) -> Double {
        let header: Double = 38 + 10
        let tiles: Double = 3 * 46 + 2 * 8 + 10
        let sound: Double = 20 + 3 * 36 + 10
        var h: Double = header + tiles + sound
        if state.status.hasBattery { h += 28 }
        if c.brightnessAvailable { h += 40 }
        if c.inputSources.count > 1 { h += 40 }
        if state.media.available { h += 54 }
        let extras: Double = 26 + Double(c.extraRows) * 36
        return h + extras
    }

    var body: some View {
        let s = state.status
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MaterialIcon("tune", size: 16).foregroundStyle(theme[.onPrimaryContainer])
                    .frame(width: 38, height: 38).background(Circle().fill(theme[.primaryContainer]))
                Text("Controls").font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onSurface])
                Spacer(minLength: 0)
            }
            tiles
            if s.hasBattery {
                Text(batteryLine).font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1).frame(height: 18)
                    .accessibilityIdentifier("controls.battery")
            }
            sound
            if controls.brightnessAvailable {
                HSlider(value: s.brightness, icon: "sun.max.fill", onSet: controls.onBrightness)
                    .frame(height: 30).accessibilityLabel("Brightness")
            }
            if controls.inputSources.count > 1 { inputSource }
            if state.media.available { nowPlaying }
            extras
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("popout.controls")
    }

    private var batteryLine: String {
        let s = state.status
        var parts = ["Battery \(s.batteryPercent)%"]
        parts.append(s.batteryCharging ? "Charging" : (s.batteryPluggedIn ? "Plugged in" : "On battery"))
        if s.lowPowerMode { parts.append("Low Power Mode") }
        return parts.joined(separator: " · ")
    }

    // MARK: Toggles

    private var tiles: some View {
        let s = state.status
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ControlTile(icon: s.wifiEnabled ? "wifi" : "wifi_off", title: "Wi-Fi",
                        subtitle: !s.wifiEnabled ? "Off" : (s.ssid ?? (s.ethernetConnected ? "Ethernet" : "Not connected")),
                        on: s.wifiEnabled, enabled: s.wifiAvailable, action: { model.onWifi(!s.wifiEnabled) },
                        more: { controls.onOpen(.network) })
            ControlTile(icon: "bluetooth", title: "Bluetooth",
                        subtitle: !s.bluetoothAvailable ? "Unavailable" : (!s.bluetoothOn ? "Off" : connectedBluetooth),
                        on: s.bluetoothOn, enabled: s.bluetoothAvailable, action: { model.onBluetoothPower(!s.bluetoothOn) },
                        more: { controls.onOpen(.bluetooth) })
            ControlTile(icon: state.doNotDisturb ? "do_not_disturb_on" : "do_not_disturb_off", title: "Do Not Disturb",
                        subtitle: state.doNotDisturb ? "SkyRose toasts muted" : "Off",
                        on: state.doNotDisturb, action: { controls.onDND(!state.doNotDisturb) },
                        more: controls.onFocusSettings, moreHelp: "macOS Focus settings (no app may switch Focus)")
            ControlTile(icon: "nightlight", title: "Night Shift",
                        subtitle: controls.nightShift == nil ? "Not on this Mac" : (controls.nightShift == true ? "On" : "Off"),
                        on: controls.nightShift == true, enabled: controls.nightShift != nil,
                        action: { controls.onNightShift(!(controls.nightShift ?? false)) })
            ControlTile(icon: "battery_saver", title: "Low Power",
                        subtitle: controls.lowPowerBusy ? "Asking macOS…" : (s.lowPowerMode ? "On" : "Off"),
                        on: s.lowPowerMode, enabled: !controls.lowPowerBusy, action: { controls.onLowPower(!s.lowPowerMode) },
                        help: "macOS asks for an administrator password (pmset needs root)")
            ControlTile(icon: "share", title: "AirDrop", subtitle: "Open AirDrop", on: false, action: controls.onAirDrop,
                        help: "Opens the AirDrop window; who can see you is set at its bottom")
        }
    }

    private var connectedBluetooth: String {
        let c = state.status.bluetoothPaired.filter(\.connected)
        if c.isEmpty { return "On" }
        return c.count == 1 ? c[0].name : "\(c.count) devices"
    }

    // MARK: Sound

    private var sound: some View {
        let s = state.status
        return VStack(alignment: .leading, spacing: 6) {
            Text("Sound").font(theme.sans(12, weight: .semibold)).foregroundStyle(theme[.onSurfaceVariant]).frame(height: 20)
            HStack(spacing: 8) {
                HSlider(value: s.muted ? 0 : s.volume, icon: s.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", onSet: model.onVolume)
                    .accessibilityLabel("Volume")
                RoundIconButton(symbol: s.muted ? "speaker.slash.fill" : "speaker.fill", size: 30, action: model.onMute)
                    .help(s.muted ? "Unmute" : "Mute")
            }
            .frame(height: 30)
            picker(icon: "speaker.wave.2.fill", label: s.outputDeviceName.isEmpty ? "No output device" : s.outputDeviceName,
                   items: model.devices.map { d in (d.name, d.isDefault, { model.onSetOutput(d.id) }) }, a11y: "Output device")
            HStack(spacing: 8) {
                picker(icon: "mic.fill", label: s.inputDeviceName.isEmpty ? "No input device" : s.inputDeviceName,
                       items: controls.inputDevices.map { d in (d.name, d.isDefault, { controls.onSetInput(d.id) }) }, a11y: "Input device")
                RoundIconButton(symbol: s.micMuted ? "mic.slash.fill" : "mic.fill", size: 30, action: model.onMicMute)
                    .help(s.micMuted ? "Unmute the microphone" : "Mute the microphone")
            }
        }
    }

    private var inputSource: some View {
        let current = controls.inputSources.first(where: \.selected)?.name ?? state.status.keyboardLayout
        return picker(icon: "keyboard", label: current,
                      items: controls.inputSources.map { src in (src.name, src.selected, { controls.onInputSource(src.id) }) },
                      a11y: "Keyboard input source")
    }

    private func picker(icon: String, label: String, items: [(String, Bool, () -> Void)], a11y: String) -> some View {
        Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { item.2() } label: { if item.1 { Label(item.0, systemImage: "checkmark") } else { Text(item.0) } }
            }
        } label: {
            HStack(spacing: 8) {
                MaterialIcon(icon, size: 12).foregroundStyle(theme[.onSurfaceVariant]).frame(width: 18)
                Text(label).font(theme.sans(12.5)).foregroundStyle(theme[.onSurface]).lineLimit(1)
                Spacer(minLength: 4)
                MaterialIcon("expand_more", size: 12).foregroundStyle(theme[.onSurfaceVariant])
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme[.onSurface].opacity(0.06)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel("\(a11y): \(label)")
    }

    // MARK: Now playing

    private var nowPlaying: some View {
        let m = state.media
        return HStack(spacing: 8) {
            Button(action: controls.onRaisePlayer) {
                HStack(spacing: 8) {
                    if let icon = AppIconCache.icon(bundleID: m.playerBundleID) {
                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28)
                    } else {
                        MaterialIcon("music_note", size: 14).foregroundStyle(theme[.onSurfaceVariant]).frame(width: 28, height: 28)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(m.title.isEmpty ? "Nothing playing" : m.title).font(theme.sans(12.5, weight: .semibold))
                            .foregroundStyle(theme[.onSurface]).lineLimit(1)
                        Text(m.artist.isEmpty ? m.player : m.artist).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Bring \(m.player.isEmpty ? "the player" : m.player) forward")
            RoundIconButton(symbol: "skip_previous", size: 28, action: controls.onPrevious).accessibilityLabel("Previous")
            RoundIconButton(symbol: m.isPlaying ? "pause" : "play_arrow", size: 32, filled: true, action: controls.onPlayPause)
                .accessibilityLabel(m.isPlaying ? "Pause" : "Play")
            RoundIconButton(symbol: "skip_next", size: 28, action: controls.onNext).accessibilityLabel("Next")
        }
        .frame(height: 44)
    }

    // MARK: Menu-bar apps

    private var extras: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Menu bar apps").font(theme.sans(12, weight: .semibold)).foregroundStyle(theme[.onSurfaceVariant])
                Spacer()
                Button(action: controls.onShowMenuBar) {
                    HStack(spacing: 4) { Text("Show menu bar"); MaterialIcon("arrow_upward", size: 10, weight: .medium) }
                        .font(theme.sans(11, weight: .medium)).foregroundStyle(theme[.primary])
                }
                .buttonStyle(.plain).help("Shows the real macOS menu bar for 5 seconds (Super + Shift + B)")
            }
            .frame(height: 20)
            if controls.extras.isEmpty {
                Text(controls.extrasLoading ? "Reading menu bar items…"
                     : "No app menu bar items SkyRose can reach. Super + Shift + B shows the real menu bar for 5 seconds.")
                    .font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).frame(height: 36, alignment: .leading)
            } else {
                let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 7)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    ForEach(controls.extras) { e in ExtraButton(extra: e) { controls.onExtra(e) } }
                }
            }
        }
    }
}

private struct ControlTile: View {
    var icon: String
    var title: String
    var subtitle: String
    var on: Bool
    var enabled = true
    var action: () -> Void
    var more: (() -> Void)?
    var moreHelp = "More"
    var help: String?
    @State private var hover = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    MaterialIcon(icon, size: 14, weight: .medium, fill: on)
                        .foregroundStyle(on ? theme[.onPrimary] : theme[.onSurface])
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(on ? theme[.primary] : theme[.onSurface].opacity(0.1)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(theme.sans(12, weight: .semibold)).foregroundStyle(theme[.onSurface]).lineLimit(1)
                        Text(subtitle).font(theme.sans(10.5)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .help(help ?? title)
            .accessibilityLabel("\(title), \(subtitle)")
            if let more {
                Button(action: more) {
                    MaterialIcon("chevron_right", size: 13, weight: .medium).foregroundStyle(theme[.onSurfaceVariant])
                        .frame(width: 24, height: 46).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(moreHelp).accessibilityLabel("\(title): \(moreHelp)")
            }
        }
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(on ? theme[.primary].opacity(0.14) : theme[.onSurface].opacity(hover ? 0.09 : 0.06)))
        .opacity(enabled ? 1 : 0.5)
        .onHover { hover = $0 }
    }
}

private struct ExtraButton: View {
    var extra: MenuExtra
    var action: () -> Void
    @State private var hover = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        Button(action: action) {
            Group {
                if let icon = NSRunningApplication(processIdentifier: extra.pid)?.icon ?? AppIconCache.icon(bundleID: extra.bundleID) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                } else {
                    Text(String(extra.appName.prefix(1))).font(theme.sans(13, weight: .semibold)).foregroundStyle(theme[.onSurface])
                }
            }
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme[.onSurface].opacity(hover ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(extra.title == extra.appName ? extra.appName : "\(extra.appName): \(extra.title)")
        .accessibilityLabel("\(extra.appName) menu bar item")
    }
}
