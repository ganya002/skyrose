import XCTest
import CaelestiaCore
@testable import CaelestiaWMKit

@MainActor
final class AppLauncherPlanTests: XCTestCase {
    private func plan(_ kind: ActionKind, _ apps: AppsConfig = AppsConfig(), args: [String: ArgValue] = [:]) -> (executable: String, arguments: [String])? {
        AppLauncher.plan(for: Action(kind, args: args), apps: apps)
    }

    func testTerminalChoices() {
        var apps = AppsConfig()
        apps.terminal = "kitty"
        var p = plan(.appTerminal, apps)
        XCTAssertEqual(p?.executable, "/usr/bin/open")
        XCTAssertEqual(p?.arguments, ["-n", "-b", "net.kovidgoyal.kitty"])
        apps.terminal = "rex"
        XCTAssertEqual(plan(.appTerminal, apps)?.arguments, ["-b", "com.superlogical.rex"])
        apps.terminal = "com.apple.Terminal"
        XCTAssertEqual(plan(.appTerminal, apps)?.arguments, ["-b", "com.apple.Terminal"])
        apps.terminal = "wezterm start"
        p = plan(.appTerminal, apps)
        XCTAssertEqual(p?.executable, "/bin/sh")
        XCTAssertEqual(p?.arguments, ["-c", "wezterm start"])
    }

    func testBrowserEditorFiles() {
        var apps = AppsConfig()
        apps.browser = "com.apple.Safari"
        XCTAssertEqual(plan(.appBrowser, apps)?.arguments, ["-b", "com.apple.Safari"])
        apps.editor = "Visual Studio Code"
        XCTAssertEqual(plan(.appEditor, apps)?.arguments, ["-a", "Visual Studio Code"])
        apps.fileManager = "https://example.com"
        XCTAssertEqual(plan(.appFiles, apps)?.arguments, ["https://example.com"])
        apps.audioSettings = "com.apple.systempreferences"
        XCTAssertEqual(plan(.appAudioSettings, apps)?.executable, "/usr/bin/open")
    }

    func testExec() {
        let p = plan(.exec, args: ["cmd": .string("echo hi")])
        XCTAssertEqual(p?.executable, "/bin/sh")
        XCTAssertEqual(p?.arguments, ["-c", "echo hi"])
        XCTAssertNil(plan(.exec))
        XCTAssertNil(plan(.exec, args: ["cmd": .string("")]))
    }

    func testOtherActionsNotHandled() {
        XCTAssertNil(plan(.wmPanic))
    }
}

@MainActor
final class AppLauncherFallbackTests: XCTestCase {
    func testMissingTerminalFallsBackToMacOSTerminal() {
        var apps = AppsConfig()
        apps.terminal = "kitty"
        let missing = AppLauncher.plan(for: Action(.appTerminal), apps: apps, installed: { _ in false })
        XCTAssertEqual(missing?.arguments, ["-b", "com.apple.Terminal"])
        let present = AppLauncher.plan(for: Action(.appTerminal), apps: apps, installed: { _ in true })
        XCTAssertEqual(present?.arguments, ["-n", "-b", "net.kovidgoyal.kitty"])
        apps.terminal = "wezterm start"
        XCTAssertEqual(AppLauncher.plan(for: Action(.appTerminal), apps: apps, installed: { _ in false })?.executable, "/bin/sh",
                       "commands are run as written")
    }
}
