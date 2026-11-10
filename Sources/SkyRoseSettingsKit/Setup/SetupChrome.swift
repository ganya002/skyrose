import AppKit
import CaelestiaCore
import CaelestiaShell
import SwiftUI

/// The frame shared by the installer and the uninstaller: a stage rail on the left (the active
/// stage carries a pill that slides between rows), the stage's content on the right, and an
/// overall 0–100 % bar along the bottom that never leaves the window.
///
/// Motion is Caelestia's: stage changes and the bar run on expressiveDefaultSpatial
/// (500 ms × `durations.scale`, 400 ms at 0.8), colours on defaultEffects. SwiftUI retargets
/// these from the current value, so a new stage interrupts the last one mid-flight. Under
/// Reduce Motion everything is a short cross-fade without slide or overshoot
/// (``ShellTheme/token(_:ms:)``).
struct SetupChrome<Content: View, Footer: View>: View {
    @Environment(\.look) var look
    var title: String
    var steps: [SetupStep]
    var active: Int
    var stateOf: (Int) -> SetupStepState
    var fraction: Double
    var status: String
    var badge: String? = nil
    var onClose: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @Namespace private var ns

    static var size: NSSize { NSSize(width: 820, height: 580) }

    var body: some View {
        HStack(spacing: 0) {
            rail
            VStack(spacing: 0) {
                HStack {
                    if let badge {
                        Label(badge, systemImage: "eye").font(look.font(11.5, .semibold))
                            .foregroundStyle(look[.onTertiaryContainer])
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(look[.tertiaryContainer]))
                    }
                    Spacer()
                }
                .frame(height: 30)
                .padding(.horizontal, 28).padding(.top, 14)
                ZStack {
                    content
                        .id(active)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: look.theme.slide(24))),
                            removal: .opacity.combined(with: .offset(y: look.theme.slide(-16)))))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 32)
                .clipped()
                progressBar
                footer
                    .padding(.horizontal, 28).padding(.vertical, 16)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PanelBackground())
        .animation(look.theme.spatial, value: active)
    }

    var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let onClose { WindowButtons(onClose: onClose) }
                Spacer()
            }
            .frame(height: 20)
            .padding(.bottom, 18)
            HStack(spacing: 10) {
                BrandIcon(which: .main, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(look.font(16, .semibold)).foregroundStyle(look[.onSurface])
                    Text("SkyRose \(CaelestiaVersion.string)").font(look.mono(10.5)).foregroundStyle(look[.onSurfaceVariant])
                }
            }
            .padding(.bottom, 22)
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                StepRow(step: step, number: i + 1, state: stateOf(i), isActive: i == active, ns: ns)
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: SettingsLook.insetPanelRadius, style: .continuous)
                .fill(look[.surfaceContainer].opacity(max(0.5, look.theme.layerAlpha + 0.3)))
        )
        .padding(SettingsLook.panelInset)
    }

    var progressBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(status).font(look.font(12.5, .medium)).foregroundStyle(look[.onSurfaceVariant])
                    .lineLimit(1).truncationMode(.tail)
                    .contentTransition(.opacity)
                    .animation(look.theme.small, value: status)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%").font(look.mono(12, .semibold)).foregroundStyle(look[.onSurface])
                    .contentTransition(.numericText(value: fraction))
                    .animation(look.theme.small, value: fraction)
                    .accessibilityIdentifier("setup.percent")
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(look[.surfaceContainerHighest])
                    Capsule().fill(look[.primary])
                        .frame(width: fraction > 0 ? max(10, geo.size.width * min(1, fraction)) : 0)
                        .animation(look.theme.spatial, value: fraction)
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 28).padding(.top, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent, \(status)")
    }
}

private struct StepRow: View {
    @Environment(\.look) var look
    var step: SetupStep
    var number: Int
    var state: SetupStepState
    var isActive: Bool
    var ns: Namespace.ID

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(dotFill).frame(width: 26, height: 26)
                Group {
                    switch state {
                    case .done: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    case .failed: Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold))
                    case .active, .pending: Image(systemName: step.icon).font(.system(size: 11, weight: .semibold))
                    }
                }
                .foregroundStyle(dotInk)
                .contentTransition(.symbolEffect(.replace))
            }
            Text(step.title).font(look.font(13.5, isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? look[.onSecondaryContainer] : state == .pending ? look[.onSurfaceVariant] : look[.onSurface])
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: SettingsLook.rowRadius, style: .continuous)
                    .fill(look[.secondaryContainer])
                    .matchedGeometryEffect(id: "activeStep", in: ns)
            }
        }
        .animation(look.theme.small, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(step.title)")
        .accessibilityValue(stateText)
    }

    var dotFill: Color {
        switch state {
        case .done: return look[.primary]
        case .failed: return look[.error]
        case .active: return look[.primary].opacity(0.22)
        case .pending: return look[.surfaceContainerHighest]
        }
    }

    var dotInk: Color {
        switch state {
        case .done: return look[.onPrimary]
        case .failed: return look[.onError]
        case .active: return look[.primary]
        case .pending: return look[.outline]
        }
    }

    var stateText: String {
        switch state {
        case .done: return "done"
        case .failed: return "failed"
        case .active: return "in progress"
        case .pending: return "not started"
        }
    }
}

/// An error inside the window (never a system alert): what went wrong, the engine's last words,
/// and the way on.
struct SetupErrorCard: View {
    @Environment(\.look) var look
    var title: String
    var message: String
    var detail: String
    var fixTitle: String? = nil
    var fix: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18)).foregroundStyle(look[.error])
                Text(title).font(look.font(16, .semibold)).foregroundStyle(look[.onSurface])
            }
            Text(message).font(look.font(13)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
            if let fixTitle, let fix {
                PillButton(title: fixTitle, icon: "arrow.clockwise", kind: .filled, action: fix)
                    .accessibilityIdentifier("setup.fix")
            }
            if !detail.isEmpty {
                ScrollView {
                    Text(detail).font(look.mono(11)).foregroundStyle(look[.onSurface])
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look[.surfaceContainerHighest]))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SettingsLook.cardRadius, style: .continuous).fill(look[.errorContainer].opacity(0.35)))
        .accessibilityIdentifier("setup.error")
    }
}

/// One reported line (done / skipped / left / failed / would run).
struct SetupItemRow: View {
    @Environment(\.look) var look
    var item: SetupItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint).frame(width: 14)
            Text(item.text.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(item.kind == .dry ? look.mono(11.5) : look.font(12.5))
                .foregroundStyle(item.kind == .skip ? look[.onSurfaceVariant] : look[.onSurface])
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    var icon: String {
        switch item.kind {
        case .done: return "checkmark"
        case .skip: return "minus"
        case .left: return "hand.point.right"
        case .fail: return "xmark"
        case .dry: return "eye"
        }
    }

    var tint: Color {
        switch item.kind {
        case .done: return look[.success]
        case .skip: return look[.outline]
        case .left: return look[.tertiary]
        case .fail: return look[.error]
        case .dry: return look[.primary]
        }
    }
}
