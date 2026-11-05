import Foundation

/// One-time move of a pre-rename (Caelestia for Mac) install to the SkyRose locations:
///
/// | before | after |
/// |---|---|
/// | `~/.config/caelestia-mac/` | `~/.config/skyrose/` |
/// | `~/Library/Application Support/CaelestiaMac/` | `~/Library/Application Support/SkyRose/` |
/// | `~/Library/Logs/CaelestiaMac/` | `~/Library/Logs/SkyRose/` |
/// | `…/backup.json` | `…/restore-manifest.json` (same format) |
/// | `~/.config/kitty/caelestia-theme.conf` | `~/.config/kitty/skyrose-theme.conf` (+ a symlink at the old name so an `include` keeps working) |
/// | `theme = "caelestia-…"` in config.toml | `theme = "skyrose-…"` |
///
/// Rules: files are moved (renamed), never copied and never deleted. When a file exists on both
/// sides the SkyRose one wins and the old one stays in a `…-pre-skyrose` folder next to the old
/// location, so nothing is lost. The IPC socket is not moved (it belongs to a running process).
/// Running it again does nothing: the marker `migration.json` records that it ran, and the old
/// folders are gone (or renamed) afterwards. Callers skip it while a pre-rename `CaelestiaWM` is
/// still running (it would keep writing to the old folder).
public struct LegacyMigration: Sendable {
    public struct Locations: Sendable, Equatable {
        public var legacyConfigDir: URL
        public var configDir: URL
        public var legacyAppSupport: URL
        public var appSupport: URL
        public var legacyLogsDir: URL
        public var logsDir: URL
        public var legacyKittyTheme: URL
        public var kittyTheme: URL

        public init(
            legacyConfigDir: URL, configDir: URL, legacyAppSupport: URL, appSupport: URL,
            legacyLogsDir: URL, logsDir: URL, legacyKittyTheme: URL, kittyTheme: URL
        ) {
            self.legacyConfigDir = legacyConfigDir
            self.configDir = configDir
            self.legacyAppSupport = legacyAppSupport
            self.appSupport = appSupport
            self.legacyLogsDir = legacyLogsDir
            self.logsDir = logsDir
            self.legacyKittyTheme = legacyKittyTheme
            self.kittyTheme = kittyTheme
        }

        /// The real locations under the user's home directory.
        public static var user: Locations {
            Locations(
                legacyConfigDir: Paths.legacyConfigDir, configDir: Paths.configDir,
                legacyAppSupport: Paths.legacyAppSupport, appSupport: Paths.appSupport,
                legacyLogsDir: Paths.legacyLogsDir, logsDir: Paths.logsDir,
                legacyKittyTheme: Paths.legacyKittyThemeFile, kittyTheme: Paths.kittyThemeFile
            )
        }

        /// Every location under `root` (tests).
        public static func under(_ root: URL) -> Locations {
            Locations(
                legacyConfigDir: root.appendingPathComponent(".config/caelestia-mac", isDirectory: true),
                configDir: root.appendingPathComponent(".config/skyrose", isDirectory: true),
                legacyAppSupport: root.appendingPathComponent("Library/Application Support/CaelestiaMac", isDirectory: true),
                appSupport: root.appendingPathComponent("Library/Application Support/SkyRose", isDirectory: true),
                legacyLogsDir: root.appendingPathComponent("Library/Logs/CaelestiaMac", isDirectory: true),
                logsDir: root.appendingPathComponent("Library/Logs/SkyRose", isDirectory: true),
                legacyKittyTheme: root.appendingPathComponent(".config/kitty/caelestia-theme.conf"),
                kittyTheme: root.appendingPathComponent(".config/kitty/skyrose-theme.conf")
            )
        }
    }

    /// What one run did.
    public struct Report: Codable, Sendable, Equatable {
        public enum Outcome: String, Codable, Sendable {
            /// Nothing from a pre-rename install was found.
            case nothingToDo
            /// Already migrated earlier (marker present).
            case alreadyDone
            /// Moved everything listed in `moved`.
            case migrated
            /// A pre-rename WM is running; nothing was touched.
            case skippedLegacyRunning
        }

        public var outcome: Outcome
        /// "old path → new path" for every file or folder moved.
        public var moved: [String]
        /// Old files kept aside because SkyRose already had a file with the same name.
        public var keptAside: [String]
        /// Other notes (theme names rewritten, symlink left, …).
        public var notes: [String]
        public var date: Date

        public init(outcome: Outcome, moved: [String] = [], keptAside: [String] = [], notes: [String] = [], date: Date = Date()) {
            self.outcome = outcome
            self.moved = moved
            self.keptAside = keptAside
            self.notes = notes
            self.date = date
        }
    }

    public var locations: Locations
    public static let markerName = "migration.json"
    /// File names never moved (they belong to a running process).
    static let skippedNames: Set<String> = ["ipc.sock", ".DS_Store"]

    public init(locations: Locations = .user) {
        self.locations = locations
    }

    public var markerURL: URL { locations.appSupport.appendingPathComponent(Self.markerName) }

    /// True when a pre-rename install is present and has not been migrated yet.
    public var isNeeded: Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: markerURL.path) { return false }
        return [locations.legacyConfigDir, locations.legacyAppSupport, locations.legacyLogsDir, locations.legacyKittyTheme]
            .contains { fm.fileExists(atPath: $0.path) && !Self.isSymlink($0) }
    }

    /// Runs the migration (see the type comment). `legacyWMRunning`: a `CaelestiaWM` process is
    /// alive; then nothing is touched and the next launch tries again.
    @discardableResult
    public func run(legacyWMRunning: Bool = false) -> Report {
        let fm = FileManager.default
        if fm.fileExists(atPath: markerURL.path) { return Report(outcome: .alreadyDone) }
        guard isNeeded else { return Report(outcome: .nothingToDo) }
        if legacyWMRunning { return Report(outcome: .skippedLegacyRunning, notes: ["CaelestiaWM is still running; quit it first"]) }

        var report = Report(outcome: .migrated)
        moveDirectory(locations.legacyConfigDir, to: locations.configDir, report: &report)
        moveDirectory(locations.legacyAppSupport, to: locations.appSupport, report: &report)
        moveDirectory(locations.legacyLogsDir, to: locations.logsDir, report: &report)
        renameManifest(report: &report)
        rewriteThemeNames(report: &report)
        moveKittyTheme(report: &report)
        writeMarker(report)
        return report
    }

    // MARK: Steps

    private func moveDirectory(_ old: URL, to new: URL, report: inout Report) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: old.path, isDirectory: &isDir), isDir.boolValue, !Self.isSymlink(old) else { return }
        do {
            try fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: new.path) {
                // Whole folder in one rename, minus the socket (moved out of the way first).
                let socket = old.appendingPathComponent("ipc.sock")
                if fm.fileExists(atPath: socket.path) || Self.isSymlink(socket) { try? fm.removeItem(at: socket) }
                try fm.moveItem(at: old, to: new)
                report.moved.append("\(old.path) → \(new.path)")
                return
            }
            try mergeContents(of: old, into: new, keptAsideRoot: Self.asideURL(for: old), report: &report)
            // Only empty folders (and a stale socket) are left behind: remove them; else keep aside.
            if Self.isEffectivelyEmpty(old) {
                try? fm.removeItem(at: old)
            }
        } catch {
            report.notes.append("could not move \(old.path): \(error.localizedDescription)")
        }
    }

    /// Moves every entry of `old` that `new` lacks; recurses into folders present on both sides.
    /// A file present on both sides goes to `keptAsideRoot` (same relative path).
    private func mergeContents(of old: URL, into new: URL, keptAsideRoot: URL, report: inout Report) throws {
        let fm = FileManager.default
        for name in try fm.contentsOfDirectory(atPath: old.path).sorted() where !Self.skippedNames.contains(name) {
            let src = old.appendingPathComponent(name)
            let dst = new.appendingPathComponent(name)
            var srcDir: ObjCBool = false, dstDir: ObjCBool = false
            fm.fileExists(atPath: src.path, isDirectory: &srcDir)
            if !fm.fileExists(atPath: dst.path, isDirectory: &dstDir) {
                try fm.moveItem(at: src, to: dst)
                report.moved.append("\(src.path) → \(dst.path)")
            } else if srcDir.boolValue, dstDir.boolValue, !Self.isSymlink(src) {
                try mergeContents(of: src, into: dst, keptAsideRoot: keptAsideRoot.appendingPathComponent(name), report: &report)
                if Self.isEffectivelyEmpty(src) { try? fm.removeItem(at: src) }
            } else {
                try fm.createDirectory(at: keptAsideRoot, withIntermediateDirectories: true)
                var aside = keptAsideRoot.appendingPathComponent(name)
                var n = 1
                while fm.fileExists(atPath: aside.path) {
                    aside = keptAsideRoot.appendingPathComponent("\(n)-\(name)")
                    n += 1
                }
                try fm.moveItem(at: src, to: aside)
                report.keptAside.append("\(src.path) → \(aside.path)")
            }
        }
    }

    /// `backup.json` (pre-rename name) → `restore-manifest.json`. When both exist the old entries
    /// go first (they are older), so the uninstaller still restores the true originals.
    private func renameManifest(report: inout Report) {
        let fm = FileManager.default
        let old = locations.appSupport.appendingPathComponent("backup.json")
        let new = locations.appSupport.appendingPathComponent("restore-manifest.json")
        guard fm.fileExists(atPath: old.path) else { return }
        do {
            if !fm.fileExists(atPath: new.path) {
                try fm.moveItem(at: old, to: new)
                report.moved.append("\(old.path) → \(new.path)")
                return
            }
            let merged = BackupJournal(url: locations.appSupport.appendingPathComponent(".manifest-merge.json"))
            try? fm.removeItem(at: merged.url)
            for e in try BackupJournal(url: old).entries() + BackupJournal(url: new).entries() { try merged.append(e) }
            _ = try fm.replaceItemAt(new, withItemAt: merged.url)
            let aside = Self.asideURL(for: locations.legacyAppSupport).appendingPathComponent("backup.json")
            try fm.createDirectory(at: aside.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: old, to: aside)
            report.notes.append("merged backup.json into restore-manifest.json (original kept at \(aside.path))")
        } catch {
            report.notes.append("could not rename backup.json: \(error.localizedDescription)")
        }
    }

    /// `theme = "caelestia-dynamic"` → `theme = "skyrose-dynamic"` (the loader accepts both; this
    /// keeps the file in step with the docs). Only that one key is touched, comments stay.
    private func rewriteThemeNames(report: inout Report) {
        let file = locations.configDir.appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        let updated = Self.rewritingThemeNames(in: text)
        guard updated != text else { return }
        do {
            try Data(updated.utf8).write(to: file, options: .atomic)
            report.notes.append("config.toml: theme renamed to its SkyRose name")
        } catch {
            report.notes.append("could not update config.toml: \(error.localizedDescription)")
        }
    }

    static func rewritingThemeNames(in text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("theme"), let eq = trimmed.firstIndex(of: "="),
                trimmed[..<eq].trimmingCharacters(in: .whitespaces) == "theme"
            else { return line }
            var out = line
            for (old, new) in SchemeLoader.legacyNames.sorted(by: { $0.key.count > $1.key.count }) {
                out = out.replacingOccurrences(of: "\"\(old)\"", with: "\"\(new)\"")
            }
            return out
        }.joined(separator: "\n")
    }

    private func moveKittyTheme(report: inout Report) {
        let fm = FileManager.default
        let old = locations.legacyKittyTheme, new = locations.kittyTheme
        guard fm.fileExists(atPath: old.path), !Self.isSymlink(old) else { return }
        do {
            if fm.fileExists(atPath: new.path) {
                let aside = old.deletingLastPathComponent().appendingPathComponent("caelestia-theme.pre-skyrose.conf")
                try? fm.removeItem(at: aside)
                try fm.moveItem(at: old, to: aside)
                report.keptAside.append("\(old.path) → \(aside.path)")
            } else {
                try fm.moveItem(at: old, to: new)
                report.moved.append("\(old.path) → \(new.path)")
            }
            // kitty.conf may `include caelestia-theme.conf`: keep that line working.
            try fm.createSymbolicLink(atPath: old.path, withDestinationPath: new.lastPathComponent)
            report.notes.append("left \(old.lastPathComponent) as a link to \(new.lastPathComponent) for kitty.conf includes")
        } catch {
            report.notes.append("could not move the kitty theme: \(error.localizedDescription)")
        }
    }

    private func writeMarker(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return }
        try? FileManager.default.createDirectory(at: locations.appSupport, withIntermediateDirectories: true)
        try? data.write(to: markerURL, options: .atomic)
    }

    // MARK: Helpers

    /// `<old folder>-pre-skyrose`, next to it: where duplicates are kept.
    static func asideURL(for old: URL) -> URL {
        old.deletingLastPathComponent().appendingPathComponent(old.lastPathComponent + "-pre-skyrose", isDirectory: true)
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// No entries except skipped ones (a stale socket) and empty subfolders.
    static func isEffectivelyEmpty(_ dir: URL) -> Bool {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
        return names.allSatisfy { name in
            if skippedNames.contains(name) { return true }
            let u = dir.appendingPathComponent(name)
            var d: ObjCBool = false
            return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue && !isSymlink(u) && isEffectivelyEmpty(u)
        }
    }
}
