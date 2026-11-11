import AppKit
import CaelestiaCore
import SwiftUI

/// The visualiser ring's bars (Caelestia `Audio.cava.values`), 0...1, from the system-output tap.
@MainActor
public final class VisualiserModel: ObservableObject {
    /// Caelestia `services.visualiserBars`.
    public nonisolated static let bars = 45
    @Published public var values: [Double] = []
    public init() {}
}

/// The dashboard Media tab in the layout of Caelestia's older `dashboard/Media.qml` (Gabby's
/// media-player.png): round rotating cover art in a radial bar visualiser, the details column, and
/// the bongo cat. Sizes are measured on the reference against the 860 pt dashboard.
struct MediaTabView: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DashboardModel
    @Environment(\.shellTheme) var theme

    static let cover: Double = 150
    /// Caelestia `mediaVisualiserSize`: the longest a bar grows past the cover.
    static let visualiserSize: Double = 55
    static let detailsWidth: Double = 210

    var body: some View {
        let m = state.media
        let ring = Self.cover + 2 * Self.visualiserSize
        HStack(spacing: 12) {
            CoverVisualiser(model: model.visualiser, artwork: m.available ? m.artworkPath : nil, playing: m.isPlaying)
                .frame(width: ring, height: ring)
            MediaDetails(media: m, model: model, lyrics: state.config.dashboard.lyrics)
                .frame(width: Self.detailsWidth)
            Group {
                if state.config.dashboard.bongoCat {
                    BongoCat(paw: model.bongoPaw, playing: m.isPlaying && model.shown)
                        .frame(width: 200, height: 126)
                } else {
                    Color.clear
                }
            }
            .frame(width: ring, height: ring)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("dashboard.mediaTab")
    }
}

/// Round cover art that turns slowly while playing, with `VisualiserModel.bars` bars around it:
/// each starts `spacing` past the art and grows by value × `visualiserSize` (Caelestia's ShapePath).
struct CoverVisualiser: View {
    @ObservedObject var model: VisualiserModel
    var artwork: URL?
    var playing: Bool
    @Environment(\.shellTheme) var theme
    /// Degrees turned before the current run, and when the run started.
    @State private var turned: Double = 0
    @State private var since: Date?

    /// One turn in 20 s.
    static let degreesPerSecond = 18.0
    static let spacing = 12.0

    var body: some View {
        let cover = MediaTabView.cover
        let n = VisualiserModel.bars
        let stroke = 360.0 / Double(n) - 2  // Caelestia: 360 / bars - spacing.small / 4
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r0 = cover / 2 + Self.spacing + stroke / 2
                var path = Path()
                for i in 0..<n {
                    let v = min(1, max(1e-3, i < model.values.count ? model.values[i] : 0))
                    let a = Double(i) * 2 * .pi / Double(n)
                    let r1 = r0 + v * MediaTabView.visualiserSize
                    path.move(to: CGPoint(x: c.x + r0 * cos(a), y: c.y + r0 * sin(a)))
                    path.addLine(to: CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a)))
                }
                ctx.stroke(path, with: .color(theme[.primary]), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            TimelineView(.animation(paused: !playing)) { tl in
                ArtworkView(url: artwork)
                    .frame(width: cover, height: cover)
                    .clipShape(Circle())
                    .rotationEffect(.degrees(angle(at: tl.date)))
            }
        }
        .onAppear { if playing { since = Date() } }
        .onChange(of: playing) { _, now in
            if now {
                since = Date()
            } else {
                turned = angle(at: Date())
                since = nil
            }
        }
        .accessibilityIdentifier("media.visualiser")
    }

    private func angle(at date: Date) -> Double {
        (turned + (since.map { date.timeIntervalSince($0) } ?? 0) * Self.degreesPerSecond).truncatingRemainder(dividingBy: 360)
    }
}

/// Title / album / artist, the transport, the seek bar with times, and the player row.
struct MediaDetails: View {
    var media: MediaInfo
    @ObservedObject var model: DashboardModel
    var lyrics: Bool
    @Environment(\.shellTheme) var theme

    var body: some View {
        let m = media
        VStack(spacing: 8) {
            Text(m.available ? (m.title.isEmpty ? "Unknown title" : m.title) : "No media")
                .font(theme.sans(15, weight: .medium))
                .foregroundStyle(m.available ? theme[.primary] : theme[.onSurface])
            if m.available {
                Text(m.album.isEmpty ? "Unknown album" : m.album)
                    .font(theme.sans(12)).foregroundStyle(theme[.outline])
            }
            Text(m.available ? (m.artist.isEmpty ? "Unknown artist" : m.artist) : "Play some music for stuff to show up here!")
                .font(theme.sans(13))
                .foregroundStyle(m.available ? theme[.secondary] : theme[.outline])
                .multilineTextAlignment(.center)
            if lyrics, m.available, !model.lyricLines.isEmpty {
                LyricsColumn(model: model).frame(height: 120)
            }
            HStack(spacing: 8) {
                TextIconButton(icon: "skip_previous", size: 26, action: model.onPrevious)
                Button(action: model.onPlayPause) {
                    MaterialIcon(m.isPlaying ? "pause" : "play_arrow", size: 22, fill: true)
                        .foregroundStyle(theme[.onPrimary])
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(theme[.primary]))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("media.playPause")
                TextIconButton(icon: "skip_next", size: 26, action: model.onNext)
            }
            .padding(.top, 4)
            SeekBar(position: m.position, duration: m.duration, enabled: m.available && m.canSeek && m.duration > 0,
                    onSeek: model.onSeek)
                .frame(height: 30)
            HStack {
                Text(Self.time(m.available ? m.position : -1))
                Spacer()
                Text(Self.time(m.available ? m.duration : -1))
            }
            .font(theme.sans(11)).monospacedDigit().foregroundStyle(theme[.onSurfaceVariant])
            .padding(.top, -6)
            PlayerRow(media: m, model: model)
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// Caelestia `lengthStr`.
    static func time(_ s: Double) -> String {
        guard s >= 0, s.isFinite else { return "-1:-1" }
        let t = Int(s)
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// An icon-only button (Caelestia IconButton.Text).
struct TextIconButton: View {
    var icon: String
    var size: Double
    var color: ColorRole = .onSurface
    var disabled = false
    var action: () -> Void
    @Environment(\.shellTheme) var theme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            MaterialIcon(icon, size: size)
                .foregroundStyle(theme[color].opacity(disabled ? 0.38 : 1))
                .frame(width: size + 10, height: size + 10)
                .background(Circle().fill(theme[.onSurface].opacity(hover && !disabled ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover = $0 }
    }
}

/// Caelestia `StyledSlider`: a thin track, primary up to a tall rounded handle, the rest in
/// secondaryContainer, a gap either side of the handle. Click or drag to seek; scroll moves 10 s.
struct SeekBar: View {
    var position: Double
    var duration: Double
    var enabled: Bool
    var onSeek: (Double) -> Void
    @Environment(\.shellTheme) var theme
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let handle = 4.0, gap = 6.0
            let v = dragging ?? (duration > 0 ? min(1, max(0, position / duration)) : 0)
            let x = handle / 2 + v * (w - handle)
            ZStack(alignment: .leading) {
                Capsule().fill(theme[.primary])
                    .frame(width: max(0, x - handle / 2 - gap), height: 4)
                Capsule().fill(theme[.secondaryContainer])
                    .frame(width: max(0, w - x - handle / 2 - gap), height: 4)
                    .offset(x: x + handle / 2 + gap)
                Capsule().fill(theme[.primary])
                    .frame(width: handle, height: h * 0.7)
                    .offset(x: x - handle / 2)
            }
            .frame(width: w, height: h)
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in if enabled { dragging = min(1, max(0, d.location.x / w)) } }
                .onEnded { d in
                    guard enabled else { return }
                    onSeek(min(1, max(0, d.location.x / w)) * duration)
                    dragging = nil
                })
            .background(ScrollStepCatcher(onStep: { step in
                guard enabled else { return }
                onSeek(min(duration, max(0, position - Double(step) * 10)))
            }))
            .animation(dragging == nil ? theme.token(.standard, ms: CaelestiaTokens.Duration.large) : nil, value: v)
        }
        .accessibilityIdentifier("media.seek")
    }
}

/// Raise the player, the player switch (the source pill), and quit.
struct PlayerRow: View {
    var media: MediaInfo
    @ObservedObject var model: DashboardModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        HStack(spacing: 8) {
            TextIconButton(icon: "move_up", size: 18, color: .secondary, disabled: media.playerBundleID.isEmpty,
                           action: model.onRaisePlayer)
                .help("Open in \(media.player)")
                .accessibilityIdentifier("media.raise")
            if media.players.count > 1 {
                Menu {
                    ForEach(media.players, id: \.bundleID) { p in
                        Button {
                            model.onSelectPlayer(p.bundleID)
                        } label: {
                            if p.bundleID == media.playerBundleID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                        }
                    }
                } label: { pill }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("media.players")
            } else {
                pill
            }
            TextIconButton(icon: "delete", size: 18, color: .error, disabled: !media.canQuit, action: model.onQuitPlayer)
                .help(media.canQuit ? "Quit \(media.player)" : "This player can't be quit from here")
                .accessibilityIdentifier("media.quit")
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            if let icon = AppIconCache.icon(bundleID: media.playerBundleID) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                MaterialIcon(media.players.isEmpty ? "music_off" : "animated_images", size: 14)
            }
            Text(media.player.isEmpty ? "No players" : media.player).font(theme.sans(12, weight: .medium))
            if media.players.count > 1 { MaterialIcon("unfold_more", size: 12) }
        }
        .foregroundStyle(theme[.onSecondaryContainer])
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(theme[.secondaryContainer]))
    }
}
