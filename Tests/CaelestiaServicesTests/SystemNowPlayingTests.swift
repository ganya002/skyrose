import XCTest
@testable import CaelestiaServices

final class SystemNowPlayingTests: XCTestCase {
    private func parse(_ text: String, now: Double = 1000) -> MediaState? {
        SystemNowPlaying.parse(Data(text.utf8), now: Date(timeIntervalSince1970: now))
    }

    func testABrowserTabIsATrack() throws {
        let s = try XCTUnwrap(parse(#"{"bundle":"org.mozilla.firefox","name":"Firefox","title":"Song","artist":"A","album":"B","duration":200,"elapsed":10,"rate":1,"timestamp":998,"playing":true}"#))
        XCTAssertTrue(s.available)
        XCTAssertTrue(s.isPlaying)
        XCTAssertEqual(s.player, "Firefox")
        XCTAssertEqual(s.playerBundleID, "org.mozilla.firefox")
        XCTAssertEqual(s.position, 12, accuracy: 0.001, "elapsed plus the time since it was reported")
    }

    func testPausedDoesNotAdvanceAndMissingFieldsAreFine() throws {
        let s = try XCTUnwrap(parse(#"{"bundle":"x","title":"Song","elapsed":10,"rate":0,"timestamp":900,"playing":false}"#))
        XCTAssertFalse(s.isPlaying)
        XCTAssertEqual(s.position, 10)
        XCTAssertEqual(s.artist, "")
        XCTAssertEqual(s.duration, 0)
        XCTAssertEqual(s.player, "x")
    }

    func testPositionStopsAtTheEnd() throws {
        let s = try XCTUnwrap(parse(#"{"title":"S","duration":100,"elapsed":99,"rate":1,"timestamp":900,"playing":true}"#))
        XCTAssertEqual(s.position, 100)
    }

    func testNothingPlayingIsNil() {
        XCTAssertNil(parse("{}"))
        XCTAssertNil(parse(#"{"title":""}"#))
        XCTAssertNil(parse("not json"))
    }

    /// Runs the real script. Nothing may be playing, so only "it does not fail or hang" is checked.
    func testTheScriptAnswersOnThisMac() async {
        let started = Date()
        _ = await SystemNowPlaying.read()
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
}
