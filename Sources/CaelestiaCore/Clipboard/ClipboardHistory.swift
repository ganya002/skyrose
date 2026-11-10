import Foundation

/// One thing the user copied. Images are PNG bytes. Passwords never get this far.
public struct ClipboardEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var text: String?
    public var imagePNG: Data?

    public init(id: UUID = UUID(), date: Date, text: String? = nil, imagePNG: Data? = nil) {
        self.id = id
        self.date = date
        self.text = text
        self.imagePNG = imagePNG
    }

    public var preview: String {
        if let text, !text.isEmpty { return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text }
        if imagePNG != nil { return "Image" }
        return ""
    }
}

/// Local clipboard history. Concealed and transient pasteboard items are refused.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public static let concealedType = "org.nspasteboard.ConcealedType"
    public static let transientType = "org.nspasteboard.TransientType"
    public static let blockedTypes: Set<String> = [concealedType, transientType]

    public var entries: [ClipboardEntry]
    public var maxEntries: Int
    public var maxBytes: Int
    public var paused: Bool

    public init(entries: [ClipboardEntry] = [], maxEntries: Int = 50, maxBytes: Int = 32 * 1024 * 1024, paused: Bool = false) {
        self.entries = entries
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(1, maxBytes)
        self.paused = paused
    }

    /// Records a copy. Returns false when it was skipped (paused, secret, empty, or a repeat of the newest).
    @discardableResult
    public mutating func record(text: String?, imagePNG: Data?, types: Set<String>, at date: Date) -> Bool {
        if paused { return false }
        if !types.isDisjoint(with: Self.blockedTypes) { return false }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = (trimmed?.isEmpty == false) ? trimmed : nil
        let image = (imagePNG?.isEmpty == false) ? imagePNG : nil
        guard words != nil || image != nil else { return false }
        if let newest = entries.first, newest.text == words, newest.imagePNG == image { return false }
        entries.insert(ClipboardEntry(date: date, text: words, imagePNG: image), at: 0)
        evict()
        return true
    }

    public mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func clear() { entries = [] }

    public var imageBytes: Int { entries.reduce(0) { $0 + ($1.imagePNG?.count ?? 0) } }

    private mutating func evict() {
        while entries.count > maxEntries { entries.removeLast() }
        while imageBytes > maxBytes, let index = entries.lastIndex(where: { $0.imagePNG != nil }) {
            entries.remove(at: index)
        }
    }
}

/// `~/Library/Application Support/SkyRose/clipboard`. Uninstall removes Application Support.
public enum ClipboardArchive {
    public static func index(in directory: URL) -> URL { directory.appendingPathComponent("index.json") }

    public static func save(_ history: ClipboardHistory, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let kept = Set(history.entries.map { $0.id.uuidString })
        if let names = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in names where url.pathExtension == "png" && !kept.contains(url.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        var stored = history
        for index in stored.entries.indices {
            guard let png = stored.entries[index].imagePNG else { continue }
            let url = directory.appendingPathComponent(stored.entries[index].id.uuidString + ".png")
            try png.write(to: url, options: .atomic)
            stored.entries[index].imagePNG = nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(stored).write(to: index(in: directory), options: .atomic)
    }

    public static func load(from directory: URL, maxEntries: Int = 50, maxBytes: Int = 32 * 1024 * 1024) -> ClipboardHistory {
        let url = index(in: directory)
        guard let data = try? Data(contentsOf: url) else { return ClipboardHistory(maxEntries: maxEntries, maxBytes: maxBytes) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var history = try? decoder.decode(ClipboardHistory.self, from: data) else {
            return ClipboardHistory(maxEntries: maxEntries, maxBytes: maxBytes)
        }
        history.maxEntries = maxEntries
        history.maxBytes = maxBytes
        for index in history.entries.indices where history.entries[index].imagePNG == nil {
            let png = directory.appendingPathComponent(history.entries[index].id.uuidString + ".png")
            history.entries[index].imagePNG = try? Data(contentsOf: png)
        }
        return history
    }
}
