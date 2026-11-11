import Foundation

/// What an addon is. Data kinds are files SkyRose reads and never runs; code kinds run logic
/// (a keymap is code too: a bind can `exec` any command). See docs/skystore-security.md.
public enum AddonKind: String, Codable, Sendable, CaseIterable {
    /// A colour scheme (`schemes/*.toml` or Caelestia `*.json`), listed in Settings › Appearance.
    case scheme
    /// Images or videos, shown as their own group in the wallpaper picker.
    case wallpaper
    /// Binds; code, since a bind can run `exec`.
    case keymap
    /// A bar module or dashboard widget with its own logic.
    case widget
    /// A builtin SkyRose feature split out later (clamshell, colour picker, keep-awake).
    case feature

    /// Data kinds: installable by this SkyRose and never executed.
    public var isDataOnly: Bool { self == .scheme || self == .wallpaper }

    public var title: String {
        switch self {
        case .scheme: return "Colour scheme"
        case .wallpaper: return "Wallpapers"
        case .keymap: return "Keymap"
        case .widget: return "Widget"
        case .feature: return "Feature"
        }
    }

    /// Material icon for the Store.
    public var icon: String {
        switch self {
        case .scheme: return "palette"
        case .wallpaper: return "wallpaper"
        case .keymap: return "keyboard"
        case .widget: return "widgets"
        case .feature: return "extension"
        }
    }
}

/// One declared permission. Spelled `name` or `name:scope` in the manifest
/// (`network:api.example.com`, `files:~/Pictures/Wallpapers`).
public struct AddonPermission: Hashable, Sendable, Comparable, CustomStringConvertible {
    public enum Name: String, Sendable, CaseIterable {
        /// Outgoing HTTPS to one host (scope = host).
        case network
        /// Read one folder (scope = path).
        case files
        /// Post notifications and toasts.
        case notifications
        /// Read what is playing and control playback.
        case media
        /// Read the clipboard history.
        case clipboard
        /// Add or change keybinds (and so run commands).
        case keybinds
        /// Read window titles and apps.
        case windows
    }

    public var name: Name
    public var scope: String?

    public init(_ name: Name, scope: String? = nil) {
        self.name = name
        self.scope = scope
    }

    /// Parses `name` / `name:scope`; nil for an unknown name or a missing/extra scope.
    public init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard let first = parts.first, let n = Name(rawValue: first) else { return nil }
        let scope = parts.count > 1 ? parts[1] : nil
        let scoped = n == .network || n == .files
        guard scoped == (scope != nil), scope?.isEmpty != true, scope?.contains(where: \.isWhitespace) != true else { return nil }
        self.init(n, scope: scope)
    }

    public var description: String { scope.map { "\(name.rawValue):\($0)" } ?? name.rawValue }
    public static func < (a: Self, b: Self) -> Bool { a.description < b.description }

    /// What the user is asked to allow.
    public var summary: String {
        switch name {
        case .network: return "Connect to \(scope ?? "")"
        case .files: return "Read files in \(scope ?? "")"
        case .notifications: return "Show notifications"
        case .media: return "See and control what is playing"
        case .clipboard: return "Read your clipboard history"
        case .keybinds: return "Add keybinds (they can run commands)"
        case .windows: return "See your window titles and apps"
        }
    }

    public var icon: String {
        switch name {
        case .network: return "language"
        case .files: return "folder_open"
        case .notifications: return "notifications"
        case .media: return "music_note"
        case .clipboard: return "content_paste"
        case .keybinds: return "keyboard"
        case .windows: return "desktop_mac"
        }
    }
}

/// What changes between the permissions granted now and the ones a version asks for.
public struct PermissionDiff: Equatable, Sendable {
    public var added: [AddonPermission]
    public var removed: [AddonPermission]
    public var kept: [AddonPermission]

    public init(granted: [AddonPermission], requested: [AddonPermission]) {
        let g = Set(granted), r = Set(requested)
        added = r.subtracting(g).sorted()
        removed = g.subtracting(r).sorted()
        kept = r.intersection(g).sorted()
    }

    /// The user must agree again: something new is asked for.
    public var grows: Bool { !added.isEmpty }
}

/// `manifest.json` at the top of every addon bundle.
public struct AddonManifest: Codable, Equatable, Sendable {
    public static let fileName = "manifest.json"
    public static let schemaVersion = 1

    public struct Entry: Codable, Equatable, Sendable {
        /// Scheme files (kind `scheme`).
        public var schemes: [String]?
        /// Image/video files (kind `wallpaper`).
        public var wallpapers: [String]?
        public init(schemes: [String]? = nil, wallpapers: [String]? = nil) {
            self.schemes = schemes
            self.wallpapers = wallpapers
        }
    }

    public var schema: Int
    /// Reverse-DNS style, lower case: `dev.gabby.rose-pine`.
    public var id: String
    public var name: String
    public var author: String
    public var version: String
    /// Oldest SkyRose that can install it.
    public var minSkyRose: String
    public var kind: AddonKind
    public var summary: String
    public var description: String?
    /// SPDX id (`MIT`, `GPL-3.0-only`, `CC-BY-4.0`).
    public var licence: String
    public var homepage: String?
    public var permissions: [String]
    public var entry: Entry
    /// Bundle paths.
    public var icon: String?
    public var screenshots: [String]?
    /// Every other file in the bundle and its SHA-256 (written by `skyrose store pack`).
    public var files: [String: String]

    public init(id: String, name: String, author: String, version: String, minSkyRose: String, kind: AddonKind, summary: String,
                description: String? = nil, licence: String, homepage: String? = nil, permissions: [String] = [], entry: Entry,
                icon: String? = nil, screenshots: [String]? = nil, files: [String: String] = [:]) {
        schema = Self.schemaVersion
        self.id = id
        self.name = name
        self.author = author
        self.version = version
        self.minSkyRose = minSkyRose
        self.kind = kind
        self.summary = summary
        self.description = description
        self.licence = licence
        self.homepage = homepage
        self.permissions = permissions
        self.entry = entry
        self.icon = icon
        self.screenshots = screenshots
        self.files = files
    }

    public static func decode(_ data: Data) throws -> AddonManifest {
        do { return try JSONDecoder().decode(AddonManifest.self, from: data) } catch {
            throw StoreError.badManifest(Self.describe(error))
        }
    }

    public func encoded() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)) ?? Data()
    }

    public var parsedPermissions: [AddonPermission] { permissions.compactMap(AddonPermission.init) }

    /// Every problem with the manifest itself (files are checked by `AddonBundle`).
    public func issues() -> [String] {
        var out: [String] = []
        if schema != Self.schemaVersion { out.append("schema must be \(Self.schemaVersion) (got \(schema))") }
        if !Self.isValidID(id) { out.append("id '\(id)' must be reverse-DNS, lower case: letters, digits, '-' and '.', like dev.you.my-theme") }
        for (field, value) in [("name", name), ("author", author), ("summary", summary), ("licence", licence)]
        where value.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append("\(field) must not be empty")
        }
        if name.count > 40 { out.append("name must be at most 40 characters") }
        if summary.count > 120 { out.append("summary must be at most 120 characters") }
        if !Self.isVersion(version) { out.append("version '\(version)' must be numeric, like 1.0.0") }
        if !Self.isVersion(minSkyRose) { out.append("minSkyRose '\(minSkyRose)' must be numeric, like 0.5.0") }
        if let h = homepage, URL(string: h)?.scheme != "https" { out.append("homepage must be an https URL") }
        for p in permissions where AddonPermission(p) == nil {
            out.append("unknown permission '\(p)' (known: \(AddonPermission.Name.allCases.map(\.rawValue).joined(separator: ", ")); network and files need a scope, like network:api.example.com)")
        }
        if Set(permissions).count != permissions.count { out.append("permissions has duplicates") }
        let listed = (entry.schemes ?? []) + (entry.wallpapers ?? [])
        switch kind {
        case .scheme:
            if entry.schemes?.isEmpty ?? true { out.append("entry.schemes must list at least one scheme file") }
            if entry.wallpapers != nil { out.append("entry.wallpapers is for wallpaper addons") }
        case .wallpaper:
            if entry.wallpapers?.isEmpty ?? true { out.append("entry.wallpapers must list at least one image or video") }
            if entry.schemes != nil { out.append("entry.schemes is for scheme addons") }
        default: break
        }
        for p in listed + (screenshots ?? []) + (icon.map { [$0] } ?? []) where !Self.isSafePath(p) {
            out.append("path '\(p)' must be relative, inside the bundle, without '..'")
        }
        for (p, sha) in files {
            if !Self.isSafePath(p) { out.append("files: path '\(p)' must be relative, inside the bundle, without '..'") }
            if p == Self.fileName { out.append("files must not list manifest.json") }
            if sha.count != 64 || sha.contains(where: { !$0.isHexDigit || $0.isUppercase }) { out.append("files: '\(p)' needs a lower-case SHA-256") }
        }
        for p in listed + (screenshots ?? []) + (icon.map { [$0] } ?? []) where files[p] == nil {
            out.append("'\(p)' is not in files (run skyrose store pack)")
        }
        return out
    }

    public static func isValidID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, id.count <= 80 else { return false }
        return parts.allSatisfy { p in
            !p.isEmpty && p.first != "-" && p.last != "-" && p.allSatisfy { ($0.isASCII && $0.isLowercase) || $0.isNumber && $0.isASCII || $0 == "-" }
        }
    }

    public static func isVersion(_ v: String) -> Bool {
        let parts = v.split(separator: ".", omittingEmptySubsequences: false)
        return (1...4).contains(parts.count) && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// Relative, no `..`, no leading `/` or `~`, no backslash.
    public static func isSafePath(_ p: String) -> Bool {
        guard !p.isEmpty, !p.hasPrefix("/"), !p.hasPrefix("~"), !p.contains("\\"), !p.contains("\0") else { return false }
        return !p.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." || $0.isEmpty }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let c): return "missing \(path(c.codingPath + [key]))"
        case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c): return "wrong type at \(path(c.codingPath))"
        case DecodingError.dataCorrupted(let c):
            return c.codingPath.isEmpty ? "not valid JSON" : "bad value at \(path(c.codingPath)): \(c.debugDescription)"
        default: return error.localizedDescription
        }
    }

    private static func path(_ keys: [CodingKey]) -> String { keys.map(\.stringValue).joined(separator: ".") }
}

/// Which kinds this SkyRose installs and the permissions each may ask for. Data kinds get none:
/// SkyRose only reads their files. Code kinds wait for the out-of-process addon host
/// (docs/skystore-security.md), so `current` refuses them.
public struct AddonPolicy: Sendable {
    public var installable: [AddonKind: Set<AddonPermission.Name>]
    public init(installable: [AddonKind: Set<AddonPermission.Name>]) { self.installable = installable }

    public static let current = AddonPolicy(installable: [.scheme: [], .wallpaper: []])

    public func issues(kind: AddonKind, permissions: [AddonPermission]) -> [String] {
        guard let allowed = installable[kind] else {
            return ["\(kind.rawValue) addons run code; this SkyRose installs only data addons (\(installable.keys.map(\.rawValue).sorted().joined(separator: ", ")))"]
        }
        let extra = permissions.filter { !allowed.contains($0.name) }
        if extra.isEmpty { return [] }
        if allowed.isEmpty { return ["a \(kind.rawValue) addon is data only and cannot ask for permissions"] }
        return extra.map { "a \(kind.rawValue) addon cannot ask for \($0)" }
    }

    /// Manifest problems plus what this policy refuses.
    public func issues(_ m: AddonManifest) -> [String] {
        m.issues() + issues(kind: m.kind, permissions: m.parsedPermissions)
    }
}

/// Every Store failure, worded for the user.
public enum StoreError: Error, Equatable, Sendable, LocalizedError {
    case badManifest(String)
    case invalid([String])
    case badIndex(String)
    case badSignature
    case noTrustedKey
    case insecureURL(String)
    case download(String)
    case checksumMismatch(expected: String, got: String)
    case tooLarge(Int)
    case unsafeBundle(String)
    case mismatch(String)
    case revoked(String)
    case incompatible(String)
    case notInstallable(String)
    case permissionsDeclined
    case notFound(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .badManifest(let why): return "The manifest could not be read: \(why)."
        case .invalid(let issues): return "The addon is not valid: " + issues.joined(separator: "; ") + "."
        case .badIndex(let why): return "The SkyStore index could not be read: \(why)."
        case .badSignature: return "The SkyStore index signature is not valid. Nothing was changed."
        case .noTrustedKey: return "This SkyRose has no SkyStore signing key yet, so it cannot trust any index."
        case .insecureURL(let u): return "Refusing \(u): SkyStore only downloads over HTTPS."
        case .download(let why): return "The download failed: \(why)."
        case .checksumMismatch(let e, let g): return "SHA-256 did not match (expected \(e.prefix(12))…, got \(g.prefix(12))…). Nothing was installed."
        case .tooLarge(let n): return "The bundle is too large (\(n / 1_048_576) MB)."
        case .unsafeBundle(let why): return "The bundle is unsafe: \(why)."
        case .mismatch(let why): return "The bundle does not match the index: \(why)."
        case .revoked(let why): return "This addon was revoked: \(why)."
        case .incompatible(let why): return why
        case .notInstallable(let why): return why
        case .permissionsDeclined: return "The new permissions were not allowed. Nothing was changed."
        case .notFound(let id): return "No addon '\(id)'."
        case .io(let why): return why
        }
    }
}
