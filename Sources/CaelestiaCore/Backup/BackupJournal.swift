import Foundation

// MARK: - Values

/// A recorded setting value. `absent` means the key did not exist before we touched it (restore
/// deletes it). Encoded as `{"type": ..., "value": ...}` so the uninstall script can read it without
/// Swift.
public indirect enum BackupValue: Codable, Sendable, Hashable {
    case absent
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    /// Raw bytes, stored base64-encoded.
    case data(Data)
    case array([BackupValue])
    case dict([String: BackupValue])

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum Kind: String, Codable {
        case absent, string, int, double, bool, date, data, array, dict
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .absent: self = .absent
        case .string: self = .string(try c.decode(String.self, forKey: .value))
        case .int: self = .int(try c.decode(Int.self, forKey: .value))
        case .double: self = .double(try c.decode(Double.self, forKey: .value))
        case .bool: self = .bool(try c.decode(Bool.self, forKey: .value))
        case .date: self = .date(try c.decode(Date.self, forKey: .value))
        case .data:
            let base64 = try c.decode(String.self, forKey: .value)
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c, debugDescription: "invalid base64")
            }
            self = .data(data)
        case .array: self = .array(try c.decode([BackupValue].self, forKey: .value))
        case .dict: self = .dict(try c.decode([String: BackupValue].self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absent:
            try c.encode(Kind.absent, forKey: .type)
        case .string(let v):
            try c.encode(Kind.string, forKey: .type)
            try c.encode(v, forKey: .value)
        case .int(let v):
            try c.encode(Kind.int, forKey: .type)
            try c.encode(v, forKey: .value)
        case .double(let v):
            try c.encode(Kind.double, forKey: .type)
            try c.encode(v, forKey: .value)
        case .bool(let v):
            try c.encode(Kind.bool, forKey: .type)
            try c.encode(v, forKey: .value)
        case .date(let v):
            try c.encode(Kind.date, forKey: .type)
            try c.encode(v, forKey: .value)
        case .data(let v):
            try c.encode(Kind.data, forKey: .type)
            try c.encode(v.base64EncodedString(), forKey: .value)
        case .array(let v):
            try c.encode(Kind.array, forKey: .type)
            try c.encode(v, forKey: .value)
        case .dict(let v):
            try c.encode(Kind.dict, forKey: .type)
            try c.encode(v, forKey: .value)
        }
    }

    /// Converts a property-list object (as returned by `UserDefaults`/`CFPreferences`) into a value.
    /// Unsupported objects become their `description` string. `nil` becomes `absent`.
    public init(plist: Any?) {
        switch plist {
        case nil:
            self = .absent
        case let v as String:
            self = .string(v)
        case let v as NSNumber:
            // Swift Bool/Int/Double bridge to NSNumber; keep the plist type (bool vs integer vs real).
            if CFGetTypeID(v) == CFBooleanGetTypeID() {
                self = .bool(v.boolValue)
            } else if ["f", "d"].contains(String(cString: v.objCType)) {
                self = .double(v.doubleValue)
            } else {
                self = .int(v.intValue)
            }
        case let v as Date:
            self = .date(v)
        case let v as Data:
            self = .data(v)
        case let v as [Any]:
            self = .array(v.map { BackupValue(plist: $0) })
        case let v as [String: Any]:
            self = .dict(v.mapValues { BackupValue(plist: $0) })
        case let v?:
            self = .string(String(describing: v))
        }
    }

    /// The property-list object for this value (`nil` for `absent`), suitable for `UserDefaults.set`.
    public var plistValue: Any? {
        switch self {
        case .absent: return nil
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .date(let v): return v
        case .data(let v): return v
        case .array(let v): return v.map(\.plistValue).map { $0 ?? NSNull() }
        case .dict(let v): return v.compactMapValues(\.plistValue)
        }
    }

    public var isAbsent: Bool {
        if case .absent = self { return true }
        return false
    }
}

// MARK: - Entries

/// One recorded change (spec 10.4): `{domain, key, old value or absent, new value, timestamp}` plus
/// the kind of setting and an optional note.
public struct BackupEntry: Codable, Sendable, Hashable, Identifiable {
    /// What kind of setting was changed, which decides how Platform restores it.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A `defaults` key: `domain` is the preferences domain, `key` the key.
        case defaults
        /// A `hidutil` key remapping: `domain` is the device selector, `key` the mapping id.
        case hidutil
        /// A `com.apple.symbolichotkeys` entry: `key` is the hotkey number.
        case symbolichotkeys
        /// Desktop wallpaper: `domain` is the display id, `key` "wallpaper", values are file paths.
        case wallpaper
        /// `~/.config/kitty/kitty.conf` or an include: `key` is the file path.
        case kittyConfig
        /// A login item: `key` is the bundle id or path.
        case loginItem
        /// An installed font: `key` is the file path.
        case font
        /// Any other file we replaced: `key` is the file path, values are copies (see `copyOriginal`).
        case file
        /// A mode SkyRose ran in that changes the system around it (`key` e.g. "sipOff"). Nothing
        /// to write back; the uninstaller reads it to explain what the user must undo by hand.
        case mode
    }

    public var domain: String
    public var key: String
    public var oldValue: BackupValue
    public var newValue: BackupValue
    public var timestamp: Date
    public var kind: Kind
    public var note: String?

    public init(
        domain: String, key: String, oldValue: BackupValue, newValue: BackupValue, timestamp: Date = Date(),
        kind: Kind = .defaults, note: String? = nil
    ) {
        self.domain = domain
        self.key = key
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = timestamp
        self.kind = kind
        self.note = note
    }

    /// `domain` + `key` identify a setting across entries.
    public var id: String { "\(domain)\u{1F}\(key)" }
}

/// Errors raised by ``BackupJournal``.
public enum BackupError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case io(path: String, message: String)
    case corrupt(path: String, message: String)
    case missingSource(path: String)

    public var description: String {
        switch self {
        case .io(let path, let message): return "\(path): \(message)"
        case .corrupt(let path, let message): return "\(path): journal is corrupt: \(message)"
        case .missingSource(let path): return "\(path): file to back up does not exist"
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Journal

/// Append-only journal of every setting we change, stored as JSON at
/// `~/Library/Application Support/SkyRose/backup.json` (spec 10.4). Thread-safe. Restoration
/// (actually writing `defaults` back) is done by the Platform module from ``restorePlan()``.
///
/// File format: `{"version": 1, "entries": [BackupEntry...]}` with ISO-8601 timestamps and sorted keys,
/// rewritten atomically on each append (entries are never removed).
public final class BackupJournal: @unchecked Sendable {
    public static let formatVersion = 1

    public let url: URL
    private let lock = NSLock()

    /// - Parameter url: journal location; tests inject a temporary file.
    public init(url: URL = Paths.backupJournal) {
        self.url = url
    }

    private struct Document: Codable {
        var version: Int
        var entries: [BackupEntry]
    }

    /// Records a change. The first entry for a (domain, key) pair is the original value and is what
    /// ``restorePlan()`` restores.
    public func append(_ entry: BackupEntry) throws {
        try lock.withLock {
            var document = try readDocument()
            document.entries.append(entry)
            try writeDocument(document)
        }
    }

    /// Every entry in the order recorded (empty when the journal does not exist yet).
    public func entries() throws -> [BackupEntry] {
        try lock.withLock { try readDocument().entries }
    }

    /// The first (original) entry recorded for a setting, or `nil` if we never changed it.
    public func firstEntry(domain: String, key: String) throws -> BackupEntry? {
        try entries().first { $0.domain == domain && $0.key == key }
    }

    /// Whether a setting has ever been recorded (so callers back up only once per key).
    public func contains(domain: String, key: String) throws -> Bool {
        try firstEntry(domain: domain, key: key) != nil
    }

    /// One entry per (domain, key): the original `oldValue` and `kind` from the first record and the
    /// latest `newValue` (what we expect to find before restoring), ordered newest-first-changed, so
    /// restoring in order undoes our changes in reverse.
    public func restorePlan() throws -> [BackupEntry] {
        let all = try entries()
        var firstIndex: [String: Int] = [:]
        var latest: [String: BackupValue] = [:]
        for (i, entry) in all.enumerated() {
            if firstIndex[entry.id] == nil { firstIndex[entry.id] = i }
            latest[entry.id] = entry.newValue
        }
        return firstIndex.sorted { $0.value > $1.value }.map { id, index in
            var entry = all[index]
            if let newest = latest[id] { entry.newValue = newest }
            return entry
        }
    }

    /// Copies a file (e.g. the symbolichotkeys plist) next to the journal, under
    /// `originals/<yyyyMMdd-HHmmss>-<name>`, and returns the copy's location. The copy is never
    /// overwritten: a suffix is added when the name is taken.
    @discardableResult
    public func copyOriginal(file source: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BackupError.missingSource(path: source.path)
        }
        let directory = url.deletingLastPathComponent().appendingPathComponent("originals", isDirectory: true)
        let stamp = BackupJournal.stampFormatter.string(from: Date())
        return try lock.withLock {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var candidate = directory.appendingPathComponent("\(stamp)-\(source.lastPathComponent)")
                var counter = 1
                while FileManager.default.fileExists(atPath: candidate.path) {
                    candidate = directory.appendingPathComponent("\(stamp)-\(counter)-\(source.lastPathComponent)")
                    counter += 1
                }
                try FileManager.default.copyItem(at: source, to: candidate)
                return candidate
            } catch let error as BackupError {
                throw error
            } catch {
                throw BackupError.io(path: source.path, message: error.localizedDescription)
            }
        }
    }

    // MARK: Private

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private func readDocument() throws -> Document {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Document(version: BackupJournal.formatVersion, entries: [])
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.io(path: url.path, message: error.localizedDescription)
        }
        if data.isEmpty { return Document(version: BackupJournal.formatVersion, entries: []) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Document.self, from: data)
        } catch {
            throw BackupError.corrupt(path: url.path, message: String(describing: error))
        }
    }

    private func writeDocument(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(document)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw BackupError.io(path: url.path, message: error.localizedDescription)
        }
    }
}
