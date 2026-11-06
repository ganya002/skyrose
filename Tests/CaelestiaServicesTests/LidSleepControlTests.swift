import XCTest
@testable import CaelestiaCore
@testable import CaelestiaServices

/// A fake `pmset` / `sudo -n`.
final class FakeSleepSwitch: SleepSwitch, @unchecked Sendable {
    var value = false
    var helperInstalled = true
    var sets: [Bool] = []
    func read() -> Bool { value }
    func set(disabled: Bool) -> String? {
        sets.append(disabled)
        guard helperInstalled else { return "sudo: a password is required" }
        value = disabled
        return nil
    }
}

@MainActor
final class LidSleepControlTests: XCTestCase {
    var marker: URL!

    override func setUp() {
        marker = FileManager.default.temporaryDirectory.appendingPathComponent("lidsleep-\(UUID().uuidString)/marker")
    }

    func testClamshellAndKeepAwakeHoldSleepDisabledUntilBothAreOff() {
        let sw = FakeSleepSwitch()
        let c = LidSleepControl(sleepSwitch: sw, marker: marker)
        c.start()
        XCTAssertEqual(c.status.helper, .ready)
        sw.sets.removeAll()
        c.setClamshell(true)
        XCTAssertTrue(sw.value); XCTAssertTrue(c.ownsSleepDisabled)
        c.setKeepAwake(true)
        XCTAssertEqual(sw.sets, [true], "already 1: no second sudo call")
        c.setClamshell(false)
        XCTAssertTrue(sw.value, "keep-awake still on")
        c.setKeepAwake(false)
        XCTAssertFalse(sw.value); XCTAssertFalse(c.ownsSleepDisabled)
        XCTAssertEqual(sw.sets, [true, false])
    }

    func testMissingHelperNeverRetriesInteractively() {
        let sw = FakeSleepSwitch()
        sw.helperInstalled = false
        let c = LidSleepControl(sleepSwitch: sw, marker: marker)
        c.start()
        XCTAssertEqual(c.status.helper, .missing)
        c.setClamshell(true)
        XCTAssertFalse(sw.value)
        XCTAssertEqual(c.status.helper, .missing)
        XCTAssertEqual(c.lastError, "sudo: a password is required")
        XCTAssertFalse(c.ownsSleepDisabled)
        XCTAssertTrue(c.installCommand.contains("/etc/sudoers.d/skyrose"))
        // Installed later: the next status turns it ready and the next switch works.
        sw.helperInstalled = true
        c.refresh()
        XCTAssertEqual(c.status.helper, .ready)
        c.setClamshell(true)
        XCTAssertTrue(sw.value)
    }

    func testStartLeavesSomeoneElsesValueButRestoresAStaleOwnOne() {
        let other = FakeSleepSwitch(); other.value = true
        LidSleepControl(sleepSwitch: other, marker: marker).start()
        XCTAssertTrue(other.value, "not SkyRose's: left alone")

        let stale = FakeSleepSwitch(); stale.value = true
        let c1 = LidSleepControl(sleepSwitch: stale, marker: marker)
        c1.setClamshell(true)  // takes it (already 1)
        XCTAssertTrue(c1.ownsSleepDisabled)
        // Crash: a new process starts with the marker still there.
        LidSleepControl(sleepSwitch: stale, marker: marker).start()
        XCTAssertFalse(stale.value)
    }

    func testQuitRestoresOwnPanicRestoresAny() {
        let sw = FakeSleepSwitch()
        let c = LidSleepControl(sleepSwitch: sw, marker: marker)
        c.setClamshell(true)
        c.releaseForQuit()
        XCTAssertFalse(sw.value); XCTAssertFalse(c.status.clamshellOn)

        sw.value = true  // set by another app
        let q = LidSleepControl(sleepSwitch: sw, marker: marker)
        q.releaseForQuit()
        XCTAssertTrue(sw.value, "quit does not undo another app's value")
        q.releaseForPanic()
        XCTAssertFalse(sw.value, "panic puts stock sleep back")
    }
}
