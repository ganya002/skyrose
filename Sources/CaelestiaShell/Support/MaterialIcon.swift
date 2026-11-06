import CaelestiaCore
import SwiftUI

/// One shell icon, like Caelestia's `MaterialIcon`: a Material Symbols Rounded ligature with its
/// FILL and wght axes, drawn on a square of the SF size it replaces so layouts do not move. Without
/// the font (not downloaded) or for a name with no Material equivalent, the SF Symbol.
///
/// `name` is a Material name ("wifi_off") or an SF name ("wifi.slash"); see ``ShellIcon/glyph(_:)``.
/// `fill` forces the filled/outlined variant; nil keeps the one the name implies.
public struct MaterialIcon: View {
    @Environment(\.shellTheme) private var theme
    var name: String
    var size: Double
    var weight: Font.Weight
    var fill: Bool?

    public init(_ name: String, size: Double, weight: Font.Weight = .regular, fill: Bool? = nil) {
        self.name = name
        self.size = size
        self.weight = weight
        self.fill = fill
    }

    public var body: some View {
        let g = ShellIcon.glyph(name)
        // `theme.fontGeneration` is read so a font download re-renders the icon in Material.
        if let m = g.material, theme.fontGeneration >= 0, ShellIcon.materialAvailable {
            let px = size * ShellIcon.materialScale
            Text(verbatim: m)
                .font(Font(ShellIcon.materialFont(size: px, weight: ShellIcon.materialWeight(weight), fill: fill ?? g.fill)))
                .lineLimit(1)
                .fixedSize()
                .frame(width: px, height: px)
                .accessibilityLabel(Text(m.replacingOccurrences(of: "_", with: " ")))
        } else {
            Image(systemName: g.sf).font(.system(size: size, weight: weight))
        }
    }
}
