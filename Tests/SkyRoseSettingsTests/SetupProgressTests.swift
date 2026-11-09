import Foundation
import XCTest

@testable import SkyRoseSettingsKit

final class SetupProgressTests: XCTestCase {
    func testParsesEveryProtocolLine() {
        XCTAssertEqual(SetupEvent.parse("::stage 3 9 settings Restoring macOS settings\n"),
                       .stage(index: 3, total: 9, id: "settings", label: "Restoring macOS settings"))
        XCTAssertEqual(SetupEvent.parse("::done Dock auto-hide back to off"), .item(SetupItem(kind: .done, text: "Dock auto-hide back to off")))
        XCTAssertEqual(SetupEvent.parse("::skip no login item"), .item(SetupItem(kind: .skip, text: "no login item")))
        XCTAssertEqual(SetupEvent.parse("::left run sudo pmset disablesleep 0"), .item(SetupItem(kind: .left, text: "run sudo pmset disablesleep 0")))
        XCTAssertEqual(SetupEvent.parse("::fail hidutil refused"), .item(SetupItem(kind: .fail, text: "hidutil refused")))
        XCTAssertEqual(SetupEvent.parse("::dry trash /Users/x/Applications/SkyRose.app"), .item(SetupItem(kind: .dry, text: "trash /Users/x/Applications/SkyRose.app")))
        XCTAssertEqual(SetupEvent.parse("::sip"), .sip)
        XCTAssertEqual(SetupEvent.parse("::finished"), .finished)
        XCTAssertEqual(SetupEvent.parse("plain output"), .other("plain output"))
        XCTAssertEqual(SetupEvent.parse("::stage x 9 id"), .other("::stage x 9 id"), "a malformed stage is not a stage")
    }

    func testProgressComesOnlyFromTheEngineAndOnlyGoesUp() {
        var p = SetupProgressState()
        XCTAssertEqual(p.fraction, 0)
        var last = 0.0
        for i in 1...9 {
            p.apply(.stage(index: i, total: 9, id: "s\(i)", label: "Stage \(i)"))
            XCTAssertGreaterThanOrEqual(p.fraction, last)
            last = p.fraction
            for _ in 0..<8 {
                p.apply(.item(SetupItem(kind: .done, text: "x")))
                XCTAssertGreaterThanOrEqual(p.fraction, last)
                XCTAssertLessThan(p.fraction, Double(i) / 9, "a stage never fills past its own share")
                last = p.fraction
            }
        }
        XCTAssertLessThan(p.fraction, 1, "100 % only on ::finished")
        p.apply(.finished)
        XCTAssertEqual(p.fraction, 1)
    }

    func testEngineStagesMapOntoTheFiveWindowStages() {
        let steps = SetupFlow.uninstall
        XCTAssertEqual(steps.map(\.id), ["confirm", "restore", "profile", "apps", "report"])
        var p = SetupProgressState()
        XCTAssertEqual(SetupFlow.activeIndex(steps, progress: p, started: false), 0)
        XCTAssertEqual(SetupFlow.activeIndex(steps, progress: p, started: true), 1)
        let expected = ["windows": 1, "cursor": 1, "settings": 1, "sleep": 1, "login": 1, "profile": 2, "sip": 3, "apps": 3, "data": 3]
        for (i, id) in ["windows", "cursor", "settings", "sleep", "login", "profile", "sip", "apps", "data"].enumerated() {
            p.apply(.stage(index: i + 1, total: 9, id: id, label: id))
            XCTAssertEqual(SetupFlow.activeIndex(steps, progress: p, started: true), expected[id], id)
        }
        p.apply(.finished)
        XCTAssertEqual(SetupFlow.activeIndex(steps, progress: p, started: true), 4)
        XCTAssertEqual(SetupFlow.state(of: 4, active: 4, failed: false, finished: true), .done)
        XCTAssertEqual(SetupFlow.state(of: 2, active: 3, failed: true, finished: true), .done)
        XCTAssertEqual(SetupFlow.state(of: 3, active: 3, failed: true, finished: true), .failed)
        XCTAssertEqual(SetupFlow.state(of: 4, active: 3, failed: false, finished: false), .pending)
    }

    func testEveryEngineStageOfTheScriptHasAWindowStage() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: repo.appendingPathComponent("scripts/uninstall.sh"), encoding: .utf8)
        let ids = script.split(separator: "\n").compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("stage "), !t.hasPrefix("stage()") else { return nil }
            return t.split(separator: " ").dropFirst().first.map(String.init)
        }
        XCTAssertEqual(ids.count, 9)
        let mapped = SetupFlow.uninstall.reduce(into: Set<String>()) { $0.formUnion($1.engineStages) }
        for id in ids { XCTAssertTrue(mapped.contains(id), "\(id) is not shown in the uninstaller window") }
    }

    @MainActor
    func testRunnerStreamsLinesAsTheyArriveAndReportsTheEnd() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("setup-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = dir.appendingPathComponent("engine.sh")
        try """
        #!/bin/sh
        [ "$1" = --progress ] || exit 9
        echo "::stage 1 2 windows Stopping the window manager"
        echo "::done windows back"
        sleep 0.3
        echo "::stage 2 2 apps Moving the apps"
        echo "::left one thing for you"
        echo "::sip"
        printf '::finished'
        """.write(to: engine, atomically: true, encoding: .utf8)
        let runner = ScriptRunner()
        var seen: [SetupEvent] = []
        runner.onEvent = { seen.append($0) }
        runner.start(script: engine, arguments: [])
        XCTAssertTrue(runner.isRunning)
        var midway: Double?
        let deadline = Date().addingTimeInterval(5)
        while runner.isRunning, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            if midway == nil, runner.progress.stages.count == 1, !runner.progress.items.isEmpty { midway = runner.progress.fraction }
        }
        XCTAssertNotNil(midway, "the first stage showed before the script ended")
        XCTAssertGreaterThan(midway ?? 1, 0)
        XCTAssertLessThan(midway ?? 1, 0.5)
        XCTAssertEqual(runner.phase, .ended(exitCode: 0))
        XCTAssertFalse(runner.stoppedEarly)
        XCTAssertTrue(runner.progress.finished, "a last line without a newline still counts")
        XCTAssertTrue(runner.progress.sipReminder)
        XCTAssertEqual(runner.progress.items(.left).map(\.text), ["one thing for you"])
        XCTAssertEqual(seen.last, .finished)
    }

    @MainActor
    func testRunnerReportsAnEarlyExitWithItsError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("setup-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = dir.appendingPathComponent("engine.sh")
        try "echo '::stage 1 9 windows x'\necho 'refusing: real HOME' >&2\nexit 4\n".write(to: engine, atomically: true, encoding: .utf8)
        let runner = ScriptRunner()
        runner.start(script: engine, arguments: [])
        let deadline = Date().addingTimeInterval(5)
        while runner.isRunning || runner.errorOutput.isEmpty, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(runner.phase, .ended(exitCode: 4))
        XCTAssertTrue(runner.stoppedEarly)
        XCTAssertTrue(runner.errorOutput.contains("refusing"))
        XCTAssertLessThan(runner.progress.fraction, 1)
    }

    @MainActor
    func testRunnerAcknowledgesTheSIPReminderOnStdin() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("setup-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = dir.appendingPathComponent("engine.sh")
        try """
        #!/bin/sh
        echo "::sip"
        read -r line || line=EOF
        echo "::done $line"
        echo "::finished"
        """.write(to: engine, atomically: true, encoding: .utf8)
        let runner = ScriptRunner()
        runner.start(script: engine, arguments: [])
        runner.acknowledgeSIP()
        let deadline = Date().addingTimeInterval(5)
        while runner.isRunning, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(runner.phase, .ended(exitCode: 0))
        XCTAssertEqual(runner.progress.items(.done).map(\.text), ["ack"])
        XCTAssertTrue(runner.progress.sipReminder)
        XCTAssertTrue(runner.progress.finished)
    }

    func testUninstallerLaunchOptions() {
        let o = SettingsLaunchOptions.parse(["--uninstaller", "--dry-run"])
        XCTAssertTrue(o.uninstaller)
        XCTAssertTrue(o.dryRun)
        XCTAssertFalse(SettingsLaunchOptions.parse([]).uninstaller)
        XCTAssertEqual(SettingsPage(rawValue: "backup"), .backup)
    }

    func testFindsTheScriptInsideTheAppNextToSettings() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("setup-locate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let scripts = dir.appendingPathComponent("SkyRose.app/Contents/Resources/scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: scripts.appendingPathComponent("uninstall.sh"), atomically: true, encoding: .utf8)
        let found = SetupLocator.uninstallScript(bundle: dir.appendingPathComponent("SkyRose Settings.app"), executable: nil)
        XCTAssertEqual(found?.standardizedFileURL, scripts.appendingPathComponent("uninstall.sh").standardizedFileURL)
    }
}
