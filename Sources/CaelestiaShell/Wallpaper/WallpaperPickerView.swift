import AppKit
import CaelestiaCore
import SwiftUI

@MainActor
public final class WallpaperModel: ObservableObject {
    @Published public var shown = false
    @Published public var items: [URL] = []
    /// Sub-folders of the wallpaper folder (Static/, Live/, …); the chips filter by them.
    @Published public var groups: [WallpaperLibrary.Group] = []
    /// nil = every group.
    @Published public var selectedGroup: String?
    @Published public var message: String?
    @Published public var current: URL?
    @Published public var thumbs: [URL: NSImage] = [:]
    @Published public var loading = false
    public var onPick: (URL) -> Void = { _ in }
    public var onNeedThumb: (URL) -> Void = { _ in }
    public var onRandom: () -> Void = {}
    public init() {}

    /// What the strip shows: the selected group, or everything.
    public var visibleItems: [URL] {
        guard let name = selectedGroup, let g = groups.first(where: { $0.name == name }) else { return items }
        return g.urls
    }
}

struct WallpaperPickerView: View {
    @ObservedObject var model: WallpaperModel
    @Environment(\.shellTheme) var theme
    let fillet: Double
    var bodySize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                FrostedShape(shape: DrawerShape(edge: .bottom, radius: theme.frameRounding, fillet: fillet), theme: theme)
                    .liquidBody(edge: .bottom, shown: model.shown, depth: bodySize.height, theme: theme)
                content.padding(.horizontal, fillet + 4).padding(.top, 14).padding(.bottom, 12)
                    .liquidContent(edge: .bottom, shown: model.shown, depth: bodySize.height, theme: theme)
            }
            .frame(width: bodySize.width + 2 * fillet, height: bodySize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var content: some View {
        if let message = model.message, model.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30, weight: .light))
                Text(message).font(theme.sans(13)).multilineTextAlignment(.center)
                Text("Set `appearance.wallpaperFolder` in config.toml").font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant].opacity(0.8))
            }
            .foregroundStyle(theme[.onSurfaceVariant]).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("Wallpaper").font(theme.sans(13, weight: .semibold)).foregroundStyle(theme[.onSurface])
                    if model.groups.count > 1 {
                        chip("All", count: model.items.count, selected: model.selectedGroup == nil) { model.selectedGroup = nil }
                        ForEach(model.groups) { g in
                            chip(g.title, count: g.urls.count, selected: model.selectedGroup == g.name) { model.selectedGroup = g.name }
                        }
                    } else {
                        Text("\(model.items.count) wallpapers").font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant])
                    }
                    Spacer()
                    RoundIconButton(symbol: "shuffle", size: 26, action: model.onRandom)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.visibleItems, id: \.self) { url in
                            Button { model.onPick(url) } label: {
                                ZStack(alignment: .bottomLeading) {
                                    theme[.surfaceContainerHigh]
                                    if let img = model.thumbs[url] { Image(nsImage: img).resizable().scaledToFill() }
                                    if WallpaperLibrary.isLive(url) {
                                        Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                            .padding(6).background(Circle().fill(.black.opacity(0.45))).padding(7)
                                    }
                                }
                                .frame(width: 168, height: 102)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(model.current == url ? theme[.primary] : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .help(url.lastPathComponent)
                            .onAppear { model.onNeedThumb(url) }
                            .accessibilityIdentifier("wallpaper.item")
                        }
                    }
                    .padding(.horizontal, 2).padding(.vertical, 3)
                }
            }
        }
    }

    private func chip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(theme.sans(11, weight: .medium))
                Text("\(count)").font(theme.sans(10)).opacity(0.75)
            }
            .foregroundStyle(selected ? theme[.onPrimary] : theme[.onSurfaceVariant])
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(selected ? theme[.primary] : theme[.surfaceContainerHigh]))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wallpaper.group")
    }
}
