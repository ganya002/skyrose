import AppKit
import CaelestiaCore
import SwiftUI

@MainActor
public final class DashboardModel: ObservableObject {
    @Published public var shown = false
    @Published public var tab: DashboardTab = .overview
    @Published public var monthOffset = 0
    @Published public var now = Date()
    /// Scale and body size chosen by the controller for the display the drawer is on.
    @Published public var scale: Double = 1
    public var onPlayPause: () -> Void = {}
    public var onNext: () -> Void = {}
    public var onPrevious: () -> Void = {}
    public init() {}
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme
    let fillet: Double

    private var design: CGSize { ShellSizing.dashboardDesign }

    var body: some View {
        let s = model.scale
        let body = CGSize(width: design.width * s, height: design.height * s)
        VStack(spacing: 0) {
            ZStack {
                FrostedShape(shape: DrawerShape(edge: .top, radius: theme.frameRounding, fillet: fillet), theme: theme)
                content
                    .frame(width: design.width, height: design.height)
                    .scaleEffect(s, anchor: .center)
                    .frame(width: body.width, height: body.height)
            }
            .frame(width: body.width + 2 * fillet, height: body.height)
            .offset(y: model.shown ? 0 : -(body.height + 4))
            .animation(model.shown ? theme.drawerOpen : theme.drawerClose, value: model.shown)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DashboardTab.allCases, id: \.self) { tab in
                    TabButton(tab: tab, selected: model.tab == tab) { withAnimation(theme.small) { model.tab = tab } }
                }
            }
            .frame(height: 62)
            Rectangle().fill(theme[.outlineVariant].opacity(0.5)).frame(height: 1).padding(.horizontal, 12)
            Group {
                switch model.tab {
                case .overview: OverviewTab(model: model, state: state)
                case .media: MediaTab(state: state, model: model)
                case .performance: PerformanceTab(state: state)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxHeight: .infinity)
            .id(model.tab)
            .transition(.opacity)
        }
        .padding(.top, 8)
    }
}

private struct TabButton: View {
    var tab: DashboardTab
    var selected: Bool
    var action: () -> Void
    @Environment(\.shellTheme) var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon).font(.system(size: 15, weight: .medium))
                Text(tab.title).font(theme.sans(13, weight: .medium))
                Rectangle().fill(selected ? theme[.primary] : .clear).frame(height: 2).padding(.horizontal, 22)
            }
            .foregroundStyle(selected ? theme[.primary] : theme[.onSurfaceVariant])
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.tab.\(tab.rawValue)")
    }
}

// MARK: Overview

private struct OverviewTab: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    WeatherCard(weather: state.weather).frame(width: 275, height: 130)
                    UserCard(state: state).frame(width: 339, height: 130)
                }
                HStack(spacing: 12) {
                    ClockCard(now: model.now, seconds: state.config.dashboard.showClockSeconds).frame(width: 110)
                    CalendarCard(model: model).frame(width: 378)
                    GaugesCard(state: state).frame(width: 113)
                }
            }
            MediaCard(state: state, model: model).frame(width: 197)
        }
    }
}

struct WeatherCard: View {
    var weather: WeatherInfo?
    @Environment(\.shellTheme) var theme

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: weather.map { ShellIcon.sf($0.icon) } ?? "cloud.sun")
                .font(.system(size: 54, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme[.onSurface])
            VStack(spacing: 4) {
                Text(weather.map { "\(Int($0.temperatureC.rounded()))°C" } ?? "--°C")
                    .font(theme.sans(30, weight: .semibold)).foregroundStyle(theme[.primary])
                Text(weather?.description ?? "Weather not set up")
                    .font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurface]).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellCard()
        .accessibilityIdentifier("dashboard.weather")
    }
}

struct UserCard: View {
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(theme[.primaryContainer])
                    Text(String(NSFullUserName().first ?? "?").uppercased())
                        .font(theme.sans(36, weight: .semibold)).foregroundStyle(theme[.onPrimaryContainer])
                }
                .frame(width: 84, height: 84)
                Image(systemName: "apple.logo").font(.system(size: 13))
                    .foregroundStyle(theme[.onSecondaryContainer])
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(theme[.secondaryContainer]))
                    .offset(x: 6, y: 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                Chip(icon: "macwindow", text: "macOS \(v.majorVersion).\(v.minorVersion) · CaelestiaWM", fill: theme[.surfaceContainerHighest].opacity(0.8), fg: theme[.onSurface])
                Chip(icon: "clock.arrow.circlepath", text: ShellText.uptimeText(state.performance.uptimeSeconds), fill: theme[.tertiaryContainer].opacity(0.9), fg: theme[.onTertiaryContainer])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellCard()
        .accessibilityIdentifier("dashboard.user")
    }
}

struct Chip: View {
    var icon: String
    var text: String
    var fill: Color
    var fg: Color
    @Environment(\.shellTheme) var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium))
            Text(text).font(theme.sans(12, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(fill))
    }
}

struct ClockCard: View {
    var now: Date
    var seconds: Bool
    @Environment(\.shellTheme) var theme

    var body: some View {
        let p = ClockParts.make(now, use24h: ClockParts.localeUses24h(), seconds: seconds)
        VStack(spacing: 6) {
            Text(p.hours).font(theme.sans(32, weight: .bold))
            dots
            Text(p.minutes).font(theme.sans(32, weight: .bold))
            if let s = p.seconds {
                dots
                Text(s).font(theme.sans(32, weight: .bold)).foregroundStyle(theme[.tertiary])
            }
            if let m = p.meridiem { Text(m).font(theme.sans(15, weight: .semibold)).foregroundStyle(theme[.onSurfaceVariant]) }
        }
        .monospacedDigit()
        .foregroundStyle(theme[.primary])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellCard()
        .accessibilityIdentifier("dashboard.clock")
    }

    private var dots: some View {
        HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 4, height: 4) } }
            .foregroundStyle(theme[.onSurfaceVariant].opacity(0.6))
    }
}

struct CalendarCard: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        let cal = Calendar.current
        let start = CalendarGrid.monthStart(containing: model.now, offsetMonths: model.monthOffset)
        let weeks = CalendarGrid.weeks(monthStart: start, today: model.now)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(spacing: 6) {
            HStack {
                arrow("chevron.left") { model.monthOffset -= 1 }
                Spacer()
                Button { model.monthOffset = 0 } label: {
                    Text(start, format: .dateTime.month(.wide).year()).font(theme.sans(15, weight: .semibold)).foregroundStyle(theme[.onSurface])
                }.buttonStyle(.plain)
                Spacer()
                arrow("chevron.right") { model.monthOffset += 1 }
            }
            LazyVGrid(columns: cols, spacing: 4) {
                // Header IDs must not collide with Day.id (0..<42) in the same grid, or SwiftUI drops week 1.
                ForEach(Array(CalendarGrid.weekdayHeaders(calendar: cal).enumerated()), id: \.offset.headerID) { _, d in
                    Text(d).font(theme.sans(12, weight: .semibold)).foregroundStyle(theme[.onSurface])
                }
                ForEach(weeks.flatMap { $0 }) { day in
                    ZStack {
                        if day.isToday { CookieShape().fill(theme[.primaryContainer]).frame(width: 30, height: 30) }
                        Text("\(day.number)")
                            .font(theme.sans(13, weight: day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? theme[.onPrimaryContainer] : (day.inMonth ? theme[.onSurface] : theme[.onSurfaceVariant].opacity(0.4)))
                    }
                    .frame(height: 32)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellCard()
        .onScrollWheelStep { model.monthOffset += $0 }
        .accessibilityIdentifier("dashboard.calendar")
    }

    private func arrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme[.onSurfaceVariant]).frame(width: 28, height: 24)
        }.buttonStyle(.plain)
    }
}

struct GaugesCard: View {
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        let p = state.performance
        let mem = p.memoryTotalBytes > 0 ? Double(p.memoryUsedBytes) / Double(p.memoryTotalBytes) : 0
        let disk = p.storageTotalBytes > 0 ? Double(p.storageUsedBytes) / Double(p.storageTotalBytes) : 0
        VStack(spacing: 10) {
            gauge("cpu", p.cpuPercent / 100, "CPU \(Int(p.cpuPercent.rounded()))%")
            gauge("memorychip", mem, "Memory \(ShellText.bytesText(p.memoryUsedBytes)) of \(ShellText.bytesText(p.memoryTotalBytes))")
            gauge("internaldrive", disk, "Storage \(ShellText.bytesText(p.storageUsedBytes)) of \(ShellText.bytesText(p.storageTotalBytes))")
        }
        .padding(.vertical, 14).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellCard()
        .accessibilityIdentifier("dashboard.gauges")
    }

    private func gauge(_ icon: String, _ value: Double, _ help: String) -> some View {
        ZStack {
            ProgressArc(value: value, sweep: 300, lineWidth: 5)
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(theme[.onSurface])
                Text("\(Int((value * 100).rounded()))%").font(theme.sans(10, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
            }
        }
        .frame(width: 80, height: 80)
        .help(help)
    }
}

struct MediaCard: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DashboardModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        let m = state.media
        let progress = m.duration > 0 ? m.position / m.duration : 0
        VStack(spacing: 8) {
            ZStack {
                ProgressArc(value: progress, sweep: 240, lineWidth: 4).frame(width: 156, height: 156)
                ArtworkView(url: m.available ? m.artworkPath : nil)
                    .clipShape(CookieShape(bumps: 10, depth: 0.05)).frame(width: 118, height: 118)
            }
            .padding(.top, 14)
            Text(m.available ? (m.title.isEmpty ? "Unknown title" : m.title) : "No media")
                .font(theme.sans(15, weight: .semibold)).foregroundStyle(theme[.onSurface]).lineLimit(1)
            Text(m.available ? (m.artist.isEmpty ? "Unknown artist" : m.artist) : "Nothing playing")
                .font(theme.sans(13)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
            if m.available, !m.album.isEmpty {
                Text(m.album).font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant].opacity(0.8)).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                RoundIconButton(symbol: "backward.fill", size: 36, action: model.onPrevious)
                RoundIconButton(symbol: m.isPlaying ? "pause.fill" : "play.fill", size: 44, filled: true, action: model.onPlayPause)
                RoundIconButton(symbol: "forward.fill", size: 36, action: model.onNext)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellCard(radius: 30)
        .accessibilityIdentifier("dashboard.media")
    }
}

// MARK: Media tab

private struct MediaTab: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DashboardModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        let m = state.media
        HStack(spacing: 28) {
            ZStack {
                ProgressArc(value: m.duration > 0 ? m.position / m.duration : 0, sweep: 300, lineWidth: 6).frame(width: 300, height: 300)
                ArtworkView(url: m.available ? m.artworkPath : nil).clipShape(CookieShape(bumps: 12, depth: 0.05)).frame(width: 236, height: 236)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(m.available ? (m.title.isEmpty ? "Unknown title" : m.title) : "No media")
                    .font(theme.sans(28, weight: .bold)).foregroundStyle(theme[.onSurface]).lineLimit(2)
                Text(m.available ? m.artist : "Nothing is playing").font(theme.sans(18)).foregroundStyle(theme[.primary]).lineLimit(1)
                if !m.album.isEmpty { Text(m.album).font(theme.sans(15)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1) }
                if m.available {
                    HStack {
                        Text(timeText(m.position)); Spacer(); Text(timeText(m.duration))
                    }
                    .font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).monospacedDigit().padding(.top, 8)
                    ProgressView(value: min(1, max(0, m.duration > 0 ? m.position / m.duration : 0))).tint(theme[.primary])
                    Text("Playing in \(m.player)").font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant])
                } else {
                    Text("macOS only lets Apple's own processes read the system Now Playing feed, so Caelestia reads Spotify and Music directly. Start one of them to see it here.")
                        .font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    RoundIconButton(symbol: "backward.fill", size: 46, action: model.onPrevious)
                    RoundIconButton(symbol: m.isPlaying ? "pause.fill" : "play.fill", size: 56, filled: true, action: model.onPlayPause)
                    RoundIconButton(symbol: "forward.fill", size: 46, action: model.onNext)
                }.padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellCard()
        .accessibilityIdentifier("dashboard.mediaTab")
    }

    private func timeText(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

// MARK: Performance tab

private struct PerformanceTab: View {
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        let p = state.performance
        let mem = p.memoryTotalBytes > 0 ? Double(p.memoryUsedBytes) / Double(p.memoryTotalBytes) : 0
        let disk = p.storageTotalBytes > 0 ? Double(p.storageUsedBytes) / Double(p.storageTotalBytes) : 0
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: cols, spacing: 12) {
            StatCard(icon: "cpu", title: "CPU", value: "\(Int(p.cpuPercent.rounded()))%", detail: "all cores", fraction: p.cpuPercent / 100, history: p.cpuHistory.map { $0 / 100 })
            StatCard(icon: "memorychip", title: "Memory", value: "\(Int((mem * 100).rounded()))%",
                     detail: "\(ShellText.bytesText(p.memoryUsedBytes)) of \(ShellText.bytesText(p.memoryTotalBytes))", fraction: mem, history: p.memoryHistory.map { $0 / 100 })
            StatCard(icon: "internaldrive", title: "Storage", value: "\(Int((disk * 100).rounded()))%",
                     detail: "\(ShellText.bytesText(p.storageUsedBytes)) of \(ShellText.bytesText(p.storageTotalBytes))", fraction: disk, history: [])
            if let gpu = p.gpuPercent {
                StatCard(icon: "display", title: "GPU", value: "\(Int(gpu.rounded()))%", detail: "device utilization", fraction: gpu / 100, history: [])
            }
            NetCard(p: p)
            if state.status.hasBattery, state.config.dashboard.showBattery { BatteryCard(status: state.status) }
            StatCard(icon: "thermometer.medium", title: "Thermal", value: ShellText.thermalText(p.thermalState), detail: "pressure; degrees need root", fraction: Double(p.thermalState) / 3, history: [])
        }
        .accessibilityIdentifier("dashboard.performance")
    }
}

private struct StatCard: View {
    var icon: String, title: String, value: String, detail: String, fraction: Double, history: [Double]
    @Environment(\.shellTheme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(theme[.primary])
                Text(title).font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onSurface])
                Spacer()
                Text(value).font(theme.sans(20, weight: .bold)).foregroundStyle(theme[.primary])
            }
            Text(detail).font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
            Spacer(minLength: 0)
            if history.count > 1 { Sparkline(values: history).frame(height: 56) }
            else {
                ZStack(alignment: .leading) {
                    Capsule().fill(theme[.onSurface].opacity(0.1))
                    GeometryReader { g in Capsule().fill(theme[.primary]).frame(width: g.size.width * min(1, max(0, fraction))) }
                }.frame(height: 8)
            }
        }
        .padding(14)
        .frame(height: 140)
        .shellCard(radius: 22)
    }
}

private struct NetCard: View {
    var p: PerformanceInfo
    @Environment(\.shellTheme) var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "network").font(.system(size: 14)).foregroundStyle(theme[.primary])
                Text("Network").font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onSurface])
            }
            Text("↓ \(ShellText.rateText(p.networkDownBytesPerSec))   ↑ \(ShellText.rateText(p.networkUpBytesPerSec))")
                .font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurface]).monospacedDigit()
            Spacer(minLength: 0)
            let peak = max(1, (p.networkDownHistory + p.networkUpHistory).max() ?? 1)
            if p.networkDownHistory.count > 1 { Sparkline(values: p.networkDownHistory, maxValue: peak).frame(height: 56) }
        }
        .padding(14).frame(height: 140).shellCard(radius: 22)
    }
}

private struct BatteryCard: View {
    var status: StatusInfo
    @Environment(\.shellTheme) var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: status.batteryCharging ? "battery.100percent.bolt" : "battery.75percent").font(.system(size: 14)).foregroundStyle(theme[.primary])
                Text("Battery").font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onSurface])
                Spacer()
                Text("\(status.batteryPercent)%").font(theme.sans(20, weight: .bold)).foregroundStyle(theme[.primary])
            }
            Text(BatteryText.status(status)).font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(2)
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                Capsule().fill(theme[.onSurface].opacity(0.1))
                GeometryReader { g in Capsule().fill(status.batteryPercent <= 15 && !status.batteryCharging ? theme[.error] : theme[.primary]).frame(width: g.size.width * Double(status.batteryPercent) / 100) }
            }.frame(height: 8)
        }
        .padding(14).frame(height: 140).shellCard(radius: 22)
    }
}

/// Month change by scrolling over the calendar.
extension View {
    func onScrollWheelStep(_ step: @escaping (Int) -> Void) -> some View {
        background(ScrollStepCatcher(onStep: step))
    }
}

struct ScrollStepCatcher: NSViewRepresentable {
    var onStep: (Int) -> Void
    func makeNSView(context: Context) -> V { let v = V(); v.onStep = onStep; return v }
    func updateNSView(_ v: V, context: Context) { v.onStep = onStep }
    final class V: NSView {
        var onStep: (Int) -> Void = { _ in }
        private var acc = 0.0
        override func scrollWheel(with event: NSEvent) {
            acc += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
            if abs(acc) >= 40 { onStep(acc > 0 ? -1 : 1); acc = 0 }
            if event.phase == .ended || event.momentumPhase == .ended { acc = 0 }
        }
    }
}


private extension Int {
    var headerID: String { "header-\(self)" }
}
