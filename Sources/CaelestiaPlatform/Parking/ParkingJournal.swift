import CaelestiaCore
import CoreGraphics
import Foundation

/// One parked window: enough to find it again after a WM crash (the CGWindowID stays valid while
/// the owning app lives; pid/bundle id/title are fallbacks) and the frame to restore.
public struct ParkedWindowRecord: Codable, Hashable, Sendable {
    public var windowID: UInt32
    public var pid: Int32
    public var bundleID: String
    public var title: String
    /// Frame to restore (top-left space).
    public var restoreFrame: CGRect
    /// Stable id of the display the window was on.
    public var displayID: String?
    public var parkedAt: Date

    public init(
        windowID: UInt32, pid: Int32, bundleID: String, title: String, restoreFrame: CGRect,
        displayID: String? = nil, parkedAt: Date = Date()
    ) {
        self.windowID = windowID
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
        self.restoreFrame = restoreFrame
        self.displayID = displayID
        self.parkedAt = parkedAt
    }
}

/// On-disk journal of parked windows (`Paths.parkedWindowsJournal`, spec 4.4 / 10.10). The record
/// is written BEFORE a window is moved off-screen and removed only after it is back, so a crash at
/// any point leaves enough on disk for the next launch (or `caelestia wm restore-all`, or the
/// uninstaller) to bring every window back. Thread-safe; writes are atomic.
///
/// Format: `{"version": 1, "windows": [ParkedWindowRecord...]}`, ISO-8601 dates, sorted keys.
/// A corrupt file is moved aside (never deleted) and treated as empty.
public final class ParkingJournal: @unchecked Sendable {
    public static let formatVersion = 1

    public let url: URL
    private let lock = NSLock()
    private var cache: [UInt32: ParkedWindowRecord]?

    public init(url: URL = Paths.parkedWindowsJournal) {
        self.url = url
    }

    private struct Document: Codable {
        var version: Int
        var windows: [ParkedWindowRecord]
    }

    /// Every record, oldest first.
    public func records() -> [ParkedWindowRecord] {
        lock.withLock { load().values.sorted { ($0.parkedAt, $0.windowID) < ($1.parkedAt, $1.windowID) } }
    }

    public func record(for windowID: UInt32) -> ParkedWindowRecord? {
        lock.withLock { load()[windowID] }
    }

    /// Adds or replaces a record. A window parked twice keeps its FIRST restore frame (the second
    /// "frame" would be the parked one).
    public func upsert(_ record: ParkedWindowRecord) throws {
        try lock.withLock {
            var all = load()
            var next = record
            if let existing = all[record.windowID] { next.restoreFrame = existing.restoreFrame }
            all[record.windowID] = next
            try save(all)
        }
    }

    public func remove(_ windowID: UInt32) throws {
        try lock.withLock {
            var all = load()
            guard all.removeValue(forKey: windowID) != nil else { return }
            try save(all)
        }
    }

    public func removeAll() throws {
        try lock.withLock { try save([:]) }
    }

    private func load() -> [UInt32: ParkedWindowRecord] {
        if let cache { return cache }
        var result: [UInt32: ParkedWindowRecord] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let doc = try? decoder.decode(Document.self, from: data) {
                for r in doc.windows { result[r.windowID] = r }
            } else {
                let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
                try? FileManager.default.moveItem(at: url, to: aside)
                Log.wm.error("parking journal was corrupt; moved to \(aside.path, privacy: .public)")
            }
        }
        cache = result
        return result
    }

    private func save(_ all: [UInt32: ParkedWindowRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let doc = Document(version: Self.formatVersion, windows: all.values.sorted { $0.windowID < $1.windowID })
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(doc).write(to: url, options: .atomic)
        cache = all
    }
}
