import AppKit
import CaelestiaCore
import CaelestiaShell
import SwiftUI

/// Motion for the Settings app and the onboarding: springs between 150 and 300 ms (SwiftUI
/// springs retarget from the current value and velocity, so every one is interruptible), and a
/// 120 ms cross-fade under Reduce Motion (macOS or SkyRose's own switch).
public struct SettingsMotion: Equatable, Sendable {
    public var reduceMotion: Bool
    /// Multiplier from `animations.speed` (2 = twice as fast), clamped so nothing leaves 150–300 ms.
    public var speed: Double

    public init(reduceMotion: Bool, speed: Double = 1) {
        self.reduceMotion = reduceMotion
        self.speed = speed
    }

    /// Clamp a duration into the 150–300 ms band after the speed factor.
    public static func clamped(_ seconds: Double, speed: Double) -> Double {
        let s = speed > 0 && speed.isFinite ? speed : 1
        return min(0.30, max(0.15, seconds / s))
    }

    /// Small things: toggles, hover, selection (≈180 ms).
    public var quick: Animation { spring(0.18, bounce: 0.12) }
    /// Page / step changes, the sidebar pill (≈260 ms).
    public var page: Animation { spring(0.26, bounce: 0.14) }
    /// Cards appearing, the success check (≈300 ms, a touch of overshoot).
    public var pop: Animation { spring(0.30, bounce: 0.25) }

    public func spring(_ seconds: Double, bounce: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.12) }
        return .spring(duration: Self.clamped(seconds, speed: speed), bounce: bounce)
    }

    /// The duration a spring of `seconds` settles in (what tests check).
    public func duration(_ seconds: Double) -> Double { reduceMotion ? 0.12 : Self.clamped(seconds, speed: speed) }

    /// Slide distance for transitions: none under Reduce Motion.
    public func slide(_ d: Double) -> Double { reduceMotion ? 0 : d }
}

/// Theme for every Settings view: the shell's ``ShellTheme`` (same palette, radii and fonts)
/// plus the motion above.
public struct SettingsLook: Equatable {
    public var theme: ShellTheme
    public var motion: SettingsMotion

    /// Large cards and the window: Caelestia `rounding.large` (25).
    public static let windowRadius: Double = 25
    public static let cardRadius: Double = 20
    /// Rows and controls: the window rounding (15).
    public static let rowRadius: Double = 15
    public static let pillRadius: Double = 999

    public init(theme: ShellTheme, motion: SettingsMotion) {
        self.theme = theme
        self.motion = motion
    }

    public subscript(_ role: ColorRole) -> Color { theme[role] }
    public func font(_ size: Double, _ weight: Font.Weight = .regular) -> Font { theme.sans(size, weight: weight) }
    public func mono(_ size: Double, _ weight: Font.Weight = .regular) -> Font { theme.mono(size, weight: weight) }
}

private struct SettingsLookKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = SettingsLook(theme: .gabby, motion: SettingsMotion(reduceMotion: false))
}

public extension EnvironmentValues {
    var look: SettingsLook {
        get { self[SettingsLookKey.self] }
        set { self[SettingsLookKey.self] = newValue }
    }
}

// MARK: - Surfaces

/// The window background: the shell's panel colour over a behind-window blur, 25 pt corners,
/// a hairline outline.
struct PanelBackground: View {
    @Environment(\.look) var look
    var body: some View {
        ZStack {
            VisualEffectBlur()
            Color(nsColor: look.theme.panelFill)
        }
        .clipShape(RoundedRectangle(cornerRadius: SettingsLook.windowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLook.windowRadius, style: .continuous)
                .strokeBorder(look[.outlineVariant].opacity(0.6), lineWidth: 1)
        )
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// An inner card (surfaceContainer at the layer transparency).
struct Card<Content: View>: View {
    @Environment(\.look) var look
    var padding: Double = 18
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsLook.cardRadius, style: .continuous)
                    .fill(look[.surfaceContainer].opacity(max(0.55, look.theme.layerAlpha + 0.35)))
            )
    }
}

/// Page title + one-line explanation.
struct PageHeader: View {
    @Environment(\.look) var look
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(look.font(26, .semibold)).foregroundStyle(look[.onSurface])
            Text(subtitle).font(look.font(13.5)).foregroundStyle(look[.onSurfaceVariant])
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}

struct SectionLabel: View {
    @Environment(\.look) var look
    var text: String
    var body: some View {
        Text(text.uppercased()).font(look.font(11, .semibold)).tracking(0.8)
            .foregroundStyle(look[.primary].opacity(0.9))
    }
}

/// One setting: title, optional explanation, control on the right.
struct SettingRow<Control: View>: View {
    @Environment(\.look) var look
    var title: String
    var detail: String? = nil
    var icon: String? = nil
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(look[.primary])
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(look[.primaryContainer].opacity(0.55)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(look.font(14, .medium)).foregroundStyle(look[.onSurface])
                if let detail {
                    Text(detail).font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Controls

/// Material 3 switch: a pill track and a thumb that grows when on.
struct PillToggle: View {
    @Environment(\.look) var look
    @Binding var isOn: Bool
    var enabled: Bool = true
    var accessibilityLabel: String = ""
    var body: some View {
        Button {
            withAnimation(look.motion.quick) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? look[.primary] : look[.surfaceContainerHighest])
                    .overlay(Capsule().strokeBorder(isOn ? Color.clear : look[.outline], lineWidth: 1.5))
                Circle().fill(isOn ? look[.onPrimary] : look[.outline])
                    .frame(width: isOn ? 20 : 14, height: isOn ? 20 : 14)
                    .overlay(
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(look[.primary]).opacity(isOn ? 1 : 0)
                    )
                    .padding(.horizontal, isOn ? 4 : 7)
            }
            .frame(width: 50, height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isButton)
    }
}

/// A pill segmented control with a sliding selection (spring, interruptible).
struct PillSegmented<T: Hashable>: View {
    @Environment(\.look) var look
    var options: [(T, String, String?)]
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let selected = opt.0 == selection
                Button {
                    withAnimation(look.motion.quick) { selection = opt.0 }
                } label: {
                    HStack(spacing: 5) {
                        if let icon = opt.2 { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                        Text(opt.1).font(look.font(12.5, .medium))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(selected ? look[.onPrimary] : look[.onSurfaceVariant])
                    .background {
                        if selected { Capsule().fill(look[.primary]).matchedGeometryEffect(id: "sel", in: ns) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(opt.1)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(look[.surfaceContainerHighest].opacity(0.9)))
    }
}

/// A slider in the shell's style; `onCommit` runs when the drag ends (and on clicks).
struct PillSlider: View {
    @Environment(\.look) var look
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    var onCommit: () -> Void = {}
    @State private var dragging = false
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let f = range.upperBound > range.lowerBound ? (value - range.lowerBound) / (range.upperBound - range.lowerBound) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(look[.surfaceContainerHighest]).frame(height: 8)
                    Capsule().fill(look[.primary]).frame(width: max(8, w * f), height: 8)
                    Capsule().fill(look[.primary]).frame(width: 5, height: dragging ? 24 : 20)
                        .offset(x: min(max(0, w * f - 2.5), w - 5))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        let raw = range.lowerBound + Double(min(max(0, g.location.x / max(1, w)), 1)) * (range.upperBound - range.lowerBound)
                        let stepped = (raw / step).rounded() * step
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        withAnimation(look.motion.quick) { dragging = false }
                        onCommit()
                    })
            }
            .frame(width: 170, height: 26)
            Text(format(value)).font(look.mono(12)).foregroundStyle(look[.onSurfaceVariant]).frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement()
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { dir in
            value = min(max(value + (dir == .increment ? step : -step), range.lowerBound), range.upperBound)
            onCommit()
        }
    }
}

/// Filled (primary) or tonal pill button.
struct PillButton: View {
    @Environment(\.look) var look
    enum Kind { case filled, tonal, outline, danger }
    var title: String
    var icon: String? = nil
    var kind: Kind = .filled
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(look.font(13, .semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(fg)
            .background(Capsule().fill(bg))
            .overlay(Capsule().strokeBorder(kind == .outline ? look[.outline] : .clear, lineWidth: 1))
            .scaleEffect(hover && !look.motion.reduceMotion ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(look.motion.quick) { hover = h } }
    }

    var fg: Color {
        switch kind {
        case .filled: return look[.onPrimary]
        case .tonal: return look[.onSecondaryContainer]
        case .outline: return look[.onSurface]
        case .danger: return look[.onError]
        }
    }

    var bg: Color {
        switch kind {
        case .filled: return look[.primary].opacity(hover ? 0.92 : 1)
        case .tonal: return look[.secondaryContainer].opacity(hover ? 1 : 0.85)
        case .outline: return hover ? look[.surfaceContainerHighest] : .clear
        case .danger: return look[.error]
        }
    }
}

/// Green when granted, the error colour when missing, outline while unknown.
struct StatusDot: View {
    @Environment(\.look) var look
    var state: Bool?
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.18)).frame(width: 30, height: 30)
            Image(systemName: state == true ? "checkmark" : state == false ? "xmark" : "ellipsis")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(look.motion.pop, value: state)
    }

    var color: Color { state == true ? look[.success] : state == false ? look[.error] : look[.outline] }
}

/// The SkyRose / SkyRose WM icon from the app bundle (falls back to the build folder, then a symbol).
struct BrandIcon: View {
    enum Which: String { case main = "SkyRose", wm = "SkyRoseWM" }
    var which: Which
    var size: Double
    var body: some View {
        if let img = BrandIcon.image(which) {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: which == .main ? "sparkles" : "rectangle.split.3x1").font(.system(size: size * 0.5))
                .frame(width: size, height: size)
        }
    }

    static func image(_ which: Which) -> NSImage? {
        if let url = Bundle.main.url(forResource: which.rawValue, withExtension: "icns"), let i = NSImage(contentsOf: url) { return i }
        // `swift run` from the repo: Packaging/<name>-1024.png.
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let d = dir else { break }
            let png = d.appendingPathComponent("Packaging/\(which.rawValue)-1024.png")
            if let i = NSImage(contentsOf: png) { return i }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }
}

/// A key cap for chords in the cheat sheet and the Keybinds page.
struct KeyCaps: View {
    @Environment(\.look) var look
    var text: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, part in
                Text(String(part)).font(look.font(12, .semibold)).foregroundStyle(look[.onSurface])
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(look[.surfaceContainerHighest]))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(look[.outlineVariant], lineWidth: 1))
            }
        }
    }
}
