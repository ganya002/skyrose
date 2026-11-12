import XCTest

@testable import CaelestiaIPC

final class WifiCLITests: XCTestCase {
    private func verb(_ argv: [String]) throws -> WifiVerb {
        guard case .local(.wifi(let v)) = try CLIParser.parse(argv).kind else { XCTFail("not wifi"); return .status }
        return v
    }

    func testVerbs() throws {
        XCTAssertEqual(try verb(["wifi"]), .status)
        XCTAssertEqual(try verb(["wifi", "scan"]), .scan)
        XCTAssertEqual(try verb(["wifi", "off"]), .off)
        XCTAssertEqual(try verb(["wifi", "disconnect"]), .disconnect)
        XCTAssertEqual(try verb(["wifi", "connect", "Home Net"]), .connect(ssid: "Home Net", passwordFromStdin: false))
        XCTAssertEqual(try verb(["wifi", "join", "Cafe", "--password-stdin"]), .connect(ssid: "Cafe", passwordFromStdin: true))
        XCTAssertEqual(try verb(["wifi", "forget", "Old"]), .forget(ssid: "Old"))
    }

    func testBadInputIsAUsageError() {
        XCTAssertThrowsError(try CLIParser.parse(["wifi", "connect"]))
        XCTAssertThrowsError(try CLIParser.parse(["wifi", "teleport"]))
        XCTAssertThrowsError(try CLIParser.parse(["wifi", "scan", "extra"]))
        XCTAssertThrowsError(try CLIParser.parse(["wifi", "connect", "x", "--password", "secret"]))
    }
}
