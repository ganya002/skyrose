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
    /// Extra height at the top that the drawer covers but keeps empty: the notch dip.
    @Published public var topInset: Double = 0
    public var onPlayPause: () -> Void = {}
    public var onNext: () -> Void = {}
    public var onPrevious: () -> Void = {}
    public var onSeek: (Double) -> Void = { _ in }
    /// Which paw is down. Nil is the resting pose.
    @Published public var bongoPaw: Int?
    @Published public var lyricLines: [LyricLine] = []
    @Published public var lyricNote: String = ""
    @Published public var lyricClock = LyricClock()
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
        let top = model.topInset
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                DrawerBackground(edge: .top, fillet: fillet, radius: theme.frameRounding, shown: model.shown, depth: body.height + top)
                content
                    .frame(width: design.width, height: design.height)
                    .scaleEffect(s, anchor: .center)
                    .frame(width: body.width, height: body.height)
                    .liquidContent(edge: .top, shown: model.shown, depth: body.height + top, theme: theme)
            }
            .frame(width: body.width + 2 * fillet, height: body.height + top)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DashboardTab.allCases, id: \.self) { tab in
                    TabButton(tab: tab, selected: model.tab == tab) { withAnimation(theme.spatial) { model.tab = tab } }
                }
            }
            .frame(height: 62)
            Rectangle().fill(theme[.outlineVariant].opacity(0.5)).frame(height: 1).padding(.horizontal, 12)
            Group {
                switch model.tab {
                case .overview: OverviewTab(model: model, state: state)
                case .media: MediaTab(state: state, model: model)
                case .performance: PerformanceTab(state: state)
                case .weather: WeatherTab(state: state)
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
                MaterialIcon(tab.icon, size: 15, weight: .medium)
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
                    WeatherCard(state: state).frame(width: 275, height: 130)
                        .onTapGesture { withAnimation(theme.spatial) { model.tab = .weather } }
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
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        Group {
            if let w = state.weather {
                HStack(spacing: 20) {
                    MaterialIcon(w.icon, size: 54, weight: .light)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme[.onSurface])
                    VStack(spacing: 4) {
                        Text(WeatherText.temperature(w.temperatureC, fahrenheit: state.config.weather.fahrenheit))
                            .font(theme.sans(30, weight: .semibold)).foregroundStyle(theme[.primary])
                        Text(w.description)
                            .font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurface]).multilineTextAlignment(.center)
                        Text(w.location).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
                    }
                }
            } else {
                WeatherPlaceholderText(status: state.weatherStatus, compact: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellCard()
        .accessibilityIdentifier("dashboard.weather")
    }
}

/// What to show instead of numbers: set-up hint, loading, or the error. No fake values.
struct WeatherPlaceholderText: View {
    var status: WeatherStatus
    var compact: Bool
    @Environment(\.shellTheme) var theme

    var body: some View {
        let (icon, title, detail): (String, String, String) = {
            switch status {
            case .notConfigured: return ("location.magnifyingglass", "No city set", "Choose one in Settings › Bar and Shell")
            case .loading: return ("arrow.triangle.2.circlepath", "Getting the weather…", "")
            case .ready: return ("cloud", "No weather yet", "")
            case .failed(let why): return ("exclamationmark.icloud", "Weather unavailable", why)
            }
        }()
        VStack(spacing: compact ? 4 : 8) {
            MaterialIcon(icon, size: compact ? 28 : 40, weight: .light).foregroundStyle(theme[.onSurfaceVariant])
            Text(title).font(theme.sans(compact ? 14 : 17, weight: .semibold)).foregroundStyle(theme[.onSurface])
            if !detail.isEmpty {
                Text(detail).font(theme.sans(compact ? 11 : 13)).foregroundStyle(theme[.onSurfaceVariant])
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: Weather tab

private struct WeatherTab: View {
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var f: Bool { state.config.weather.fahrenheit }

    var body: some View {
        Group {
            if let w = state.weather {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        current(w).frame(width: 300)
                        details(w)
                    }
                    .frame(height: 170)
                    hourly(w).frame(height: 104)
                    daily(w)
                }
            } else {
                WeatherPlaceholderText(status: state.weatherStatus, compact: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).shellCard()
            }
        }
        .accessibilityIdentifier("dashboard.weatherTab")
    }

    func current(_ w: WeatherInfo) -> some View {
        HStack(spacing: 18) {
            MaterialIcon(w.icon, size: 64, weight: .light)
                .symbolRenderingMode(.hierarchical).foregroundStyle(theme[.onSurface])
            VStack(alignment: .leading, spacing: 4) {
                Text(WeatherText.temperature(w.temperatureC, fahrenheit: f)).font(theme.sans(40, weight: .semibold)).foregroundStyle(theme[.primary])
                Text(w.description).font(theme.sans(14, weight: .medium)).foregroundStyle(theme[.onSurface])
                Label(w.location, systemImage: state.config.weather.useLocation ? "location.fill" : "mappin.and.ellipse")
                    .font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
        .shellCard()
    }

    func details(_ w: WeatherInfo) -> some View {
        let items: [(String, String, String)] = [
            w.feelsLikeC.map { ("thermometer.medium", "Feels like", WeatherText.temperature($0, fahrenheit: f)) },
            w.humidity.map { ("humidity.fill", "Humidity", "\($0)%") },
            w.windKmh.map { ("wind", "Wind", f ? "\(Int(($0 / 1.609).rounded())) mph" : "\(Int($0.rounded())) km/h") },
            w.sunrise.map { ("sunrise.fill", "Sunrise", $0.formatted(date: .omitted, time: .shortened)) },
            w.sunset.map { ("sunset.fill", "Sunset", $0.formatted(date: .omitted, time: .shortened)) },
            w.updated.map { ("clock.arrow.circlepath", "Updated", $0.formatted(date: .omitted, time: .shortened)) },
        ].compactMap { $0 }
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(items, id: \.1) { item in
                HStack(spacing: 8) {
                    MaterialIcon(item.0, size: 15).foregroundStyle(theme[.primary]).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.1).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant])
                        Text(item.2).font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onSurface]).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).frame(height: 70).shellCard(radius: 20)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    func hourly(_ w: WeatherInfo) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(w.hourly.prefix(12).enumerated()), id: \.offset) { i, h in
                VStack(spacing: 5) {
                    Text(i == 0 ? "Now" : h.time.formatted(.dateTime.hour())).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant])
                    MaterialIcon(h.icon, size: 17).symbolRenderingMode(.hierarchical).foregroundStyle(theme[.onSurface]).frame(height: 22)
                    Text(WeatherText.temperature(h.temperatureC, fahrenheit: f, unit: false)).font(theme.sans(13, weight: .semibold)).foregroundStyle(theme[.onSurface])
                    Text(h.precipitationChance.map { $0 >= 10 ? "\($0)%" : " " } ?? " ").font(theme.sans(10)).foregroundStyle(theme[.primary])
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .shellCard()
    }

    func daily(_ w: WeatherInfo) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(w.daily.prefix(7).enumerated()), id: \.offset) { i, d in
                VStack(spacing: 6) {
                    Text(i == 0 ? "Today" : d.date.formatted(.dateTime.weekday(.abbreviated))).font(theme.sans(12, weight: .medium)).foregroundStyle(theme[.onSurface])
                    MaterialIcon(d.icon, size: 20).symbolRenderingMode(.hierarchical).foregroundStyle(theme[.onSurface]).frame(height: 26)
                    Text(WeatherText.temperature(d.maxC, fahrenheit: f, unit: false)).font(theme.sans(13, weight: .semibold)).foregroundStyle(theme[.primary])
                    Text(WeatherText.temperature(d.minC, fahrenheit: f, unit: false)).font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shellCard(radius: 20)
            }
        }
        .frame(maxHeight: .infinity)
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
                MaterialIcon("apple.logo", size: 13)
                    .foregroundStyle(theme[.onSecondaryContainer])
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(theme[.secondaryContainer]))
                    .offset(x: 6, y: 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                Chip(icon: "macwindow", text: "macOS \(v.majorVersion).\(v.minorVersion) · SkyRose WM", fill: theme[.surfaceContainerHighest].opacity(0.8), fg: theme[.onSurface])
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
            MaterialIcon(icon, size: 11, weight: .medium)
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
            MaterialIcon(symbol, size: 12, weight: .semibold).foregroundStyle(theme[.onSurfaceVariant]).frame(width: 28, height: 24)
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
                MaterialIcon(icon, size: 15).foregroundStyle(theme[.onSurface])
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
            if state.config.dashboard.bongoCat {
                BongoCat(paw: model.bongoPaw, playing: m.isPlaying && model.shown)
                    .frame(width: 72, height: 48)
            }
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
                if state.config.dashboard.bongoCat {
                    BongoCat(paw: model.bongoPaw, playing: m.isPlaying && model.shown).frame(width: 120, height: 72)
                }
                if state.config.dashboard.lyrics { lyricList(m) }
                if m.available {
                    HStack {
                        Text(timeText(m.position)); Spacer(); Text(timeText(m.duration))
                    }
                    .font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).monospacedDigit().padding(.top, 8)
                    ProgressView(value: min(1, max(0, m.duration > 0 ? m.position / m.duration : 0))).tint(theme[.primary])
                    Text("Playing in \(m.player)").font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant])
                } else {
                    Text("macOS only lets Apple's own processes read the system Now Playing feed, so SkyRose reads Spotify and Music directly. Start one of them to see it here.")
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

    @ViewBuilder private func lyricList(_ m: MediaInfo) -> some View {
        if model.lyricLines.isEmpty {
            Text(model.lyricNote.isEmpty ? "No lyrics found" : model.lyricNote)
                .font(theme.sans(13)).foregroundStyle(theme[.onSurfaceVariant])
        } else {
            // Ticks only while the song runs and the dashboard is open.
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                LyricList(model: model, current: Lyrics.index(of: model.lyricLines, at: model.lyricClock.position(at: context.date)))
            }
        }
    }
}

private struct LyricList: View {
    @ObservedObject var model: DashboardModel
    var current: Int?
    @Environment(\.shellTheme) var theme

    var body: some View {
        let synced = Lyrics.isSynced(model.lyricLines)
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.lyricLines.enumerated()), id: \.offset) { index, line in
                        Text(line.text)
                            .font(theme.sans(index == current ? 16 : 13, weight: index == current ? .semibold : .regular))
                            .foregroundStyle(index == current ? theme[.primary] : theme[.onSurfaceVariant])
                            .animation(theme.small, value: current)
                            .id(index)
                            .onTapGesture { if synced { model.onSeek(line.time) } }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            .onChange(of: current) { _, index in
                if let index { withAnimation(theme.spatial) { proxy.scrollTo(index, anchor: .center) } }
            }
            .onChange(of: model.lyricLines) { _, _ in proxy.scrollTo(0, anchor: .top) }
        }
    }
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
            if let t = p.temperatureC {
                StatCard(icon: "thermometer.medium", title: "CPU temp", value: ShellText.celsius(t),
                         detail: [p.cpuMaxTemperatureC.map { "hottest \(ShellText.celsius($0))" }, "pressure \(ShellText.thermalText(p.thermalState).lowercased())"].compactMap { $0 }.joined(separator: " · "),
                         fraction: ShellText.temperatureFraction(t), history: p.temperatureHistory.map(ShellText.temperatureFraction))
            } else {
                StatCard(icon: "thermometer.medium", title: "Thermal", value: ShellText.thermalText(p.thermalState), detail: "pressure", fraction: Double(p.thermalState) / 3, history: [])
            }
            if p.gpuTemperatureC != nil || p.batteryTemperatureC != nil || p.ssdTemperatureC != nil {
                TempsCard(p: p)
            }
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
                MaterialIcon(icon, size: 14).foregroundStyle(theme[.primary])
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

/// The other temperatures that this Mac exposes (each row hidden when its sensor is missing).
private struct TempsCard: View {
    var p: PerformanceInfo
    @Environment(\.shellTheme) var theme
    var body: some View {
        let rows: [(String, String, Double)] = [
            p.gpuTemperatureC.map { ("display", "GPU", $0) },
            p.batteryTemperatureC.map { ("battery.75percent", "Battery", $0) },
            p.ssdTemperatureC.map { ("internaldrive", "SSD", $0) },
        ].compactMap { $0 }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MaterialIcon("thermometer.variable", size: 14).foregroundStyle(theme[.primary])
                Text("Temperatures").font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onSurface])
            }
            ForEach(rows, id: \.1) { r in
                HStack(spacing: 8) {
                    MaterialIcon(r.0, size: 12).foregroundStyle(theme[.onSurfaceVariant]).frame(width: 18)
                    Text(r.1).font(theme.sans(13)).foregroundStyle(theme[.onSurface])
                    Spacer()
                    Text(ShellText.celsius(r.2)).font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.primary]).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(height: 140).shellCard(radius: 22)
        .accessibilityIdentifier("dashboard.temperatures")
    }
}

private struct NetCard: View {
    var p: PerformanceInfo
    @Environment(\.shellTheme) var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                MaterialIcon("network", size: 14).foregroundStyle(theme[.primary])
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
                MaterialIcon(status.batteryCharging ? "battery.100percent.bolt" : "battery.75percent", size: 14).foregroundStyle(theme[.primary])
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
