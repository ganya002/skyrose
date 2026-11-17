import CoreGraphics
import XCTest

@testable import CaelestiaShell

final class FullscreenCoverTests: XCTestCase {
    let builtIn = FullscreenCover.Display(id: "A", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchInset: 33)
    let external = FullscreenCover.Display(id: "B", frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440))
    var displays: [FullscreenCover.Display] { [builtIn, external] }

    func testFullscreenWindowCoversOnlyItsDisplay() {
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [builtIn.frame], isGame: false), ["A"])
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [external.frame], isGame: false), ["B"])
    }

    func testBorderlessWindowSlightlyLargerCounts() {
        let w = builtIn.frame.insetBy(dx: -0.5, dy: -0.5)
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [w], isGame: false), ["A"])
    }

    func testMaximisedWindowBelowTheMenuBarIsNotFullscreen() {
        let w = CGRect(x: 0, y: 33, width: 1512, height: 949)
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [w], isGame: false), [])
    }

    /// Live: macOS 27 puts a native fullscreen window below the notch (0,33 1470x923) with a
    /// black layer -1 window behind it over the whole display.
    func testNativeFullscreenBelowTheNotchCounts() {
        let w = CGRect(x: 0, y: 33, width: 1512, height: 949)
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [w], backdrops: [builtIn.frame], isGame: false), ["A"])
        // No notch on the external display: the same shape there needs the whole display.
        let ext = CGRect(x: 1512, y: -170, width: 2560, height: 1410)
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [ext], backdrops: [external.frame], isGame: false), [])
    }

    func testWindowedGameCoversTheDisplayUnderItsFrontWindow() {
        let game = CGRect(x: 1700, y: 100, width: 1280, height: 720)
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [game], isGame: true), ["B"])
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [game], isGame: false), [])
    }

    func testAWindowedWindowInFrontOfTheFullscreenOneBringsTheBarBack() {
        let windowed = CGRect(x: 100, y: 100, width: 640, height: 420)
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [windowed, builtIn.frame], isGame: false), [])
        // Its own front window on the other display still counts there.
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [windowed, external.frame], isGame: false), ["B"])
    }

    func testSmallWindowsAndNoWindowsCoverNothing() {
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [CGRect(x: 10, y: 10, width: 40, height: 40)], isGame: true), [])
        XCTAssertEqual(FullscreenCover.covered(displays: displays, windows: [], isGame: true), [])
    }

    func testRegionRecordingClipsToTheDisplay() {
        let d = external.frame
        XCTAssertEqual(DisplayMovieRecorder.sourceRect(CGRect(x: 1600, y: -100, width: 300, height: 200), in: d),
                       CGRect(x: 88, y: 100, width: 300, height: 200))
        // Hanging off the left edge: clipped.
        XCTAssertEqual(DisplayMovieRecorder.sourceRect(CGRect(x: 1400, y: 0, width: 300, height: 200), in: d),
                       CGRect(x: 0, y: 200, width: 188, height: 200))
        XCTAssertNil(DisplayMovieRecorder.sourceRect(CGRect(x: 0, y: 0, width: 100, height: 100), in: d))
    }
}
