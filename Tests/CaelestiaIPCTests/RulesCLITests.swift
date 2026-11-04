import XCTest

@testable import CaelestiaIPC

/// `caelestia rules apps | set <bundle> <tile|float|auto> | focused | reload`.
final class RulesCLITests: XCTestCase {
    private func request(_ argv: [String]) throws -> IPCRequest {
        let inv = try CLIParser.parse(argv)
        guard case let .ipc(req) = inv.kind else {
            XCTFail("\(argv) did not produce an IPC request: \(inv.kind)")
            throw IPCError.remote("not ipc")
        }
        return req
    }

    func testApps() throws {
        XCTAssertEqual(try request(["rules", "apps"]).knownCommand, .rulesApps)
        let inv = try CLIParser.parse(["rules", "apps", "--json"])
        XCTAssertTrue(inv.json)
        XCTAssertEqual(inv.request?.knownCommand, .rulesApps)
    }

    func testFocused() throws {
        XCTAssertEqual(try request(["rules", "focused"]).knownCommand, .rulesFocused)
    }

    func testReloadStillWorks() throws {
        XCTAssertEqual(try request(["rules", "reload"]).knownCommand, .rulesReload)
    }

    func testSet() throws {
        for mode in ["tile", "float", "auto"] {
            let r = try request(["rules", "set", "com.apple.finder", mode])
            XCTAssertEqual(r.knownCommand, .rulesSet)
            XCTAssertEqual(r.string("bundleID"), "com.apple.finder")
            XCTAssertEqual(r.string("mode"), mode)
        }
        XCTAssertEqual(try request(["rules", "set", "com.apple.finder", "FLOAT"]).string("mode"), "float", "mode is lower-cased")
    }

    func testBadInvocationsAreRejected() {
        XCTAssertThrowsError(try CLIParser.parse(["rules", "set"]))
        XCTAssertThrowsError(try CLIParser.parse(["rules", "set", "com.apple.finder"]))
        XCTAssertThrowsError(try CLIParser.parse(["rules", "set", "com.apple.finder", "sideways"]))
        XCTAssertThrowsError(try CLIParser.parse(["rules", "set", "com.apple.finder", "float", "extra"]))
        XCTAssertThrowsError(try CLIParser.parse(["rules", "apps", "extra"]))
        XCTAssertThrowsError(try CLIParser.parse(["rules", "focused", "extra"]))
        XCTAssertThrowsError(try CLIParser.parse(["rules", "bogus"]))
        XCTAssertThrowsError(try CLIParser.parse(["rules"]))
    }

    func testCommandsAreRegisteredWithSpecs() {
        for c in [IPCCommand.rulesApps, .rulesSet, .rulesFocused] {
            XCTAssertEqual(IPCCommand(rawValue: c.rawValue), c)
            XCTAssertFalse(c.spec.summary.isEmpty)
        }
        XCTAssertEqual(IPCCommand.rulesSet.rawValue, "rules.set")
        XCTAssertEqual(IPCCommand.rulesSet.spec.arguments.map(\.name), ["bundleID", "mode"])
    }
}
