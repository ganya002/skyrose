import XCTest
@testable import CaelestiaCore

final class LyricsTests: XCTestCase {
    func testLRCParsesTimesAndSkipsTags() {
        let text = """
        [ar:Someone]
        [00:01.50] Hello
        [00:03.00] [00:05.25] Again
        [00:04] Between
        """
        let lines = Lyrics.parse(text)
        XCTAssertEqual(lines.map(\.text), ["Hello", "Again", "Between", "Again"])
        XCTAssertEqual(lines.map { Int($0.time * 100) }, [150, 300, 400, 525])
    }

    func testCurrentLineFollowsTheClock() {
        let lines = Lyrics.parse("[00:01.00] One\n[00:03.00] Two")
        XCTAssertNil(Lyrics.index(of: lines, at: 0.2))
        XCTAssertEqual(Lyrics.index(of: lines, at: 1.0), 0)
        XCTAssertEqual(Lyrics.index(of: lines, at: 2.9), 0)
        XCTAssertEqual(Lyrics.index(of: lines, at: 3.0), 1)
    }

    func testLRCLIBPrefersSyncedAndFallsBackToPlain() throws {
        let synced = #"{"syncedLyrics":"[00:01.00] Hi","plainLyrics":"nope"}"#.data(using: .utf8)!
        XCTAssertEqual(Lyrics.fromLRCLIB(synced)?.map(\.text), ["Hi"])
        let plain = #"{"syncedLyrics":"","plainLyrics":"Just words"}"#.data(using: .utf8)!
        XCTAssertEqual(Lyrics.fromLRCLIB(plain)?.first?.text, "Just words")
        XCTAssertNil(Lyrics.fromLRCLIB(Data("{}" .utf8)))
        let url = try XCTUnwrap(Lyrics.requests(for: LyricTrack(title: "Song", artist: "A", album: "B", duration: 180)).first)
        XCTAssertEqual(url.host, "lrclib.net")
        XCTAssertTrue(url.query?.contains("track_name=Song") == true)
    }

    func testCacheRoundTripAndKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-\(UUID().uuidString)", isDirectory: true)
        let track = LyricTrack(title: "A Song!", artist: "The Band", album: "LP", duration: 200)
        XCTAssertFalse(track.cacheKey.contains(" "))
        XCTAssertFalse(track.cacheKey.contains("!"))
        let lines = [LyricLine(time: 1.5, text: "Hello")]
        try LyricCache.save(lines, track: track, directory: dir)
        XCTAssertEqual(LyricCache.load(track: track, directory: dir), lines)
        try? FileManager.default.removeItem(at: dir)
    }

    func testBeatsLandOnTheClicksAndNotTheSilence() {
        var detector = BeatDetector(sampleRate: 44100, window: 1024, multiplier: 2.2, refractory: 0.2)
        var samples = [Float](repeating: 0, count: 44100 * 2)
        for at in [0.5, 1.0, 1.5] {
            let start = Int(at * 44100)
            for i in start..<start + 180 { samples[i] = 1 }
        }
        let beats = detector.feed(samples)
        XCTAssertEqual(beats.count, 3, "\(beats)")
        XCTAssertEqual(beats[0], 0.5, accuracy: 0.05)
        XCTAssertEqual(beats[1], 1.0, accuracy: 0.05)
        XCTAssertEqual(beats[2], 1.5, accuracy: 0.05)
        var quiet = BeatDetector()
        XCTAssertTrue(quiet.feed([Float](repeating: 0, count: 44100)).isEmpty)
    }

    func testAWrongAlbumStillFindsTheSong() throws {
        let urls = Lyrics.requests(for: LyricTrack(title: "Song", artist: "A", album: "Greatest Hits", duration: 180))
        XCTAssertEqual(urls.count, 3)
        XCTAssertTrue(urls[0].query?.contains("album_name") == true)
        XCTAssertFalse(urls[1].query?.contains("album_name") == true, "LRCLIB 404s on a wrong album")
        XCTAssertFalse(urls[2].query?.contains("duration") == true)
    }

    func testVideoSiteNamesAreCleaned() {
        XCTAssertEqual(Lyrics.cleanTitle("Queen - Bohemian Rhapsody (Official Video Remastered)"), "Bohemian Rhapsody")
        XCTAssertEqual(Lyrics.cleanTitle("Song [Lyrics]"), "Song")
        XCTAssertEqual(Lyrics.cleanTitle("Song (feat. Someone)"), "Song")
        XCTAssertEqual(Lyrics.cleanTitle("Song ft. Someone"), "Song")
        XCTAssertEqual(Lyrics.cleanTitle("Live and Let Die"), "Live and Let Die")
        XCTAssertEqual(Lyrics.cleanArtist("Queen - Topic"), "Queen")
        XCTAssertEqual(Lyrics.cleanArtist("QueenVEVO"), "Queen")
        XCTAssertEqual(Lyrics.cleanArtist("A, B & C"), "A")
    }

    func testSearchWantsTheRightLengthForSyncedLyrics() {
        let body = #"[{"duration":300,"syncedLyrics":"[00:01.00] Wrong cut\n[00:02.00] x"},{"duration":355,"syncedLyrics":"[00:01.00] Right\n[00:02.00] y"}]"#
        XCTAssertEqual(Lyrics.fromSearch(Data(body.utf8), duration: 354)?.first?.text, "Right")
        XCTAssertEqual(Lyrics.fromSearch(Data(body.utf8), duration: 0)?.first?.text, "Wrong cut", "no length to compare")
        let plain = #"[{"duration":300,"syncedLyrics":"[00:01.00] Wrong\n[00:02.00] x"},{"duration":200,"plainLyrics":"Words"}]"#
        XCTAssertEqual(Lyrics.fromSearch(Data(plain.utf8), duration: 354)?.map(\.text), ["Words"])
    }

    func testPlainLyricsKeepEveryLineAndHaveNoCurrentLine() throws {
        let data = #"{"plainLyrics":"One\nTwo\n\nThree"}"#.data(using: .utf8)!
        let lines = try XCTUnwrap(Lyrics.fromLRCLIB(data))
        XCTAssertEqual(lines.map(\.text), ["One", "Two", "Three"])
        XCTAssertFalse(Lyrics.isSynced(lines))
        XCTAssertNil(Lyrics.index(of: lines, at: 30))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-\(UUID().uuidString)", isDirectory: true)
        let track = LyricTrack(title: "T", artist: "A", album: "", duration: 0)
        try LyricCache.save(lines, track: track, directory: dir)
        XCTAssertEqual(LyricCache.load(track: track, directory: dir)?.map(\.text), ["One", "Two", "Three"])
        try? FileManager.default.removeItem(at: dir)
    }

    func testTheClockCountsBetweenReportsAndStopsWhenPaused() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(LyricClock(position: 10, at: start, playing: true, duration: 300).position(at: start + 1.5), 11.5)
        XCTAssertEqual(LyricClock(position: 10, at: start, playing: false, duration: 300).position(at: start + 5), 10)
        XCTAssertEqual(LyricClock(position: 299, at: start, playing: true, duration: 300).position(at: start + 5), 300)
    }
}
