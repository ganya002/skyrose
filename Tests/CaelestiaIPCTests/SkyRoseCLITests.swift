import XCTest

@testable import CaelestiaIPC

final class SkyRoseCLITests: XCTestCase {
    private func request(_ argv: [String]) throws -> IPCRequest {
        let inv = try CLIParser.parse(argv)
        return try XCTUnwrap(inv.request, "\(argv) -> \(inv.kind)")
    }

    func testStoreVerbs() throws {
        func local(_ argv: [String]) throws -> CLILocalCommand? {
            if case .local(let c) = try CLIParser.parse(argv).kind { return c }
            return nil
        }
        let open = try request(["store"])
        XCTAssertEqual(open.knownCommand, .shellDrawersToggle)
        XCTAssertEqual(open.string("drawer"), "store")
        XCTAssertEqual(try local(["store", "install", "dev.a.b"]), .store(.install("dev.a.b")))
        XCTAssertEqual(try local(["store", "update"]), .store(.update(nil)))
        XCTAssertEqual(try local(["store", "remove", "dev.a.b"]), .store(.uninstall("dev.a.b")))
        XCTAssertEqual(try local(["store", "new", "dev.a.b", "--kind", "wallpaper"]), .store(.new(id: "dev.a.b", kind: "wallpaper")))
        XCTAssertEqual(try local(["store", "submit", "--repo", "me/addons"]), .store(.submit(nil, repo: "me/addons")))
        XCTAssertEqual(try local(["store", "pack", "dir"]), .store(.pack("dir")))
        XCTAssertThrowsError(try CLIParser.parse(["store", "install"]))
        XCTAssertThrowsError(try CLIParser.parse(["store", "new", "dev.a.b", "--kind", "widget"]))
        XCTAssertThrowsError(try CLIParser.parse(["store", "frobnicate"]))
        XCTAssertTrue(CLIParser.usage(for: "store").contains("store validate"))
    }

    func testConfigGet() throws {
        XCTAssertEqual(try request(["config", "get"]).knownCommand, .configGet)
        XCTAssertNil(try request(["config", "get"]).string("path"))
        XCTAssertEqual(try request(["config", "get", "wm.gapsIn"]).string("path"), "wm.gapsIn")
        XCTAssertThrowsError(try CLIParser.parse(["config", "get", "a", "b"]))
    }

    func testConfigSet() throws {
        let r = try request(["config", "set", "wm.gapsIn", "8"])
        XCTAssertEqual(r.knownCommand, .configSet)
        XCTAssertEqual(r.string("path"), "wm.gapsIn")
        XCTAssertEqual(r.args["value"], .number(8))
        XCTAssertEqual(try request(["config", "set", "shell.osd", "false"]).args["value"], .bool(false))
        XCTAssertEqual(try request(["config", "set", "apps.terminal", "wezterm", "start"]).args["value"], .string("wezterm start"))
        XCTAssertEqual(try request(["config", "set", "x.y", "[1, 2]"]).args["value"], .string("[1, 2]"))
        XCTAssertThrowsError(try CLIParser.parse(["config", "set"]))
        XCTAssertThrowsError(try CLIParser.parse(["config", "set", "wm.gapsIn"]))
    }

    func testConfigReset() throws {
        let r = try request(["config", "reset", "wm.gapsIn"])
        XCTAssertEqual(r.knownCommand, .configReset)
        XCTAssertEqual(r.string("path"), "wm.gapsIn")
        XCTAssertThrowsError(try CLIParser.parse(["config", "reset"]))
        XCTAssertThrowsError(try CLIParser.parse(["config", "reset", "a", "b"]))
        XCTAssertEqual(try request(["config", "reload"]).knownCommand, .configReload)
    }

    func testPermissionsRequest() throws {
        for kind in ["accessibility", "inputMonitoring", "screenRecording"] {
            let r = try request(["permissions", "request", kind])
            XCTAssertEqual(r.knownCommand, .permissionsRequest)
            XCTAssertEqual(r.string("kind"), kind)
        }
        XCTAssertThrowsError(try CLIParser.parse(["permissions", "request"]))
        XCTAssertThrowsError(try CLIParser.parse(["permissions", "request", "camera"]))
        XCTAssertEqual(try request(["permissions", "status"]).knownCommand, .permissionsStatus)
    }

    func testLocalCommands() throws {
        XCTAssertEqual(try CLIParser.parse(["migrate"]).kind, .local(.migrate))
        XCTAssertEqual(try CLIParser.parse(["settings"]).kind, .local(.openSettings(onboarding: false)))
        XCTAssertEqual(try CLIParser.parse(["onboarding"]).kind, .local(.openSettings(onboarding: true)))
        XCTAssertThrowsError(try CLIParser.parse(["migrate", "x"]))
        XCTAssertThrowsError(try CLIParser.parse(["settings", "x"]))
        XCTAssertThrowsError(try CLIParser.parse(["onboarding", "x"]))
    }

    func testDeprecatedAlias() {
        XCTAssertTrue(CLIAlias.isDeprecatedName("caelestia"))
        XCTAssertTrue(CLIAlias.isDeprecatedName("/usr/local/bin/caelestia"))
        XCTAssertFalse(CLIAlias.isDeprecatedName("skyrose"))
        XCTAssertFalse(CLIAlias.isDeprecatedName("/usr/local/bin/skyrose"))
        XCTAssertTrue(CLIAlias.deprecationNotice.contains("skyrose"))
    }

    func testConfigValueConversion() {
        XCTAssertEqual(CLIParser.configValue("true"), .bool(true))
        XCTAssertEqual(CLIParser.configValue("1.5"), .number(1.5))
        XCTAssertEqual(CLIParser.configValue("\"a b\""), .string("a b"))
        XCTAssertEqual(CLIParser.configValue("kitty"), .string("kitty"))
    }

    func testNewCommandsHaveSpecs() {
        let names: [IPCCommand] = [.configGet, .configSet, .configReset, .configReload, .permissionsStatus, .permissionsRequest, .rulesApps, .rulesSet, .rulesFocused, .keysList, .keysPause]
        for c in names {
            XCTAssertFalse(c.spec.summary.isEmpty, "\(c)")
        }
        XCTAssertEqual(IPCCommand.configSet.spec.arguments.map(\.name), ["path", "value"])
        XCTAssertEqual(IPCCommand.permissionsRequest.spec.arguments.map(\.name), ["kind", "open"])
        XCTAssertEqual(IPCCommand.configGet.spec.arguments.first?.required, false)
        for c in IPCCommand.allCases { XCTAssertFalse(c.spec.summary.isEmpty, "\(c)") }
    }
}
