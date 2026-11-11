import AppKit
import CaelestiaCore
import Foundation
import ImageIO

/// Wallpaper access: reads the configured folder, makes thumbnails off the main thread (cached on
/// disk and in memory), and sets the desktop picture on every display. Setting a wallpaper is an
/// explicit user action (picker click, `skyrose wallpaper set|random`).
@MainActor
public final class WallpaperService {
    public static let thumbnailSize = 320
    nonisolated static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SkyRose/wallpaper-thumbs", isDirectory: true)
    }

    private let memory = NSCache<NSString, NSImage>()
    public private(set) var lastSet: URL?

    public init() {}

    /// Folder scan off the main thread.
    public func scan(folder: String, completion: @escaping @MainActor (WallpaperLibrary.ScanResult) -> Void) {
        let url = WallpaperLibrary.folderURL(folder)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = WallpaperLibrary.withAddons(WallpaperLibrary.scan(folder: url))
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }

    /// The carousel's items are 280 pt wide (560 px on Retina).
    public static let carouselThumbnailSize = 640

    public func cachedThumbnail(for url: URL, maxPixel: Int = WallpaperService.thumbnailSize) -> NSImage? {
        memory.object(forKey: Self.memoryKey(url, maxPixel))
    }

    private static func memoryKey(_ url: URL, _ maxPixel: Int) -> NSString {
        (maxPixel == thumbnailSize ? url.path : "\(url.path)@\(maxPixel)") as NSString
    }

    /// Generates (or loads from the disk cache) a thumbnail without blocking the main thread.
    public func thumbnail(for url: URL, maxPixel: Int = WallpaperService.thumbnailSize, completion: @escaping @MainActor (NSImage?) -> Void) {
        if let hit = cachedThumbnail(for: url, maxPixel: maxPixel) { completion(hit); return }
        let key = Self.memoryKey(url, maxPixel)
        DispatchQueue.global(qos: .utility).async {
            let image = Self.makeThumbnail(url, maxPixel: maxPixel)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let image { self.memory.setObject(image, forKey: key) }
                    completion(image)
                }
            }
        }
    }

    nonisolated static func makeThumbnail(_ url: URL, maxPixel: Int = 320) -> NSImage? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? Int) ?? 0
        let key = WallpaperLibrary.thumbnailKey(path: url.path, modified: modified, size: size)
        let cached = cacheDir.appendingPathComponent(key + (maxPixel == 320 ? "" : "-\(maxPixel)") + ".jpg")
        if let data = try? Data(contentsOf: cached), let img = NSImage(data: data) { return img }
        guard let cg = thumbnailImage(url, maxPixel: maxPixel) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? jpeg.write(to: cached, options: .atomic)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// A downsampled image of a picture, or the first frame of a live wallpaper. Blocks.
    public nonisolated static func thumbnailImage(_ url: URL, maxPixel: Int) -> CGImage? {
        if WallpaperLibrary.isLive(url) { return LiveWallpaperStill.firstFrame(url, maxPixel: maxPixel) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// The restore manifest the wallpaper changes are recorded in (nil: not recorded). Set by the
    /// WM daemon; tests leave it nil so they never write the user's manifest.
    public var journal: BackupJournal?

    /// Sets the desktop picture on all displays. Returns false (with a reason) on failure.
    @discardableResult
    public func apply(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return "File not found: \(url.path)" }
        var failure: String?
        for screen in NSScreen.screens {
            record(url, on: screen)
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
            catch { failure = error.localizedDescription }
        }
        if failure == nil { lastSet = url }
        return failure
    }

    /// Records the display's picture from before SkyRose's first change (the uninstaller puts it
    /// back, but only on a display that still shows what SkyRose set last), then each new
    /// picture SkyRose sets (`newValue`, only when it changes).
    func record(_ url: URL, on screen: NSScreen) {
        guard let journal else { return }
        let id = Self.displayID(screen)
        do {
            let latest = try journal.entries().last { $0.kind == .wallpaper && $0.domain == id }
            if case .string(url.path)? = latest?.newValue { return }
            let before = NSWorkspace.shared.desktopImageURL(for: screen).map { BackupValue.string($0.path) } ?? .absent
            try journal.append(BackupEntry(domain: id, key: "wallpaper", oldValue: latest == nil ? before : latest!.oldValue,
                                           newValue: .string(url.path), kind: .wallpaper, note: screen.localizedName))
        } catch {
            Log.shell.error("wallpaper: restore manifest not written: \(String(describing: error), privacy: .public)")
        }
    }

    /// The display's stable UUID (as in `query monitors`), or its number when it has none.
    static func displayID(_ screen: NSScreen) -> String {
        let n = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue(), let s = CFUUIDCreateString(nil, uuid) as String? { return s }
        return "display-\(n)"
    }

    /// The wallpaper of the main display as macOS reports it (nil for dynamic / unknown).
    public func current() -> URL? {
        lastSet ?? NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }
}

/// Extracts the source colour of a wallpaper and caches it by file (path, mtime), so scheme
/// refreshes after wake / Space change cost one `stat`.
@MainActor
public final class WallpaperColors {
    private var cache: [String: RGBA?] = [:]
    public init() {}

    public static func key(_ url: URL) -> String {
        let m = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(Int(m))"
    }

    public func cached(for url: URL) -> RGBA?? { cache[Self.key(url)] }

    public func source(for url: URL, completion: @escaping @MainActor (RGBA?) -> Void) {
        let key = Self.key(url)
        if let hit = cache[key] { completion(hit); return }
        DispatchQueue.global(qos: .utility).async {
            let source = Self.loadPixels(url).flatMap { PaletteExtractor.sourceColor(rgba: $0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.cache[key] = .some(source)
                    completion(source)
                }
            }
        }
    }

    /// RGBA8 pixels of `url` downsampled to at most `maxPixel` on the long side.
    nonisolated static func loadPixels(_ url: URL, maxPixel: Int = 112) -> [UInt8]? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? data : nil
    }
}
