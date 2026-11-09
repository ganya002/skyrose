import CryptoKit
import Foundation

/// Compares the installed version with a GitHub release and checks a downloaded zip.
/// Never treats an older tag as an update.
public enum Updater {
    public struct Asset: Decodable, Equatable, Sendable {
        public var name: String
        public var browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" }
    }

    public struct Release: Decodable, Equatable, Sendable {
        public var tagName: String
        public var assets: [Asset]
        enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case assets }
    }

    public enum Plan: Equatable, Sendable {
        case update(tag: String, zip: URL, checksum: URL)
        case upToDate
        case newerInstalled(tag: String)
        case unreadable(String)
    }

    public static let releaseAPI = URL(string: "https://api.github.com/repos/ganya002/skyrose/releases/latest")!

    /// `0.2.0` and `v0.3.0` compare numerically. A non-numeric tag does not count as newer.
    public static func compare(_ installed: String, _ latest: String) -> ComparisonResult {
        let a = parts(installed), b = parts(latest)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func plan(current: String, json: Data) -> Plan {
        let decoder = JSONDecoder()
        guard let release = try? decoder.decode(Release.self, from: json) else {
            return .unreadable("The release list could not be read.")
        }
        switch compare(current, release.tagName) {
        case .orderedDescending:
            return .newerInstalled(tag: release.tagName)
        case .orderedSame:
            return .upToDate
        case .orderedAscending:
            guard let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") && !$0.name.hasSuffix(".zip.sha256") }),
                  let sha = release.assets.first(where: { $0.name == zip.name + ".sha256" }) else {
                return .unreadable("The release has no zip and checksum.")
            }
            return .update(tag: release.tagName, zip: zip.browserDownloadURL, checksum: sha.browserDownloadURL)
        }
    }

    public static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The first field of a `shasum` line.
    public static func expectedHash(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
    }

    public static func checksumMatches(file: URL, shaFile: URL) -> Bool {
        guard let got = sha256(of: file) else { return false }
        let expected = expectedHash((try? String(contentsOf: shaFile, encoding: .utf8)) ?? "")
        return !expected.isEmpty && got == expected
    }

    private static func parts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".").map { Int($0) ?? 0 }
    }
}
