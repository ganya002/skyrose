import Foundation

/// Creator mode: scaffold, lint, pack and submit an addon (`skyrose store new|validate|pack|submit`).
/// Nothing here talks to the network or stores a token; `submit` only builds the `gh` command and
/// the pre-filled pull-request URL for the creator's own login.
public enum AddonCreator {
    public static let indexRepo = "ganya002/skystore-index"
    public static let distFolder = "dist"
    public static let maxBundleFiles = 200

    /// `skyrose store new <id> [--kind scheme|wallpaper]`: a folder named after the id with a
    /// manifest to fill in and, for a scheme, a copy of SkyRose Default to edit.
    public static func scaffold(id: String, kind: AddonKind, in parent: URL) throws -> URL {
        guard AddonManifest.isValidID(id) else { throw StoreError.invalid(["id '\(id)' must be reverse-DNS, lower case, like dev.you.my-theme"]) }
        let issues = AddonPolicy.current.issues(kind: kind, permissions: [])
        guard issues.isEmpty else { throw StoreError.notInstallable(issues.joined(separator: "; ")) }
        let dir = parent.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: dir.path) else { throw StoreError.io("\(dir.path) already exists") }
        let stem = id.split(separator: ".").last.map(String.init) ?? "addon"
        var entry = AddonManifest.Entry()
        do {
            try fm.createDirectory(at: dir.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
            switch kind {
            case .scheme:
                try fm.createDirectory(at: dir.appendingPathComponent("schemes"), withIntermediateDirectories: true)
                var s = SchemeLoader.builtIn(named: "skyrose-default") ?? Scheme(name: stem, colors: [:])
                s.name = stem
                try SchemeLoader.serialize(s).write(to: dir.appendingPathComponent("schemes/\(stem).toml"), atomically: true, encoding: .utf8)
                entry.schemes = ["schemes/\(stem).toml"]
            default:
                try fm.createDirectory(at: dir.appendingPathComponent("wallpapers"), withIntermediateDirectories: true)
                entry.wallpapers = []
            }
            let m = AddonManifest(id: id, name: stem.replacingOccurrences(of: "-", with: " ").capitalized, author: "", version: "1.0.0",
                                  minSkyRose: CaelestiaVersion.string, kind: kind, summary: "", licence: "MIT", entry: entry)
            try m.encoded().write(to: dir.appendingPathComponent(AddonManifest.fileName))
        } catch let e as StoreError { throw e } catch { throw StoreError.io(error.localizedDescription) }
        return dir
    }

    /// The files that go into the bundle: everything but the manifest, `dist/` and hidden files.
    static func payload(_ dir: URL) throws -> [String: URL] {
        try AddonBundle.files(in: dir).filter { rel, _ in
            rel != AddonManifest.fileName && !rel.hasPrefix(distFolder + "/") && !rel.split(separator: "/").contains { $0.hasPrefix(".") }
        }
    }

    /// The manifest in `dir` with `files` filled in from what is on disk.
    public static func manifest(in dir: URL) throws -> AddonManifest {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(AddonManifest.fileName)) else {
            throw StoreError.badManifest("no manifest.json in \(dir.path)")
        }
        var m = try AddonManifest.decode(data)
        m.files = try payload(dir).mapValues { (try? Data(contentsOf: $0))?.sha256Hex ?? "" }
        return m
    }

    /// `skyrose store validate`: every problem with the manifest, its permissions and files, and a
    /// packed bundle whose checksum file no longer matches. Empty = ready to pack.
    public static func validate(_ dir: URL) -> [String] {
        let m: AddonManifest
        do { m = try manifest(in: dir) } catch { return [(error as? LocalizedError)?.errorDescription ?? "\(error)"] }
        var out = AddonPolicy.current.issues(m)
        if m.files.count > maxBundleFiles { out.append("at most \(maxBundleFiles) files (got \(m.files.count))") }
        let size = m.files.keys.reduce(0) { $0 + ((try? dir.appendingPathComponent($1).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        if size > StoreSource.maxBundleBytes { out.append("files add up to \(size / 1_048_576) MB; the limit is \(StoreSource.maxBundleBytes / 1_048_576) MB") }
        for s in m.entry.schemes ?? [] where m.files[s] != nil {
            do { _ = try SchemeLoader.load(from: dir.appendingPathComponent(s)) } catch { out.append("\(s): \(error.localizedDescription)") }
        }
        for w in m.entry.wallpapers ?? [] where !AddonBundle.wallpaperExtensions.contains((w as NSString).pathExtension.lowercased()) {
            out.append("\(w) is not an image or video (\(AddonBundle.wallpaperExtensions.sorted().joined(separator: ", ")))")
        }
        for p in (m.screenshots ?? []) + (m.icon.map { [$0] } ?? []) where !["png", "jpg", "jpeg"].contains((p as NSString).pathExtension.lowercased()) {
            out.append("\(p): icon and screenshots must be PNG or JPEG")
        }
        let bundle = bundleURL(dir, m)
        if FileManager.default.fileExists(atPath: bundle.path) {
            let sha = (try? Data(contentsOf: bundle))?.sha256Hex ?? ""
            let listed = Updater.expectedHash((try? String(contentsOf: URL(fileURLWithPath: bundle.path + ".sha256"), encoding: .utf8)) ?? "")
            if sha != listed { out.append("\(distFolder)/\(bundle.lastPathComponent).sha256 does not match the bundle (run skyrose store pack again)") }
        }
        return out
    }

    static func bundleURL(_ dir: URL, _ m: AddonManifest) -> URL {
        dir.appendingPathComponent(distFolder, isDirectory: true).appendingPathComponent("\(m.id)-\(m.version).\(AddonBundle.fileExtension)")
    }

    public struct Packed: Equatable, Sendable {
        public var manifest: AddonManifest
        public var bundle: URL
        public var sha256: String
        public var size: Int
    }

    /// `skyrose store pack`: validates, then writes `dist/<id>-<version>.skyaddon` (the manifest with
    /// every file's SHA-256, plus the files) and `….skyaddon.sha256`.
    public static func pack(_ dir: URL) throws -> Packed {
        let issues = validate(dir).filter { !$0.contains(".sha256 does not match") }
        guard issues.isEmpty else { throw StoreError.invalid(issues) }
        let m = try manifest(in: dir)
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("skystore-pack-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let bundle = bundleURL(dir, m)
        do {
            for rel in m.files.keys {
                let to = staging.appendingPathComponent(rel)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: dir.appendingPathComponent(rel), to: to)
            }
            try m.encoded().write(to: staging.appendingPathComponent(AddonManifest.fileName))
            try fm.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: bundle.path) { try fm.removeItem(at: bundle) }
        } catch { throw StoreError.io(error.localizedDescription) }
        guard AddonBundle.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", staging.path, bundle.path]).status == 0,
              let data = try? Data(contentsOf: bundle) else { throw StoreError.io("Could not write \(bundle.path)") }
        let sha = data.sha256Hex
        do { try "\(sha)  \(bundle.lastPathComponent)\n".write(toFile: bundle.path + ".sha256", atomically: true, encoding: .utf8) } catch {
            throw StoreError.io(error.localizedDescription)
        }
        return Packed(manifest: m, bundle: bundle, sha256: sha, size: data.count)
    }

    public struct Submission: Equatable, Sendable {
        /// Uploads the bundle as a release asset of the creator's own repo (their `gh` login).
        public var releaseCommand: [String]
        /// GitHub's "new file" page on the index, pre-filled with the submission; GitHub forks the
        /// index for the creator and opens the pull request from there.
        public var pullRequestURL: URL
        /// `submissions/<id>-<version>.json`.
        public var entryJSON: String
    }

    /// `skyrose store submit --repo <owner/name>`: from a packed bundle.
    public static func submission(_ p: Packed, repo: String, released: Date = Date()) throws -> Submission {
        let parts = repo.split(separator: "/")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }) else {
            throw StoreError.invalid(["--repo must be your GitHub repo as owner/name (got '\(repo)')"])
        }
        let m = p.manifest
        let tag = "\(m.id)-v\(m.version)"
        let file = p.bundle.lastPathComponent
        let asset = URL(string: "https://github.com/\(repo)/releases/download/\(tag)/\(file)")!
        let day = ISO8601DateFormatter.string(from: released, timeZone: TimeZone(identifier: "UTC")!, formatOptions: [.withFullDate])
        let entry = StoreEntry(id: m.id, name: m.name, author: m.author, summary: m.summary, description: m.description, kind: m.kind,
                               licence: m.licence, homepage: m.homepage.flatMap(URL.init(string:)),
                               versions: [StoreVersion(version: m.version, minSkyRose: m.minSkyRose, url: asset, sha256: p.sha256, size: p.size,
                                                       permissions: m.permissions, released: day)])
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = String(decoding: (try? e.encode(entry)) ?? Data(), as: UTF8.self) + "\n"
        var c = URLComponents(string: "https://github.com/\(indexRepo)/new/main")!
        c.queryItems = [URLQueryItem(name: "filename", value: "submissions/\(m.id)-\(m.version).json"), URLQueryItem(name: "value", value: json)]
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let release = ["gh", "release", "create", tag, p.bundle.path, p.bundle.path + ".sha256", "--repo", repo,
                       "--title", "\(m.name) \(m.version)", "--notes", "SkyStore bundle for \(m.id) \(m.version). SHA-256 \(p.sha256)"]
        return Submission(releaseCommand: release, pullRequestURL: c.url!, entryJSON: json)
    }
}
