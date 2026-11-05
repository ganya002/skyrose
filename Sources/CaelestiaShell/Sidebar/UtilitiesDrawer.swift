import AppKit
import SwiftUI

/// The standalone utilities drawer (Caelestia `utilities`): keep awake, volume/brightness and
/// quick toggles in a blob growing out of the bottom-right corner. Opened by hovering that corner
/// or `drawers utilities`; with the sidebar open the same controls show at its bottom instead.
@MainActor
public final class UtilitiesDrawerModel: ObservableObject {
    @Published public var shown = false
    /// The drawer's own height (fillets included); its panel is taller by the overshoot room.
    @Published public var bodyHeight: Double = 0
    public init() {}
}

struct UtilitiesDrawerView: View {
    @ObservedObject var model: UtilitiesDrawerModel
    @ObservedObject var sidebar: SidebarModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme
    let fillet: Double

    /// Padding around the controls inside the body (the fillets come on top, left and top).
    static let padding: Double = 12

    var body: some View {
        GeometryReader { proxy in
            let h = model.bodyHeight > 0 ? min(model.bodyHeight, proxy.size.height) : proxy.size.height
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                // Grows up out of the bottom band, like the launcher; the neck widens from the corner.
                ZStack(alignment: .bottomTrailing) {
                    FrostedShape(shape: CornerDrawerShape(radius: theme.frameRounding, fillet: fillet), theme: theme)
                        .liquidBody(edge: .bottom, shown: model.shown, depth: h, theme: theme, neckAnchor: .bottomTrailing)
                    UtilitiesSection(model: sidebar, state: state)
                        .padding(.leading, fillet + Self.padding).padding(.top, fillet + Self.padding)
                        .padding(.trailing, Self.padding).padding(.bottom, Self.padding)
                        .liquidContent(edge: .bottom, shown: model.shown, depth: h, theme: theme)
                }
                .frame(width: proxy.size.width, height: h)
            }
        }
    }

    /// The drawer's size for a body `width` (fillets included): the controls' own height.
    static func size(bodyWidth width: Double, fillet: Double, sidebar: SidebarModel, state: ShellState, theme: ShellTheme) -> CGSize {
        let content = width - 2 * padding
        let probe = NSHostingView(rootView: UtilitiesSection(model: sidebar, state: state)
            .environment(\.shellTheme, theme).frame(width: content))
        let h = probe.fittingSize.height
        return CGSize(width: width + fillet, height: (h + 2 * padding + fillet).rounded(.up))
    }
}
