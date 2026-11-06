import CoreGraphics
import Foundation
import XCTest
@testable import CaelestiaCore

final class CaptureTests: XCTestCase {
    func testModesAndDefault() {
        XCTAssertEqual(CaptureMode(argument: nil), .region)
        XCTAssertEqual(CaptureMode(argument: ""), .region)
        XCTAssertEqual(CaptureMode(argument: "Freeze"), .freeze)
        XCTAssertEqual(CaptureMode(argument: "window"), .window)
        XCTAssertNil(CaptureMode(argument: "bogus"))
    }

    func testSelectionClickAndLocalPixels() {
        XCTAssertEqual(CaptureGeometry.selection(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20)), CGRect(x: 10, y: 20, width: 40, height: 60))
        XCTAssertTrue(CaptureGeometry.isClick(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 13, y: 12)))
        XCTAssertFalse(CaptureGeometry.isClick(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 15, y: 10)))
        // A second display to the right, at 1470: a selection over it in its own coordinates.
        let display = CGRect(x: 1470, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(CaptureGeometry.local(CGRect(x: 1500, y: 100, width: 200, height: 50), in: display), CGRect(x: 30, y: 100, width: 200, height: 50))
        // Clipped at the edge; outside → nil.
        XCTAssertEqual(CaptureGeometry.local(CGRect(x: 1400, y: 0, width: 100, height: 10), in: display), CGRect(x: 0, y: 0, width: 30, height: 10))
        XCTAssertNil(CaptureGeometry.local(CGRect(x: 0, y: 0, width: 100, height: 100), in: display))
        XCTAssertEqual(CaptureGeometry.pixels(CGRect(x: 10.4, y: 20.6, width: 100.2, height: 50), scale: 2), CGRect(x: 20, y: 41, width: 200, height: 100))
    }

    func testWindowUnderPointerSkipsOwnPanelsAndOtherLayers() {
        let w: [CaptureGeometry.WindowCandidate] = [
            .init(id: 1, pid: 99, layer: 0, bounds: CGRect(x: 0, y: 0, width: 2000, height: 1000)),   // our own panel
            .init(id: 2, pid: 10, layer: 25, bounds: CGRect(x: 0, y: 0, width: 2000, height: 30)),    // menu bar
            .init(id: 3, pid: 11, layer: 0, bounds: CGRect(x: 100, y: 100, width: 4, height: 4)),     // sliver
            .init(id: 4, pid: 12, layer: 0, bounds: CGRect(x: 50, y: 50, width: 400, height: 300)),
        ]
        XCTAssertEqual(CaptureGeometry.windowUnder(CGPoint(x: 101, y: 10), in: w, excludingPID: 99)?.id, nil)
        XCTAssertEqual(CaptureGeometry.windowUnder(CGPoint(x: 101, y: 101), in: w, excludingPID: 99)?.id, 4)
    }

    func testFileNameMatchesMacOSAndAvoidsCollisions() {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (2026, 11, 6, 9, 5, 7)
        let date = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(CaptureGeometry.fileName(at: date), "Screenshot 2026-11-06 at 09.05.07.png")
        let taken: Set = ["Screenshot 2026-11-06 at 09.05.07.png", "Screenshot 2026-11-06 at 09.05.07 (2).png"]
        XCTAssertEqual(CaptureGeometry.fileName(at: date) { taken.contains($0) }, "Screenshot 2026-11-06 at 09.05.07 (3).png")
        XCTAssertEqual(CaptureGeometry.folderURL("~/Pictures/Screenshots").path, NSHomeDirectory() + "/Pictures/Screenshots")
    }

    func testDefaultsLeaveMacOSShortcutsAlone() throws {
        let c = Config().capture
        XCTAssertFalse(c.overrideSystemShortcuts)
        XCTAssertTrue(c.saveToFolder && c.copyToClipboard && c.thumbnail)
        XCTAssertEqual(c.folder, "~/Pictures/Screenshots")
        let keymap = KeymapLoader.loadDefault()
        XCTAssertEqual(CaptureGeometry.withSystemShortcuts(keymap, enabled: false), keymap)
        // No default bind is a plain ⇧⌘3/4/5.
        let opt = keymap.modifiers
        for b in keymap.binds where b.action.kind == .captureRegion || b.action.kind == .captureFull || b.action.kind == .captureFreeze {
            for chord in b.chords {
                let physical = Set(chord.modifiers.map { opt[$0] })
                XCTAssertFalse(physical == [.lcmd, .shift] || physical == [.cmd, .shift], "\(b.id) overrides macOS")
            }
        }
    }

    func testOptInBindsUseTheCommandModifierOfThePreset() {
        let a = CaptureGeometry.systemShortcutBinds(modifiers: .optionIsSuper)
        XCTAssertEqual(a.map(\.keys), [["ALT + SHIFT + 3"], ["ALT + SHIFT + 4"], ["ALT + SHIFT + 5"]], "preset A: ALT is ⌘")
        XCTAssertEqual(a.map(\.action.kind), [.captureFull, .captureRegion, .captureFreeze])
        XCTAssertTrue(a.allSatisfy { $0.chords.count == 1 })
        XCTAssertEqual(CaptureGeometry.systemShortcutBinds(modifiers: .commandIsSuper).first?.keys, ["SUPER + SHIFT + 3"])
        XCTAssertTrue(CaptureGeometry.systemShortcutBinds(modifiers: .capsLockIsHyper).isEmpty, "no ⌘ modifier, no binds")
        let k = CaptureGeometry.withSystemShortcuts(KeymapLoader.loadDefault(), enabled: true)
        XCTAssertEqual(k.binds.filter { $0.id.hasPrefix("capture.system.") }.count, 3)
        XCTAssertEqual(CaptureGeometry.withSystemShortcuts(k, enabled: true).binds.count, k.binds.count, "idempotent")
    }
}
