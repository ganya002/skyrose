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
    /// Where the bar items with a hover popout sit in the bar window (top-left space). The
    /// controller hit-tests its pointer monitor against these: SwiftUI hover does not reach a
    /// non-activating panel while another app is active.
    public var itemFrames: [String: CGRect] = [:]

    func setItemFrame(_ id: String, _ frame: CGRect?) { itemFrames[id] = frame }

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
                ActiveWindowColumn(window: state.activeWindow?.displayID == model.displayID || state.focusedDisplayID == model.displayID ? state.activeWindow : nil,
                                   report: { model.setItemFrame("activeWindow", $0) })
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
                StatusColumn(state: state, onTap: model.onStatus, report: model.setItemFrame)
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
            MaterialIcon(symbol, size: size * theme.uiScale, weight: .medium)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(theme[.onSurface].opacity(hover ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(theme.small, value: hover)
    }
}

/// Workspace pills (spec 5.2, Caelestia Workspace.qml): each workspace is a shape (active: a
/// large dot, occupied: a small square, empty: a faint dot) followed by its windows' app icons
/// (at most `WorkspacePill.maxWindowIcons`). The active indicator is a primary capsule behind the
/// active workspace whose two ends move separately (Caelestia ActiveIndicator.qml with
/// `activeTrail`): the leading end on the default spatial token, the trailing end 1.5× slower,
/// so it stretches towards the new workspace and then catches up.
struct WorkspacesColumn: View {
    var pills: [WorkspacePill]
    var special: String?
    var onFocus: (Int) -> Void
    @Environment(\.shellTheme) var theme
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var placed = false

    static let shape: Double = 22
    static let icon: Double = 16
    static let iconGap: Double = 2
    static let spacing: Double = 2
    static let padding: Double = 6

    /// Height of one workspace: the shape plus its icons (Caelestia: + extraSmall padding).
    static func height(of pill: WorkspacePill) -> Double {
        pill.apps.isEmpty ? shape : shape + Double(pill.apps.count) * (icon + iconGap) + 4
    }

    /// Top and bottom of the active workspace inside the column (nil: none is active).
    static func activeSpan(_ pills: [WorkspacePill]) -> (start: Double, end: Double)? {
        var y = padding
        for p in pills {
            let h = height(of: p)
            if p.active { return (y, y + h) }
            y += h + spacing
        }
        return nil
    }

    /// Leading and trailing durations for a move from `old` to `new` (Caelestia: the edge in the
    /// direction of travel leads).
    static func trailDurations(goingUp: Bool, leading: Double) -> (start: Double, end: Double) {
        let trailing = leading * 1.5
        return goingUp ? (leading, trailing) : (trailing, leading)
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(pills) { pill in
                Button { onFocus(pill.id) } label: { item(pill) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bar.workspace.\(pill.id)")
                    .help("Workspace \(pill.name)")
            }
            if let special {
                MaterialIcon("sparkles", size: 11, weight: .semibold)
                    .foregroundStyle(theme[.tertiary])
                    .frame(width: 30, height: Self.shape)
                    .help("Special workspace \(special)")
            }
        }
        .padding(.vertical, Self.padding)
        .frame(width: 34)
        .background(alignment: .top) {
            if end > start {
                Capsule().fill(theme[.primary])
                    .frame(width: 30, height: end - start)
                    .offset(y: start)
            }
        }
        .background(Capsule().fill(theme[.surfaceContainer].opacity(theme.layerAlpha + 0.4)))
        .animation(theme.spatial, value: pills)
        .onAppear { moveIndicator(animated: false) }
        .onChange(of: pills) { _, _ in moveIndicator(animated: true) }
    }

    @ViewBuilder func item(_ pill: WorkspacePill) -> some View {
        let fg = pill.active ? theme[.onPrimary] : (pill.occupied ? theme[.onSurface] : theme[.onSurfaceVariant].opacity(0.4))
        VStack(spacing: Self.iconGap) {
            ZStack {
                if pill.active {
                    Circle().fill(fg).frame(width: 10, height: 10)
                } else if pill.occupied {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(fg).frame(width: 6, height: 6)
                } else {
                    Circle().fill(fg).frame(width: 5, height: 5)
                }
            }
            .frame(height: Self.shape)
            ForEach(Array(pill.apps.enumerated()), id: \.offset) { _, bundleID in
                Group {
                    if let image = AppIconCache.icon(bundleID: bundleID) {
                        Image(nsImage: image).resizable().interpolation(.high)
                    } else {
                        MaterialIcon("macwindow", size: 11).foregroundStyle(fg)
                    }
                }
                .frame(width: Self.icon, height: Self.icon)
                .saturation(pill.active || pill.occupied ? 1 : 0.4)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            if !pill.apps.isEmpty { Color.clear.frame(height: 4 - Self.iconGap) }
        }
        .frame(width: 30, height: Self.height(of: pill), alignment: .top)
        .contentShape(Rectangle())
    }

    private func moveIndicator(animated: Bool) {
        guard let span = Self.activeSpan(pills) else {
            withAnimation(theme.small) { end = start }
            return
        }
        guard animated, placed, !theme.reduceMotion else {
            var t = Transaction()
            t.animation = theme.reduceMotion && placed ? theme.small : nil
            withTransaction(t) { start = span.start; end = span.end }
            placed = true
            return
        }
        let d = Self.trailDurations(goingUp: span.start < start, leading: CaelestiaTokens.Duration.defaultSpatial)
        withAnimation(theme.token(.defaultSpatial, ms: d.start)) { start = span.start }
        withAnimation(theme.token(.defaultSpatial, ms: d.end)) { end = span.end }
    }
}

/// App icon + the window title as rotated vertical text.
struct ActiveWindowColumn: View {
    var window: ActiveWindowInfo?
    var report: (CGRect?) -> Void = { _ in }
    @Environment(\.shellTheme) var theme

    var body: some View {
        VStack(spacing: 8) {
            if let window {
                if let icon = AppIconCache.icon(bundleID: window.bundleID) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 22, height: 22)
                }
                let title = window.title.isEmpty ? window.appName : window.title
                // A 220×20 box rotated about its centre fills a 20×220 frame only when it is centred
                // in it; leading-aligned text then reads from the top. ActiveWindow.qml: primary.
                Text(title)
                    .font(theme.sans(13, weight: .medium))
                    .foregroundStyle(theme[.primary])
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 220, height: 20, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 220)
                    .accessibilityIdentifier("bar.activeWindow")
            }
        }
        .frame(width: 34)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report(window == nil ? nil : $0) }
        .onChange(of: window == nil) { _, none in if none { report(nil) } }
        .onDisappear { report(nil) }
    }
}

struct ClockColumn: View {
    var now: Date
    var onTap: () -> Void = {}
    @Environment(\.shellTheme) var theme

    var body: some View {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        VStack(spacing: 2) {
            MaterialIcon("calendar", size: 14, weight: .medium)
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
    var report: (String, CGRect?) -> Void = { _, _ in }
    @Environment(\.shellTheme) var theme

    var body: some View {
        let enabled = state.config.bar.statusIcons.filter(\.enabled).map(\.id) + (state.config.bar.controlsButton ? ["controls"] : [])
        VStack(spacing: 10) {
            ForEach(enabled, id: \.self) { id in
                if let symbol = symbol(for: id) {
                    StatusIconButton(symbol: symbol, hasPopout: PopoutKind.forStatusIcon(id) != nil,
                                     report: { report(id, $0) }) { midY in onTap(id, midY) }
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
        case "controls": return "tune"
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
        case "controls": return "Controls: Wi-Fi, Bluetooth, sound, brightness, Night Shift, menu bar apps"
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
    var report: (CGRect?) -> Void = { _ in }
    var onTap: (Double) -> Void
    @State private var midY: Double = 0
    @State private var hover = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        Button { if hasPopout { onTap(midY) } } label: {
            MaterialIcon(symbol, size: 14, weight: .medium)
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if hasPopout { report($0) } }
        .onDisappear { report(nil) }
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
