import Foundation

/// Apple's menu bar, as Settings › Appearance offers it.
///
/// `shown` is the ordinary bar. `auto` hides it until the pointer touches the top edge.
/// `off` asks macOS to auto-hide and tells SkyRose not to reserve that strip. With SIP on,
/// macOS can still reveal the bar when the pointer touches the top. A peek shows it for a few seconds.
public enum MenuBarChoice: String, Codable, Equatable, Sendable {
    case shown, auto, off
}

public enum MenuBarChoiceStore {
    public static let fileName = "menu-bar-mode"

    public static func file(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public static func read(_ url: URL) -> MenuBarChoice? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return MenuBarChoice(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func write(_ choice: MenuBarChoice, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(choice.rawValue.utf8).write(to: url, options: .atomic)
    }
}

/// What SkyRose writes for a choice. `hides` is `_HIHideMenuBar`. `reserve` is the layout inset.
public enum MenuBarPlan {
    public static func hides(_ choice: MenuBarChoice) -> Bool { choice != .shown }
    public static func reserve(_ choice: MenuBarChoice) -> Bool { choice != .off }
}
