import AppKit
import CaelestiaServices
import Foundation

/// Installed apps for the launcher (spec 5.3): /Applications, ~/Applications,
/// /System/Applications and their Utilities folders, one level of sub-folders deep. Read off the
/// main thread; launch counts persist in Application Support.
public enum AppIndex {
    public static var searchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
        ]
    }

    /// Scans `roots` (blocking; call from a background queue).
    public static func scan(roots: [URL] = searchRoots, counts: [String: Int] = [:]) -> [LaunchableApp] {
        var seen = Set<String>()
        var apps: [LaunchableApp] = []
        let fm = FileManager.default
        func visit(_ dir: URL, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for url in entries {
                if url.pathExtension == "app" {
                    guard let app = read(url), !seen.contains(app.id) else { continue }
                    seen.insert(app.id)
                    var a = app
                    a.launchCount = counts[a.id] ?? 0
                    apps.append(a)
                } else if depth < 1, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(url, depth: depth + 1)
                }
            }
        }
        for root in roots { visit(root, depth: 0) }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func read(_ url: URL) -> LaunchableApp? {
        guard let bundle = Bundle(url: url), let info = bundle.infoDictionary else { return nil }
        if (info["LSUIElement"] as? Bool) == true || (info["LSUIElement"] as? String) == "1" { return nil }
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
        "com.caelestia.mac.testwindows": "Caelestia test windows",
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
