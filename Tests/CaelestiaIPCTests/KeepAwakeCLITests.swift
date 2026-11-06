import XCTest
import CaelestiaCore
@testable import CaelestiaIPC

/// `skyrose keepawake on [30m|1h|forever] | off | status`.
final class KeepAwakeCLITests: XCTestCase {
    private func request(_ args: [String]) throws -> IPCRequest {
        guard case let .ipc(req) = try CLIParser.parse(args).kind else {
            XCTFail("\(args) did not produce an IPC request")
            throw IPCError.remote("not ipc")
        }
        return req
    }

    func testOnWithAndWithoutDuration() throws {
        let timed = try request(["keepawake", "on", "30m"])
        XCTAssertEqual(timed.knownCommand, .keepAwake)
        XCTAssertEqual(timed.string("state"), "on")
        XCTAssertEqual(timed.double("seconds"), 1800)
        XCTAssertEqual(try request(["keepawake", "on", "1h"]).double("seconds"), 3600)
        XCTAssertNil(try request(["keepawake", "on"]).double("seconds"))
        XCTAssertNil(try request(["keepawake", "on", "forever"]).double("seconds"))
    }

    func testOffStatusAndAliases() throws {
        XCTAssertEqual(try request(["keepawake", "off"]).string("state"), "off")
        XCTAssertEqual(try request(["keepawake", "status"]).string("state"), "status")
        XCTAssertEqual(try request(["keepawake"]).string("state"), "status", "status is the default")
        XCTAssertEqual(try request(["caffeinate", "on", "1h"]).knownCommand, .keepAwake)
        XCTAssertEqual(try request(["keep-awake", "off"]).knownCommand, .keepAwake)
    }

    func testBadInputIsAUsageError() {
        XCTAssertThrowsError(try CLIParser.parse(["keepawake", "on", "soon"]))
        XCTAssertThrowsError(try CLIParser.parse(["keepawake", "on", "1h", "extra"]))
        XCTAssertThrowsError(try CLIParser.parse(["keepawake", "off", "now"]))
        XCTAssertThrowsError(try CLIParser.parse(["keepawake", "maybe"]))
    }

    func testCommandIsRegistered() {
        XCTAssertEqual(IPCCommand.keepAwake.rawValue, "keepawake")
        XCTAssertEqual(IPCCommand.keepAwake.spec.arguments.map(\.name), ["state", "seconds"])
    }
}

/// `skyrose clamshell [status]` (alias lid).
final class ClamshellCLITests: XCTestCase {
    func testStatusIsTheOnlyVerb() throws {
        for args in [["clamshell"], ["clamshell", "status"], ["lid"]] {
            guard case let .ipc(req) = try CLIParser.parse(args).kind else { return XCTFail("\(args)") }
            XCTAssertEqual(req.knownCommand, .clamshell)
        }
        XCTAssertThrowsError(try CLIParser.parse(["clamshell", "on"]), "nothing to switch: macOS decides")
        XCTAssertThrowsError(try CLIParser.parse(["clamshell", "status", "x"]))
    }
}
