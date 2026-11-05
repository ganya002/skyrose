import Foundation

/// Wallpaper folder scanning and small pure helpers (the picker and `skyrose wallpaper list`).
public enum WallpaperLibrary {
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]
    /// Live wallpapers: looped muted on the desktop (`LiveWallpaperController`).
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    public static var extensions: Set<String> { imageExtensions.union(videoExtensions) }
    /// Sub-folder levels scanned below the wallpaper folder (Static/, Live/, Live/Anime/, …).
    public static let maxDepth = 3

    public static func isLive(_ url: URL) -> Bool { videoExtensions.contains(url.pathExtension.lowercased()) }

    /// Wallpapers of one folder: `name` is the path below the wallpaper folder ("" for its top level).
    public struct Group: Equatable, Sendable, Identifiable {
        public var name: String
        public var urls: [URL]
        public var id: String { name }
        public var liveCount: Int { urls.filter(WallpaperLibrary.isLive).count }
        /// Label in the picker and Settings ("Wallpapers" for files directly in the folder).
        public var title: String { name.isEmpty ? "Wallpapers" : name }
        public init(name: String, urls: [URL]) {
            self.name = name
            self.urls = urls
        }
    }

    public struct ScanResult: Equatable, Sendable {
        /// Every wallpaper, group by group (the top level first, then folders by name).
        public var urls: [URL]
        public var groups: [Group]
        /// Why the list is empty (missing folder, empty folder, not a folder).
        public var message: String?
        public init(urls: [URL], groups: [Group]? = nil, message: String? = nil) {
            self.urls = urls
            self.groups = groups ?? (urls.isEmpty ? [] : [Group(name: "", urls: urls)])
            self.message = message
        }
    }

    /// `~` and relative-to-home paths expanded; an empty string means the default folder.
    public static func folderURL(_ path: String) -> URL {
        let p = path.trimmingCharacters(in: .whitespaces)
        let raw = p.isEmpty ? "~/Pictures/Wallpapers" : p
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Images and videos in `folder` and its sub-folders (hidden files and non-media such as
    /// .md notes skipped), grouped by sub-folder, sorted by name. Never throws.
    public static func scan(folder: URL, fileManager fm: FileManager = .default) -> ScanResult {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir) else {
            return ScanResult(urls: [], message: "Folder not found: \(folder.path)")
        }
        guard isDir.boolValue else { return ScanResult(urls: [], message: "Not a folder: \(folder.path)") }
        guard fm.isReadableFile(atPath: folder.path),
              (try? fm.contentsOfDirectory(atPath: folder.path)) != nil else {
            return ScanResult(urls: [], message: "Cannot read \(folder.path)")
        }
        var groups: [Group] = []
        func byName(_ a: URL, _ b: URL) -> Bool {
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        func visit(_ dir: URL, name: String, depth: Int) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
            var files: [URL] = []
            var dirs: [URL] = []
            for url in entries {
                let v = try? url.resourceValues(forKeys: Set(keys))
                if v?.isDirectory == true {
                    if v?.isSymbolicLink != true, v?.isPackage != true { dirs.append(url) }
                } else if extensions.contains(url.pathExtension.lowercased()) {
                    files.append(url)
                }
            }
            if !files.isEmpty { groups.append(Group(name: name, urls: files.sorted(by: byName))) }
            guard depth < maxDepth else { return }
            for d in dirs.sorted(by: byName) {
                visit(d, name: name.isEmpty ? d.lastPathComponent : name + "/" + d.lastPathComponent, depth: depth + 1)
            }
        }
        visit(folder, name: "", depth: 0)
        let urls = groups.flatMap(\.urls)
        return ScanResult(urls: urls, groups: groups, message: urls.isEmpty ? "No wallpapers in \(folder.path)" : nil)
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
