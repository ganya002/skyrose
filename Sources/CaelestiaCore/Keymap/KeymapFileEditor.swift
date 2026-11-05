import Foundation

/// Errors from ``KeymapFileEditor``.
public enum KeymapEditError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case unknownBind(String)
    /// The panic bind is fixed (the parser restores it anyway).
    case fixedBind(String)
    case rejected(String)
    case io(String)

    public var description: String {
        switch self {
        case .unknownBind(let id): return "no bind with id \"\(id)\""
        case .fixedBind(let id): return "\"\(id)\" is the panic bind; it cannot be changed"
        case .rejected(let reason): return "keymap not changed: \(reason)"
        case .io(let m): return m
        }
    }

    public var errorDescription: String? { description }
}

/// Edits one bind of the user's `keymap.toml` without rewriting the rest (comments stay). The
/// first edit copies the bundled default keymap to the user file. Every edit is parsed before it
/// is written; an edit that does not parse is rolled back. The WM's keymap watcher applies a good
/// edit within ~200 ms.
public struct KeymapFileEditor: Sendable {
    public let file: URL

    public init(file: URL = Paths.keymapFile) {
        self.file = file
    }

    /// The user's keymap text, or the bundled default when there is none yet.
    public func currentText() throws -> String {
        if let t = try? String(contentsOf: file, encoding: .utf8) { return t }
        return try KeymapLoader.defaultKeymapText()
    }

    /// Sets the chords of bind `id` (as written in keymap.toml, e.g. `"SUPER + T"`).
    @discardableResult
    public func setKeys(_ keys: [String], forBind id: String) throws -> Keymap {
        try edit(id) { Self.setting("keys", to: "[" + keys.map(ConfigFileEditor.string).joined(separator: ", ") + "]", forBind: id, in: $0) }
    }

    /// Turns bind `id` on or off.
    @discardableResult
    public func setEnabled(_ enabled: Bool, forBind id: String) throws -> Keymap {
        try edit(id) { Self.setting("enabled", to: enabled ? "true" : "false", forBind: id, in: $0) }
    }

    /// Puts bind `id` back to the bundled default (keys and enabled).
    @discardableResult
    public func resetBind(_ id: String) throws -> Keymap {
        let defaults = try KeymapLoader.loadDefaultOrThrow()
        guard let d = defaults.bind(id: id) else { throw KeymapEditError.unknownBind(id) }
        try setKeys(d.keys, forBind: id)
        return try setEnabled(d.enabled, forBind: id)
    }

    private func edit(_ id: String, _ change: (String) -> String?) throws -> Keymap {
        if id == KeymapParser.panicBind.id { throw KeymapEditError.fixedBind(id) }
        let before = try currentText()
        guard let after = change(before) else { throw KeymapEditError.unknownBind(id) }
        let keymap: Keymap
        do {
            keymap = try KeymapParser.parse(toml: after)
        } catch {
            throw KeymapEditError.rejected(String(describing: error))
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(after.utf8).write(to: file, options: .atomic)
        } catch {
            throw KeymapEditError.io("cannot write \(file.path): \(error.localizedDescription)")
        }
        return keymap
    }

    /// `text` with `key = value` set inside the `[[bind]]` whose `id` is `bindID`; nil when there
    /// is no such bind.
    public static func setting(_ key: String, to value: String, forBind bindID: String, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            guard lines[i].trimmingCharacters(in: .whitespaces) == "[[bind]]" else { i += 1; continue }
            var end = i + 1
            while end < lines.count, !ConfigFileEditor.isHeader(lines[end]) { end += 1 }
            let body = (i + 1)..<end
            let idLine = body.first { ConfigFileEditor.keyName(of: lines[$0].trimmingCharacters(in: .whitespaces)) == "id" }
            if let idLine, Self.stringValue(of: lines[idLine]) == bindID {
                let entry = "\(key) = \(value)"
                if let existing = body.first(where: {
                    let t = lines[$0].trimmingCharacters(in: .whitespaces)
                    return !t.hasPrefix("#") && ConfigFileEditor.keyName(of: t) == key
                }) {
                    // Keep the column alignment of the original (`keys        = [...]`).
                    let original = lines[existing]
                    if let eq = original.firstIndex(of: "=") {
                        lines[existing] = String(original[..<eq]) + "= " + value
                    } else {
                        lines[existing] = entry
                    }
                } else {
                    var last = idLine
                    for j in body where !lines[j].trimmingCharacters(in: .whitespaces).isEmpty { last = j }
                    lines.insert(entry, at: last + 1)
                }
                return lines.joined(separator: "\n")
            }
            i = end
        }
        return nil
    }

    static func stringValue(of line: String) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        var v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if let hash = v.range(of: " #") { v = String(v[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
        guard v.count >= 2, v.hasPrefix("\""), v.hasSuffix("\"") else { return nil }
        return String(v.dropFirst().dropLast())
    }
}
