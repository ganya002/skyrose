import AppKit
import CaelestiaCore
import SwiftUI

/// Volume / brightness OSD (spec 5.9; Caelestia `modules/osd`): the sliders stacked in a column in a
/// drawer on the right edge, shown on a change and hidden `hideDelay` after the last one.
@MainActor
public final class OSDModel: ObservableObject {
    @Published public var shown = false
    @Published public var volume: Double = 0
    @Published public var muted = false
    @Published public var brightness: Double = 1
    @Published public var brightnessAvailable = true
    /// The pointer is over the OSD: it stays.
    @Published public var hovered = false
    /// Caelestia `osd.hideDelay` (2000 ms).
    public nonisolated static let hideDelay: TimeInterval = 2
    public var onSetVolume: (Double) -> Void = { _ in }
    public var onSetBrightness: (Double) -> Void = { _ in }
    /// One scroll step over a slider: +1 up, -1 down (Caelestia `incrementVolume` / brightness step).
    public var onStepVolume: (Int) -> Void = { _ in }
    public var onStepBrightness: (Int) -> Void = { _ in }

    /// Caelestia `Tokens.sizes.osd` and the padding / spacing of `osd/Content.qml`.
    public static let sliderWidth: Double = 30
    public static let sliderHeight: Double = 150
    public static let padding: Double = 16
    public static let spacing: Double = 12
    /// `horizontalCenterOffset`: clamp(padding.large - border.thickness, 0, padding.large) / 2 with
    /// Caelestia's 10 pt border. shortcut: fixed for the default border, recompute if the frame inset grows.
    public static let centerOffset: Double = 3

    public init() {}

    public var bodySize: CGSize { Self.size(sliders: brightnessAvailable ? 2 : 1) }

    public static var maxBodySize: CGSize { size(sliders: 2) }

    public static func size(sliders n: Int) -> CGSize {
        let n = Double(n)
        return CGSize(width: sliderWidth + padding + 2 * centerOffset,
                      height: n * sliderHeight + (n - 1) * spacing + 2 * padding)
    }

    /// Caelestia `Icons.getVolumeIcon`.
    public nonisolated static func volumeIcon(_ value: Double, muted: Bool) -> String {
        if muted { return "volume_off" }
        if value >= 0.5 { return "volume_up" }
        return value > 0 ? "volume_down" : "volume_mute"
    }

    /// Caelestia: `brightness_${round(value * 6) + 1}`.
    public nonisolated static func brightnessIcon(_ value: Double) -> String {
        "brightness_\(Int((min(1, max(0, value)) * 6).rounded()) + 1)"
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
                DrawerBackground(edge: .right, fillet: fillet, radius: theme.frameRounding, shown: model.shown, depth: size.width)
                VStack(spacing: OSDModel.spacing) {
                    OSDSlider(value: model.volume, icon: OSDModel.volumeIcon(model.volume, muted: model.muted),
                              onSet: model.onSetVolume, onStep: model.onStepVolume)
                        .accessibilityIdentifier("osd.volume")
                    if model.brightnessAvailable {
                        OSDSlider(value: model.brightness, icon: OSDModel.brightnessIcon(model.brightness),
                                  onSet: model.onSetBrightness, onStep: model.onStepBrightness)
                            .accessibilityIdentifier("osd.brightness")
                    }
                }
                .offset(x: OSDModel.centerOffset)
                .liquidContent(edge: .right, shown: model.shown, depth: size.width, theme: theme)
            }
            .frame(width: size.width, height: size.height + 2 * fillet)
            .onHover { model.hovered = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

/// Caelestia `FilledSlider`: a full-round track (surfaceContainer), the part below the handle in
/// secondary, and a round inverseSurface handle with the icon that shows the percentage while the
/// value moves (500 ms after the last change). Drag anywhere; scroll steps the value.
struct OSDSlider: View {
    var value: Double
    var icon: String
    var onSet: (Double) -> Void
    var onStep: (Int) -> Void
    @Environment(\.shellTheme) var theme
    @State private var moving = false
    @State private var pressed = false
    @State private var settle: DispatchWorkItem?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let v = min(1, max(0, value))
            let y = (1 - v) * (h - w)
            ZStack(alignment: .top) {
                Capsule().fill(theme[.surfaceContainer])
                Capsule().fill(theme[.secondary]).frame(height: h - y).offset(y: y)
                ZStack {
                    Circle().fill(theme[.inverseSurface])
                        .shadow(color: .black.opacity(hovering ? 0.3 : 0.2), radius: hovering ? 3 : 1.5, y: 1)
                    Group {
                        if moving {
                            Text(verbatim: "\(Int((v * 100).rounded()))")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                        } else {
                            MaterialIcon(icon, size: 15)
                        }
                    }
                    .foregroundStyle(theme[.inverseOnSurface])
                    .offset(y: 1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
                .frame(width: w, height: w)
                .offset(y: y)
                .onHover { hovering = $0 }
            }
            .animation(theme.token(.standard, ms: CaelestiaTokens.Duration.large), value: v)
            .animation(theme.token(.standardDecel, ms: CaelestiaTokens.Duration.normal / 2), value: moving)
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    pressed = true
                    moving = true
                    onSet(min(1, max(0, 1 - (g.location.y - w / 2) / (h - w))))
                }
                .onEnded { _ in pressed = false; settleSoon() })
            .background(ScrollStepCatcher(onStep: { onStep(-$0) }))
        }
        .frame(width: OSDModel.sliderWidth, height: OSDModel.sliderHeight)
        .onChange(of: value) { old, new in
            guard abs(new - old) >= 0.01 else { return }
            moving = true
            settleSoon()
        }
    }

    private func settleSoon() {
        settle?.cancel()
        let work = DispatchWorkItem { if !pressed { moving = false } }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
