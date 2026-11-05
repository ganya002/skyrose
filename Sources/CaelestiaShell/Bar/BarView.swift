import AppKit
import CaelestiaCore
import SwiftUI

/// Per-bar observable bits that are not part of the shared `ShellState`.
@MainActor
public final class BarModel: ObservableObject {
    public let displayID: String
    /// 0 = hidden (slid out to the left), 1 = shown.
    @Published public var reveal: Double = 0
    @Published public var now = Date()
    public var onLogo: () -> Void = {}
    public var onPower: () -> Void = {}
    public var onWorkspace: (Int) -> Void = { _ in }
    public var onScrollWorkspace: (Int) -> Void = { _ in }
    public var onTray: () -> Void = {}
    public var onClock: () -> Void = {}
    /// A status icon was clicked: its id and the vertical centre in the bar window (top-left space).
    public var onStatus: (String, Double) -> Void = { _, _ in }

    public init(displayID: String) {
        self.displayID = displayID
    }
}

/// The left vertical bar (spec 5.2), top to bottom: logo, workspaces, active window, tray, clock,
/// status icons, power. No background of its own: the screen frame draws the band behind it.
struct BarView: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: BarModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        let width = theme.barWidth
        let bar = state.config.bar
        VStack(spacing: 0) {
            if bar.showLogo {
                BarIconButton(symbol: "apple.logo", size: 18, color: theme[.primary], action: model.onLogo)
                    .padding(.top, 14)
                    .accessibilityIdentifier("bar.logo")
            } else {
                Color.clear.frame(height: 14)
            }
            if bar.showWorkspaces {
                WorkspacesColumn(pills: state.workspaces[model.displayID] ?? [], special: state.openSpecial[model.displayID],
                                 onFocus: model.onWorkspace)
                    .padding(.top, 12)
                    .background(ScrollCatcher(onScroll: model.onScrollWorkspace))
            }
            if bar.showActiveWindow {
                ActiveWindowColumn(window: state.activeWindow?.displayID == model.displayID || state.focusedDisplayID == model.displayID ? state.activeWindow : nil)
                    .padding(.top, 14)
            }
            Spacer(minLength: 8)
            if bar.showTray {
                BarIconButton(symbol: "menubar.rectangle", size: 14, color: theme[.onSurfaceVariant], action: model.onTray)
                    .help("Show the macOS menu bar (menu-bar extras)")
                    .accessibilityIdentifier("bar.tray")
            }
            if bar.showClock {
                ClockColumn(now: model.now, onTap: model.onClock)
                    .padding(.top, 12)
            }
            if bar.showStatusIcons {
                StatusColumn(state: state, onTap: model.onStatus)
                    .padding(.top, 12)
            }
            if bar.showPower {
                BarIconButton(symbol: "power", size: 16, color: theme[.error], action: model.onPower)
                    .padding(.top, 10)
                    .accessibilityIdentifier("bar.power")
            }
            Color.clear.frame(height: 14)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .offset(x: BarMotion.contentOffset(reveal: model.reveal, width: width))
        .opacity(model.reveal <= 0.001 ? 0 : 1)
    }
}

struct BarIconButton: View {
    var symbol: String
    var size: Double
    var color: Color
    var action: () -> Void
    @State private var hover = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * theme.uiScale, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(theme[.onSurface].opacity(hover ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(theme.small, value: hover)
    }
}

/// Workspace pills (spec 5.2): active = primary pill that stretches, occupied = dot, empty = a
/// faint dot. The indicator slides between slots on the fast spatial curve.
struct WorkspacesColumn: View {
    var pills: [WorkspacePill]
    var special: String?
    var onFocus: (Int) -> Void
    @Environment(\.shellTheme) var theme
    @Namespace private var ns

    static let slot: Double = 22
    static let activeSlot: Double = 40

    var body: some View {
        VStack(spacing: 2) {
            ForEach(pills) { pill in
                Button { onFocus(pill.id) } label: {
                    ZStack {
                        if pill.active {
                            Capsule().fill(theme[.primary])
                                .matchedGeometryEffect(id: "active", in: ns)
                                .frame(width: 14, height: Self.activeSlot - 8)
                        } else {
                            Circle()
                                .fill(pill.occupied ? theme[.onSurface] : theme[.onSurfaceVariant].opacity(0.35))
                                .frame(width: pill.occupied ? 6 : 4, height: pill.occupied ? 6 : 4)
                        }
                    }
                    .frame(width: 30, height: pill.active ? Self.activeSlot : Self.slot)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bar.workspace.\(pill.id)")
                .help("Workspace \(pill.name)")
            }
            if let special {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme[.tertiary])
                    .frame(width: 30, height: Self.slot)
                    .help("Special workspace \(special)")
            }
        }
        .padding(.vertical, 6)
        .frame(width: 34)
        .background(Capsule().fill(theme[.surfaceContainer].opacity(theme.layerAlpha + 0.4)))
        .animation(theme.fastSpatial, value: pills)
    }
}

/// App icon + the window title as rotated vertical text.
struct ActiveWindowColumn: View {
    var window: ActiveWindowInfo?
    @Environment(\.shellTheme) var theme

    var body: some View {
        VStack(spacing: 8) {
            if let window {
                if let icon = AppIconCache.icon(bundleID: window.bundleID) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 22, height: 22)
                }
                let title = window.title.isEmpty ? window.appName : window.title
                Text(title)
                    .font(theme.sans(13, weight: .medium))
                    .foregroundStyle(theme[.onSurface])
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 220, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 220, alignment: .top)
                    .clipped()
                    .accessibilityIdentifier("bar.activeWindow")
            }
        }
        .frame(width: 34)
    }
}

struct ClockColumn: View {
    var now: Date
    var onTap: () -> Void = {}
    @Environment(\.shellTheme) var theme

    var body: some View {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        VStack(spacing: 2) {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme[.tertiary])
                .padding(.bottom, 4)
            Text(String(format: "%02d", c.hour ?? 0))
            Text(String(format: "%02d", c.minute ?? 0))
        }
        .font(theme.sans(14, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(theme[.tertiary])
        .contentShape(Rectangle())
        .overlay(Button(action: onTap) { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain))
        .help("Open the dashboard")
        .accessibilityIdentifier("bar.clock")
    }
}

/// Status icons in a pill: Caps Lock (only while on), audio, network, Bluetooth, keyboard layout,
/// battery, in the order and with the switches of `bar.statusIcons`.
struct StatusColumn: View {
    @ObservedObject var state: ShellState
    var onTap: (String, Double) -> Void = { _, _ in }
    @Environment(\.shellTheme) var theme

    var body: some View {
        let enabled = state.config.bar.statusIcons.filter(\.enabled).map(\.id)
        VStack(spacing: 10) {
            ForEach(enabled, id: \.self) { id in
                if let symbol = symbol(for: id) {
                    StatusIconButton(symbol: symbol, hasPopout: PopoutKind.forStatusIcon(id) != nil) { midY in onTap(id, midY) }
                        .accessibilityIdentifier("bar.status.\(id)")
                        .help(help(for: id))
                }
            }
        }
        .padding(.vertical, 10)
        .frame(width: 34)
        .background(Capsule().fill(theme[.surfaceContainer].opacity(theme.layerAlpha + 0.4)))
    }

    func symbol(for id: String) -> String? {
        let s = state.status
        switch id {
        case "lockStatus": return state.capsLockOn ? "capslock.fill" : nil
        case "audio":
            if s.muted || s.volume <= 0 { return "speaker.slash.fill" }
            return s.volume < 0.34 ? "speaker.wave.1.fill" : (s.volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        case "microphone": return s.micMuted ? "mic.slash.fill" : "mic.fill"
        case "network":
            if s.ethernetConnected { return "cable.connector" }
            if !s.wifiEnabled { return "wifi.slash" }
            return s.wifiConnected ? "wifi" : "wifi.exclamationmark"
        case "bluetooth": return s.bluetoothOn ? "dot.radiowaves.left.and.right" : nil
        case "kbLayout": return "keyboard"
        case "battery":
            guard s.hasBattery else { return nil }
            if s.batteryCharging { return "battery.100percent.bolt" }
            let p = s.batteryPercent
            return p > 87 ? "battery.100percent" : p > 62 ? "battery.75percent" : p > 37 ? "battery.50percent" : p > 12 ? "battery.25percent" : "battery.0percent"
        default: return nil
        }
    }

    func help(for id: String) -> String {
        let s = state.status
        switch id {
        case "audio": return s.muted ? "Muted" : "Volume \(Int((s.volume * 100).rounded()))%"
        case "network": return s.ssid ?? (s.wifiConnected ? "Connected" : "Not connected")
        case "battery": return "\(s.batteryPercent)%"
        case "kbLayout": return s.keyboardLayout
        default: return id
        }
    }
}

/// Scroll over the workspaces switches workspace (spec 5.2).
struct ScrollCatcher: NSViewRepresentable {
    var onScroll: (Int) -> Void

    func makeNSView(context: Context) -> ScrollCatcherView {
        let v = ScrollCatcherView()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ v: ScrollCatcherView, context: Context) { v.onScroll = onScroll }

    final class ScrollCatcherView: NSView {
        var onScroll: (Int) -> Void = { _ in }
        private var accumulated: Double = 0
        override func scrollWheel(with event: NSEvent) {
            accumulated += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
            if abs(accumulated) >= 30 {
                onScroll(accumulated > 0 ? -1 : 1)
                accumulated = 0
            }
            if event.phase == .ended || event.momentumPhase == .ended { accumulated = 0 }
        }
    }
}

/// App icons by bundle id (NSWorkspace lookups are slow enough to matter per frame).
@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }

    static func icon(url: URL) -> NSImage {
        let key = url.path
        if let hit = cache[key] { return hit }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[key] = image
        return image
    }
}


/// A status icon; clicking opens its utilities popout (audio, network, Bluetooth, battery).
struct StatusIconButton: View {
    var symbol: String
    var hasPopout: Bool
    var onTap: (Double) -> Void
    @State private var midY: Double = 0
    @State private var hover = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        Button { if hasPopout { onTap(midY) } } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme[.onSurface])
                .frame(width: 28, height: 22)
                .background(Capsule().fill(theme[.onSurface].opacity(hover && hasPopout ? 0.1 : 0)))
                .background(GeometryReader { g in
                    Color.clear.onAppear { midY = g.frame(in: .global).midY }
                        .onChange(of: g.frame(in: .global).midY) { _, v in midY = v }
                })
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Where the bar's content sits for a reveal: slid out to the left below 1; past 1 (the reveal
/// spring's swing) it moves right by half the band's swell so it stays centred in the band.
enum BarMotion {
    static func contentOffset(reveal: Double, width: Double) -> Double {
        if reveal <= 1 { return -(1 - reveal) * width }
        return (min(reveal, LiquidMotion.barSwellCap) - 1) * width / 2
    }
}
