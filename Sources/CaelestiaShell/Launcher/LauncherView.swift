import AppKit
import CaelestiaCore
import SwiftUI

/// Launcher state: the query, the ranked rows, the selection. The view and the keyboard both go
/// through it, so it is testable without a window.
@MainActor
public final class LauncherModel: ObservableObject {
    @Published public var query = "" { didSet { if query != oldValue { selected = 0; refresh() } } }
    @Published public private(set) var items: [LauncherItem] = []
    @Published public var selected = 0
    /// Slides the drawer: 0 = closed (below the frame), 1 = open.
    @Published public var shown = false
    public var apps: [LaunchableApp] = [] { didSet { refresh() } }
    public var onActivate: (LauncherItem) -> Void = { _ in }
    public var onClose: () -> Void = {}

    /// Caelestia `launcher.maxShown` and sizes (measured on 1-launcher.jpg at 1 px = 1 pt).
    public static let maxShown = 7
    public static let itemWidth: Double = 600
    public static let itemHeight: Double = 57
    public static let itemSpacing: Double = 8
    public static let padding: Double = 15
    public static let searchHeight: Double = 48
    public static let gap: Double = 10

    public init() {}

    public func refresh() {
        items = LauncherSearch.results(for: query, apps: apps)
        selected = items.isEmpty ? 0 : min(selected, items.count - 1)
        if query.isEmpty || selected >= items.count { selected = 0 }
    }

    public func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
    }

    public func activateSelected() {
        guard items.indices.contains(selected) else { return }
        onActivate(items[selected])
    }

    public func reset() {
        query = ""
        selected = 0
        refresh()
    }

    /// Visible list rows (at least one so an empty result still shows a row of room).
    public var visibleRows: Int { max(1, min(Self.maxShown, items.count)) }

    public var listHeight: Double {
        Double(visibleRows) * Self.itemHeight + Double(visibleRows - 1) * Self.itemSpacing
    }

    /// Body size (without fillets).
    public var bodySize: CGSize {
        CGSize(width: Self.itemWidth + 2 * Self.padding,
               height: Self.padding + listHeight + Self.gap + Self.searchHeight + Self.padding)
    }

    public static var maxBodySize: CGSize {
        let list = Double(maxShown) * itemHeight + Double(maxShown - 1) * itemSpacing
        return CGSize(width: itemWidth + 2 * padding, height: padding + list + gap + searchHeight + padding)
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.shellTheme) var theme
    @FocusState private var focused: Bool
    let fillet: Double

    var body: some View {
        let size = model.bodySize
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                FrostedShape(shape: DrawerShape(edge: .bottom, radius: theme.frameRounding, fillet: fillet), theme: theme)
                    .liquidBody(edge: .bottom, shown: model.shown, depth: size.height, theme: theme)
                VStack(spacing: LauncherModel.gap) {
                    list
                    search
                }
                .padding(LauncherModel.padding)
                .frame(width: size.width)
                .liquidContent(edge: .bottom, shown: model.shown, depth: size.height, theme: theme)
            }
            .frame(width: size.width + 2 * fillet, height: size.height)
            .animation(theme.small, value: model.visibleRows)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: model.shown) { _, shown in if shown { focused = true } }
        .onAppear { focused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: LauncherModel.itemSpacing) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        LauncherRow(item: item, selected: index == model.selected)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selected = index
                                model.activateSelected()
                            }
                            .onHover { if $0 { model.selected = index } }
                    }
                }
            }
            .frame(height: model.listHeight)
            .onChange(of: model.selected) { _, new in
                guard model.items.indices.contains(new) else { return }
                withAnimation(theme.small) { proxy.scrollTo(model.items[new].id) }
            }
            .onChange(of: model.query) { _, _ in
                if let first = model.items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme[.onSurfaceVariant])
            TextField("", text: $model.query, prompt: Text("Type \">\" for commands").foregroundColor(theme[.onSurfaceVariant]))
                .textFieldStyle(.plain)
                .font(theme.sans(16))
                .foregroundStyle(theme[.onSurface])
                .focused($focused)
                .onSubmit { model.activateSelected() }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.tab) { model.move(1); return .handled }
                .onKeyPress(.escape) { model.onClose(); return .handled }
                .onKeyPress(keys: ["j", "k"]) { press in
                    guard press.modifiers.contains(.control) else { return .ignored }
                    model.move(press.characters == "j" ? 1 : -1)
                    return .handled
                }
                .accessibilityIdentifier("launcher.search")
        }
        .padding(.horizontal, 20)
        .frame(height: LauncherModel.searchHeight)
        .background(Capsule().fill(theme[.secondaryContainer].opacity(0.7)))
    }
}

struct LauncherRow: View {
    var item: LauncherItem
    var selected: Bool
    @Environment(\.shellTheme) var theme

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(theme.sans(20))
                    .foregroundStyle(theme[.onSurface])
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(theme.sans(16))
                    .foregroundStyle(theme[.outline])
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: LauncherModel.itemHeight)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(theme[.secondaryContainer].opacity(selected ? 0.6 : 0))
        )
        .animation(theme.small, value: selected)
    }

    @ViewBuilder private var icon: some View {
        switch item {
        case .app(let app):
            Image(nsImage: AppIconCache.icon(url: app.url)).resizable().interpolation(.high)
        case .command(let c):
            Image(systemName: ShellIcon.sf(c.icon))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme[.onSurfaceVariant])
        case .calc:
            Image(systemName: "equal.circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(theme[.primary])
        }
    }
}

/// SwiftUI front for `FrostedView`: blur masked to `shape` under the panel fill.
struct FrostedShape<S: Shape>: NSViewRepresentable {
    var shape: S
    var theme: ShellTheme
    var caps = NSEdgeInsets(top: 60, left: 60, bottom: 60, right: 60)

    func makeNSView(context: Context) -> FrostedView {
        let s = shape
        return FrostedView(shape: { rect in s.path(in: rect).cgPath }, caps: caps, fill: theme.panelFill)
    }

    func updateNSView(_ v: FrostedView, context: Context) {
        let s = shape
        v.shape = { rect in s.path(in: rect).cgPath }
        if v.fillColor != theme.panelFill { v.fillColor = theme.panelFill }
        v.refreshShape()
    }
}
