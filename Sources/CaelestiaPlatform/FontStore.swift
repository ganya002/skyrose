import AppKit
import CaelestiaCore
import CoreText
import Foundation

/// Fetches, registers and (optionally) installs the ``FontPack``.
///
/// - **Download** (Settings › Appearance › Fonts, `skyrose fonts download`): every file is checked
///   against its pinned SHA-256 before it is kept, in `~/Library/Application Support/SkyRose/Fonts`.
/// - **Register** (the WM and Settings at start): the cached fonts are registered for *this
///   process only* (`CTFontManagerRegisterFontURLs`, `.process`), so the bar, shell and Settings
///   draw in Rubik / CaskaydiaCove without anything installed system-wide.
/// - **Install for kitty** (explicit): copies the files into `~/Library/Fonts` so other apps (kitty)
///   see them. Files already there are left alone; what was copied is listed in
///   `Fonts/installed.json` and journalled (`kind: font`) so uninstall removes exactly that.
public final class FontStore: @unchecked Sendable {
    public let cacheDirectory: URL
    public let userFontsDirectory: URL
    private let fetch: @Sendable (URL) async throws -> Data
    private let lock = NSLock()
    private var registered: Set<String> = []

    public init(cacheDirectory: URL = FontPack.cacheDirectory, userFontsDirectory: URL = FontPack.userFontsDirectory,
                fetch: (@Sendable (URL) async throws -> Data)? = nil) {
        self.cacheDirectory = cacheDirectory
        self.userFontsDirectory = userFontsDirectory
        self.fetch = fetch ?? { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FontStoreError.http(url.absoluteString, http.statusCode)
            }
            return data
        }
    }

    public static let shared = FontStore()

    public enum FontStoreError: Error, LocalizedError, Equatable {
        case http(String, Int)
        case checksum(String)
        public var errorDescription: String? {
            switch self {
            case .http(let url, let code): return "\(url): HTTP \(code)"
            case .checksum(let file): return "\(file): checksum mismatch (download discarded)"
            }
        }
    }

    public struct FamilyStatus: Equatable, Sendable {
        public var name: String
        public var downloaded: Bool
        /// Copied into ~/Library/Fonts by SkyRose.
        public var installedBySkyRose: Bool
        /// Visible to every app (installed by anyone, or by us).
        public var availableSystemWide: Bool
    }

    public var manifestURL: URL { cacheDirectory.appendingPathComponent("installed.json") }

    public func status() -> [FamilyStatus] {
        let installed = Set(installedPaths())
        return FontPack.families.map { f in
            let ours = f.files.allSatisfy { installed.contains(userFontsDirectory.appendingPathComponent($0.fileName).path) }
            return FamilyStatus(name: f.name, downloaded: FontPack.isCached(f, in: cacheDirectory), installedBySkyRose: ours,
                                availableSystemWide: ours || systemHasFamily(f.name))
        }
    }

    /// Downloads every missing family file and licence (verified); returns what was fetched.
    @discardableResult
    public func download(progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }) async throws -> [String] {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let assets = FontPack.families.flatMap { $0.files + [$0.licenceFile] }
        var fetched: [String] = []
        for (i, asset) in assets.enumerated() {
            progress(i, assets.count)
            if FontPack.looksCached(asset, in: cacheDirectory) { continue }
            guard let url = URL(string: asset.url) else { continue }
            let data = try await fetch(url)
            guard FontPack.verify(data, asset) else { throw FontStoreError.checksum(asset.fileName) }
            try data.write(to: cacheDirectory.appendingPathComponent(asset.fileName), options: .atomic)
            fetched.append(asset.fileName)
        }
        progress(assets.count, assets.count)
        return fetched
    }

    /// Registers every downloaded font for this process (idempotent). Returns the families
    /// newly registered.
    @discardableResult
    public func registerForProcess() -> [String] {
        var newly: [String] = []
        for f in FontPack.families where FontPack.isCached(f, in: cacheDirectory) {
            let done = lock.withLock { registered.contains(f.name) }
            if done { continue }
            // Already installed system-wide (by the user or "Install for kitty"): nothing to do.
            if systemHasFamily(f.name) { lock.withLock { _ = registered.insert(f.name) }; continue }
            let urls = f.files.map { cacheDirectory.appendingPathComponent($0.fileName) as CFURL } as CFArray
            CTFontManagerRegisterFontURLs(urls, .process, false, nil)
            lock.withLock { _ = registered.insert(f.name) }
            newly.append(f.name)
        }
        return newly
    }

    /// Copies the downloaded files of `families` (default: all) into ~/Library/Fonts.
    @discardableResult
    public func installForUser(families names: [String]? = nil, journal: BackupJournal? = nil) throws -> [String] {
        try FileManager.default.createDirectory(at: userFontsDirectory, withIntermediateDirectories: true)
        var paths = installedPaths()
        var notes: [String] = []
        for f in FontPack.families where names?.contains(f.name) ?? true {
            guard FontPack.isCached(f, in: cacheDirectory) else { notes.append("\(f.name): not downloaded"); continue }
            for asset in f.files {
                let dest = userFontsDirectory.appendingPathComponent(asset.fileName)
                if FileManager.default.fileExists(atPath: dest.path) { continue }
                try FileManager.default.copyItem(at: cacheDirectory.appendingPathComponent(asset.fileName), to: dest)
                paths.append(dest.path)
                try journal?.append(BackupEntry(domain: "fonts", key: dest.path, oldValue: .absent, newValue: .string(f.name),
                                                kind: .font, note: "\(f.name) (\(f.licence))"))
                notes.append("installed \(dest.lastPathComponent)")
            }
        }
        try writeInstalled(paths)
        return notes
    }

    /// Removes the files ``installForUser`` copied (never anything else).
    @discardableResult
    public func uninstallUser() throws -> [String] {
        var notes: [String] = []
        for path in installedPaths() where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
            notes.append("removed \(path)")
        }
        try writeInstalled([])
        return notes
    }

    /// Deletes the download cache (fonts stay registered until the process quits).
    public func removeDownloads() throws {
        for f in FontPack.families {
            for a in f.files + [f.licenceFile] {
                try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(a.fileName))
            }
        }
    }

    // MARK: Private

    func installedPaths() -> [String] {
        guard let data = try? Data(contentsOf: manifestURL), let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    private func writeInstalled(_ paths: [String]) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(Array(Set(paths)).sorted()).write(to: manifestURL, options: .atomic)
    }

    /// A family installed for every app: a font file of that family outside SkyRose's cache
    /// (process-only registrations of the cache do not count).
    func systemHasFamily(_ family: String) -> Bool {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        guard let descs = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] else { return false }
        let cache = cacheDirectory.standardizedFileURL.path
        return descs.contains { d in
            guard (CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String) == family else { return false }
            guard let url = CTFontDescriptorCopyAttribute(d, kCTFontURLAttribute) as? URL else { return true }
            return !url.standardizedFileURL.path.hasPrefix(cache)
        }
    }
}
