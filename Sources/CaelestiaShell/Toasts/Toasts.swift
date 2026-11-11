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
    /// A picture shown on the right (screenshot thumbnail); "" = none.
    public var imagePath: String

    public init(id: UUID = UUID(), kind: ToastKind, title: String, message: String = "", icon: String = "", createdAt: TimeInterval, imagePath: String = "") {
        self.id = id
        self.imagePath = imagePath
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

/// Notifications and toasts: one drawer that grows down out of the frame's top-right corner, part
/// of the liquid surface (Caelestia's notifications module, measured on notification_popup.mp4:
/// 430 wide, 15 pt padding left/bottom, 5 pt (padding − border) top/right, cards 10 apart).
struct ToastsView: View {
    @ObservedObject var model: ToastModel
    @Environment(\.shellTheme) var theme
    static let width: Double = 430
    static let padding: Double = 15
    static let edgePadding: Double = 5

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(model.queue.toasts) { toast in
                ToastCard(toast: toast)
                    .transition(theme.reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(EdgeInsets(top: Self.edgePadding, leading: Self.padding, bottom: Self.padding, trailing: Self.edgePadding))
        .frame(width: Self.width)
        .background(DrawerBackground(edge: .top, fillet: 0, radius: theme.frameRounding, shown: !model.queue.isEmpty, depth: 120))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(theme.spatial, value: model.queue.toasts.map(\.id))
    }
}

/// One Caelestia notification card: icon circle, summary · time, a one-line body.
struct ToastCard: View {
    var toast: Toast
    @Environment(\.shellTheme) var theme

    var body: some View {
        HStack(spacing: 12) {
            if !toast.imagePath.isEmpty, let image = NSImage(contentsOfFile: toast.imagePath) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .accessibilityIdentifier("toast.thumbnail")
            } else {
                MaterialIcon(toast.icon.isEmpty ? toast.kind.defaultIcon : toast.icon, size: 20)
                    .foregroundStyle(toast.kind == .error ? theme[.onError] : theme[.onSecondaryContainer])
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(toast.kind == .error ? theme[.error] : theme[.secondaryContainer]))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(toast.title).font(theme.sans(15, weight: .medium)).foregroundStyle(theme[.onSurface]).lineLimit(1)
                    Text("•  now").font(theme.sans(13)).foregroundStyle(theme[.onSurfaceVariant]).fixedSize()
                }
                if !toast.message.isEmpty {
                    Text(toast.message).font(theme.sans(13.5)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: ToastsView.width - ToastsView.padding - ToastsView.edgePadding, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(toast.kind == .error ? theme[.secondaryContainer] : theme[.surfaceContainer].opacity(0.6)))
        .accessibilityIdentifier("toast.\(toast.kind.rawValue)")
    }
}
