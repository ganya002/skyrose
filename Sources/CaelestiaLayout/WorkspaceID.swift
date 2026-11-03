import Foundation
import CaelestiaCore

/// Identifies a managed window. This is the window's CGWindowID (`kCGWindowNumber`).
public typealias WindowID = UInt32

/// A Hyprland-style workspace identifier: a numbered workspace (1...50 with five groups of ten)
/// or a named special workspace ("special", "sysmon", "music", "communication", "todo", ...).
///
/// The textual form matches Hyprland: `"3"` for `.numbered(3)` and `"special:music"` for
/// `.special("music")`. That form is used for `Codable` (single string value) and as a
/// dictionary key, so journals stay readable.
public enum WorkspaceID: Hashable, Sendable, CustomStringConvertible {
    case numbered(Int)
    case special(String)

    /// The default special workspace (Hyprland `special:special`).
    public static let defaultSpecial = WorkspaceID.special("special")

    /// Parses the Hyprland textual form: `"12"`, `"special"` or `"special:name"`.
    public init?(parsing text: String) {
        let s = text.trimmingCharacters(in: .whitespaces)
        if let n = Int(s), n >= 1 {
            self = .numbered(n)
        } else if s == "special" {
            self = .special("special")
        } else if s.hasPrefix("special:"), s.count > 8 {
            self = .special(String(s.dropFirst(8)))
        } else {
            return nil
        }
    }

    public var isSpecial: Bool {
        if case .special = self { return true }
        return false
    }

    /// The workspace number, or nil for special workspaces.
    public var number: Int? {
        if case .numbered(let n) = self { return n }
        return nil
    }

    /// The special workspace name, or nil for numbered workspaces.
    public var specialName: String? {
        if case .special(let s) = self { return s }
        return nil
    }

    public var description: String {
        switch self {
        case .numbered(let n): return String(n)
        case .special(let s): return "special:" + s
        }
    }
}

extension WorkspaceID: Comparable {
    /// Numbered workspaces sort by number and before special ones; specials sort by name.
    public static func < (a: WorkspaceID, b: WorkspaceID) -> Bool {
        switch (a, b) {
        case (.numbered(let x), .numbered(let y)): return x < y
        case (.numbered, .special): return true
        case (.special, .numbered): return false
        case (.special(let x), .special(let y)): return x < y
        }
    }
}

extension WorkspaceID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = WorkspaceID(parsing: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid workspace id \"\(text)\"")
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension WorkspaceID: CodingKeyRepresentable {
    public var codingKey: CodingKey { WorkspaceCodingKey(stringValue: description) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(parsing: codingKey.stringValue)
    }
}

struct WorkspaceCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Caelestia workspace arithmetic (hypr/utils/functions.lua `wsaction`): workspaces are numbered
/// `10·(group−1) + n` with `n` in 1...10. Five groups give workspaces 1...50.
public enum WorkspaceMath {
    /// Workspaces per group (Caelestia: 10).
    public static let defaultPerGroup = 10

    /// `10·(group−1) + n`.
    public static func number(n: Int, group: Int, perGroup: Int = defaultPerGroup) -> Int {
        perGroup * (group - 1) + n
    }

    /// 1-based group of a workspace number: 1...10 → 1, 11...20 → 2, ...
    public static func group(of number: Int, perGroup: Int = defaultPerGroup) -> Int {
        (max(number, 1) - 1) / perGroup + 1
    }

    /// 1-based slot inside the group (`wsaction` `slot = (id − 1) % 10 + 1`).
    public static func indexInGroup(of number: Int, perGroup: Int = defaultPerGroup) -> Int {
        (max(number, 1) - 1) % perGroup + 1
    }

    /// The workspace number `wsaction` starts from: the active numbered workspace, or 1 when the
    /// active workspace is special/named (no numbered group) or unknown.
    public static func baseNumber(of active: WorkspaceID?) -> Int {
        if case .numbered(let n)? = active, n >= 1 { return n }
        return 1
    }

    /// Plain `wsaction` (focus/move/move_silent, index `i` in 1...10): stays in the active
    /// workspace's group, `floor((id−1)/10)·10 + i`.
    public static func target(index i: Int, active: WorkspaceID?, perGroup: Int = defaultPerGroup) -> Int {
        (baseNumber(of: active) - 1) / perGroup * perGroup + i
    }

    /// Group `wsaction` (focus/move with "group", group `g` in 1...): keeps the active slot,
    /// `(g−1)·10 + slot`.
    public static func target(group g: Int, active: WorkspaceID?, perGroup: Int = defaultPerGroup) -> Int {
        (g - 1) * perGroup + indexInGroup(of: baseNumber(of: active), perGroup: perGroup)
    }
}
