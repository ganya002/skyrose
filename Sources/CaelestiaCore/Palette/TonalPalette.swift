import Foundation

/// One hue and chroma at every tone 0...100 (Material You tonal palette).
public struct TonalPalette: Equatable, Sendable {
    public var hue: Double
    public var chroma: Double

    public init(hue: Double, chroma: Double) {
        self.hue = ColorMath.sanitizeDegrees(hue)
        self.chroma = chroma
    }

    public func tone(_ t: Double) -> RGBA {
        Hct(hue: hue, chroma: chroma, tone: t).rgba
    }
}
