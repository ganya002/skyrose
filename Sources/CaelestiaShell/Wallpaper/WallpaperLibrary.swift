import Foundation

/// Wallpaper folder scanning and small pure helpers (the picker and `caelestia wallpaper list`).
public enum WallpaperLibrary {
    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]

    public struct ScanResult: Equatable, Sendable {
        public var urls: [URL]
        /// Why the list is empty (missing folder, empty folder, not a folder).
        public var message: String?
    }

    /// `~` and relative-to-home paths expanded; an empty string means the default folder.
    public static func folderURL(_ path: String) -> URL {
        let p = path.trimmingCharacters(in: .whitespaces)
        let raw = p.isEmpty ? "~/Pictures/Wallpapers" : p
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Images directly in `folder`, hidden files skipped, sorted by name. Never throws.
    public static func scan(folder: URL, fileManager fm: FileManager = .default) -> ScanResult {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir) else {
            return ScanResult(urls: [], message: "Folder not found: \(folder.path)")
        }
        guard isDir.boolValue else { return ScanResult(urls: [], message: "Not a folder: \(folder.path)") }
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return ScanResult(urls: [], message: "Cannot read \(folder.path)")
        }
        let images = entries
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return ScanResult(urls: images, message: images.isEmpty ? "No images in \(folder.path)" : nil)
    }

    /// A stable cache key for a thumbnail (FNV-1a over path, modification time and size).
    public static func thumbnailKey(path: String, modified: TimeInterval, size: Int) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in "\(path)|\(Int(modified))|\(size)".utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }

    /// A random image other than `current` (when there is a choice).
    public static func random(from urls: [URL], excluding current: URL?, using rng: inout some RandomNumberGenerator) -> URL? {
        let pool = urls.count > 1 ? urls.filter { $0 != current } : urls
        return pool.randomElement(using: &rng)
    }
}
