import AppKit
import CaelestiaCore
import Foundation
import ImageIO

/// Wallpaper access: reads the configured folder, makes thumbnails off the main thread (cached on
/// disk and in memory), and sets the desktop picture on every display. Setting a wallpaper is an
/// explicit user action (picker click, `caelestia wallpaper set|random`).
@MainActor
public final class WallpaperService {
    public static let thumbnailSize = 320
    nonisolated static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CaelestiaMac/wallpaper-thumbs", isDirectory: true)
    }

    private let memory = NSCache<NSString, NSImage>()
    public private(set) var lastSet: URL?

    public init() {}

    /// Folder scan off the main thread.
    public func scan(folder: String, completion: @escaping @MainActor (WallpaperLibrary.ScanResult) -> Void) {
        let url = WallpaperLibrary.folderURL(folder)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = WallpaperLibrary.scan(folder: url)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }

    public func cachedThumbnail(for url: URL) -> NSImage? { memory.object(forKey: url.path as NSString) }

    /// Generates (or loads from the disk cache) a thumbnail without blocking the main thread.
    public func thumbnail(for url: URL, completion: @escaping @MainActor (NSImage?) -> Void) {
        if let hit = cachedThumbnail(for: url) { completion(hit); return }
        DispatchQueue.global(qos: .utility).async {
            let image = Self.makeThumbnail(url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let image { self.memory.setObject(image, forKey: url.path as NSString) }
                    completion(image)
                }
            }
        }
    }

    nonisolated static func makeThumbnail(_ url: URL) -> NSImage? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? Int) ?? 0
        let key = WallpaperLibrary.thumbnailKey(path: url.path, modified: modified, size: size)
        let cached = cacheDir.appendingPathComponent(key + ".jpg")
        if let data = try? Data(contentsOf: cached), let img = NSImage(data: data) { return img }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? jpeg.write(to: cached, options: .atomic)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Sets the desktop picture on all displays. Returns false (with a reason) on failure.
    @discardableResult
    public func apply(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return "File not found: \(url.path)" }
        var failure: String?
        for screen in NSScreen.screens {
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
            catch { failure = error.localizedDescription }
        }
        if failure == nil { lastSet = url }
        return failure
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
