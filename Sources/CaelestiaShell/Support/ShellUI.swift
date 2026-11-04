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

/// An arc gauge: `sweep` degrees of track with the first `value` of it filled, opening at the bottom.
struct ProgressArc: View {
    var value: Double
    var sweep: Double = 270
    var lineWidth: Double = 5
    @Environment(\.shellTheme) var theme

    var body: some View {
        let start = 90 + (360 - sweep) / 2
        ZStack {
            Arc(start: start, sweep: sweep).stroke(theme[.onSurface].opacity(0.1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Arc(start: start, sweep: max(0.5, sweep * min(1, max(0, value))))
                .stroke(theme[.primary], style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .animation(theme.small, value: value)
    }

    struct Arc: Shape {
        var start: Double
        var sweep: Double
        var animatableData: Double {
            get { sweep }
            set { sweep = newValue }
        }
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let r = min(rect.width, rect.height) / 2
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: r, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
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
    var action: () -> Void
    @State private var hover = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(filled ? theme[.onPrimary] : theme[.onSurface])
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? theme[.primary] : theme[.onSurface].opacity(hover ? 0.2 : 0.12)))
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
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme[.onPrimary])
                    .frame(width: h, height: h)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in onSet(min(1, max(0, g.location.x / w))) })
        }
        .frame(height: 30)
        .animation(theme.small, value: value)
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
        Image(systemName: placeholder).font(.system(size: 30)).foregroundStyle(theme[.onSurfaceVariant])
    }
}
