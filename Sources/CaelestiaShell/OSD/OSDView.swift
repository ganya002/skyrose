import AppKit
import CaelestiaCore
import SwiftUI

/// Volume / brightness OSD (spec 5.9; Caelestia `osd`): two vertical sliders in a drawer on the
/// right edge, shown on a change and hidden `hideDelay` after the last one.
@MainActor
public final class OSDModel: ObservableObject {
    @Published public var shown = false
    @Published public var volume: Double = 0
    @Published public var muted = false
    @Published public var brightness: Double = 1
    @Published public var brightnessAvailable = true
    /// The pointer is over the OSD: it stays.
    @Published public var hovered = false
    public nonisolated static let hideDelay: TimeInterval = 1.5
    public var onSetVolume: (Double) -> Void = { _ in }
    public var onSetBrightness: (Double) -> Void = { _ in }

    public static let sliderWidth: Double = 30
    public static let sliderHeight: Double = 150
    public static let padding: Double = 10
    public static let spacing: Double = 10

    public init() {}

    public var bodySize: CGSize {
        let n = brightnessAvailable ? 2.0 : 1.0
        return CGSize(width: n * Self.sliderWidth + (n - 1) * Self.spacing + 2 * Self.padding,
                      height: Self.sliderHeight + 2 * Self.padding)
    }

    public static var maxBodySize: CGSize {
        CGSize(width: 2 * sliderWidth + spacing + 2 * padding, height: sliderHeight + 2 * padding)
    }
}

/// When the OSD hides: `hideDelay` after the last change, never while hovered. Pure.
public struct OSDTimer: Equatable, Sendable {
    public private(set) var lastChange: TimeInterval?
    public init() {}
    public mutating func changed(at now: TimeInterval) { lastChange = now }
    public func shouldHide(at now: TimeInterval, hovered: Bool, delay: TimeInterval = OSDModel.hideDelay) -> Bool {
        guard let t = lastChange, !hovered else { return false }
        return now - t >= delay
    }
    public mutating func reset() { lastChange = nil }
}

struct OSDView: View {
    @ObservedObject var model: OSDModel
    @Environment(\.shellTheme) var theme
    let fillet: Double

    var body: some View {
        let size = model.bodySize
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                FrostedShape(shape: DrawerShape(edge: .right, radius: theme.frameRounding, fillet: fillet), theme: theme)
                    .liquidBody(edge: .right, shown: model.shown, depth: size.width, theme: theme)
                HStack(spacing: OSDModel.spacing) {
                    OSDSlider(value: model.muted ? 0 : model.volume, icon: volumeIcon, onSet: model.onSetVolume)
                        .accessibilityIdentifier("osd.volume")
                    if model.brightnessAvailable {
                        OSDSlider(value: model.brightness, icon: model.brightness < 0.5 ? "sun.min.fill" : "sun.max.fill",
                                  onSet: model.onSetBrightness)
                            .accessibilityIdentifier("osd.brightness")
                    }
                }
                .liquidContent(edge: .right, shown: model.shown, depth: size.width, theme: theme)
            }
            .frame(width: size.width, height: size.height + 2 * fillet)
            .onHover { model.hovered = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var volumeIcon: String {
        if model.muted || model.volume <= 0 { return "speaker.slash.fill" }
        return model.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }
}

/// A vertical pill slider: track in onSurface @ low alpha, fill in primary from the bottom,
/// the icon inside the fill at the bottom (Caelestia `FilledSlider`).
struct OSDSlider: View {
    var value: Double
    var icon: String
    var onSet: (Double) -> Void
    @Environment(\.shellTheme) var theme

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let fillH = max(w, h * min(1, max(0, value)))
            ZStack(alignment: .bottom) {
                Capsule().fill(theme[.onSurface].opacity(0.1))
                Capsule().fill(theme[.primary]).frame(height: fillH)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[.onPrimary])
                    .frame(width: w, height: w)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                onSet(min(1, max(0, 1 - g.location.y / h)))
            })
        }
        .frame(width: OSDModel.sliderWidth, height: OSDModel.sliderHeight)
        .animation(theme.small, value: value)
    }
}
