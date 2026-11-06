import XCTest
import CaelestiaCore
@testable import CaelestiaIPC

/// `skyrose frame calibrate [display]`.
final class FrameCalibrateCLITests: XCTestCase {
    private func request(_ args: [String]) throws -> IPCRequest {
        guard case let .ipc(req) = try CLIParser.parse(args).kind else {
            XCTFail("\(args) did not produce an IPC request")
            throw IPCError.remote("not ipc")
        }
        return req
    }

    func testCalibrateWithoutDisplay() throws {
        let r = try request(["frame", "calibrate"])
        XCTAssertEqual(r.knownCommand, .frameCalibrate)
        XCTAssertNil(r.string("display"))
    }

    func testDisplayArgumentIsJoinedWithSpaces() throws {
        let r = try request(["frame", "calibrate", "Built-in", "Retina", "Display"])
        XCTAssertEqual(r.knownCommand, .frameCalibrate)
        XCTAssertEqual(r.string("display"), "Built-in Retina Display")
        XCTAssertEqual(try request(["frame", "calibrate", "Built-in Retina Display"]).string("display"), "Built-in Retina Display")
        XCTAssertEqual(try request(["frame", "calibrate", "37D8832A-2D66-02CA-B9F7-8F30A301B230"]).string("display"),
                       "37D8832A-2D66-02CA-B9F7-8F30A301B230")
    }

    func testUnknownVerbIsAnError() {
        XCTAssertThrowsError(try CLIParser.parse(["frame", "bogus"])) { error in
            guard case let CLIUsageError.unknownVerb(group, verb, expected) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(group, "frame")
            XCTAssertEqual(verb, "bogus")
            XCTAssertEqual(expected, ["calibrate"])
        }
    }

    func testMissingVerbIsAnError() {
        XCTAssertThrowsError(try CLIParser.parse(["frame"])) { error in
            guard case CLIUsageError.missingArgument(let command, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(command, "frame")
        }
    }

    func testCommandIsRegisteredWithAnOptionalDisplayArgument() {
        XCTAssertEqual(IPCCommand.frameCalibrate.rawValue, "frame.calibrate")
        XCTAssertTrue(IPCCommand.allCases.contains(.frameCalibrate))
        let spec = IPCCommand.frameCalibrate.spec
        XCTAssertEqual(spec.arguments.map(\.name), ["display"])
        XCTAssertFalse(spec.arguments[0].required)
    }
}

final class ScreenshotCLITests: XCTestCase {
    func testModesIncludingWindow() throws {
        for mode in ["region", "freeze", "window", "full"] {
            guard case let .ipc(req) = try CLIParser.parse(["screenshot", mode]).kind else { return XCTFail(mode) }
            XCTAssertEqual(req.string("mode"), mode)
        }
        guard case let .ipc(def) = try CLIParser.parse(["screenshot"]).kind else { return XCTFail() }
        XCTAssertEqual(def.string("mode"), "region")
        XCTAssertThrowsError(try CLIParser.parse(["screenshot", "area"]))
    }
}
