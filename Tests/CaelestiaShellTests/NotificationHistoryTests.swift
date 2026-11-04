import CaelestiaCore
import XCTest
@testable import CaelestiaShell

/// The persisted notification history and its hookup in the shell controller.
@MainActor
final class NotificationHistoryTests: XCTestCase {
    var dir: URL!
    var url: URL { dir.appendingPathComponent("sub/notifications.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("notif-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Whole-second dates (the file stores ISO 8601 without fractions).
    func note(_ summary: String, age: TimeInterval) -> ShellNotification {
        ShellNotification(appName: "app", appBundleID: "com.example", summary: summary, body: "body \(summary)", icon: "bell",
                          date: Date(timeIntervalSince1970: 1_700_000_000 - age), actions: ["open"], urgency: "critical")
    }

    func testSaveLoadRoundTrip() {
        let file = NotificationHistoryFile(url: url)
        let items = [note("new", age: 0), note("old", age: 60)]
        XCTAssertTrue(file.save(items), "creates the missing directory")
        XCTAssertEqual(file.load(), items)
    }

    func testLoadTruncatesToLimitKeepingNewest() {
        let file = NotificationHistoryFile(url: url)
        let items = (0..<10).map { note("n\($0)", age: Double($0) * 10) }
        file.save(items)
        let loaded = file.load(limit: 3)
        XCTAssertEqual(loaded.map(\.summary), ["n0", "n1", "n2"])
    }

    func testLoadSortsNewestFirst() {
        let file = NotificationHistoryFile(url: url)
        file.save([note("old", age: 100), note("new", age: 0)])
        XCTAssertEqual(file.load().map(\.summary), ["new", "old"])
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertEqual(NotificationHistoryFile(url: url).load(), [])
    }

    func testCorruptFileLoadsEmpty() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(NotificationHistoryFile(url: url).load(), [])
        try Data("{\"version\":1,\"notifications\":[{\"oops\":1}]}".utf8).write(to: url)
        XCTAssertEqual(NotificationHistoryFile(url: url).load(), [])
    }

    func testSaveToUnwritableLocationReturnsFalse() throws {
        // A regular file where the directory should be.
        let blocker = dir.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        XCTAssertFalse(NotificationHistoryFile(url: blocker.appendingPathComponent("n.json")).save([note("x", age: 0)]))
    }

    // MARK: ShellController

    func controller() -> ShellController {
        let state = ShellState(
            scheme: ShellTheme.gabby.scheme, config: Config(), animations: AnimationTable.gabbySpringy,
            displays: [], converter: CoordinateConverter(primaryHeight: 956)
        )
        return ShellController(state: state, host: nil)
    }

    func testControllerPersistsAddDismissAndClear() {
        let file = NotificationHistoryFile(url: url)
        let c = controller()
        c.useNotificationHistory(file)
        XCTAssertTrue(c.notificationStore.items.isEmpty)

        let first = c.notify(title: "one")
        let second = c.notify(title: "two")
        XCTAssertEqual(Set(file.load().map(\.id)), [first, second])
        XCTAssertEqual(c.state.notifications.count, 2)

        c.dismissNotification(first)
        XCTAssertEqual(file.load().map(\.id), [second])
        XCTAssertEqual(c.state.notifications.map(\.id), [second])

        c.clearNotifications()
        XCTAssertEqual(file.load(), [])
        XCTAssertTrue(c.state.notifications.isEmpty)
    }

    func testControllerLoadsExistingHistory() {
        let file = NotificationHistoryFile(url: url)
        let saved = [note("kept", age: 5)]
        file.save(saved)
        let c = controller()
        c.useNotificationHistory(file)
        XCTAssertEqual(c.notificationStore.items, saved)
        XCTAssertEqual(c.state.notifications, saved)
        // A second controller (a restart) sees what the first persisted.
        _ = c.notify(title: "later")
        let c2 = controller()
        c2.useNotificationHistory(file)
        XCTAssertEqual(c2.notificationStore.items.count, 2)
    }

    func testControllerWithoutHistoryFileStaysInMemory() {
        let c = controller()
        _ = c.notify(title: "x")
        XCTAssertEqual(c.notificationStore.count, 1)
        XCTAssertNil(c.notificationHistory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
