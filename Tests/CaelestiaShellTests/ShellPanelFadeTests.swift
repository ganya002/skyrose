import AppKit
import XCTest

@testable import CaelestiaShell

/// The end of a hide must not put the panel back at full opacity while it is still on screen.
/// That one frame is the flash after every drawer, OSD and menu closes.
@MainActor
final class ShellPanelFadeTests: XCTestCase {
    func testAnInstantHideStaysAtZeroUntilThePanelIsGone() {
        let panel = ShellPanel(frame: CGRect(x: 80, y: 80, width: 40, height: 20), level: .floating, name: "fade-test")
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        XCTAssertTrue(panel.isVisible)
        panel.fadeOut(duration: 0)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 0, "alpha stays at the end value; restoring 1 while ordered in is the flash")
        panel.close()
    }

    func testTheRestPoseReturnsOnlyAfterThePanelIsHidden() {
        let panel = ShellPanel(frame: CGRect(x: 80, y: 80, width: 40, height: 20), level: .floating, name: "fade-restore")
        panel.orderFrontRegardless()
        panel.alphaValue = 1
        panel.orderOutSettled()
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 0)
        let done = expectation(description: "rest pose")
        DispatchQueue.main.async {
            XCTAssertFalse(panel.isVisible)
            XCTAssertEqual(panel.alphaValue, 1, "the rest pose is restored only once the panel is ordered out")
            panel.close()
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func testShowingAgainCancelsTheDeferredRestore() {
        let panel = ShellPanel(frame: CGRect(x: 80, y: 80, width: 40, height: 20), level: .floating, name: "fade-cancel")
        panel.orderFrontRegardless()
        panel.orderOutSettled()
        panel.cancelHideRestore()
        panel.alphaValue = 0.25
        panel.orderFrontRegardless()
        let done = expectation(description: "no restore")
        DispatchQueue.main.async {
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.alphaValue, 0.25, accuracy: 0.001, "a show in progress is not snapped back to 1")
            panel.close()
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }
}
