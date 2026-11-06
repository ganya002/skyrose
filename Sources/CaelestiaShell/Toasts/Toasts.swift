import AppKit
import CaelestiaCore
import SwiftUI

/// Caelestia `toaster` IPC kinds.
public enum ToastKind: String, Sendable, CaseIterable, Codable {
    case error, warn, info, success

    public var defaultIcon: String {
        switch self {
        case .error: return "error"
        case .warn: return "warning"
        case .info: return "info"
        case .success: return "check_circle"
        }
    }
}

public struct Toast: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ToastKind
    public var title: String
    public var message: String
    /// Material Symbols or SF Symbols name; empty = the kind's default.
    public var icon: String
    public var createdAt: TimeInterval

    public init(id: UUID = UUID(), kind: ToastKind, title: String, message: String = "", icon: String = "", createdAt: TimeInterval) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.icon = icon
        self.createdAt = createdAt
    }
}

/// The visible toasts, newest first. Pure: the controller ticks it.
public struct ToastQueue: Equatable, Sendable {
    public private(set) var toasts: [Toast] = []
    public var maxVisible = 4
    public var timeout: TimeInterval = 5
    public init() {}

    @discardableResult
    public mutating func add(_ toast: Toast) -> UUID {
        // The same toast twice in a row refreshes instead of stacking.
        if let i = toasts.firstIndex(where: { $0.kind == toast.kind && $0.title == toast.title && $0.message == toast.message }) {
            toasts.remove(at: i)
        }
        toasts.insert(toast, at: 0)
        if toasts.count > maxVisible { toasts.removeLast(toasts.count - maxVisible) }
        return toast.id
    }

    /// Drops expired toasts; returns true when something changed.
    @discardableResult
    public mutating func expire(at now: TimeInterval) -> Bool {
        let before = toasts.count
        toasts.removeAll { now - $0.createdAt >= timeout }
        return toasts.count != before
    }

    public mutating func dismiss(_ id: UUID) { toasts.removeAll { $0.id == id } }
    public var isEmpty: Bool { toasts.isEmpty }
}

@MainActor
public final class ToastModel: ObservableObject {
    @Published public var queue = ToastQueue()
    public init() {}
    public static let width: Double = 360
}

struct ToastsView: View {
    @ObservedObject var model: ToastModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(model.queue.toasts) { toast in
                ToastCard(toast: toast)
                    .transition(theme.reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .scale(scale: 0.8, anchor: .trailing)).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .trailing).combined(with: .opacity)))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(theme.drawerOpen, value: model.queue.toasts.map(\.id))
    }
}

struct ToastCard: View {
    var toast: Toast
    @Environment(\.shellTheme) var theme

    var body: some View {
        let (bg, fg, accent) = colors
        HStack(alignment: .top, spacing: 12) {
            MaterialIcon(toast.icon.isEmpty ? toast.kind.defaultIcon : toast.icon, size: 18, weight: .semibold)
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(theme.sans(15, weight: .semibold))
                    .foregroundStyle(fg)
                    .lineLimit(2)
                if !toast.message.isEmpty {
                    Text(toast.message)
                        .font(theme.sans(13))
                        .foregroundStyle(fg.opacity(0.8))
                        .lineLimit(4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: ToastModel.width, alignment: .leading)
        .background(
            ZStack {
                FrostedShape(shape: RoundedRectangle(cornerRadius: 17, style: .continuous), theme: theme,
                             caps: NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
                RoundedRectangle(cornerRadius: 17, style: .continuous).fill(bg)
                RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(theme[.outlineVariant].opacity(0.5), lineWidth: 1)
            }
        )
        .accessibilityIdentifier("toast.\(toast.kind.rawValue)")
    }

    private var colors: (Color, Color, Color) {
        switch toast.kind {
        case .error: return (theme[.errorContainer].opacity(0.85), theme[.onErrorContainer], theme[.error])
        case .warn: return (theme[.surfaceContainer].opacity(0.6), theme[.onSurface], theme[.tertiary])
        case .info: return (theme[.surfaceContainer].opacity(0.6), theme[.onSurface], theme[.primary])
        case .success: return (theme[.successContainer].opacity(0.85), theme[.onSuccessContainer], theme[.success])
        }
    }
}
