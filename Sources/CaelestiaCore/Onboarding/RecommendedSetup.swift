import Foundation

/// What "Use recommended" decides, before anything is written.
public enum RecommendedDecision: Equatable, Sendable {
    /// Write the recommended value.
    case apply
    /// It is already the recommended value.
    case already
    /// Leave it, and say why.
    case skip(String)
}

/// The five things the first-run recommended step offers as one button.
public enum RecommendedSetup {
    public static let dockTitle = "Hide the Dock"
    public static let menuBarTitle = "Hide the menu bar"
    public static let cursorTitle = "Bibata cursor"
    public static let wallpaperTitle = "Starter wallpaper"
    public static let cornersTitle = "Screen corners"

    public static let cursorName = "Bibata-Modern-Classic"

    public static func dock(hidden: Bool) -> RecommendedDecision { hidden ? .already : .apply }

    public static func menuBar(autoHides: Bool) -> RecommendedDecision { autoHides ? .already : .apply }

    /// `configured` is `appearance.cursor`. Empty means the macOS cursors.
    public static func cursor(configured: String, capeAvailable: Bool) -> RecommendedDecision {
        if !capeAvailable { return .skip("Bibata is not in this copy of SkyRose.") }
        if configured == cursorName { return .already }
        return .apply
    }

    /// A starter picture is set only when SkyRose has never set one and the pictures ship in the app.
    public static func wallpaper(alreadySet: Bool, bundled: Bool) -> RecommendedDecision {
        if alreadySet { return .already }
        if !bundled { return .skip("This copy has no starter pictures, so your wallpaper stays.") }
        return .apply
    }

    /// Recommended corners are the automatic ones (`displayCornerRadius` negative).
    public static func corners(displayCornerRadius: Double) -> RecommendedDecision {
        displayCornerRadius < 0 ? .already : .apply
    }
}
