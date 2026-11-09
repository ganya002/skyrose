import CryptoKit
import Foundation

/// Copies the wallpapers that ship with SkyRose into `~/Pictures/Wallpapers/Static`.
/// Files are named `SkyRose - <title>`. An existing file is never overwritten, and a file
/// whose bytes are already in that folder (any name) is skipped. Each copy is journaled
/// with its SHA-256 so uninstall removes only those files.
public enum StarterWallpapers {
    public static let collection = "SkyRose"

    /// Images inside the Core resource bundle. Missing when none are licensed to ship.
    public static var bundledFolder: URL? {
        let root = Bundle.module.resourceURL
        return [root?.appendingPathComponent("Wallpapers", isDirectory: true),
                root?.appendingPathComponent("Resources/Wallpapers", isDirectory: true)]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public struct Report: Equatable, Sendable {
        public var copied: [URL]
        public var skipped: [String]
        /// A starter picture to set when the user has no SkyRose wallpaper yet.
        public var suggested: URL?
    }

    /// `bundled` is the folder of images inside the app. `destination` is `Static/`.
    public static func install(bundled: URL, destination: URL, journal: BackupJournal, hasSkyRoseWallpaper: Bool) throws -> Report {
        let files = ((try? FileManager.default.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil)) ?? [])
            .filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var hashes = try hashes(in: destination)
        var copied: [URL] = []
        var skipped: [String] = []
        for src in files {
            let name = src.lastPathComponent
            guard name.hasPrefix("\(collection) - ") else { skipped.append("\(name): not a SkyRose title"); continue }
            let digest = sha256(url: src)
            let dest = destination.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) || hashes.contains(digest) {
                skipped.append(name)
                continue
            }
            try FileManager.default.copyItem(at: src, to: dest)
            hashes.insert(digest)
            try journal.append(BackupEntry(domain: "wallpapers", key: dest.path, oldValue: .absent, newValue: .string(digest),
                                            kind: .file, note: "starter wallpaper \(digest)"))
            copied.append(dest)
        }
        let suggested = hasSkyRoseWallpaper ? nil : (copied.first ?? files.first.map { destination.appendingPathComponent($0.lastPathComponent) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil })
        return Report(copied: copied, skipped: skipped, suggested: suggested)
    }

    public static func sha256(url: URL) -> String {
        let data = (try? Data(contentsOf: url)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hashes(in folder: URL) throws -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return Set(files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }.map(sha256(url:)))
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp"]
}
