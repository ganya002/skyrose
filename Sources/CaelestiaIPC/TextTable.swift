import Foundation

/// Minimal aligned-column table for terminal output (no box drawing, two-space gutters).
/// Column widths are measured in Unicode scalars so chords like "⌥L + ⇧ + Left" line up.
public struct TextTable: Equatable, Sendable {
    public struct Column: Equatable, Sendable {
        public var title: String
        public var rightAligned: Bool
        public var maxWidth: Int?

        public init(_ title: String, rightAligned: Bool = false, maxWidth: Int? = nil) {
            self.title = title
            self.rightAligned = rightAligned
            self.maxWidth = maxWidth
        }
    }

    public var columns: [Column]
    public var rows: [[String]]
    /// Print the header row and a dashed rule under it.
    public var showsHeader: Bool

    public init(columns: [Column], rows: [[String]] = [], showsHeader: Bool = true) {
        self.columns = columns
        self.rows = rows
        self.showsHeader = showsHeader
    }

    public init(_ titles: [String], rows: [[String]] = [], showsHeader: Bool = true) {
        self.init(columns: titles.map { Column($0) }, rows: rows, showsHeader: showsHeader)
    }

    public mutating func addRow(_ cells: [String]) {
        rows.append(cells)
    }

    /// Renders the table; every line is trimmed of trailing spaces and ends with `\n`.
    public func render() -> String {
        let count = columns.count
        var widths = columns.map { showsHeader ? TextTable.width($0.title) : 0 }
        let padded = rows.map { row -> [String] in
            var r = row.map { $0.replacingOccurrences(of: "\n", with: " ") }
            while r.count < count { r.append("") }
            return Array(r.prefix(count))
        }
        let cells = padded.map { row in
            zip(row, columns).map { cell, col in
                if let mx = col.maxWidth, TextTable.width(cell) > mx { return TextTable.truncate(cell, to: mx) }
                return cell
            }
        }
        for row in cells {
            for (i, cell) in row.enumerated() { widths[i] = max(widths[i], TextTable.width(cell)) }
        }
        var lines: [String] = []
        if showsHeader {
            lines.append(line(columns.map(\.title), widths: widths, aligns: columns.map(\.rightAligned)))
            lines.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
        }
        for row in cells { lines.append(line(row, widths: widths, aligns: columns.map(\.rightAligned))) }
        return lines.map { $0.trimmingTrailingSpaces() + "\n" }.joined()
    }

    private func line(_ cells: [String], widths: [Int], aligns: [Bool]) -> String {
        var parts: [String] = []
        for (i, cell) in cells.enumerated() {
            let pad = String(repeating: " ", count: max(0, widths[i] - TextTable.width(cell)))
            parts.append(aligns[i] ? pad + cell : cell + pad)
        }
        return parts.joined(separator: "  ")
    }

    static func width(_ s: String) -> Int { s.unicodeScalars.count }

    static func truncate(_ s: String, to max: Int) -> String {
        guard max > 1 else { return String(s.unicodeScalars.prefix(max)) }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.prefix(max - 1))
        return String(scalars) + "…"
    }
}

extension String {
    func trimmingTrailingSpaces() -> String {
        var s = Substring(self)
        while s.last == " " { s.removeLast() }
        return String(s)
    }
}

/// Renders IPC query results as tables for the terminal (`caelestia query ...` without --json).
public enum QueryFormatter {
    public static func windows(_ entries: [WindowQueryEntry]) -> String {
        var t = TextTable(columns: [
            .init("ADDRESS"), .init("WS", rightAligned: true), .init("AT"), .init("SIZE"), .init("FLAGS"),
            .init("CLASS", maxWidth: 32), .init("TITLE", maxWidth: 48), .init("PID", rightAligned: true), .init("FOCUS", rightAligned: true),
        ])
        for w in entries.sorted(by: { ($0.workspace.id, $0.focusHistoryID) < ($1.workspace.id, $1.focusHistoryID) }) {
            var flags: [String] = []
            if w.floating { flags.append("float") }
            if w.pinned { flags.append("pin") }
            if w.fullscreen == 1 { flags.append("max") }
            if w.fullscreen == 2 { flags.append("full") }
            if w.hidden == true || w.minimized == true { flags.append("hidden") }
            t.addRow([
                w.address, w.workspace.name, pair(w.at), pair(w.size), flags.joined(separator: ","),
                w.class, w.title, String(w.pid), String(w.focusHistoryID),
            ])
        }
        return t.render()
    }

    public static func workspaces(_ entries: [WorkspaceQueryEntry]) -> String {
        var t = TextTable(columns: [
            .init("ID", rightAligned: true), .init("NAME"), .init("MONITOR"), .init("WINDOWS", rightAligned: true),
            .init("FULLSCREEN"), .init("LAST WINDOW"), .init("ACTIVE"),
        ])
        for w in entries.sorted(by: { $0.id < $1.id }) {
            t.addRow([String(w.id), w.name, w.monitor, String(w.windows), w.hasfullscreen ? "yes" : "", w.lastwindow, w.active == true ? "*" : ""])
        }
        return t.render()
    }

    public static func monitors(_ entries: [MonitorQueryEntry]) -> String {
        var t = TextTable(columns: [
            .init("NAME"), .init("ID"), .init("SIZE"), .init("ORIGIN"), .init("SCALE", rightAligned: true),
            .init("RESERVED"), .init("WORKSPACE"), .init("SPECIAL"), .init("FOCUSED"),
        ])
        for m in entries {
            t.addRow([
                m.name, m.id, "\(m.width)x\(m.height)", "\(m.x),\(m.y)", trimmedNumber(m.scale),
                m.reserved.map(String.init).joined(separator: ","), m.activeWorkspace.name, m.specialWorkspace.name, m.focused ? "*" : "",
            ])
        }
        return t.render()
    }

    public static func binds(_ entries: [BindQueryEntry]) -> String {
        var t = TextTable(columns: [
            .init("ID"), .init("MAC"), .init("LINUX"), .init("ACTION"), .init("FLAGS"), .init("DESCRIPTION", maxWidth: 48),
        ])
        for b in entries {
            var flags: [String] = []
            if b.release { flags.append("release") }
            if b.repeat { flags.append("repeat") }
            if b.locked { flags.append("locked") }
            if b.mouse { flags.append("mouse") }
            if !b.enabled { flags.append("disabled") }
            t.addRow([b.id, b.mac.joined(separator: " | "), b.keys.joined(separator: " | "), b.actionDescription, flags.joined(separator: ","), b.description])
        }
        return t.render()
    }

    /// Generic key/value rendering for objects (e.g. `query state`, `permissions status`).
    public static func keyValues(_ object: [String: JSONValue]) -> String {
        var t = TextTable(["KEY", "VALUE"], showsHeader: false)
        for key in object.keys.sorted() {
            t.addRow([key, scalar(object[key]!)])
        }
        return t.render()
    }

    /// Renders any result: arrays of objects become tables, objects become key/value lists,
    /// scalars print as text.
    public static func render(_ result: JSONValue?, command: IPCCommand?) -> String {
        guard let result else { return "" }
        if let command {
            switch command {
            case .queryWindows:
                if let v: [WindowQueryEntry] = try? result.decode() { return windows(v) }
            case .queryWorkspaces:
                if let v: [WorkspaceQueryEntry] = try? result.decode() { return workspaces(v) }
            case .queryMonitors:
                if let v: [MonitorQueryEntry] = try? result.decode() { return monitors(v) }
            case .queryBinds, .keysList:
                if let v: [BindQueryEntry] = try? result.decode() { return binds(v) }
            default:
                break
            }
        }
        switch result {
        case .null: return ""
        case .bool, .number, .string: return scalar(result) + "\n"
        case .object(let o): return keyValues(o)
        case .array(let items):
            let objects = items.compactMap(\.objectValue)
            if !objects.isEmpty, objects.count == items.count {
                let keys = objects.reduce(into: Set<String>()) { $0.formUnion($1.keys) }.sorted()
                var t = TextTable(keys.map { $0.uppercased() })
                for o in objects { t.addRow(keys.map { o[$0].map(scalar) ?? "" }) }
                return t.render()
            }
            return items.map { scalar($0) + "\n" }.joined()
        }
    }

    static func scalar(_ v: JSONValue) -> String {
        switch v {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .number(let d): return trimmedNumber(d)
        case .string(let s): return s
        case .array, .object: return v.compactJSON
        }
    }

    static func trimmedNumber(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }

    static func pair(_ a: [Int]) -> String {
        a.map(String.init).joined(separator: ",")
    }
}
