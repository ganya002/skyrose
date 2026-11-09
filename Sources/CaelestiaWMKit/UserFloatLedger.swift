import Foundation

/// Windows the user explicitly floated or tiled, so the choice survives an app relaunch and a
/// reboot. The key is the app plus the window's identity (subrole and title): two windows of the
/// same app with the same title share a choice. A float rule still floats a window that has no
/// entry here. Dialogs, sheets and panels stay floating until the user tiles that exact window.
public struct UserFloatLedger: Codable, Equatable, Sendable {
    public enum Choice: String, Codable, Sendable {
        case floating
        case tiled
    }

    public var choices: [String: Choice]

    public init(choices: [String: Choice] = [:]) {
        self.choices = choices
    }

    public static func key(bundleID: String, subrole: String, title: String) -> String {
        [bundleID, subrole, title].joined(separator: "\u{1f}")
    }

    public func choice(bundleID: String, subrole: String, title: String) -> Choice? {
        choices[Self.key(bundleID: bundleID, subrole: subrole, title: title)]
    }

    public mutating func set(_ choice: Choice, bundleID: String, subrole: String, title: String) {
        guard !bundleID.isEmpty else { return }
        choices[Self.key(bundleID: bundleID, subrole: subrole, title: title)] = choice
    }

    public static func load(from url: URL) -> UserFloatLedger {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let ledger = try? JSONDecoder().decode(UserFloatLedger.self, from: data) else {
            return UserFloatLedger()
        }
        return ledger
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
