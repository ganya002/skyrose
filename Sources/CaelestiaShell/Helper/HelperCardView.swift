import AppKit
import SwiftUI

@MainActor
public final class HelperCardModel: ObservableObject {
    @Published public var flow = HelperCardFlow()
    /// The Terminal line (`sudo …/skyrose-sa-loader`), shown and copied by the fallback.
    @Published public var terminalCommand = ""
    @Published public var copied = false
    public var onEvent: (HelperCardFlow.Event) -> Void = { _ in }
    public var onOpenTerminal: () -> Void = {}
    public init() {}
}

struct HelperCardView: View {
    @ObservedObject var model: HelperCardModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        VStack(spacing: 0) {
            if model.flow.isVisible {
                card
                    .transition(theme.reduceMotion ? .opacity
                                : .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .top)))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(theme.spatial, value: model.flow.isVisible)
        .animation(theme.spatial, value: model.flow.phase)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(theme.sans(19, weight: .semibold)).foregroundStyle(theme[.onSurface])
                    Text(detail).font(theme.sans(13)).foregroundStyle(theme[.onSurfaceVariant])
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            switch model.flow.phase {
            case .offer: offer
            case .failed: buttons(primary: "Retry")
            case .terminal: terminal
            default: EmptyView()
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(
            ZStack {
                FrostedShape(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), theme: theme,
                             caps: NSEdgeInsets(top: 26, left: 26, bottom: 26, right: 26))
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme[.surfaceContainer].opacity(0.85))
                RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(theme[.outlineVariant].opacity(0.5), lineWidth: 1)
            }
        )
        .accessibilityIdentifier("helperCard")
    }

    @ViewBuilder private var badge: some View {
        ZStack {
            Circle().fill(badgeFill)
            switch model.flow.phase {
            case .waitingForPassword, .loading:
                ProgressView().controlSize(.small).tint(theme[.onPrimaryContainer])
            case .success:
                MaterialIcon("check", size: 20, weight: .bold).foregroundStyle(theme[.onPrimary])
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .failed:
                MaterialIcon("error", size: 20).foregroundStyle(theme[.onErrorContainer])
            default:
                MaterialIcon("toolbar", size: 20).foregroundStyle(theme[.onPrimaryContainer])
            }
        }
        .frame(width: 46, height: 46)
    }

    private var badgeFill: Color {
        switch model.flow.phase {
        case .success: return theme[.primary]
        case .failed: return theme[.errorContainer]
        default: return theme[.primaryContainer]
        }
    }

    private var title: String {
        switch model.flow.phase {
        case .success: return "Menu bar hidden"
        case .failed: return "The helper did not load"
        case .terminal: return "Do it in Terminal"
        default: return "Finish hiding the menu bar"
        }
    }

    private var detail: String {
        switch model.flow.phase {
        case .waitingForPassword: return "Type your Mac password in the window macOS just opened."
        case .loading: return "Loading the helper…"
        case .success: return "The helper is loaded. You are all set."
        case .failed(let why): return why
        case .terminal: return "Paste this into Terminal and press Return. It asks for your password."
        default: return "SkyRose needs your password once to load a small helper into the Dock."
        }
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { model.flow.installDaemon }, set: { model.flow.installDaemon = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Do this automatically every restart").font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurface])
                    Text("Installs a small boot daemon that runs as root at boot.").font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant])
                }
            }
            .toggleStyle(.switch).tint(theme[.primary])
            .accessibilityIdentifier("helperCard.daemon")
            buttons(primary: "Enable")
        }
    }

    private func buttons(primary: String) -> some View {
        HStack(spacing: 10) {
            Button { model.onEvent(.showTerminal) } label: {
                Text("Do it in Terminal instead").font(theme.sans(12)).underline().foregroundStyle(theme[.onSurfaceVariant])
            }
            .buttonStyle(.plain).accessibilityIdentifier("helperCard.terminal")
            Spacer(minLength: 0)
            Button { model.onEvent(.notNow) } label: {
                Text("Not now").font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
                    .padding(.horizontal, 14).frame(height: 36)
            }
            .buttonStyle(.plain).accessibilityIdentifier("helperCard.notNow")
            Button { model.onEvent(.enable) } label: {
                Text(primary).font(theme.sans(14, weight: .semibold)).foregroundStyle(theme[.onPrimary])
                    .padding(.horizontal, 22).frame(height: 38)
                    .background(Capsule().fill(theme[.primary]))
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction).accessibilityIdentifier("helperCard.enable")
        }
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.terminalCommand)
                .font(theme.mono(12)).foregroundStyle(theme[.onSurface]).textSelection(.enabled)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme[.surfaceContainerHighest].opacity(0.8)))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.terminalCommand, forType: .string)
                model.copied = true
            } label: {
                Label(model.copied ? "Copied" : "Copy", systemImage: model.copied ? "checkmark" : "doc.on.doc")
                    .font(theme.sans(15, weight: .semibold)).foregroundStyle(theme[.onPrimary])
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Capsule().fill(theme[.primary]))
            }
            .buttonStyle(.plain).accessibilityIdentifier("helperCard.copy")
            HStack {
                Button { model.onEvent(.backFromTerminal) } label: {
                    Text("Back").font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
                }.buttonStyle(.plain)
                Spacer()
                Button { model.onOpenTerminal() } label: {
                    Text("Open Terminal").font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.primary])
                }.buttonStyle(.plain).accessibilityIdentifier("helperCard.openTerminal")
            }
        }
    }
}
