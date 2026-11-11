import CryptoKit
import Foundation

/// The public SkyStore index (`index.json` in ganya002/skystore-index), signed with Ed25519 in
/// `index.json.sig`. Each version names its bundle's URL and SHA-256, so the one signature
/// covers every bundle too.
public struct StoreIndex: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var schema: Int
    /// When the maintainer built it (ISO 8601); shown, not trusted for ordering.
    public var generated: String?
    /// Raised by every `skystore build` and covered by the signature. SkyRose refuses an index
    /// with a lower serial than one it already saw, so an old signed index cannot be replayed to
    /// hide a revocation. Missing = 0 (indexes from before the field).
    public var serial: Int?
    public var addons: [StoreEntry]

    public init(addons: [StoreEntry], generated: String? = nil, serial: Int? = nil) {
        schema = Self.schemaVersion
        self.generated = generated
        self.serial = serial
        self.addons = addons
    }

    public func entry(_ id: String) -> StoreEntry? { addons.first { $0.id == id } }

    /// Parses and checks an index already verified (or a test fixture).
    public static func decode(_ data: Data) throws -> StoreIndex {
        let index: StoreIndex
        do { index = try JSONDecoder().decode(StoreIndex.self, from: data) } catch {
            throw StoreError.badIndex(AddonManifest.describe(error))
        }
        guard index.schema == schemaVersion else { throw StoreError.badIndex("schema \(index.schema) is newer than this SkyRose (\(schemaVersion))") }
        var seen = Set<String>()
        for e in index.addons {
            guard AddonManifest.isValidID(e.id), seen.insert(e.id).inserted else { throw StoreError.badIndex("bad or repeated id '\(e.id)'") }
            for v in e.versions where !AddonManifest.isVersion(v.version) || v.sha256.count != 64 {
                throw StoreError.badIndex("\(e.id) \(v.version): bad version or sha256")
            }
        }
        return index
    }

    /// `data` signed by one of `keys` (base64 raw Ed25519 public keys); throws before parsing otherwise.
    public static func verified(data: Data, signature: Data, keys: [String]) throws -> StoreIndex {
        let trusted = keys.compactMap { Data(base64Encoded: $0) }.compactMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
        guard !trusted.isEmpty else { throw StoreError.noTrustedKey }
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sig = Data(base64Encoded: text), trusted.contains(where: { $0.isValidSignature(sig, for: data) }) else {
            throw StoreError.badSignature
        }
        return try decode(data)
    }
}

public struct StoreEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var author: String
    public var summary: String
    public var description: String?
    public var kind: AddonKind
    /// Store shelf ("Themes", "Wallpapers", …); the kind's title when empty.
    public var category: String?
    public var icon: URL?
    public var screenshots: [URL]?
    public var licence: String
    public var homepage: URL?
    public var featured: Bool?
    /// Kill switch: set by the maintainer, every installed copy is disabled.
    public var revoked: String?
    /// Newest last or first; `latest` sorts them.
    public var versions: [StoreVersion]

    public init(id: String, name: String, author: String, summary: String, description: String? = nil, kind: AddonKind,
                category: String? = nil, icon: URL? = nil, screenshots: [URL]? = nil, licence: String, homepage: URL? = nil,
                featured: Bool? = nil, revoked: String? = nil, versions: [StoreVersion]) {
        self.id = id
        self.name = name
        self.author = author
        self.summary = summary
        self.description = description
        self.kind = kind
        self.category = category
        self.icon = icon
        self.screenshots = screenshots
        self.licence = licence
        self.homepage = homepage
        self.featured = featured
        self.revoked = revoked
        self.versions = versions
    }

    public var shelf: String { (category?.isEmpty ?? true) ? kind.title : category! }

    /// Newest first.
    public var history: [StoreVersion] {
        versions.sorted { Updater.compare($0.version, $1.version) == .orderedDescending }
    }

    /// The newest version this SkyRose can install (not revoked, new enough SkyRose).
    public func latest(for skyRose: String = CaelestiaVersion.string) -> StoreVersion? {
        guard revoked == nil else { return nil }
        return history.first { $0.revoked == nil && Updater.compare($0.minSkyRose, skyRose) != .orderedDescending }
    }

    public func version(_ v: String) -> StoreVersion? { versions.first { $0.version == v } }

    public func matches(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [name, author, summary, description ?? "", shelf, kind.rawValue, id].contains { $0.lowercased().contains(q) }
    }
}

public struct StoreVersion: Codable, Equatable, Sendable, Identifiable {
    public var version: String
    public var minSkyRose: String
    /// The `.skyaddon` bundle (a release asset of the index repo).
    public var url: URL
    public var sha256: String
    public var size: Int
    public var permissions: [String]
    /// ISO date.
    public var released: String
    public var notes: String?
    public var revoked: String?
    public var id: String { version }

    public init(version: String, minSkyRose: String, url: URL, sha256: String, size: Int, permissions: [String] = [], released: String,
                notes: String? = nil, revoked: String? = nil) {
        self.version = version
        self.minSkyRose = minSkyRose
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.permissions = permissions
        self.released = released
        self.notes = notes
        self.revoked = revoked
    }

    public var parsedPermissions: [AddonPermission] { permissions.compactMap(AddonPermission.init) }
}

/// Where the index comes from and how it is fetched.
public struct StoreSource: Sendable {
    /// Gabby's index. Must be HTTPS.
    public static let defaultIndexURL = "https://raw.githubusercontent.com/ganya002/skystore-index/main/index.json"
    /// Base64 raw Ed25519 public keys SkyRose trusts: Gabby's maintainer key (2026-11-11; the private
    /// half is kept offline, docs/SKYSTORE.md "Maintainer setup").
    public static let trustedKeys: [String] = ["gfdvEbFkyU5rns7ZgFsTCxJWx8DVpyuCPpIL9njAtp4="]
    /// The largest bundle SkyStore downloads.
    public static let maxBundleBytes = 64 * 1_048_576

    public var indexURL: URL
    public var keys: [String]
    /// `file://` index and bundles (creator mode only, for a local test index).
    public var allowFileURLs: Bool
    /// Returns the bytes at a URL; replaced in tests.
    public var fetch: @Sendable (URL) throws -> Data
    /// Where the highest index serial seen so far is kept (anti-replay); nil = no check.
    public var serialFile: URL?

    public init(indexURL: URL, keys: [String], allowFileURLs: Bool = false, serialFile: URL? = nil,
                fetch: @escaping @Sendable (URL) throws -> Data = StoreSource.download) {
        self.indexURL = indexURL
        self.keys = keys
        self.allowFileURLs = allowFileURLs
        self.serialFile = serialFile
        self.fetch = fetch
    }

    /// From `[store]`: the configured index, and in creator mode the extra keys and file URLs.
    public static func from(_ c: StoreConfig) -> StoreSource {
        let url = URL(string: c.indexURL.isEmpty ? defaultIndexURL : c.indexURL) ?? URL(string: defaultIndexURL)!
        // The local test index of creator mode keeps its own serials, apart from the real one's.
        let serialFile = Paths.addonsDir.appendingPathComponent(c.creatorMode && !c.indexURL.isEmpty ? "index-serial-creator" : "index-serial")
        return StoreSource(indexURL: url, keys: trustedKeys + (c.creatorMode ? c.trustedKeys : []), allowFileURLs: c.creatorMode, serialFile: serialFile)
    }

    public func check(_ url: URL) throws {
        if url.scheme == "https" || (allowFileURLs && url.isFileURL) { return }
        throw StoreError.insecureURL(url.absoluteString)
    }

    /// The signed index.
    public func loadIndex() throws -> StoreIndex {
        // No key: nothing could be trusted, so nothing is fetched.
        guard !keys.isEmpty else { throw StoreError.noTrustedKey }
        try check(indexURL)
        let data = try fetch(indexURL)
        let sig = try fetch(indexURL.deletingLastPathComponent().appendingPathComponent(indexURL.lastPathComponent + ".sig"))
        let index = try StoreIndex.verified(data: data, signature: sig, keys: keys)
        try acceptSerial(index.serial ?? 0)
        return index
    }

    /// Anti-replay: refuses a serial lower than the highest seen, else remembers it.
    func acceptSerial(_ serial: Int) throws {
        guard let serialFile else { return }
        let seen = (try? String(contentsOf: serialFile, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        guard serial >= seen else { throw StoreError.staleIndex(got: serial, seen: seen) }
        guard serial > seen else { return }
        try? FileManager.default.createDirectory(at: serialFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(serial)\n".write(to: serialFile, atomically: true, encoding: .utf8)
    }

    /// Blocking HTTPS GET (60 s), or a local file read.
    @Sendable public static func download(_ url: URL) throws -> Data {
        if url.isFileURL {
            do { return try Data(contentsOf: url) } catch { throw StoreError.download(error.localizedDescription) }
        }
        final class Box: @unchecked Sendable { var data: Data?; var error: String? }
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("SkyRose/\(CaelestiaVersion.string)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error { box.error = error.localizedDescription } else if status != 200 { box.error = "HTTP \(status)" } else { box.data = data }
            sem.signal()
        }.resume()
        guard sem.wait(timeout: .now() + 65) == .success else { throw StoreError.download("timed out") }
        guard let data = box.data else { throw StoreError.download(box.error ?? "no data") }
        return data
    }
}

public extension Data {
    var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
