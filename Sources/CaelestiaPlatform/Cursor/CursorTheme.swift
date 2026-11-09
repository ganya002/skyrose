import AppKit
import CaelestiaCore
import CoreGraphics
import Foundation

// Session-only cursor themes (Settings › Appearance › Cursor), the way Mousecape does it: the
// cursors are registered with the WindowServer for this login session through SkyLight's private
// cursor registry. Nothing on disk outside ~/Library/Application Support/SkyRose is touched, no
// SIP change is needed, and everything is gone at logout anyway.
//
// Live findings on macOS 27 (2026-11-05):
// - The legacy names (`com.apple.coregraphics.Arrow`, `IBeam`) accept a registration but the
//   system ignores it; the arrow and I-beam are `ArrowS` / `IBeamS` now.
// - `CoreCursorUnregisterAll` resets the `com.apple.cursor.N` set (resize, hand, crosshair, …)
//   but not the `coregraphics` names, so those are backed up first and written back on reset.
// - `com.apple.coregraphics.Wait` (the spinning wait cursor) cannot be put back once replaced
//   (`CGSRemoveRegisteredCursor` fails with 1000; re-registering the original does not take), so
//   it is never touched.

/// One cursor: its size in points, hotspot, and animation (frames stacked vertically in each image).
public struct CursorImage: @unchecked Sendable {
    public var size: CGSize
    public var hotSpot: CGPoint
    public var frameCount: Int
    public var frameDuration: Double
    /// One image per resolution (1x, 2x), each `frameCount` frames tall.
    public var images: [CGImage]

    public init(size: CGSize, hotSpot: CGPoint, frameCount: Int = 1, frameDuration: Double = 0, images: [CGImage]) {
        self.size = size
        self.hotSpot = hotSpot
        self.frameCount = frameCount
        self.frameDuration = frameDuration
        self.images = images
    }

    /// Same geometry and animation (what the registry reads back reliably).
    public func sameShape(as other: CursorImage) -> Bool {
        abs(size.width - other.size.width) < 0.01 && abs(size.height - other.size.height) < 0.01
            && abs(hotSpot.x - other.hotSpot.x) < 0.01 && abs(hotSpot.y - other.hotSpot.y) < 0.01
            && frameCount == other.frameCount
    }

    /// Same geometry and the same pixels in the first image.
    public func sameCursor(as other: CursorImage) -> Bool {
        guard sameShape(as: other), let a = images.first, let b = other.images.first else { return false }
        return Self.pixels(a) == Self.pixels(b)
    }

    static func pixels(_ image: CGImage) -> Data? {
        let w = image.width, h = image.height
        var data = Data(count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? data : nil
    }
}

/// The WindowServer's cursor registry (SkyLight in the app; a fake in tests).
public protocol CursorRegistry: AnyObject {
    func read(_ name: String) -> CursorImage?
    func register(_ name: String, _ cursor: CursorImage) -> Bool
    /// Resets the `com.apple.cursor.N` cursors to the system's.
    func unregisterAll() -> Bool
}

/// A Mousecape `.cape` file (a plist): cape name, identifier and cursors by registry name.
public struct CursorCape: @unchecked Sendable {
    public var identifier: String
    public var name: String
    public var author: String
    public var cursors: [String: CursorImage]

    public init(identifier: String, name: String, author: String = "", cursors: [String: CursorImage]) {
        self.identifier = identifier
        self.name = name
        self.author = author
        self.cursors = cursors
    }

    public static func load(_ url: URL) throws -> CursorCape {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let list = plist["Cursors"] as? [String: [String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var cursors: [String: CursorImage] = [:]
        for (name, c) in list {
            let reps = (c["Representations"] as? [Data] ?? []).compactMap { NSBitmapImageRep(data: $0)?.cgImage }
            guard !reps.isEmpty, let w = Self.double(c["PointsWide"]), let h = Self.double(c["PointsHigh"]) else { continue }
            cursors[name] = CursorImage(
                size: CGSize(width: w, height: h),
                hotSpot: CGPoint(x: Self.double(c["HotSpotX"]) ?? 0, y: Self.double(c["HotSpotY"]) ?? 0),
                frameCount: max(1, (c["FrameCount"] as? Int) ?? 1),
                frameDuration: Self.double(c["FrameDuration"]) ?? 0,
                images: reps
            )
        }
        let identifier = plist["Identifier"] as? String ?? url.deletingPathExtension().lastPathComponent
        return CursorCape(identifier: identifier, name: plist["CapeName"] as? String ?? identifier,
                          author: plist["Author"] as? String ?? "", cursors: cursors)
    }

    private static func double(_ v: Any?) -> Double? {
        (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue
    }
}

/// Finds capes: the cape bundled with SkyRose first, then SkyRose's own copy
/// (`~/Library/Application Support/SkyRose/cursors`), then Mousecape's library. A cape found only
/// in Mousecape's library is copied into SkyRose's folder, so the theme keeps working if Mousecape
/// is removed.
public struct CursorCapeLibrary: Sendable {
    public static let bundledIdentifier = "Bibata-Modern-Classic"
    public var bundledFolder: URL?
    public var ownFolder: URL
    public var searchFolders: [URL]

    public init(bundledFolder: URL? = CursorCapeLibrary.defaultBundledFolder,
                ownFolder: URL = Paths.appSupport.appendingPathComponent("cursors", isDirectory: true),
                searchFolders: [URL] = [Paths.home.appendingPathComponent("Library/Application Support/Mousecape/capes", isDirectory: true)]) {
        self.bundledFolder = bundledFolder
        self.ownFolder = ownFolder
        self.searchFolders = searchFolders
    }

    /// `Cursors/` inside the Platform resource bundle (Bibata Modern Classic). SwiftPM nests a
    /// copied Resources directory one level down, so both layouts are checked.
    public static var defaultBundledFolder: URL? {
        let root = Bundle.module.resourceURL
        return [root?.appendingPathComponent("Cursors", isDirectory: true),
                root?.appendingPathComponent("Resources/Cursors", isDirectory: true)]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Every cape found, the bundled one first, by identifier.
    public func available() -> [(identifier: String, name: String, url: URL)] {
        var seen = Set<String>()
        var out: [(String, String, URL)] = []
        for folder in [bundledFolder, ownFolder].compactMap({ $0 }) + searchFolders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "cape" {
                guard let meta = Self.meta(url), seen.insert(meta.identifier).inserted else { continue }
                out.append((meta.identifier, meta.name, url))
            }
        }
        return out
    }

    public func url(for identifier: String) -> URL? {
        available().first { $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame }?.url
    }

    /// Loads a cape by identifier, copying it into SkyRose's folder first if needed.
    public func load(_ identifier: String) throws -> CursorCape {
        guard let url = url(for: identifier) else { throw CocoaError(.fileNoSuchFile) }
        if url.deletingLastPathComponent().standardizedFileURL != ownFolder.standardizedFileURL {
            let copy = ownFolder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.copyItem(at: url, to: copy) }
        }
        return try CursorCape.load(url)
    }

    private static func meta(_ url: URL) -> (identifier: String, name: String)? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Cursors"] != nil else { return nil }
        let id = plist["Identifier"] as? String ?? url.deletingPathExtension().lastPathComponent
        return (id, plist["CapeName"] as? String ?? id)
    }
}

/// The cursors SkyRose replaced and what was there before, on disk
/// (`~/Library/Application Support/SkyRose/cursor-backup/`), so a reset works after a WM restart
/// or from the CLI. Kept only for the boot it was taken in (registrations end at logout).
public final class CursorBackupStore: @unchecked Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var name: String
        /// Nil: the name had no registration of its own (reset by `unregisterAll`).
        public var width: Double?
        public var height: Double?
        public var hotX: Double?
        public var hotY: Double?
        public var frameCount: Int?
        public var frameDuration: Double?
        /// PNG files, one per resolution.
        public var files: [String]?
    }

    struct Manifest: Codable {
        var version = 1
        var bootTime: Double
        var capeIdentifier: String
        var entries: [Entry]
    }

    public let folder: URL
    public init(folder: URL = Paths.appSupport.appendingPathComponent("cursor-backup", isDirectory: true)) {
        self.folder = folder
    }

    var manifestURL: URL { folder.appendingPathComponent("backup.json") }

    func loadManifest(bootTime: Double) -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL), let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        return abs(m.bootTime - bootTime) < 2 ? m : nil
    }

    func save(_ m: Manifest) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(m).write(to: manifestURL, options: .atomic)
    }

    /// Writes `cursor`'s images as PNGs and returns its entry.
    func entry(for name: String, cursor: CursorImage?) throws -> Entry {
        guard let cursor else { return Entry(name: name) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [String] = []
        for (i, image) in cursor.images.enumerated() {
            let file = "\(name)-\(i).png"
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: folder.appendingPathComponent(file), options: .atomic)
            files.append(file)
        }
        return Entry(name: name, width: cursor.size.width, height: cursor.size.height, hotX: cursor.hotSpot.x, hotY: cursor.hotSpot.y,
                     frameCount: cursor.frameCount, frameDuration: cursor.frameDuration, files: files)
    }

    func cursor(for e: Entry) -> CursorImage? {
        guard let w = e.width, let h = e.height, let files = e.files, !files.isEmpty else { return nil }
        let images = files.compactMap { NSBitmapImageRep(data: (try? Data(contentsOf: folder.appendingPathComponent($0))) ?? Data())?.cgImage }
        guard images.count == files.count else { return nil }
        return CursorImage(size: CGSize(width: w, height: h), hotSpot: CGPoint(x: e.hotX ?? 0, y: e.hotY ?? 0),
                           frameCount: e.frameCount ?? 1, frameDuration: e.frameDuration ?? 0, images: images)
    }

    public func remove() { try? FileManager.default.removeItem(at: folder) }
    public var exists: Bool { FileManager.default.fileExists(atPath: manifestURL.path) }
}

/// Applies a cape for this session and puts the macOS cursors back.
public final class CursorThemeManager: @unchecked Sendable {
    /// Never replaced: macOS cannot restore it (see the file comment).
    public static let neverTouched: Set<String> = ["com.apple.coregraphics.Wait"]
    static let legacyToCurrent = ["com.apple.coregraphics.Arrow": "com.apple.coregraphics.ArrowS",
                                  "com.apple.coregraphics.IBeam": "com.apple.coregraphics.IBeamS"]

    public struct Report: Sendable, Equatable {
        public var applied: [String] = []
        public var failed: [String] = []
        public var skipped: [String] = []
        public var ok: Bool { failed.isEmpty && !applied.isEmpty }
    }

    public struct ResetReport: Sendable, Equatable {
        public var restored: [String] = []
        public var failed: [String] = []
        public var ok: Bool { failed.isEmpty }
    }

    public let registry: CursorRegistry
    public let backup: CursorBackupStore
    let bootTime: Double

    public init(registry: CursorRegistry = SkyLightCursorRegistry.shared ?? NullCursorRegistry(),
                backup: CursorBackupStore = CursorBackupStore(), bootTime: Double = BootTime.current) {
        self.registry = registry
        self.backup = backup
        self.bootTime = bootTime
    }

    /// Registry name → cursor for this macOS: the legacy Arrow/IBeam go to their `S` names when
    /// the system has those; the wait cursor is left alone.
    public func plan(_ cape: CursorCape) -> (targets: [String: CursorImage], skipped: [String]) {
        var targets: [String: CursorImage] = [:]
        var skipped: [String] = []
        let modern = registry.read("com.apple.coregraphics.ArrowS") != nil
        for (name, cursor) in cape.cursors {
            if Self.neverTouched.contains(name) { skipped.append(name); continue }
            if modern, let to = Self.legacyToCurrent[name] {
                if cape.cursors[to] == nil { targets[to] = cursor }  // a cape's own S cursor wins
                continue
            }
            targets[name] = cursor
        }
        return (targets, skipped.sorted())
    }

    /// Backs up what is there (first time this boot only, never our own cursors), then registers
    /// every cursor of the cape and reads each back.
    public func apply(_ cape: CursorCape) throws -> Report {
        let (targets, skipped) = plan(cape)
        var manifest = backup.loadManifest(bootTime: bootTime)
            ?? CursorBackupStore.Manifest(bootTime: bootTime, capeIdentifier: cape.identifier, entries: [])
        var known = Set(manifest.entries.map(\.name))
        for name in targets.keys.sorted() where !known.contains(name) {
            let current = registry.read(name)
            if let current, current.sameCursor(as: targets[name]!) { continue }  // already ours
            manifest.entries.append(try backup.entry(for: name, cursor: current))
            known.insert(name)
        }
        manifest.capeIdentifier = cape.identifier
        try backup.save(manifest)  // before any cursor changes

        var report = Report(skipped: skipped)
        for name in targets.keys.sorted() {
            let cursor = targets[name]!
            if registry.register(name, cursor), let back = registry.read(name), back.sameShape(as: cursor) {
                report.applied.append(name)
            } else {
                report.failed.append(name)
            }
        }
        return report
    }

    /// True when every cursor of the cape is still registered (macOS can drop them on wake).
    public func isApplied(_ cape: CursorCape) -> Bool {
        let (targets, _) = plan(cape)
        return targets.allSatisfy { name, cursor in registry.read(name)?.sameShape(as: cursor) == true }
    }

    /// Puts back every cursor SkyRose replaced. Safe to call when nothing was applied.
    @discardableResult
    public func reset() -> ResetReport {
        var report = ResetReport()
        let manifest = backup.loadManifest(bootTime: bootTime)
        _ = registry.unregisterAll()
        for e in manifest?.entries ?? [] {
            guard e.files != nil else { report.restored.append(e.name); continue }
            guard let original = backup.cursor(for: e) else { report.failed.append(e.name); continue }
            if registry.register(e.name, original), registry.read(e.name)?.sameShape(as: original) == true {
                report.restored.append(e.name)
            } else {
                report.failed.append(e.name)
            }
        }
        if report.ok { backup.remove() }
        return report
    }
}

/// No registry (the private symbols are missing): every call fails.
public final class NullCursorRegistry: CursorRegistry {
    public init() {}
    public func read(_ name: String) -> CursorImage? { nil }
    public func register(_ name: String, _ cursor: CursorImage) -> Bool { false }
    public func unregisterAll() -> Bool { false }
}

/// SkyLight's cursor registry, resolved at run time (no link-time dependency on private API).
public final class SkyLightCursorRegistry: CursorRegistry, @unchecked Sendable {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias Register = @convention(c) (Int32, UnsafeMutablePointer<CChar>, Bool, Bool, CGSize, CGPoint, UInt, CGFloat, CFArray, UnsafeMutablePointer<Int32>) -> Int32
    private typealias CopyImages = @convention(c) (Int32, UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CGSize>, UnsafeMutablePointer<CGPoint>,
                                                   UnsafeMutablePointer<UInt>, UnsafeMutablePointer<CGFloat>, UnsafeMutablePointer<Unmanaged<CFArray>?>) -> Int32
    private typealias UnregisterAll = @convention(c) (Int32) -> Int32

    private let connection: Int32
    private let registerFn: Register
    private let copyFn: CopyImages
    private let unregisterAllFn: UnregisterAll

    public static let shared: SkyLightCursorRegistry? = SkyLightCursorRegistry()

    private init?() {
        _ = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        _ = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)
        let all = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let main = dlsym(all, "CGSMainConnectionID"), let reg = dlsym(all, "CGSRegisterCursorWithImages"),
              let copy = dlsym(all, "CGSCopyRegisteredCursorImages"), let unreg = dlsym(all, "CoreCursorUnregisterAll") else {
            Log.wm.error("cursor registry: private symbols not found; cursor themes are unavailable")
            return nil
        }
        connection = unsafeBitCast(main, to: MainConnection.self)()
        registerFn = unsafeBitCast(reg, to: Register.self)
        copyFn = unsafeBitCast(copy, to: CopyImages.self)
        unregisterAllFn = unsafeBitCast(unreg, to: UnregisterAll.self)
    }

    public func read(_ name: String) -> CursorImage? {
        var size = CGSize.zero, hot = CGPoint.zero, frames: UInt = 0, duration: CGFloat = 0
        var array: Unmanaged<CFArray>?
        let err = name.withCString { copyFn(connection, UnsafeMutablePointer(mutating: $0), &size, &hot, &frames, &duration, &array) }
        guard err == 0, let list = array?.takeRetainedValue() else { return nil }
        let images = (list as [AnyObject]).compactMap { obj -> CGImage? in
            CFGetTypeID(obj) == CGImage.typeID ? (obj as! CGImage) : nil
        }
        guard !images.isEmpty else { return nil }
        return CursorImage(size: size, hotSpot: hot, frameCount: Int(frames), frameDuration: Double(duration), images: images)
    }

    public func register(_ name: String, _ cursor: CursorImage) -> Bool {
        var seed: Int32 = 0
        let err = name.withCString {
            registerFn(connection, UnsafeMutablePointer(mutating: $0), true, true, cursor.size, cursor.hotSpot,
                       UInt(cursor.frameCount), CGFloat(cursor.frameDuration), cursor.images as CFArray, &seed)
        }
        return err == 0
    }

    public func unregisterAll() -> Bool { unregisterAllFn(connection) == 0 }
}
