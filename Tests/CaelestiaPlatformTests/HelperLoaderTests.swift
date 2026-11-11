@testable import CaelestiaPlatform
import XCTest

final class HelperLoaderTests: XCTestCase {
    let req = #"identifier "com.skyrose.mac" and certificate root = H"9c4908c49fe01b8646022ef0608e8efd495776db""#

    func testScriptRunsOnlyTheVerifiedRootCopy() {
        let s = HelperLoader.script(app: URL(fileURLWithPath: "/Users/me/Applications/Sky Rose's.app"), uid: 501, requirement: req, installDaemon: false)
        // The path is single-quoted, with the apostrophe escaped.
        XCTAssertTrue(s.contains(#"APP='/Users/me/Applications/Sky Rose'\''s.app'"#))
        let lines = s.components(separatedBy: "\n")
        let stage = lines.firstIndex { $0.contains("mktemp -d /private/var/tmp/") }!
        let copy = lines.firstIndex { $0.hasPrefix("ditto ") }!
        let verify = lines.firstIndex { $0.hasPrefix("codesign --verify --strict -R=") }!
        let load = lines.firstIndex { $0.contains("skyrose-sa-loader") }!
        XCTAssertTrue(stage < copy && copy < verify && verify < load, "copy, then verify the copy, then run it")
        XCTAssertTrue(lines[load].contains("\"$SA/skyrose-sa-loader\""), "never the user's own copy")
        XCTAssertFalse(lines[load].contains("$APP"))
        XCTAssertTrue(lines[load].contains("SUDO_UID=501"))
        XCTAssertFalse(s.contains("install-sa-daemon"), "the boot daemon is opt-in")
        XCTAssertTrue(s.contains("trap 'rm -rf \"$STAGE\"' EXIT"))
    }

    func testDaemonInstallerAlsoRunsFromTheStage() {
        let s = HelperLoader.script(app: URL(fileURLWithPath: "/Applications/SkyRose.app"), uid: 501, requirement: req, installDaemon: true)
        let last = s.components(separatedBy: "\n").last!
        XCTAssertEqual(last, #"SUDO_UID=501 /bin/sh "$SA/install-sa-daemon.sh""#)
    }

    func testAppleScriptEscaping() {
        let a = HelperLoader.appleScript(#"echo "a\b""#, prompt: "Hi")
        XCTAssertEqual(a, #"do shell script "echo \"a\\b\"" with prompt "Hi" with administrator privileges"#)
    }

    func testHumanReason() {
        XCTAssertEqual(HelperLoader.humanReason("ditto: ok\nthe app signature does not match the running SkyRose"),
                       "the app signature does not match the running SkyRose")
        XCTAssertEqual(HelperLoader.humanReason(""), "The helper did not load.")
    }

    /// The script is valid sh (parsed, not run).
    func testScriptParses() throws {
        let s = HelperLoader.script(app: URL(fileURLWithPath: "/Applications/SkyRose.app"), uid: 501, requirement: req, installDaemon: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-n", "-c", s]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }
}
