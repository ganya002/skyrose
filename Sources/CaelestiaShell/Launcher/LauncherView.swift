import AppKit
import CaelestiaCore
import SwiftUI

/// Launcher state: the query, the ranked rows, the selection. The view and the keyboard both go
/// through it, so it is testable without a window.
@MainActor
public final class LauncherModel: ObservableObject {
    @Published public var query = "" {
        didSet {
            guard query != oldValue else { return }
            selected = 0
            refresh()
            if isWallpaperMode { refreshWallpapers(searchChanged: wallpaperSearch(oldValue) != wallpaperSearch) }
        }
    }
    @Published public private(set) var items: [LauncherItem] = []
    @Published public var selected = 0
    /// Slides the drawer: 0 = closed (below the frame), 1 = open.
    @Published public var shown = false
    public var apps: [LaunchableApp] = [] { didSet { refresh() } }
    /// `>scheme `, `>variant ` and `>transparency ` choices (``LauncherCommand/options(_:addonSchemes:)``).
    public var options: [String: [LauncherCommand]] = [:] { didSet { refresh() } }
    public var onActivate: (LauncherItem) -> Void = { _ in }
    public var onClose: () -> Void = {}

    // MARK: Wallpaper carousel (`>wallpaper `, Caelestia WallpaperList)

    /// Every wallpaper of the folder; the carousel shows those matching the text after the command.
    public var wallpapers: [URL] = [] { didSet { if wallpapers != oldValue { refreshWallpapers(searchChanged: true) } } }
    @Published public private(set) var wallpaperResults: [URL] = []
    /// The centred item (PathView currentIndex); wraps around like a PathView.
    @Published public var wallpaperIndex = 0 { didSet { if wallpaperIndex != oldValue { previewCurrent() } } }
    @Published public var thumbs: [URL: NSImage] = [:]
    /// The wallpaper on the desktop when the launcher opened (the carousel starts on it).
    public var currentWallpaper: URL?
    /// Width the carousel may use on this display (screen − 4 × rounding − 2 × bar, Caelestia).
    @Published public var carouselRoom: Double = 1200
    /// The centred item changed: show it on the desktop (live preview).
    public var onPreview: (URL) -> Void = { _ in }
    public var onPickWallpaper: (URL) -> Void = { _ in }
    public var onNeedThumb: (URL) -> Void = { _ in }

    public static let wallpaperCommand = ">wallpaper "
    /// Caelestia `sizes.launcher.wallpaperWidth` / `wallpaperHeight`, `launcher.maxWallpapers`.
    public static let wallpaperWidth: Double = 280
    public static let wallpaperHeight: Double = 200
    public static let maxWallpapers = 9
    /// One PathView slot: the item at the neighbour scale plus padding.medium on both sides.
    public static var carouselItemWidth: Double { wallpaperWidth * 0.8 + 2 * padding }

    public var isWallpaperMode: Bool { query.hasPrefix(Self.wallpaperCommand) }
    public var wallpaperSearch: String { Self.wallpaperSearch(query) }
    private func wallpaperSearch(_ q: String) -> String { Self.wallpaperSearch(q) }
    static func wallpaperSearch(_ q: String) -> String {
        guard q.hasPrefix(wallpaperCommand) else { return "" }
        return String(q.dropFirst(wallpaperCommand.count)).trimmingCharacters(in: .whitespaces)
    }

    /// Items on the path (Caelestia numItems: what fits, at most 9, odd so one is centred).
    public static func carouselSlots(room: Double, count: Int) -> Int {
        let fit = max(0, Int((room / carouselItemWidth).rounded(.down)))
        let visible = min(fit, maxWallpapers, count)
        if visible == 2 { return 1 }
        if visible > 1, visible % 2 == 0 { return visible - 1 }
        return visible
    }

    public var carouselSlots: Int { Self.carouselSlots(room: carouselRoom, count: wallpaperResults.count) }

    /// Wallpapers matching `search` by file name (fuzzy), in folder order when empty.
    public static func filterWallpapers(_ urls: [URL], search: String) -> [URL] {
        guard !search.isEmpty else { return urls }
        return urls.compactMap { u -> (URL, Int)? in
            let name = u.deletingPathExtension().lastPathComponent
            return FuzzyMatcher.match(search, in: name).map { (u, $0.score) }
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    func refreshWallpapers(searchChanged: Bool) {
        let results = Self.filterWallpapers(wallpapers, search: wallpaperSearch)
        let before = wallpaperResults.indices.contains(wallpaperIndex) ? wallpaperResults[wallpaperIndex] : nil
        wallpaperResults = results
        // Caelestia: a search starts at the best match, no search at the desktop's wallpaper.
        let target: Int
        if !wallpaperSearch.isEmpty { target = 0 }
        else if !searchChanged, let before, let i = results.firstIndex(of: before) { target = i }
        else { target = currentWallpaper.flatMap { results.firstIndex(of: $0) } ?? 0 }
        if target != wallpaperIndex { wallpaperIndex = target } else { previewCurrent() }
    }

    private func previewCurrent() {
        guard isWallpaperMode, wallpaperResults.indices.contains(wallpaperIndex) else { return }
        onPreview(wallpaperResults[wallpaperIndex])
    }

    /// Signed distance of item `i` from the centre on the circular path.
    public static func pathOffset(_ i: Int, current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var r = ((i - current) % count + count) % count
        if r > count / 2 { r -= count }
        return r
    }

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
        items = LauncherSearch.results(for: query, apps: apps, options: options)
        selected = items.isEmpty ? 0 : min(selected, items.count - 1)
        if query.isEmpty || selected >= items.count { selected = 0 }
    }

    public func move(_ delta: Int) {
        if isWallpaperMode {
            let n = wallpaperResults.count
            guard n > 0 else { return }
            wallpaperIndex = ((wallpaperIndex + delta) % n + n) % n
            return
        }
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
    }

    public func activateSelected() {
        if isWallpaperMode {
            if wallpaperResults.indices.contains(wallpaperIndex) { onPickWallpaper(wallpaperResults[wallpaperIndex]) }
            return
        }
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

    /// Content size in wallpaper mode (Caelestia: max(itemWidth × 1.2, slots × slot), wallpaperHeight).
    public var carouselSize: CGSize {
        CGSize(width: max(Self.itemWidth * 1.2, Double(carouselSlots) * Self.carouselItemWidth), height: Self.wallpaperHeight)
    }

    /// Body size (without fillets).
    public var bodySize: CGSize {
        if isWallpaperMode {
            let c = carouselSize
            return CGSize(width: c.width + 2 * Self.padding, height: Self.padding + c.height + Self.gap + Self.searchHeight + Self.padding)
        }
        return CGSize(width: Self.itemWidth + 2 * Self.padding,
               height: Self.padding + listHeight + Self.gap + Self.searchHeight + Self.padding)
    }

    public static var maxBodySize: CGSize { maxBodySize(carouselRoom: 0) }

    /// The panel must hold both the app list and the widest carousel for this display.
    public static func maxBodySize(carouselRoom: Double) -> CGSize {
        let list = Double(maxShown) * itemHeight + Double(maxShown - 1) * itemSpacing
        let slots = carouselSlots(room: carouselRoom, count: maxWallpapers)
        let carousel = max(itemWidth * 1.2, Double(slots) * carouselItemWidth)
        let width = max(itemWidth, carouselRoom > 0 ? carousel : 0) + 2 * padding
        return CGSize(width: width, height: padding + list + gap + searchHeight + padding)
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
                DrawerBackground(edge: .bottom, fillet: fillet, radius: theme.frameRounding, shown: model.shown, depth: size.height)
                VStack(spacing: LauncherModel.gap) {
                    // Caelestia ContentList: the list fades out, the body morphs, the carousel fades in.
                    ZStack {
                        if model.isWallpaperMode {
                            WallpaperCarousel(model: model)
                                .frame(width: model.carouselSize.width, height: model.carouselSize.height)
                                .transition(.opacity)
                        } else {
                            list.transition(.opacity)
                        }
                    }
                    .animation(theme.small, value: model.isWallpaperMode)
                    search
                }
                .padding(LauncherModel.padding)
                .frame(width: size.width)
                .liquidContent(edge: .bottom, shown: model.shown, depth: size.height, theme: theme)
            }
            .frame(width: size.width + 2 * fillet, height: size.height)
            .animation(theme.spatial, value: model.visibleRows)
            .animation(theme.spatial, value: model.bodySize)
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
                withAnimation(theme.spatial) { proxy.scrollTo(model.items[new].id) }
            }
            .onChange(of: model.query) { _, _ in
                if let first = model.items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            MaterialIcon(model.isWallpaperMode ? "photo.on.rectangle.angled" : "magnifyingglass", size: 15, weight: .medium)
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
                .onKeyPress(.leftArrow) { guard model.isWallpaperMode else { return .ignored }; model.move(-1); return .handled }
                .onKeyPress(.rightArrow) { guard model.isWallpaperMode else { return .ignored }; model.move(1); return .handled }
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

/// The `>wallpaper ` carousel (Caelestia WallpaperList PathView + WallpaperItem): a horizontal,
/// circular path; the centre item at scale 1, the others on the path at 0.8, items leaving the path
/// shrink to 0 and new ones pop in from 0.5. Scrolling, arrows and Tab move it; each move previews
/// the wallpaper on the desktop.
struct WallpaperCarousel: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        let n = model.wallpaperResults.count
        let half = model.carouselSlots / 2
        let slot = LauncherModel.carouselItemWidth
        ZStack {
            if n == 0 {
                VStack(spacing: 6) {
                    MaterialIcon("photo.on.rectangle.angled", size: 30, weight: .light)
                    Text(model.wallpapers.isEmpty ? "No wallpapers found" : "No results").font(theme.sans(14, weight: .medium))
                    Text(model.wallpapers.isEmpty ? "Set appearance.wallpaperFolder in config.toml" : "Try searching for something else")
                        .font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant].opacity(0.8))
                }
                .foregroundStyle(theme[.onSurfaceVariant])
            }
            ForEach(Array(model.wallpaperResults.enumerated()), id: \.element) { i, url in
                let r = LauncherModel.pathOffset(i, current: model.wallpaperIndex, count: n)
                if abs(r) <= half + 1 {
                    CarouselItem(url: url, image: model.thumbs[url], current: r == 0, onPath: abs(r) <= half)
                        .offset(x: Double(r) * slot)
                        .animation(theme.spatial, value: r)
                        .zIndex(r == 0 ? 1 : 0)
                        .onTapGesture {
                            if r == 0 { model.activateSelected() } else { model.move(r) }
                        }
                        .onAppear { model.onNeedThumb(url) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(ScrollCatcher(onScroll: { model.move($0) }))
        .accessibilityIdentifier("launcher.wallpapers")
    }
}

struct CarouselItem: View {
    var url: URL
    var image: NSImage?
    var current: Bool
    var onPath: Bool
    @State private var appeared = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        let w = LauncherModel.wallpaperWidth
        let scale = appeared ? (current ? 1 : onPath ? 0.8 : 0) : 0.5
        VStack(spacing: 4) {
            ZStack {
                theme[.surfaceContainer]
                MaterialIcon("photo", size: 28, weight: .semibold).foregroundStyle(theme[.outline])
                if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFill().transition(.opacity) }
                if WallpaperLibrary.isLive(url) {
                    MaterialIcon("play.fill", size: 10, weight: .bold).foregroundStyle(.white)
                        .padding(6).background(Circle().fill(.black.opacity(0.45)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8)
                }
            }
            .frame(width: w, height: (w / 16 * 9).rounded())
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: .black.opacity(current ? 0.35 : 0), radius: 12, y: 5)
            .animation(theme.small, value: image != nil)
            Text(url.deletingPathExtension().lastPathComponent)
                .font(theme.sans(12, weight: .medium))
                .foregroundStyle(theme[.onSurface])
                .lineLimit(1).truncationMode(.tail)
                .frame(width: w - 30)
        }
        .animation(theme.spatial) { $0.scaleEffect(scale) }
        .animation(theme.small) { $0.opacity(appeared && onPath ? 1 : 0) }
        .onAppear { DispatchQueue.main.async { appeared = true } }
        .help(url.lastPathComponent)
    }
}

struct LauncherRow: View {
    var item: LauncherItem
    var selected: Bool
    @Environment(\.shellTheme) var theme

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(theme.sans(19))
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
            MaterialIcon(c.icon, size: 20, weight: .medium)
                .foregroundStyle(theme[.onSurfaceVariant])
        case .calc:
            MaterialIcon("equal.circle", size: 22, weight: .medium)
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
