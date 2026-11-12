import XCTest
@testable import CaelestiaServices

@MainActor
final class MediaPlayersTests: XCTestCase {
    private func systemState() -> MediaState {
        var s = MediaState()
        s.available = true
        s.isPlaying = true
        s.title = "Track"
        s.player = "QuickTime Player"
        s.playerBundleID = "com.apple.QuickTimePlayerX"
        return s
    }

    func testSystemSourceIsListedAndCannotBeQuit() async throws {
        try XCTSkipIf(MediaPlayer.allCases.contains { $0.isRunning }, "Spotify or Music is running here")
        let service = MediaService()
        let state = systemState()
        service.readSystemNowPlaying = { state }
        let published = expectation(description: "published")
        service.onChange = { _ in published.fulfill() }
        service.refresh()
        await fulfillment(of: [published], timeout: 2)
        XCTAssertEqual(service.state.players, [MediaSource(bundleID: "com.apple.QuickTimePlayerX", name: "QuickTime Player")])
        XCTAssertEqual(service.state.title, "Track")
        XCTAssertFalse(service.canQuit)
        service.quitPlayer()  // no scriptable player: does nothing
        XCTAssertEqual(service.state.title, "Track")
    }
}
