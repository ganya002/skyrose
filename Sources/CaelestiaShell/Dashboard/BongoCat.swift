import SwiftUI

/// Two drums and two paws. A paw comes down when the beat detector hears a hit.
/// While nothing is playing the cat sits still. The listener is stopped with the dashboard.
struct BongoCat: View {
    var paw: Int?
    var playing: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                drum
                drum
            }
            .offset(y: 10)
            HStack(spacing: 18) {
                pawView(0)
                pawView(1)
            }
            .offset(y: playing ? -6 : 0)
        }
        .accessibilityIdentifier("dashboard.bongo")
    }

    var drum: some View {
        Capsule()
            .fill(Color(white: 0.92))
            .frame(width: 28, height: 16)
            .overlay(Capsule().stroke(Color(white: 0.35), lineWidth: 2))
    }

    func pawView(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(white: 0.15))
            .frame(width: 22, height: 16)
            .offset(y: paw == index ? 10 : 0)
            .animation(.easeOut(duration: 0.08), value: paw)
    }
}
