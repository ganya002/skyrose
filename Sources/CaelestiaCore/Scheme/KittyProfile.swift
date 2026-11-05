import Foundation

/// SkyRose's kitty setup: Gabby's Arch `kitty.conf` (Tests/fixtures/ref/kitty) mapped to macOS,
/// written to `~/.config/kitty/skyrose.conf`, which includes the live scheme colours
/// (`skyrose-theme.conf`, ``KittyThemeWriter``). The user's own `kitty.conf` only gains one
/// `include skyrose.conf` line at its end (so our values win over earlier ones); everything else
/// in it is left alone.
///
/// Arch → macOS: `background_blur 1` (a switch on Wayland) is a blur radius on macOS: 32, as
/// Gabby's own Mac port uses. `hide_window_decorations yes` would also drop the macOS resize
/// edges and shadow: `titlebar-only`. Added for macOS: `macos_option_as_alt left` (⌥ is the WM's
/// modifier only with the other keys), `macos_quit_when_last_window_closed yes`. The Catppuccin
/// colours of the Arch file are replaced by the scheme include.
public enum KittyProfile {
    public static let fileName = "skyrose.conf"
    public static let themeFileName = "skyrose-theme.conf"
    public static let includeLine = "include \(fileName)"
    public static let headerMarker = KittyThemeWriter.headerMarker

    public struct Options: Equatable, Sendable {
        public var fontFamily: String
        public var fontSize: Double
        public init(fontFamily: String = Options.defaultFont, fontSize: Double = 13) {
            self.fontFamily = fontFamily
            self.fontSize = fontSize
        }
        /// The Arch font. kitty matches it by family name once installed (see LIMITATIONS: fonts).
        public static let defaultFont = "JetBrainsMono Nerd Font"
    }

    /// The text of `skyrose.conf`.
    public static func render(_ o: Options = Options()) -> String {
        let size = o.fontSize == o.fontSize.rounded() ? String(format: "%.1f", o.fontSize) : String(o.fontSize)
        let lines = [
            headerMarker,
            "# SkyRose kitty profile (Gabby's Arch kitty.conf, macOS values). Remove the",
            "# `\(includeLine)` line from kitty.conf, or run `skyrose kitty uninstall`, to stop using it.",
            "",
            "font_family      \(o.fontFamily)",
            "font_size        \(size)",
            "window_padding_width 14",
            "background_opacity 0.62",
            "background_blur 32",
            "hide_window_decorations titlebar-only",
            "macos_titlebar_color background",
            "macos_option_as_alt left",
            "macos_quit_when_last_window_closed yes",
            "cursor_shape beam",
            "cursor_trail 3",
            "confirm_os_window_close 0",
            "enable_audio_bell no",
            "tab_bar_style powerline",
            "tab_powerline_style slanted",
            "",
            "# Colours follow the SkyRose scheme live (rewritten on every scheme change, then kitty reloads).",
            "include \(themeFileName)",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Whether `kittyConf` (nil: no file) already includes our profile.
    public static func includes(_ kittyConf: String?) -> Bool {
        guard let kittyConf else { return false }
        return kittyConf.split(whereSeparator: \.isNewline).contains { isOurInclude(String($0)) }
    }

    /// `include skyrose.conf` (or the theme file directly, as an older manual setup may do).
    static func isOurInclude(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("include") else { return false }
        let rest = line.dropFirst("include".count)
        guard let first = rest.first, first == " " || first == "\t" else { return false }
        let target = rest.trimmingCharacters(in: .whitespaces)
        let name = (target as NSString).lastPathComponent
        return name == fileName || name == themeFileName
    }

    /// `kittyConf` with our include appended at the end (unchanged if already there). A new
    /// file (nil) is just the include, with a comment saying who wrote it.
    public static func addingInclude(to kittyConf: String?) -> String {
        guard let kittyConf else {
            return "# kitty.conf created by SkyRose: your own settings can go above the include.\n\(includeLine)\n"
        }
        if includes(kittyConf) { return kittyConf }
        let body = kittyConf.hasSuffix("\n") || kittyConf.isEmpty ? kittyConf : kittyConf + "\n"
        return body + "\n# SkyRose: kitty profile + live scheme colours (skyrose kitty uninstall removes this)\n\(includeLine)\n"
    }

    /// `kittyConf` without our include (and the comment line we put above it).
    public static func removingInclude(from kittyConf: String) -> String {
        var lines = kittyConf.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            if isOurInclude(lines[i]) {
                lines.remove(at: i)
                if i > 0, lines[i - 1].hasPrefix("# SkyRose: kitty profile") {
                    lines.remove(at: i - 1); i -= 1
                    if i > 0, lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty { lines.remove(at: i - 1); i -= 1 }
                }
            } else {
                i += 1
            }
        }
        return lines.joined(separator: "\n")
    }

    /// True when `kittyConf` holds nothing but what ``addingInclude(to:)`` writes into a new file.
    public static func isOnlyOurs(_ kittyConf: String) -> Bool {
        let meaningful = kittyConf.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("# kitty.conf created by SkyRose") }
        return meaningful.count == 1 && isOurInclude(meaningful[0])
    }
}

/// Installs, removes and live-updates the kitty profile in a kitty config directory
/// (`~/.config/kitty`; tests pass a temporary one). Never overwrites a `skyrose.conf` or theme
/// file that SkyRose did not write, and journals the `kitty.conf` it changes (copy of the
/// original under the backup folder) so the uninstaller can put it back.
public struct KittySetup: Sendable {
    public let directory: URL
    public init(directory: URL = Paths.kittyConfigDir) { self.directory = directory }

    public var kittyConf: URL { directory.appendingPathComponent("kitty.conf") }
    public var profileFile: URL { directory.appendingPathComponent(KittyProfile.fileName) }
    public var themeFile: URL { directory.appendingPathComponent(KittyProfile.themeFileName) }

    public struct Status: Equatable, Sendable {
        /// kitty.conf includes skyrose.conf (or the theme): colours follow the scheme.
        public var included: Bool
        public var kittyConfExists: Bool
        public var profileWritten: Bool
        public var themeWritten: Bool
        /// A skyrose.conf / theme file exists that SkyRose did not write (install refuses).
        public var foreignFile: String?
    }

    public enum SetupError: Error, Equatable, LocalizedError {
        case foreignFile(String)
        public var errorDescription: String? {
            switch self {
            case .foreignFile(let path): return "\(path) exists and was not written by SkyRose; move it away first."
            }
        }
    }

    public func status() -> Status {
        let conf = read(kittyConf)
        let profile = read(profileFile), theme = read(themeFile)
        var foreign: String?
        if let profile, !Self.isOurs(profile) { foreign = profileFile.path }
        if let theme, !Self.isOurs(theme) { foreign = themeFile.path }
        return Status(included: KittyProfile.includes(conf), kittyConfExists: conf != nil,
                      profileWritten: profile.map(Self.isOurs) ?? false, themeWritten: theme.map(Self.isOurs) ?? false,
                      foreignFile: foreign)
    }

    /// Writes skyrose.conf and the theme for `scheme`, then adds the include to kitty.conf.
    @discardableResult
    public func install(scheme: Scheme, options: KittyProfile.Options = .init(), journal: BackupJournal? = nil) throws -> [String] {
        let s = status()
        if let f = s.foreignFile { throw SetupError.foreignFile(f) }
        var notes: [String] = []
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(KittyProfile.render(options), to: profileFile)
        try write(KittyThemeWriter.render(scheme: scheme), to: themeFile)
        notes.append("wrote \(profileFile.path) and \(themeFile.path)")
        let conf = read(kittyConf)
        if !KittyProfile.includes(conf) {
            if let journal {
                if conf != nil {
                    let copy = try journal.copyOriginal(file: kittyConf)
                    try journal.append(BackupEntry(domain: "kitty", key: kittyConf.path, oldValue: .string(copy.path),
                                                   newValue: .string(KittyProfile.includeLine), kind: .kittyConfig,
                                                   note: "added `\(KittyProfile.includeLine)` at the end"))
                } else {
                    try journal.append(BackupEntry(domain: "kitty", key: kittyConf.path, oldValue: .absent,
                                                   newValue: .string(KittyProfile.includeLine), kind: .kittyConfig,
                                                   note: "created kitty.conf"))
                }
            }
            try write(KittyProfile.addingInclude(to: conf), to: kittyConf)
            notes.append(conf == nil ? "created \(kittyConf.path)" : "added `\(KittyProfile.includeLine)` to \(kittyConf.path)")
        }
        return notes
    }

    /// Removes our include (and a kitty.conf we created) and our two files.
    @discardableResult
    public func uninstall() throws -> [String] {
        var notes: [String] = []
        if let conf = read(kittyConf), KittyProfile.includes(conf) {
            if KittyProfile.isOnlyOurs(conf) {
                try FileManager.default.removeItem(at: kittyConf)
                notes.append("removed \(kittyConf.path) (SkyRose created it)")
            } else {
                try write(KittyProfile.removingInclude(from: conf), to: kittyConf)
                notes.append("removed the include from \(kittyConf.path)")
            }
        }
        for url in [profileFile, themeFile] {
            if let text = read(url), Self.isOurs(text) {
                try FileManager.default.removeItem(at: url)
                notes.append("removed \(url.path)")
            }
        }
        return notes
    }

    /// Rewrites the theme for `scheme` when kitty uses it and the colours changed. True when the
    /// file was written (the caller then asks running kittys to reload).
    @discardableResult
    public func syncTheme(scheme: Scheme) throws -> Bool {
        guard KittyProfile.includes(read(kittyConf)) else { return false }
        let text = KittyThemeWriter.render(scheme: scheme)
        let existing = read(themeFile)
        if let existing, !Self.isOurs(existing) { return false }
        guard existing != text else { return false }
        try write(text, to: themeFile)
        return true
    }

    static func isOurs(_ text: String) -> Bool { text.hasPrefix(KittyProfile.headerMarker) }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
    /// Writes through symlinks (dotfile setups link kitty.conf): an atomic write would otherwise
    /// replace the link with a plain file.
    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }
}
