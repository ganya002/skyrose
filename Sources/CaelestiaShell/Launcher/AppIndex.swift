import AppKit
import CaelestiaServices
import Foundation

/// Installed apps for the launcher (spec 5.3). Three sources, merged by bundle id in this order:
/// SkyRose's own bundle (and SkyRose Settings next to it), the app folders (/Applications,
/// ~/Applications, /System/Applications and the Utilities folders, sub-folders a few levels
/// deep), then everything Spotlight knows as `com.apple.application-bundle` (`AppIndexWatcher`).
/// Read off the main thread; launch counts persist in Application Support.
public enum AppIndex {
    public static let skyRoseBundleID = "com.skyrose.mac"
    public static let settingsBundleID = "com.skyrose.mac.settings"
    /// Sub-folder levels scanned below each root (Setapp/, Adobe …/, "Chrome Apps.localized"/…).
    public static let maxDepth = 3

    public static var searchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            // Finder and the CoreServices apps (Archive Utility, Directory Utility, …).
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
        ]
    }

    /// Apps outside the roots that are always listed.
    public static let pinnedApps: [URL] = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]

    /// SkyRose.app this process runs from (nil for a SwiftPM binary outside a bundle).
    public static var ownBundleURL: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// SkyRose Settings: next to SkyRose.app, else wherever Launch Services has it.
    public static func settingsAppURL(near own: URL? = ownBundleURL) -> URL? {
        if let own {
            let sibling = own.deletingLastPathComponent().appendingPathComponent("SkyRose Settings.app")
            if FileManager.default.fileExists(atPath: sibling.path) { return sibling }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: settingsBundleID)
    }

    /// SkyRose's own apps, listed even though SkyRose.app is an agent (LSUIElement).
    public static func ownApps(own: URL? = ownBundleURL, settings: URL? = nil) -> [URL] {
        [own, settings ?? settingsAppURL(near: own)].compactMap { $0 }
    }

    /// Whether a Spotlight hit is a real, launchable install: not inside another bundle, not in a
    /// hidden folder (Trash, .build, Time Machine), not a cache, container, simulator or helper.
    public static func isIndexable(path: String) -> Bool {
        guard path.hasSuffix(".app") else { return false }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return false }
        if parts.dropLast().contains(where: { $0.hasSuffix(".app") || $0.hasSuffix(".bundle") || $0.hasSuffix(".framework") }) { return false }
        if parts.contains(where: { $0.hasPrefix(".") }) { return false }
        if path.hasPrefix("/System/Library/") {
            return path.hasPrefix("/System/Library/CoreServices/Applications/") || pinnedApps.contains { $0.path == path }
        }
        // Mounted disk images (/Volumes) are installers, not installs.
        let blockedPrefixes = ["/private/", "/usr/", "/opt/", "/Volumes/", "/Library/Apple/"]
        let blockedAnywhere = ["/Library/Caches/", "/Library/Containers/", "/Library/Group Containers/", "/Library/Developer/",
                               "/Library/Application Support/", "/DerivedData/", "/Backups.backupdb/"]
        return !blockedPrefixes.contains { path.hasPrefix($0) } && !blockedAnywhere.contains { path.contains($0) }
    }

    /// Scans `roots` and merges `own` and `extra` (blocking; call from a background queue).
    /// The first copy of a bundle id wins: own apps, then roots in order, then `extra`.
    public static func scan(roots: [URL] = searchRoots, pinned: [URL] = pinnedApps, own: [URL] = [], extra: [URL] = [],
                            counts: [String: Int] = [:]) -> [LaunchableApp] {
        var seen = Set<String>()
        var apps: [LaunchableApp] = []
        let fm = FileManager.default
        func add(_ url: URL, allowAgent: Bool = false) {
            guard let app = read(url, allowAgent: allowAgent), !seen.contains(app.id) else { return }
            seen.insert(app.id)
            var a = app
            a.launchCount = counts[a.id] ?? 0
            apps.append(a)
        }
        func visit(_ dir: URL, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                            options: [.skipsHiddenFiles]) else { return }
            for url in entries {
                if url.pathExtension == "app" {
                    add(url)
                } else if depth < maxDepth, url.pathExtension.isEmpty || url.pathExtension == "localized",
                          let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          values.isDirectory == true, values.isSymbolicLink != true {
                    visit(url, depth: depth + 1)
                }
            }
        }
        for url in own { add(url, allowAgent: true) }
        for root in roots { visit(root, depth: 0) }
        for url in pinned { add(url) }
        for url in extra where isIndexable(path: url.path) { add(url) }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `allowAgent` keeps an LSUIElement app (SkyRose itself).
    public static func read(_ url: URL, allowAgent: Bool = false) -> LaunchableApp? {
        guard let bundle = Bundle(url: url), let info = bundle.infoDictionary else { return nil }
        let agent = (info["LSUIElement"] as? Bool) == true || (info["LSUIElement"] as? String) == "1"
        if agent, !allowAgent { return nil }
        if (info["LSBackgroundOnly"] as? Bool) == true { return nil }
        let localized = bundle.localizedInfoDictionary
        let name = (localized?["CFBundleDisplayName"] as? String) ?? (info["CFBundleDisplayName"] as? String)
            ?? (localized?["CFBundleName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = bundle.bundleIdentifier ?? ""
        let category = (info["LSApplicationCategoryType"] as? String).map(categoryName) ?? ""
        let description = knownDescriptions[bundleID] ?? category
        var keywords: [String] = []
        if !category.isEmpty { keywords.append(category) }
        let fileName = url.deletingPathExtension().lastPathComponent
        if fileName != name { keywords.append(fileName) }
        return LaunchableApp(name: name, bundleID: bundleID, url: url, description: description, keywords: keywords)
    }

    /// "public.app-category.developer-tools" → "Developer Tools".
    public static func categoryName(_ uti: String) -> String {
        guard let last = uti.split(separator: ".").last else { return "" }
        return last.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Short descriptions in the style of Linux .desktop files (macOS has no equivalent field).
    public static let knownDescriptions: [String: String] = [
        "org.mozilla.firefox": "Fast and private browser",
        "net.kovidgoyal.kitty": "Fast, feature-rich, GPU based terminal",
        "com.apple.finder": "Access and organize files",
        "com.apple.Terminal": "Use the command line",
        "com.apple.Safari": "Browse the web",
        "com.google.Chrome": "Access the Internet",
        "com.apple.TextEdit": "Edit text files",
        "com.apple.systempreferences": "Configure your Mac",
        "com.apple.ActivityMonitor": "View and manage running processes",
        "com.apple.mail": "Send and receive email",
        "com.apple.Music": "Play and organize music",
        "com.apple.Notes": "Write and organize notes",
        "com.apple.Preview": "View images and PDFs",
        "com.apple.calculator": "Perform calculations",
        "com.apple.iCal": "Manage your calendar",
        "com.apple.AppStore": "Find and install apps",
        "com.apple.dt.Xcode": "Build apps for Apple platforms",
        "com.microsoft.VSCode": "Code editing. Redefined.",
        "com.vscodium": "Code editing. Redefined.",
        "com.spotify.client": "Listen to music",
        "com.hnc.Discord": "Talk, chat and hang out",
        "com.skyrose.mac.testwindows": "SkyRose test windows",
        "com.skyrose.mac": "Tiling window manager and shell",
        "com.skyrose.mac.settings": "Configure SkyRose",
    ]
}

/// Launch counts for frequency ranking (`launcher-counts.json` in Application Support).
@MainActor
public final class LaunchCounts {
    public private(set) var counts: [String: Int]
    private let url: URL

    public init(url: URL = ServiceStorage.url("launcher-counts.json")) {
        self.url = url
        counts = ServiceStorage.load([String: Int].self, from: url) ?? [:]
    }

    public func bump(_ id: String) {
        counts[id, default: 0] += 1
        ServiceStorage.save(counts, to: url)
    }
}
