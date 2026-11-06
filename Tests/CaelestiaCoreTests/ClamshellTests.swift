import XCTest
@testable import CaelestiaCore

final class ClamshellTests: XCTestCase {
    func f(lid: Bool = true, closed: Bool = false, sleeps: Bool? = nil, ac: Bool, ext: Int, off: Bool = false) -> ClamshellFacts {
        ClamshellFacts(hasLid: lid, lidClosed: closed, closingCausesSleep: sleeps, onAC: ac, externalDisplays: ext, sleepDisabled: off)
    }

    func testNativeModes() {
        XCTAssertEqual(Clamshell.mode(f(lid: false, ac: true, ext: 1)), .noLid)
        XCTAssertEqual(Clamshell.mode(f(ac: true, ext: 1)), .openWillStayAwake)
        XCTAssertEqual(Clamshell.mode(f(ac: false, ext: 1)), .openWillSleep, "battery sleeps natively")
        XCTAssertEqual(Clamshell.mode(f(ac: true, ext: 0)), .openWillSleep, "no display sleeps natively")
        XCTAssertEqual(Clamshell.mode(f(closed: true, ac: true, ext: 1)), .closedRunning)
        XCTAssertEqual(Clamshell.via(f(ac: true, ext: 1)), .native)
        XCTAssertNil(Clamshell.via(f(ac: false, ext: 0)))
    }

    func testSleepDisabledWorksOnBatteryWithOnlyTheBuiltIn() {
        // The kernel keeps AppleClamshellCausesSleep = Yes with SleepDisabled 1 (seen live).
        let open = f(sleeps: true, ac: false, ext: 0, off: true)
        XCTAssertEqual(Clamshell.mode(open), .openWillStayAwake)
        XCTAssertEqual(Clamshell.via(open), .sleepDisabled)
        let closed = f(closed: true, sleeps: true, ac: false, ext: 0, off: true)
        XCTAssertEqual(Clamshell.mode(closed), .closedRunning)
        XCTAssertEqual(Clamshell.summary(closed), "Lid closed · running on battery")
        XCTAssertEqual(Clamshell.via(closed), .sleepDisabled)
    }

    func testTheKernelFlagWinsForNative() {
        XCTAssertEqual(Clamshell.mode(f(sleeps: true, ac: true, ext: 1)), .openWillSleep)
        XCTAssertEqual(Clamshell.mode(f(sleeps: false, ac: false, ext: 0)), .openWillStayAwake)
    }

    func testSummaries() {
        let on = LidSleepStatus(clamshellOn: true, helper: .ready)
        XCTAssertEqual(Clamshell.summary(f(ac: false, ext: 0)), "Closing the lid sleeps the Mac · turn on Clamshell to keep it running")
        XCTAssertEqual(Clamshell.summary(f(ac: false, ext: 0, off: true), lid: on), "Closing the lid keeps the Mac running · Clamshell on")
        XCTAssertEqual(Clamshell.summary(f(ac: false, ext: 0, off: true), lid: LidSleepStatus(keepAwakeOn: true)), "Closing the lid keeps the Mac running · Keep awake on")
        XCTAssertEqual(Clamshell.summary(f(ac: false, ext: 0, off: true)), "Closing the lid keeps the Mac running · sleep turned off outside SkyRose")
        XCTAssertEqual(Clamshell.summary(f(ac: false, ext: 0), lid: LidSleepStatus(clamshellOn: true, helper: .missing)),
                       "Closing the lid sleeps the Mac · Clamshell needs its helper (skyrose clamshell helper)")
        XCTAssertEqual(Clamshell.summary(f(ac: true, ext: 1)), "Closing the lid keeps the Mac running")
        XCTAssertEqual(Clamshell.summary(f(closed: true, ac: true, ext: 1)), "Lid closed · running on the external display")
        XCTAssertEqual(Clamshell.summary(f(closed: true, ac: true, ext: 0, off: true)), "Lid closed · running")
        XCTAssertEqual(Clamshell.summary(f(lid: false, ac: true, ext: 1)), "No lid")
        XCTAssertFalse(Clamshell.summary(f(ac: false, ext: 0)).contains("external display"), "no longer called impossible")
    }

    func testWantsSleepDisabled() {
        XCTAssertFalse(LidSleepStatus().wantsSleepDisabled)
        XCTAssertTrue(LidSleepStatus(clamshellOn: true).wantsSleepDisabled)
        XCTAssertTrue(LidSleepStatus(keepAwakeOn: true).wantsSleepDisabled)
    }

    func testPmsetParsingAndSudoArguments() {
        XCTAssertTrue(LidSleep.parseSleepDisabled(" SleepDisabled\t\t1\n Sleep On Power Button 1"))
        XCTAssertFalse(LidSleep.parseSleepDisabled(" SleepDisabled\t\t0\n"))
        XCTAssertFalse(LidSleep.parseSleepDisabled(" sleep 1\n"))
        XCTAssertEqual(LidSleep.sudoArguments(disabled: true), ["-n", "/usr/bin/pmset", "disablesleep", "1"])
        XCTAssertEqual(LidSleep.sudoArguments(disabled: false), ["-n", "/usr/bin/pmset", "disablesleep", "0"])
    }

    func testHelperRuleIsTheTwoCommandAllowlist() {
        XCTAssertEqual(LidSleep.rule(user: "gabbo"), "gabbo ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1")
        let cmd = LidSleep.installCommand(user: "gabbo")
        XCTAssertTrue(cmd.hasPrefix("printf '%s\\n' 'gabbo ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1' > /tmp/skyrose-sudoers"))
        XCTAssertTrue(cmd.contains("/usr/sbin/visudo -cf /tmp/skyrose-sudoers && sudo install -o root -g wheel -m 0440 /tmp/skyrose-sudoers /etc/sudoers.d/skyrose"))
        XCTAssertTrue(LidSleep.installCommand(user: "o'neil").contains("$(id -un)"), "odd names are not quoted into the command")
    }

    func testDefaultConfigIsOff() {
        XCTAssertFalse(Config().clamshell.keepAwake)
    }
}
