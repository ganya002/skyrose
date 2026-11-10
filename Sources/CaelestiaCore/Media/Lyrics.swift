import Foundation

/// One synced lyric line. Times are seconds from the start of the track.
public struct LyricLine: Equatable, Sendable, Identifiable {
    public var id: Int { Int(time * 1000) }
    public var time: TimeInterval
    public var text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

/// A track identity for LRCLIB and the local cache.
public struct LyricTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double

    public init(title: String, artist: String, album: String, duration: Double) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    /// Stable file name. Only letters and digits survive, so the cache path stays boring.
    public var cacheKey: String {
        let raw = "\(artist)|\(title)|\(album)|\(Int(duration.rounded()))".lowercased()
        let cleaned = raw.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return cleaned.isEmpty ? "track" : String(cleaned.prefix(120))
    }
}

/// Where a track is between position reports. Players report every couple of seconds, which is
/// too coarse for a lyric line, so the time in between is counted here.
public struct LyricClock: Equatable, Sendable {
    public var position: Double
    public var at: Date
    public var playing: Bool
    public var duration: Double

    public init(position: Double = 0, at: Date = .distantPast, playing: Bool = false, duration: Double = 0) {
        self.position = position
        self.at = at
        self.playing = playing
        self.duration = duration
    }

    public func position(at now: Date) -> Double {
        guard playing else { return position }
        let moved = position + max(0, now.timeIntervalSince(at))
        return duration > 0 ? min(moved, duration) : moved
    }
}

public enum Lyrics {
    /// Parses LRC. Several timestamps on one line each become their own line. Tags like `[ar:]` are skipped.
    public static func parse(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let row = String(raw)
            var times: [TimeInterval] = []
            var rest = row[...]
            while true {
                rest = rest.drop(while: { $0 == " " || $0 == "\t" })
                guard rest.first == "[" else { break }
                guard let end = rest.firstIndex(of: "]") else { break }
                let inside = rest[rest.index(after: rest.startIndex)..<end]
                if let time = timestamp(String(inside)) { times.append(time) }
                rest = rest[rest.index(after: end)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            guard !times.isEmpty, !words.isEmpty else { continue }
            for time in times { lines.append(LyricLine(time: time, text: words)) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// The line being sung at `time`, or nil before the first line.
    public static func index(of lines: [LyricLine], at time: TimeInterval) -> Int? {
        guard isSynced(lines) else { return nil }
        var chosen: Int?
        for (i, line) in lines.enumerated() where line.time <= time + 0.05 { chosen = i }
        return chosen
    }

    /// Plain lyrics are stored as lines at 0, so they have no line to highlight or seek to.
    public static func isSynced(_ lines: [LyricLine]) -> Bool {
        guard let first = lines.first else { return false }
        return lines.contains { $0.time != first.time }
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx`.
    static func timestamp(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let minutes = Double(parts[0]), minutes >= 0 else { return nil }
        let seconds = parts[1].replacingOccurrences(of: ",", with: ".")
        guard let secs = Double(seconds), secs >= 0, secs < 60 else { return nil }
        return minutes * 60 + secs
    }

    /// LRCLIB `GET /api/get`, most exact first. LRCLIB answers 404 when the album is wrong, and
    /// players often report a different album (a single, a remaster, a browser's page title).
    public static func requests(for track: LyricTrack) -> [URL] {
        let title = cleanTitle(track.title)
        let artist = cleanArtist(track.artist)
        var urls = [get(title: track.title, artist: track.artist, album: track.album, duration: track.duration)]
        urls.append(get(title: title, artist: artist, album: "", duration: track.duration))
        urls.append(get(title: title, artist: artist, album: "", duration: 0))
        var seen = Set<URL>()
        return urls.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    /// LRCLIB `GET /api/search`, the last resort.
    public static func searchRequest(for track: LyricTrack) -> URL? {
        var c = URLComponents(string: "https://lrclib.net/api/search")
        c?.queryItems = [
            URLQueryItem(name: "track_name", value: cleanTitle(track.title)),
            URLQueryItem(name: "artist_name", value: cleanArtist(track.artist)),
        ]
        return c?.url
    }

    private static func get(title: String, artist: String, album: String, duration: Double) -> URL? {
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration >= 1 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        var c = URLComponents(string: "https://lrclib.net/api/get")
        c?.queryItems = items
        return c?.url
    }

    /// Drops what video sites add to a song's name: "(Official Video)", "[Lyrics]", "feat. …",
    /// and an "Artist - " prefix.
    public static func cleanTitle(_ raw: String) -> String {
        var title = raw
        let noise = "official|lyrics?|audio|video|visuali[sz]er|music video|remaster(ed)?|hd|4k|mv"
        for pattern in ["[\\(\\[][^\\)\\]]*\\b(\(noise))\\b[^\\)\\]]*[\\)\\]]", "[\\(\\[]\\s*(feat\\.?|ft\\.?|with)\\s[^\\)\\]]*[\\)\\]]", "\\s(feat\\.?|ft\\.?)\\s.*$"] {
            title = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        if let dash = title.range(of: " - ") { title = String(title[dash.upperBound...]) }
        title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? raw : title
    }

    /// "Queen - Topic" and "QueenVEVO" are YouTube channel names. Only the first of several artists is kept.
    public static func cleanArtist(_ raw: String) -> String {
        var artist = raw.replacingOccurrences(of: "\\s*-\\s*Topic$", with: "", options: .regularExpression)
        artist = artist.replacingOccurrences(of: "VEVO$", with: "", options: .regularExpression)
        if let split = artist.range(of: "\\s*(,|&| x | feat\\.? | ft\\.? )\\s*", options: [.regularExpression, .caseInsensitive]) {
            artist = String(artist[..<split.lowerBound])
        }
        artist = artist.trimmingCharacters(in: .whitespaces)
        return artist.isEmpty ? raw : artist
    }

    /// Prefers synced LRC. Plain lyrics become lines at 0. Empty is nil.
    public static func fromLRCLIB(_ data: Data) -> [LyricLine]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return lines(from: object)
    }

    /// The best hit of a search: synced and the right length first, else any plain lyric.
    /// A synced lyric of another cut is left out, because its lines would be off.
    public static func fromSearch(_ data: Data, duration: Double) -> [LyricLine]? {
        guard let hits = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var plain: [LyricLine]?
        for hit in hits {
            guard let found = lines(from: hit) else { continue }
            if !isSynced(found) {
                plain = plain ?? found
                continue
            }
            let length = (hit["duration"] as? NSNumber)?.doubleValue ?? 0
            if duration < 1 || length < 1 || abs(length - duration) <= 8 { return found }
        }
        return plain
    }

    private static func lines(from object: [String: Any]) -> [LyricLine]? {
        if let synced = object["syncedLyrics"] as? String {
            let lines = parse(synced)
            if !lines.isEmpty { return lines }
        }
        if let plain = object["plainLyrics"] as? String {
            let lines = plain.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { LyricLine(time: 0, text: $0) }
            if !lines.isEmpty { return lines }
        }
        return nil
    }
}

public enum LyricCache {
    public static func file(for track: LyricTrack, in directory: URL) -> URL {
        directory.appendingPathComponent(track.cacheKey + ".lrc")
    }

    public static func load(track: LyricTrack, directory: URL) -> [LyricLine]? {
        let url = file(for: track, in: directory)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = Lyrics.parse(text)
        return lines.isEmpty ? nil : lines
    }

    public static func save(_ lines: [LyricLine], track: LyricTrack, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let body = lines.map { line in
            let m = Int(line.time) / 60
            let s = line.time - Double(m * 60)
            return String(format: "[%02d:%05.2f]%@", m, s, line.text)
        }.joined(separator: "\n")
        try Data(body.utf8).write(to: file(for: track, in: directory), options: .atomic)
    }
}
