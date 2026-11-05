import AppKit
import SwiftUI

/// The standalone utilities drawer (Caelestia `utilities`): keep awake, volume/brightness and
/// quick toggles in a blob growing out of the bottom-right corner. Opened by hovering that corner
/// or `drawers utilities`; with the sidebar open the same controls show at its bottom instead.
@MainActor
public final class UtilitiesDrawerModel: ObservableObject {
    @Published public var shown = false
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
            ZStack(alignment: .bottomTrailing) {
                FrostedShape(shape: CornerDrawerShape(radius: theme.frameRounding, fillet: fillet), theme: theme)
                UtilitiesSection(model: sidebar, state: state)
                    .padding(.leading, fillet + Self.padding).padding(.top, fillet + Self.padding)
                    .padding(.trailing, Self.padding).padding(.bottom, Self.padding)
            }
            // Grows up out of the bottom band, like the launcher.
            .offset(y: model.shown ? 0 : theme.slide(proxy.size.height + 4))
            .animation(model.shown ? theme.drawerOpen : theme.drawerClose, value: model.shown)
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
