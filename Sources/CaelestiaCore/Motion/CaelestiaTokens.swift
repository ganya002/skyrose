import Foundation

/// Caelestia's animation tokens (`plugin/src/Caelestia/Config/tokens.hpp` @ bcbb5d5): Material 3
/// Expressive curves and durations. Shell surfaces use them scaled by
/// `appearance.anim.durations.scale` (Gabby: 0.8, so defaultSpatial ≈ 400 ms). Positions, sizes
/// and scale use the Spatial curves (they overshoot); opacity and colour use the Effects curves.
///
/// This supersedes the older "nothing over ~350 ms" cap for shell panels; window animations
/// (`LiquidMotion`, `AnimationTable`) are unchanged.
public enum CaelestiaTokens {
    public enum Curve: String, CaseIterable, Sendable {
        case emphasizedAccel, emphasizedDecel, standard, standardAccel, standardDecel
        case fastSpatial, defaultSpatial, slowSpatial
        case fastEffects, defaultEffects, slowEffects

        public var bezier: CubicBezier {
            switch self {
            case .emphasizedAccel: return CubicBezier(x1: 0.3, y1: 0, x2: 0.8, y2: 0.15)
            case .emphasizedDecel: return CubicBezier(x1: 0.05, y1: 0.7, x2: 0.1, y2: 1)
            case .standard: return CubicBezier(x1: 0.2, y1: 0, x2: 0, y2: 1)
            case .standardAccel: return CubicBezier(x1: 0.3, y1: 0, x2: 1, y2: 1)
            case .standardDecel: return CubicBezier(x1: 0, y1: 0, x2: 0, y2: 1)
            case .fastSpatial: return CubicBezier(x1: 0.42, y1: 1.67, x2: 0.21, y2: 0.9)
            case .defaultSpatial: return CubicBezier(x1: 0.38, y1: 1.21, x2: 0.22, y2: 1)
            case .slowSpatial: return CubicBezier(x1: 0.39, y1: 1.29, x2: 0.35, y2: 0.98)
            case .fastEffects: return CubicBezier(x1: 0.31, y1: 0.94, x2: 0.34, y2: 1)
            case .defaultEffects: return CubicBezier(x1: 0.34, y1: 0.8, x2: 0.34, y2: 1)
            case .slowEffects: return CubicBezier(x1: 0.34, y1: 0.88, x2: 0.34, y2: 1)
            }
        }

        /// Raw duration (ms, before the scale) Caelestia pairs with the curve.
        public var milliseconds: Double {
            switch self {
            case .fastSpatial: return Duration.fastSpatial
            case .defaultSpatial: return Duration.defaultSpatial
            case .slowSpatial: return Duration.slowSpatial
            case .fastEffects: return Duration.fastEffects
            case .defaultEffects: return Duration.defaultEffects
            case .slowEffects: return Duration.slowEffects
            case .emphasizedAccel, .emphasizedDecel, .standard, .standardAccel, .standardDecel: return Duration.normal
            }
        }

        /// Spatial curves overshoot (y > 1); Reduce Motion swaps them for `standard`.
        public var overshoots: Bool { self == .fastSpatial || self == .defaultSpatial || self == .slowSpatial }
    }

    /// Raw durations in ms (`Appearance.anim.durations`).
    public enum Duration {
        public static let small: Double = 200
        public static let normal: Double = 400
        public static let large: Double = 600
        public static let extraLarge: Double = 1000
        public static let fastSpatial: Double = 350
        public static let defaultSpatial: Double = 500
        public static let slowSpatial: Double = 650
        public static let fastEffects: Double = 150
        public static let defaultEffects: Double = 200
        public static let slowEffects: Double = 300
    }

    /// Gabby's `appearance.anim.durations.scale`.
    public static let gabbyScale: Double = 0.8
    /// Caelestia `appearance.deformScale` default.
    public static let deformScale: Double = 1
    /// Panel radius (`rounding.extraLarge`).
    public static let panelRadius: Double = 28

    /// Drawer open and close times in ms, before `durations.scale`. Re-measured frame by frame on the
    /// H.264 clips of full-2026-11-05 (04-caelestia/*_open/close.mp4, scale 0.8) against SkyRose
    /// recorded the same way: each token scaled by reference ÷ SkyRose visible time (2026-11-11).
    public enum DrawerMs {
        public static let launcher = (open: 400.0, close: 212.5)
        public static let dashboard = (open: 525.0, close: 237.5)
        public static let sidebar = (open: 287.5, close: 162.5)
        public static let utilities = (open: 437.5, close: 150.0)
        public static let session = (open: 225.0, close: 212.5)
        /// osd_open.mp4: in over ~175 ms visible; out ~60 ms.
        public static let osd = (open: 225.0, close: 187.5)
        /// notification_popup.mp4: in over ~300 ms at Gabby's 0.8 scale.
        public static let notifications = (open: 375.0, close: 187.5)
        /// Not measured on their own: the default open token and the middle of the close range.
        public static let other = (open: Duration.defaultSpatial, close: 187.5)
    }

    /// Upstream per-panel `deformAmount` (ContentWindow.qml PanelBg).
    public enum DeformAmount {
        public static let dashboard = 0.1
        public static let launcher = 0.1
        public static let session = 0.2
        public static let sidebar = 0.03
        public static let osd = 0.25
        public static let notifications = 0.15
        public static let utilitiesWithSidebar = 0.1
        public static let utilities = 0.15
        public static let popoutDetached = 0.05
        public static let popoutOpen = 0.15
        public static let popout = 0.1
    }
}
