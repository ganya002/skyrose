import AppKit
import CaelestiaCore
import SwiftUI

/// Inner card of a drawer: secondaryContainer over the panel (measured: card (43,47,60) on panel
/// (20,21,26) in 1-dashboard.jpg), radius 25 (Caelestia rounding.large).
struct CardBackground: ViewModifier {
    @Environment(\.shellTheme) var theme
    var radius: Double = 25
    var tint: Double = 0.6
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme[.secondaryContainer].opacity(tint)))
    }
}

extension View {
    func shellCard(radius: Double = 25, tint: Double = 0.6) -> some View { modifier(CardBackground(radius: radius, tint: tint)) }
}

/// A scalloped circle (Material "cookie"), used for today in the calendar and the cover art.
struct CookieShape: Shape {
    var bumps = 12
    var depth = 0.06
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        let steps = 180
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let rr = r * (1 - depth + depth * cos(Double(bumps) * t))
            let pt = CGPoint(x: c.x + rr * cos(t), y: c.y + rr * sin(t))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Caelestia's M3 CircularProgress: from `start` (degrees, 0 = east, clockwise) `sweep` degrees.
/// The filled part is `fg`; after a gap the rest of the track is secondaryContainer and ends in a
/// small `fg` dot. `wavy` draws the filled part as a travelling sine wave (the media arc).
struct ProgressArc: View {
    var value: Double
    var sweep: Double = 360
    var start: Double = -90
    var lineWidth: Double = 6
    var fg: ColorRole = .primary
    var wavy = false
    var waving = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        let v = min(1, max(1.0 / 360, value.isNaN ? 0 : value))
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let amp = wavy ? lineWidth * 0.5 : 0
            let r = (size - lineWidth * (1 + (wavy ? 1 : 0))) / 2
            let gap = (8 + lineWidth) / max(1, r) * 180 / .pi
            let restStart = start + v * sweep + gap
            let rest = max(1.0 / 360, sweep * (1 - v) - gap * (sweep < 360 ? 1 : 2))
            let visible = min(1, rest)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let dotAngle = (start + sweep - gap * (sweep < 360 ? 0 : 1)) * .pi / 180
            ZStack {
                Arc(center: c, radius: r, start: restStart, sweep: rest)
                    .stroke(theme[.secondaryContainer], style: StrokeStyle(lineWidth: lineWidth * visible, lineCap: .round))
                    .opacity(visible)
                TimelineView(.animation(paused: !(wavy && waving))) { t in
                    let phase = wavy ? t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2 : 0
                    Wave(center: c, radius: r, start: start, full: sweep, value: v, amplitude: amp, phase: phase)
                        .stroke(theme[fg], style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                Circle().fill(theme[fg])
                    .frame(width: min(4, lineWidth) * visible, height: min(4, lineWidth) * visible)
                    .position(x: c.x + r * cos(dotAngle), y: c.y + r * sin(dotAngle))
                    .opacity(visible)
            }
        }
        .animation(theme.spatial, value: value)
    }

    struct Arc: Shape {
        var center: CGPoint
        var radius: Double
        var start: Double
        var sweep: Double
        var animatableData: AnimatablePair<Double, Double> {
            get { AnimatablePair(start, sweep) }
            set { start = newValue.first; sweep = newValue.second }
        }
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
            return p
        }
    }

    /// WavyLine.paintArc: r + amplitude·sin(8 waves over the full arc + phase), drawn to `value`.
    struct Wave: Shape {
        var center: CGPoint
        var radius: Double
        var start: Double
        var full: Double
        var value: Double
        var amplitude: Double
        var phase: Double
        var animatableData: Double {
            get { value }
            set { value = newValue }
        }
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let fullRad = full * .pi / 180, draw = fullRad * value
            guard draw > 0, radius > 0 else { return p }
            let n = max(64, Int((radius * draw).rounded(.up)))
            for i in 0...n {
                let d = draw * Double(i) / Double(n)
                let phi = 8 * 2 * .pi * (d * radius) / (radius * fullRad) + phase * 2 * .pi
                let r = radius + amplitude * sin(phi)
                let th = start * .pi / 180 + d
                let pt = CGPoint(x: center.x + r * cos(th), y: center.y + r * sin(th))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            return p
        }
    }
}

struct Sparkline: View {
    var values: [Double]
    var maxValue: Double = 1
    @Environment(\.shellTheme) var theme

    var body: some View {
        GeometryReader { g in
            let pts = points(g.size)
            ZStack {
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: last.x, y: g.size.height))
                    p.closeSubpath()
                }.fill(theme[.primary].opacity(0.18))
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }.stroke(theme[.primary], style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }

    private func points(_ size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let m = max(maxValue, 0.0001)
        return values.enumerated().map { i, v in
            CGPoint(x: size.width * Double(i) / Double(values.count - 1), y: size.height * (1 - min(1, max(0, v / m))))
        }
    }
}

/// A round icon button (media transport, small actions).
struct RoundIconButton: View {
    var symbol: String
    var size: Double = 36
    var filled = false
    /// M3 tonal: secondaryContainer fill.
    var tonal = false
    /// Takes the spare width of its row (a pill), like IconButton's fillWidth.
    var wide = false
    var action: () -> Void
    @State private var hover = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        let fg: Color = filled ? theme[.onPrimary] : tonal ? theme[.onSecondaryContainer] : theme[.onSurface]
        let bg: Color = filled ? theme[.primary] : tonal ? theme[.secondaryContainer] : theme[.onSurface].opacity(0.12)
        Button(action: action) {
            MaterialIcon(symbol, size: size * 0.42, weight: .semibold)
                .foregroundStyle(fg)
                .frame(width: wide ? nil : size, height: size)
                .frame(maxWidth: wide ? .infinity : nil)
                .background(Capsule().fill(bg).overlay(Capsule().fill(fg.opacity(hover ? 0.08 : 0))))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// A horizontal pill slider (volume, brightness).
struct HSlider: View {
    var value: Double
    var icon: String
    var onSet: (Double) -> Void
    @Environment(\.shellTheme) var theme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(theme[.onSurface].opacity(0.1))
                Capsule().fill(theme[.primary]).frame(width: max(h, w * min(1, max(0, value))))
                MaterialIcon(icon, size: 12, weight: .semibold)
                    .foregroundStyle(theme[.onPrimary])
                    .frame(width: h, height: h)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in onSet(min(1, max(0, g.location.x / w))) })
        }
        .frame(height: 30)
        .animation(theme.spatial, value: value)
    }
}

/// Cover art from a file or https URL; `placeholder` when there is none.
struct ArtworkView: View {
    var url: URL?
    var placeholder: String = "music.note"
    @Environment(\.shellTheme) var theme

    var body: some View {
        ZStack {
            theme[.surfaceContainerHigh]
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { icon }
                }
            } else {
                icon
            }
        }
    }

    private var icon: some View {
        MaterialIcon(placeholder, size: 30).foregroundStyle(theme[.onSurfaceVariant])
    }
}
