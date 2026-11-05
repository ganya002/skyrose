import CaelestiaCore
import SwiftUI
import XCTest
@testable import SkyRoseSettingsKit

@MainActor
final class SIPReminderModelTests: XCTestCase {
    func testDismissOnlyAfterMinimumAndCallbackOnce() {
        var t: TimeInterval = 100
        let model = SIPReminderModel(now: { t })
        var calls = 0
        model.onDismiss = { calls += 1 }
        XCTAssertEqual(model.remaining, 5)
        XCTAssertFalse(model.dismiss())
        t = 102
        model.tick()
        XCTAssertEqual(model.remaining, 3)
        XCTAssertFalse(model.dismiss())
        t = 104.5
        model.tick()
        XCTAssertEqual(model.remaining, 1)
        XCTAssertFalse(model.canDismiss)
        XCTAssertEqual(calls, 0)
        t = 105
        XCTAssertTrue(model.dismiss())
        XCTAssertEqual(model.remaining, 0)
        XCTAssertTrue(model.canDismiss)
        XCTAssertEqual(calls, 1)
    }
}

final class SettingsMotionTests: XCTestCase {
    func testClampedStaysInBand() {
        for speed in [0.1, 0.5, 1, 2, 10, 0, -3, .infinity, .nan] {
            for d in [0.05, 0.18, 0.26, 0.30, 1.0] {
                let v = SettingsMotion.clamped(d, speed: speed)
                XCTAssertGreaterThanOrEqual(v, 0.15)
                XCTAssertLessThanOrEqual(v, 0.30)
            }
        }
        XCTAssertEqual(SettingsMotion.clamped(0.26, speed: 1), 0.26, accuracy: 1e-9)
        XCTAssertEqual(SettingsMotion.clamped(0.26, speed: 10), 0.15, accuracy: 1e-9)
        XCTAssertEqual(SettingsMotion.clamped(0.26, speed: 0.1), 0.30, accuracy: 1e-9)
    }

    func testReduceMotionIsShortFade() {
        let reduced = SettingsMotion(reduceMotion: true)
        XCTAssertEqual(reduced.quick, .easeInOut(duration: 0.12))
        XCTAssertEqual(reduced.pop, .easeInOut(duration: 0.12))
        XCTAssertNotEqual(SettingsMotion(reduceMotion: false).quick, .easeInOut(duration: 0.12))
    }
}

final class ChordRecorderTests: XCTestCase {
    private let altMask: UInt64 = 0x0008_0000
    private let leftAlt: UInt64 = 0x20
    private let rightAlt: UInt64 = 0x40
    private let keyT: UInt16 = 0x11

    func testLeftOptionIsSuper() {
        XCTAssertEqual(ChordRecorder.notation(keyCode: keyT, flags: altMask | leftAlt, map: .optionIsSuper), "SUPER + T")
    }

    func testRightOptionDoesNotCountWithLeftOptionMapping() {
        XCTAssertEqual(ChordRecorder.notation(keyCode: keyT, flags: altMask | rightAlt, map: .optionIsSuper), "T")
    }

    func testPlainKeyAndUnknownKey() {
        XCTAssertEqual(ChordRecorder.notation(keyCode: keyT, flags: 0, map: .optionIsSuper), "T")
        XCTAssertNil(ChordRecorder.notation(keyCode: 0x7FFF, flags: 0, map: .optionIsSuper))
    }

    func testShiftAndControlAdded() {
        let s = ChordRecorder.notation(keyCode: keyT, flags: altMask | leftAlt | 0x0002_0000 | 0x0004_0000, map: .optionIsSuper)
        XCTAssertNotNil(s)
        XCTAssertTrue(s?.contains("SUPER") == true && s?.contains("SHIFT") == true && s?.contains("CTRL") == true, s ?? "")
        XCTAssertTrue(s?.hasSuffix("+ T") == true)
    }
}

@MainActor
final class SettingsStoreOfflineTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("settingsstore-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    func testSetWritesFile() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(api: ConfigAPI(file: file))
        store.offline = true
        store.set("wm.gapsIn", .number(12), update: { $0.wm.gapsIn = 12 })
        XCTAssertEqual(store.config.wm.gapsIn, 12)
        XCTAssertEqual(ConfigLoader.loadUserOrDefault(url: file).config.wm.gapsIn, 12)
        XCTAssertNil(store.message)
    }

    func testRejectedValueSetsMessageAndRollsBack() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(api: ConfigAPI(file: file))
        store.offline = true
        store.set("general.mode", .string("bogus"), update: { _ in })
        XCTAssertNotNil(store.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.config.general.mode, .full)
    }
}
