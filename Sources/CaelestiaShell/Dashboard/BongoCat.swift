import SwiftUI

/// A cat at two bongos, drawn here in the current scheme. A paw comes down when the beat detector
/// hears a hit, and the head nods with it. With nothing playing the cat rests with its eyes shut.
/// The listener is stopped with the dashboard.
struct BongoCat: View {
    var paw: Int?
    var playing: Bool
    @Environment(\.shellTheme) var theme

    private static let size = CGSize(width: 120, height: 72)
    private static let slap = Animation.easeOut(duration: 0.07)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.size.width, geo.size.height / Self.size.height)
            scene
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityIdentifier("dashboard.bongo")
    }

    private var scene: some View {
        ZStack(alignment: .topLeading) {
            drum(x: 16)
            drum(x: 66)
            head.offset(y: paw == nil ? 0 : 1.5).animation(Self.slap, value: paw)
            pawView(0, x: 22)
            pawView(1, x: 74)
        }
    }

    private var fur: Color { theme[.onSurface] }
    private var line: Color { theme[.surface] }

    private var head: some View {
        ZStack {
            CatHead().fill(fur)
            CatHead().stroke(line, lineWidth: 2)
            if playing {
                eye(x: 49)
                eye(x: 71)
            } else {
                shutEye(x: 49)
                shutEye(x: 71)
            }
            CatMouth().stroke(line, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    private func eye(x: CGFloat) -> some View {
        Circle().fill(line).frame(width: 5, height: 5).position(x: x, y: 27)
    }

    private func shutEye(x: CGFloat) -> some View {
        Capsule().fill(line).frame(width: 7, height: 1.8).position(x: x, y: 27)
    }

    private func drum(x: CGFloat) -> some View {
        ZStack {
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 12, bottomTrailing: 12))
                .fill(theme[.primary]).frame(width: 38, height: 16).offset(y: 8)
            Ellipse().fill(theme[.primaryContainer]).frame(width: 38, height: 11)
            Ellipse().stroke(line, lineWidth: 1.6).frame(width: 38, height: 11)
        }
        .frame(width: 38, height: 30)
        .position(x: x + 19, y: 62)
    }

    /// Up between beats, on the skin when it hits, resting on the drum when nothing plays.
    private func pawView(_ index: Int, x: CGFloat) -> some View {
        let y: CGFloat = paw == index ? 49 : (playing ? 36 : 46)
        return Capsule()
            .fill(fur)
            .overlay(Capsule().stroke(line, lineWidth: 2))
            .frame(width: 24, height: 13)
            .position(x: x + 12, y: y)
            .animation(Self.slap, value: paw)
            .animation(.easeOut(duration: 0.2), value: playing)
    }
}

/// A wide, soft head with two ears, in the 120 × 72 scene.
private struct CatHead: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 35, y: 26))
        p.addLine(to: CGPoint(x: 37, y: 5))
        p.addQuadCurve(to: CGPoint(x: 53, y: 12), control: CGPoint(x: 47, y: 7))
        p.addQuadCurve(to: CGPoint(x: 67, y: 12), control: CGPoint(x: 60, y: 10.5))
        p.addQuadCurve(to: CGPoint(x: 83, y: 5), control: CGPoint(x: 73, y: 7))
        p.addLine(to: CGPoint(x: 85, y: 26))
        p.addCurve(to: CGPoint(x: 60, y: 50), control1: CGPoint(x: 88, y: 42), control2: CGPoint(x: 76, y: 50))
        p.addCurve(to: CGPoint(x: 35, y: 26), control1: CGPoint(x: 44, y: 50), control2: CGPoint(x: 32, y: 42))
        p.closeSubpath()
        return p
    }
}

private struct CatMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 55, y: 33))
        p.addQuadCurve(to: CGPoint(x: 60, y: 33), control: CGPoint(x: 57.5, y: 37))
        p.addQuadCurve(to: CGPoint(x: 65, y: 33), control: CGPoint(x: 62.5, y: 37))
        return p
    }
}
