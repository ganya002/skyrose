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
        guard !lines.isEmpty else { return nil }
        var chosen: Int?
        for (i, line) in lines.enumerated() where line.time <= time + 0.05 { chosen = i }
        return chosen
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx`.
    static func timestamp(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let minutes = Double(parts[0]), minutes >= 0 else { return nil }
        let seconds = parts[1].replacingOccurrences(of: ",", with: ".")
        guard let secs = Double(seconds), secs >= 0, secs < 60 else { return nil }
        return minutes * 60 + secs
    }

    /// LRCLIB `GET /api/get`. Duration is omitted when it is unknown.
    public static func request(for track: LyricTrack) -> URL? {
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration >= 1 { items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        var c = URLComponents(string: "https://lrclib.net/api/get")
        c?.queryItems = items
        return c?.url
    }

    /// Prefers synced LRC. A plain lyric becomes one line at 0. Empty is nil.
    public static func fromLRCLIB(_ data: Data) -> [LyricLine]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let synced = object["syncedLyrics"] as? String {
            let lines = parse(synced)
            if !lines.isEmpty { return lines }
        }
        if let plain = object["plainLyrics"] as? String {
            let text = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return [LyricLine(time: 0, text: text)] }
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
