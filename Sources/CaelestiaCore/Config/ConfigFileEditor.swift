import Foundation

/// Minimal, comment-preserving edits to the user's `config.toml` (a tool such as
/// `caelestia frame calibrate` saves one key without rewriting the whole file with every default).
public enum ConfigFileEditor {
    /// Returns `text` with `key = value` set inside `[table]`. An existing `key` line in that
    /// table is replaced (its trailing comment dropped); otherwise the key is added after the
    /// table's last key line, and a missing table is appended at the end. `value` is TOML as-is.
    public static func setting(_ key: String, to value: String, inTable table: String, in text: String) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let entry = "\(key) = \(value)"
        guard let header = lines.firstIndex(where: { tableName(of: $0) == normalized(table) }) else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines.append("[\(table)]")
            lines.append(entry)
            return lines.joined(separator: "\n") + "\n"
        }
        var end = lines.count
        for i in (header + 1)..<lines.count where isHeader(lines[i]) {
            end = i
            break
        }
        var lastKeyLine = header
        for i in (header + 1)..<end {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            lastKeyLine = i
            if keyName(of: trimmed) == key {
                lines[i] = entry
                return lines.joined(separator: "\n") + "\n"
            }
        }
        lines.insert(entry, at: lastKeyLine + 1)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes `key = value` into `[table]` of the file at `url` (created with its folder if missing).
    public static func set(_ key: String, to value: String, inTable table: String, file url: URL) throws {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = setting(key, to: value, inTable: table, in: text)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(updated.utf8).write(to: url, options: .atomic)
    }

    /// `displays."<uuid>"` for a display id.
    public static func displayTable(_ id: String) -> String { "displays.\"\(id)\"" }

    /// A TOML float with at most two decimals (`10.0`, `10.25`).
    public static func number(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(format: "%.1f", r) : String(format: "%g", r)
    }

    static func isHeader(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    }

    static func tableName(of line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), !t.hasPrefix("[["), let close = t.firstIndex(of: "]") else { return nil }
        return normalized(String(t[t.index(after: t.startIndex)..<close]))
    }

    static func normalized(_ table: String) -> String {
        // `displays . "X"` and `displays."X"` name the same table; quoted parts keep their spaces.
        var out = ""
        var quoted = false
        for ch in table {
            if ch == "\"" { quoted.toggle() }
            if !quoted, ch == " " || ch == "\t" { continue }
            out.append(ch)
        }
        return out
    }

    static func keyName(of line: String) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        var k = line[..<eq].trimmingCharacters(in: .whitespaces)
        if k.hasPrefix("\""), k.hasSuffix("\""), k.count >= 2 { k = String(k.dropFirst().dropLast()) }
        return k
    }
}
