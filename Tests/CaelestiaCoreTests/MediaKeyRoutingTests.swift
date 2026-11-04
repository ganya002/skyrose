import XCTest

@testable import CaelestiaCore

/// Volume / brightness / mute keys: decoding, and the routing truth table that decides what is
/// swallowed and which OSD shows.
final class MediaKeyRoutingTests: XCTestCase {
    private let bools = [false, true]

    // MARK: key types

    func testNXKeyTypeMapping() {
        XCTAssertEqual(MediaKeyCommand(nxKeyType: 0), .volumeUp)
        XCTAssertEqual(MediaKeyCommand(nxKeyType: 1), .volumeDown)
        XCTAssertEqual(MediaKeyCommand(nxKeyType: 7), .mute)
        XCTAssertEqual(MediaKeyCommand(nxKeyType: 2), .brightnessUp)
        XCTAssertEqual(MediaKeyCommand(nxKeyType: 3), .brightnessDown)
        for other in [4, 5, 6, 8, 9, 10, 16, 17, 18, 19, 20, 21, 22, 23, 100, -1] {
            XCTAssertNil(MediaKeyCommand(nxKeyType: other), "\(other)")
        }
    }

    func testVolumeAndBrightnessClassification() {
        for c in MediaKeyCommand.allCases {
            XCTAssertNotEqual(c.isVolume, c.isBrightness, "\(c)")
        }
        XCTAssertTrue(MediaKeyCommand.mute.isVolume)
        XCTAssertTrue(MediaKeyCommand.brightnessUp.isBrightness)
        XCTAssertTrue(MediaKeyCommand.brightnessDown.isBrightness)
    }

    // MARK: event decoding

    func testDataDecoding() {
        // keyType << 16 | state << 8 | repeat
        let down = MediaKeyEvent(data1: (0 << 16) | (0x0A << 8))
        XCTAssertEqual(down.nxKeyType, 0)
        XCTAssertTrue(down.isDown)
        XCTAssertFalse(down.isRepeat)
        XCTAssertEqual(down.command, .volumeUp)

        let up = MediaKeyEvent(data1: (0 << 16) | (0x0B << 8))
        XCTAssertFalse(up.isDown)

        let repeating = MediaKeyEvent(data1: (3 << 16) | (0x0A << 8) | 1)
        XCTAssertEqual(repeating.nxKeyType, 3)
        XCTAssertTrue(repeating.isDown)
        XCTAssertTrue(repeating.isRepeat)
        XCTAssertEqual(repeating.command, .brightnessDown)

        let mute = MediaKeyEvent(data1: (7 << 16) | (0x0A << 8))
        XCTAssertEqual(mute.command, .mute)

        let play = MediaKeyEvent(data1: (16 << 16) | (0x0A << 8))
        XCTAssertEqual(play.nxKeyType, 16)
        XCTAssertNil(play.command)
    }

    func testFineSteps() {
        let option: UInt64 = 0x0008_0000, shift: UInt64 = 0x0002_0000
        func fine(_ flags: UInt64) -> Bool { MediaKeyEvent(nxKeyType: 0, isDown: true, flags: flags).isFine }
        XCTAssertFalse(fine(0))
        XCTAssertFalse(fine(option))
        XCTAssertFalse(fine(shift))
        XCTAssertTrue(fine(option | shift))
        XCTAssertTrue(fine(option | shift | 0x0010_0000), "other modifiers do not matter")
        XCTAssertFalse(fine(0x0010_0000 | shift))
    }

    // MARK: routing

    func testNonMediaKeyPassesThrough() {
        for intercept in bools {
            for v in bools {
                for b in bools {
                    XCTAssertEqual(MediaKeyRouting.route(nil, intercept: intercept, volumeControllable: v, brightnessControllable: b), .passThrough)
                }
            }
        }
    }

    func testRoutingTruthTable() {
        for command in MediaKeyCommand.allCases {
            for intercept in bools {
                for v in bools {
                    for b in bools {
                        let r = MediaKeyRouting.route(command, intercept: intercept, volumeControllable: v, brightnessControllable: b)
                        let ctx = "\(command) intercept \(intercept) volume \(v) brightness \(b)"
                        if command.isVolume {
                            if intercept && v {
                                XCTAssertEqual(r, MediaKeyRoute(swallow: true, command: command, osd: .volume), ctx)
                            } else if !intercept && v {
                                XCTAssertEqual(r, MediaKeyRoute(swallow: false, command: nil, osd: .volume), ctx)
                            } else {
                                XCTAssertEqual(r, .passThrough, ctx)
                            }
                        } else if b {
                            XCTAssertEqual(r, MediaKeyRoute(swallow: intercept, command: intercept ? command : nil, osd: .brightness), ctx)
                        } else {
                            XCTAssertEqual(r, .passThrough, ctx)
                        }
                    }
                }
            }
        }
    }

    func testABrightnessKeyNeverShowsTheVolumeOSD() {
        for command in [MediaKeyCommand.brightnessUp, .brightnessDown] {
            for intercept in bools {
                for v in bools {
                    for b in bools {
                        let r = MediaKeyRouting.route(command, intercept: intercept, volumeControllable: v, brightnessControllable: b)
                        XCTAssertNotEqual(r.osd, .volume, "\(command) \(intercept) \(v) \(b)")
                    }
                }
            }
        }
    }

    func testAVolumeKeyNeverShowsTheBrightnessOSD() {
        for command in [MediaKeyCommand.volumeUp, .volumeDown, .mute] {
            for intercept in bools {
                for v in bools {
                    for b in bools {
                        XCTAssertNotEqual(MediaKeyRouting.route(command, intercept: intercept, volumeControllable: v, brightnessControllable: b).osd, .brightness)
                    }
                }
            }
        }
    }

    func testUncontrollableBrightnessPassesThroughSilently() {
        for command in [MediaKeyCommand.brightnessUp, .brightnessDown] {
            for intercept in bools {
                for v in bools {
                    let r = MediaKeyRouting.route(command, intercept: intercept, volumeControllable: v, brightnessControllable: false)
                    XCTAssertFalse(r.swallow)
                    XCTAssertNil(r.osd)
                    XCTAssertNil(r.command)
                }
            }
        }
    }

    func testVolumeIsSwallowedOnlyWhenInterceptingAndControllable() {
        for command in [MediaKeyCommand.volumeUp, .volumeDown, .mute] {
            for intercept in bools {
                for v in bools {
                    let r = MediaKeyRouting.route(command, intercept: intercept, volumeControllable: v, brightnessControllable: true)
                    XCTAssertEqual(r.swallow, intercept && v, "\(command) \(intercept) \(v)")
                    if r.swallow { XCTAssertEqual(r.command, command) } else { XCTAssertNil(r.command) }
                }
            }
        }
    }
}
