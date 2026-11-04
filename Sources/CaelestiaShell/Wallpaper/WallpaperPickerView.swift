import AppKit
import CaelestiaCore
import SwiftUI

@MainActor
public final class WallpaperModel: ObservableObject {
    @Published public var shown = false
    @Published public var items: [URL] = []
    @Published public var message: String?
    @Published public var current: URL?
    @Published public var thumbs: [URL: NSImage] = [:]
    @Published public var loading = false
    public var onPick: (URL) -> Void = { _ in }
    public var onNeedThumb: (URL) -> Void = { _ in }
    public var onRandom: () -> Void = {}
    public init() {}
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
                content.padding(.horizontal, fillet + 4).padding(.top, 14).padding(.bottom, 12)
            }
            .frame(width: bodySize.width + 2 * fillet, height: bodySize.height)
            .offset(y: model.shown ? 0 : theme.slide(bodySize.height + 4))
            .animation(model.shown ? theme.drawerOpen : theme.drawerClose, value: model.shown)
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
                HStack {
                    Text("Wallpaper").font(theme.sans(13, weight: .semibold)).foregroundStyle(theme[.onSurface])
                    Text("\(model.items.count) images").font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant])
                    Spacer()
                    RoundIconButton(symbol: "shuffle", size: 26, action: model.onRandom)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.items, id: \.self) { url in
                            Button { model.onPick(url) } label: {
                                ZStack {
                                    theme[.surfaceContainerHigh]
                                    if let img = model.thumbs[url] { Image(nsImage: img).resizable().scaledToFill() }
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
}
