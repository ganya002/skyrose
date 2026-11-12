import Foundation

/// `entry.app` of an `app` addon: a whole macOS app shipped as **reviewed source** inside the
/// signed bundle, plus a declarative build recipe. Nothing here is a script: SkyRose's own
/// installer (`AppInstaller`, run out of process by `skyrose store setup`) unpacks the source,
/// fetches only the pinned `downloads`, builds `products` with the Xcode toolchain, assembles the
/// `.app` from `copy`, signs it ad hoc and starts it as its own process.
public struct AppEntry: Codable, Equatable, Sendable {
    /// A pinned artefact the build or the app needs (a runtime binary, a framework).
    public struct Download: Codable, Equatable, Sendable {
        /// Short id, unique in the manifest (`llama-cpp`).
        public var id: String
        /// What the user sees in the progress (`llama.cpp b12317: local chat runtime`).
        public var title: String
        /// HTTPS only; its host must be declared as `network:<host>`.
        public var url: String
        /// Lower-case SHA-256 of the downloaded file. A mismatch stops the install.
        public var sha256: String
        /// Bytes, for the progress and the disk check.
        public var size: Int64
        /// `tar.gz`, `zip` or `file` (kept as it is).
        public var unpack: String
        /// `deps/<path>`: kept in the addon folder, the app uses it at run time.
        /// `source/<path>`: placed into the source tree before the build (a binary framework).
        public var into: String

        public init(id: String, title: String, url: String, sha256: String, size: Int64, unpack: String, into: String) {
            self.id = id; self.title = title; self.url = url; self.sha256 = sha256; self.size = size; self.unpack = unpack; self.into = into
        }
    }

    /// One thing placed into the `.app`: `from` is `source:<path>`, `build:<product>` or
    /// `deps:<path>`; `to` starts with `Contents/`.
    public struct Copy: Codable, Equatable, Sendable {
        public var from: String
        public var to: String
        public init(from: String, to: String) { self.from = from; self.to = to }
    }

    /// The app's `CFBundleIdentifier`; also the LaunchAgent label.
    public var bundleID: String
    /// `<appName>.app`.
    public var appName: String
    /// Bundle path of a `.tar.gz` with the source tree (listed in `files`, so the signed index pins it).
    public var source: String
    /// SwiftPM products to build (`xcrun swift build -c release --product …`); the first is the app's executable.
    public var products: [String]
    /// Source path of the app's Info.plist (its CFBundleIdentifier must be `bundleID`).
    public var infoPlist: String
    public var copy: [Copy]
    /// Toolchains the installer checks and offers to install: `xcode-clt`.
    public var requires: [String]
    public var downloads: [Download]
    /// Oldest macOS (`14.0`).
    public var minMacOS: String
    /// CPU architectures (`arm64`). Intel Macs are refused with a clear message.
    public var architectures: [String]
    /// Free space the install needs (downloads, build folder and the app), checked before anything starts.
    public var diskBytes: Int64
    /// Command-line helpers copied to `addons/<id>/bin/<to>` (`from` is `source:<path>`).
    public var cli: [Copy]?
    /// Arguments to the app's executable that quit it cleanly (`["ctl", "quit"]`); SIGTERM after.
    public var stop: [String]?
    /// Start at login with a per-user LaunchAgent (needs the `login` permission).
    public var launchAgent: Bool?
    /// User data the app keeps, relative to `~` and inside `Library/Application Support`,
    /// `Library/Caches` or `Library/Logs`. Only `skyrose store uninstall <id> --purge` removes it.
    public var dataPaths: [String]?

    public init(bundleID: String, appName: String, source: String, products: [String], infoPlist: String, copy: [Copy],
                requires: [String] = ["xcode-clt"], downloads: [Download] = [], minMacOS: String = "14.0",
                architectures: [String] = ["arm64"], diskBytes: Int64, cli: [Copy]? = nil, stop: [String]? = nil,
                launchAgent: Bool? = nil, dataPaths: [String]? = nil) {
        self.bundleID = bundleID; self.appName = appName; self.source = source; self.products = products
        self.infoPlist = infoPlist; self.copy = copy; self.requires = requires; self.downloads = downloads
        self.minMacOS = minMacOS; self.architectures = architectures; self.diskBytes = diskBytes; self.cli = cli
        self.stop = stop; self.launchAgent = launchAgent; self.dataPaths = dataPaths
    }

    public static let knownRequirements: Set<String> = ["xcode-clt"]
    public static let knownArchitectures: Set<String> = ["arm64"]
    public static let unpackKinds: Set<String> = ["tar.gz", "zip", "file"]
    /// The oldest macOS SkyRose itself runs on.
    public static let oldestMacOS = "14.0"
    static let dataRoots = ["Library/Application Support/", "Library/Caches/", "Library/Logs/"]

    public var appFolderName: String { appName + ".app" }
    public var executable: String { products.first ?? appName }

    /// Every problem with the recipe. `permissions` are the manifest's (download hosts must be
    /// declared, a LaunchAgent needs `login`).
    public func issues(permissions: [AddonPermission]) -> [String] {
        var out: [String] = []
        let idChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        if bundleID.split(separator: ".").count < 2 || bundleID.unicodeScalars.contains(where: { !idChars.contains($0) }) {
            out.append("entry.app.bundleID '\(bundleID)' must be reverse-DNS (letters, digits, '.', '-')")
        }
        if appName.isEmpty || appName.count > 40 || appName.contains("/") || appName.hasPrefix(".") {
            out.append("entry.app.appName must be a plain name (at most 40 characters, no '/')")
        }
        if !source.hasSuffix(".tar.gz") { out.append("entry.app.source must be a .tar.gz in the bundle") }
        if products.isEmpty { out.append("entry.app.products must name at least one SwiftPM product") }
        for p in products where p.isEmpty || p.contains(where: { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")) }) {
            out.append("entry.app.products: '\(p)' is not a product name")
        }
        if !AddonManifest.isSafePath(infoPlist) { out.append("entry.app.infoPlist must be a relative path in the source") }
        for c in copy {
            if !Self.isValidFrom(c.from, products: products) { out.append("entry.app.copy: from '\(c.from)' must be source:<path>, build:<product> or deps:<path>") }
            if !c.to.hasPrefix("Contents/") || !AddonManifest.isSafePath(c.to) { out.append("entry.app.copy: to '\(c.to)' must be a path under Contents/") }
            if c.to == "Contents/Info.plist" || c.to == "Contents/MacOS/\(executable)" { out.append("entry.app.copy: '\(c.to)' is written by SkyRose") }
        }
        for c in cli ?? [] {
            if !c.from.hasPrefix("source:") || !AddonManifest.isSafePath(String(c.from.dropFirst(7))) { out.append("entry.app.cli: from '\(c.from)' must be source:<path>") }
            if c.to.isEmpty || c.to.contains("/") || c.to.hasPrefix(".") { out.append("entry.app.cli: to '\(c.to)' must be a plain file name") }
        }
        for r in requires where !Self.knownRequirements.contains(r) { out.append("entry.app.requires: unknown '\(r)' (known: \(Self.knownRequirements.sorted().joined(separator: ", ")))") }
        let hosts = Set(permissions.filter { $0.name == .network }.compactMap(\.scope))
        var seen = Set<String>()
        for d in downloads {
            if !seen.insert(d.id).inserted { out.append("entry.app.downloads: id '\(d.id)' is repeated") }
            guard let url = URL(string: d.url), url.scheme == "https", let host = url.host else {
                out.append("entry.app.downloads: '\(d.id)' must be an https URL"); continue
            }
            if !hosts.contains(host) { out.append("entry.app.downloads: '\(d.id)' downloads from \(host); declare network:\(host)") }
            if d.sha256.count != 64 || d.sha256.contains(where: { !$0.isHexDigit || $0.isUppercase }) { out.append("entry.app.downloads: '\(d.id)' needs a lower-case SHA-256") }
            if d.size <= 0 { out.append("entry.app.downloads: '\(d.id)' needs its size in bytes") }
            if !Self.unpackKinds.contains(d.unpack) { out.append("entry.app.downloads: '\(d.id)' unpack must be tar.gz, zip or file") }
            if !(d.into.hasPrefix("deps/") || d.into.hasPrefix("source/")) || !AddonManifest.isSafePath(d.into) {
                out.append("entry.app.downloads: '\(d.id)' into must be deps/<path> or source/<path>")
            }
        }
        if !AddonManifest.isVersion(minMacOS) || Updater.compare(minMacOS, Self.oldestMacOS) == .orderedAscending {
            out.append("entry.app.minMacOS must be \(Self.oldestMacOS) or newer")
        }
        if architectures.isEmpty || architectures.contains(where: { !Self.knownArchitectures.contains($0) }) {
            out.append("entry.app.architectures must be [\"arm64\"] (SkyRose runs on Apple Silicon only)")
        }
        if diskBytes <= 0 { out.append("entry.app.diskBytes must say how much room the install needs") }
        if launchAgent == true, !permissions.contains(where: { $0.name == .login }) { out.append("entry.app.launchAgent needs the login permission") }
        if let stop, stop.isEmpty || stop.count > 8 { out.append("entry.app.stop must be 1 to 8 arguments") }
        for p in dataPaths ?? [] {
            let root = Self.dataRoots.first { p.hasPrefix($0) }
            if !AddonManifest.isSafePath(p) || root == nil || p.count <= (root?.count ?? 0) {
                out.append("entry.app.dataPaths: '\(p)' must be a folder inside ~/Library/Application Support, Caches or Logs")
            }
        }
        return out
    }

    static func isValidFrom(_ from: String, products: [String]) -> Bool {
        if from.hasPrefix("build:") { return products.contains(String(from.dropFirst(6))) }
        for prefix in ["source:", "deps:"] where from.hasPrefix(prefix) { return AddonManifest.isSafePath(String(from.dropFirst(prefix.count))) }
        return false
    }
}
