import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaPlatform

/// Off-screen parking and the crash journal (spec 4.1, 4.4, 10.10, Riko R6).
final class ParkingTests: XCTestCase {
    let air = CGRect(x: 0, y: 0, width: 1470, height: 956)
    let size = CGSize(width: 700, height: 500)

    func testParksInBottomRightLeavingOnePoint() {
        let r = ParkingPlanner.parkedFrame(size: size, on: air, others: [])
        XCTAssertEqual(r.origin, CGPoint(x: 1469, y: 955))
        XCTAssertEqual(r.intersection(air).size, CGSize(width: 1, height: 1))
    }

    func testAvoidsDisplayToTheRight() {
        let right = CGRect(x: 1470, y: 0, width: 2560, height: 1440)
        let r = ParkingPlanner.parkedFrame(size: size, on: air, others: [right])
        XCTAssertFalse(r.insetBy(dx: 1, dy: 1).intersects(right))
        XCTAssertEqual(r.origin, CGPoint(x: 1 - size.width, y: 955), "bottom-left corner")
    }

    func testAvoidsDisplaysRightAndBelow() {
        let right = CGRect(x: 1470, y: 0, width: 2560, height: 1440)
        let below = CGRect(x: -800, y: 956, width: 4000, height: 1000)
        let r = ParkingPlanner.parkedFrame(size: size, on: air, others: [right, below])
        XCTAssertFalse(r.insetBy(dx: 1, dy: 1).intersects(right))
        XCTAssertFalse(r.insetBy(dx: 1, dy: 1).intersects(below))
    }

    func testOffScreenDetection() {
        let parked = ParkingPlanner.parkedFrame(size: size, on: air, others: [])
        XCTAssertTrue(ParkingPlanner.isOffScreen(parked, displays: [air]))
        XCTAssertFalse(ParkingPlanner.isOffScreen(CGRect(x: 100, y: 100, width: 300, height: 300), displays: [air]))
    }

    func testRestoreKeepsAVisibleRememberedFrame() {
        let displays = [DisplayInfo(id: "air", frame: air, menuBarHeight: 33, isPrimary: true)]
        let frame = CGRect(x: 21, y: 54, width: 708, height: 881)
        XCTAssertEqual(ParkingPlanner.restoreFrame(remembered: frame, preferredDisplay: "air", displays: displays), frame)
    }

    func testRestoreCentresAFrameFromAnUnpluggedDisplay() {
        let displays = [DisplayInfo(id: "air", frame: air, menuBarHeight: 33, isPrimary: true)]
        let lost = CGRect(x: 3000, y: 100, width: 2000, height: 600)
        let r = ParkingPlanner.restoreFrame(remembered: lost, preferredDisplay: "ext", displays: displays)
        let usable = displays[0].usableArea(reserved: .zero)
        XCTAssertTrue(usable.contains(r))
        XCTAssertEqual(r.width, 1470, "shrunk to fit")
        XCTAssertEqual(r.height, 600)
    }

    // MARK: Journal

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("parking-\(UUID().uuidString).json")
    }

    func record(_ id: UInt32, frame: CGRect = CGRect(x: 1, y: 2, width: 3, height: 4)) -> ParkedWindowRecord {
        ParkedWindowRecord(windowID: id, pid: 42, bundleID: "net.kovidgoyal.kitty", title: "~", restoreFrame: frame, displayID: "air")
    }

    func testJournalSurvivesARestart() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try ParkingJournal(url: url).upsert(record(7))
        try ParkingJournal(url: url).upsert(record(8))
        let reopened = ParkingJournal(url: url)
        XCTAssertEqual(reopened.records().map(\.windowID).sorted(), [7, 8])
        try reopened.remove(7)
        XCTAssertEqual(ParkingJournal(url: url).records().map(\.windowID), [8])
    }

    func testReparkingKeepsTheFirstRestoreFrame() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let j = ParkingJournal(url: url)
        try j.upsert(record(7, frame: CGRect(x: 21, y: 21, width: 100, height: 100)))
        try j.upsert(record(7, frame: CGRect(x: 1469, y: 955, width: 100, height: 100)))
        XCTAssertEqual(j.record(for: 7)?.restoreFrame, CGRect(x: 21, y: 21, width: 100, height: 100))
    }

    func testCorruptJournalIsMovedAsideNotDeleted() throws {
        let url = tempURL()
        try Data("not json".utf8).write(to: url)
        let dir = url.deletingLastPathComponent()
        defer {
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for f in leftovers where f.hasPrefix(url.lastPathComponent) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        }
        XCTAssertTrue(ParkingJournal(url: url).records().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix(url.lastPathComponent + ".corrupt-") })
    }
}
