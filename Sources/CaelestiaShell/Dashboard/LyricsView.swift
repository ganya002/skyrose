import CaelestiaCore
import SwiftUI

/// The right column of the media tab, after Caelestia's `LyricsAndSelector`: a "Lyrics" header over
/// the list, or its loading or empty state.
struct LyricsColumn: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.shellTheme) var theme

    private var loading: Bool { model.lyricLines.isEmpty && model.lyricNote == "Loading lyrics..." }
    private var empty: Bool { model.lyricLines.isEmpty && !loading }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MaterialIcon("lyrics", size: 18)
                Text("Lyrics").font(theme.sans(16, weight: .medium))
            }
            .foregroundStyle(theme[.onSurface])
            ZStack {
                lyricLines.opacity(model.lyricLines.isEmpty ? 0 : 1)
                Text(model.lyricNote).font(theme.sans(16, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant]).opacity(loading ? 1 : 0)
                VStack(spacing: 6) {
                    MaterialIcon("sentiment_sad", size: 44)
                    Text("No lyrics found").font(theme.sans(16, weight: .medium))
                }
                .foregroundStyle(theme[.outline])
                .opacity(empty ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(theme.small, value: model.lyricLines.isEmpty)
            .animation(theme.small, value: loading)
        }
        .accessibilityIdentifier("dashboard.lyrics")
    }

    @ViewBuilder private var lyricLines: some View {
        if !model.lyricLines.isEmpty {
            // Ticks only while the song runs and the dashboard is open.
            TimelineView(.animation(minimumInterval: 0.2, paused: !model.lyricClock.playing || !model.shown)) { context in
                LyricList(model: model, current: Lyrics.index(of: model.lyricLines, at: model.lyricClock.position(at: context.date)))
            }
        }
    }
}

/// Synced lines centred on the current one. Rows are laid out at the current line's size and only
/// scaled down, so a line becoming current never changes the height of the list and nothing jumps.
struct LyricList: View {
    @ObservedObject var model: DashboardModel
    var current: Int?
    @Environment(\.shellTheme) var theme
    @State private var centers: [Int: CGFloat] = [:]
    @State private var hovered: Int?
    @State private var animates = false

    private static let fade = 0.1
    private static let restScale = 0.74

    var body: some View {
        GeometryReader { box in
            if Lyrics.isSynced(model.lyricLines) { synced(box.size) } else { plain }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: Self.fade),
                                     .init(color: .black, location: 1 - Self.fade), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .onAppear { settle() }
        .onChange(of: model.lyricLines) { _, _ in centers = [:]; settle() }
    }

    /// Placing the list on open or on a new song is not a scroll, so the spring waits for layout.
    private func settle() {
        animates = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { animates = true }
    }

    private func synced(_ size: CGSize) -> some View {
        let y = size.height / 2 - (centers[current ?? 0] ?? size.height / 2)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(model.lyricLines.enumerated()), id: \.offset) { index, line in row(index, line) }
        }
        .coordinateSpace(name: "lyrics")
        .onPreferenceChange(LyricCenters.self) { centers = $0 }
        .frame(width: size.width, alignment: .leading)
        .offset(y: y)
        .animation(animates ? .spring(response: 0.48, dampingFraction: 0.82) : nil, value: y)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func row(_ index: Int, _ line: LyricLine) -> some View {
        let isCurrent = index == current
        return Text(line.text.isEmpty ? ". . ." : line.text)
            .font(theme.sans(19, weight: .semibold))
            .foregroundStyle(isCurrent ? theme[.primary] : hovered == index ? theme[.onSurface] : theme[.outline])
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(isCurrent ? 1 : Self.restScale, anchor: .leading)
            .opacity(isCurrent ? 1 : abs(index - (current ?? 0)) == 1 ? 0.8 : 0.5)
            .shadow(color: isCurrent ? theme[.primary].opacity(0.5) : .clear, radius: 6)
            .animation(theme.small, value: isCurrent)
            .background(GeometryReader { row in
                Color.clear.preference(key: LyricCenters.self, value: [index: row.frame(in: .named("lyrics")).midY])
            })
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
            .onTapGesture { model.onSeek(line.time) }
    }

    private var plain: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.lyricLines.enumerated()), id: \.offset) { _, line in
                    Text(line.text.isEmpty ? ". . ." : line.text).font(theme.sans(14)).foregroundStyle(theme[.outline])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
        }
    }
}

private struct LyricCenters: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
