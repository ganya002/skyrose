import XCTest
import CaelestiaCore
@testable import CaelestiaIPC

/// CLI parsing (spec 4.8), the 1:1 mapping of the Linux shell IPC targets (ipc-commands.txt), the
/// JSON-lines wire format, and a real socket round trip.
final class IPCTests: XCTestCase {
    func request(_ argv: String) throws -> IPCRequest {
        let inv = try CLIParser.parse(argv.split(separator: " ").map(String.init))
        guard case let .ipc(req) = inv.kind else {
            XCTFail("\(argv) did not produce an IPC request: \(inv.kind)")
            throw IPCError.remote("not ipc")
        }
        return req
    }

    // MARK: CLI

    func testWorkspaceCommands() throws {
        let focus = try request("ws focus 3")
        XCTAssertEqual(focus.knownCommand, .wsFocus)
        XCTAssertEqual(focus.int("index"), 3)
        let move = try request("ws move 3 --silent")
        XCTAssertEqual(move.knownCommand, .wsMove)
        XCTAssertEqual(move.bool("silent"), true)
        XCTAssertEqual(try request("ws move 3").bool("silent"), false)
        XCTAssertEqual(try request("ws toggle-special music").string("name"), "music")
        XCTAssertNil(try request("ws toggle-special").string("name"))
    }

    func testWindowAndQueryCommands() throws {
        let focus = try request("window focus left")
        XCTAssertEqual(focus.knownCommand, .windowFocus)
        XCTAssertEqual(focus.direction("direction"), .left)
        let inv = try CLIParser.parse(["query", "windows", "--json"])
        XCTAssertTrue(inv.json)
        XCTAssertEqual(inv.request?.knownCommand, .queryWindows)
        for q in ["workspaces", "monitors", "binds"] {
            XCTAssertNotNil(try request("query \(q)").knownCommand)
        }
    }

    func testShellPanelsAndDaemonFlags() throws {
        XCTAssertEqual(try request("shell launcher").knownCommand, .shellLauncher)
        XCTAssertEqual(try request("shell lock").knownCommand, .shellLockLock)
        XCTAssertEqual(try CLIParser.parse(["shell", "-d"]).kind, .local(.shellStart))
    }

    func testUsageErrors() {
        XCTAssertThrowsError(try CLIParser.parse(["ws", "focus"]))
        XCTAssertThrowsError(try CLIParser.parse(["ws", "focus", "three"]))
        XCTAssertThrowsError(try CLIParser.parse(["ws", "fly"]))
        XCTAssertThrowsError(try CLIParser.parse(["shell", "toaster", "info", "only-title"]))
        XCTAssertThrowsError(try CLIParser.parse(["--timeout", "-1", "query", "windows"]))
    }

    /// Every `target X / function f(args)` of the Linux shell parses with the same names and arity.
    func testEveryLinuxShellTargetMaps() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/ref/ipc-commands.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        var target: String?
        var checked = 0
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("target ") {
                target = String(line.dropFirst("target ".count))
                continue
            }
            guard line.hasPrefix("function "), let target else { continue }
            let signature = line.dropFirst("function ".count)
            let name = String(signature.prefix { $0 != "(" })
            let params = signature.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            let arity = params.isEmpty ? 0 : params.split(separator: ",").count
            let argv = ["shell", target, name] + Array(repeating: "1", count: arity)
            let inv = try CLIParser.parse(argv)
            guard case .ipc = inv.kind else { return XCTFail("\(argv) is not an IPC call") }
            let mapped = try XCTUnwrap(ShellTarget(cliName: target), target)
            XCTAssertEqual(mapped.function(named: name)?.parameters.count, arity, "\(target).\(name)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 40)
    }

    // MARK: Wire format

    func testRequestResponseLinesRoundTrip() throws {
        let req = IPCRequest(id: 7, .wsMove, args: ["index": .number(3), "silent": .bool(true)])
        let line = try IPCWire.encodeLine(req)
        XCTAssertEqual(line.last, IPCWire.newline)
        XCTAssertEqual(line.filter { $0 == IPCWire.newline }.count, 1, "exactly one JSON line")
        XCTAssertEqual(try IPCWire.decodeLine(IPCRequest.self, from: line), req)

        let resp = IPCResponse.failure(for: req, error: "no window")
        XCTAssertEqual(try IPCWire.decodeLine(IPCResponse.self, from: IPCWire.encodeLine(resp)), resp)
    }

    // MARK: Socket

    func testServerAndClientTalkOverAUnixSocket() throws {
        let dir = URL(fileURLWithPath: "/tmp").appendingPathComponent("cm-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("ipc.sock")
        let server = IPCServer(path: path) { req in
            if req.knownCommand == .wsFocus { return .success(for: req, result: .number(Double(req.int("index") ?? 0))) }
            return .failure(for: req, error: "unsupported")
        }
        try server.start()
        defer { server.stop() }

        let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600, "socket is private to the user")

        let client = IPCClient(path: path)
        XCTAssertTrue(client.isRunning)
        XCTAssertEqual(try client.call(.wsFocus, args: ["index": .number(4)]), .number(4))
        XCTAssertFalse(try client.send(.queryBinds).ok)
        XCTAssertThrowsError(try client.call(.queryBinds))
    }

    func testClientReportsNotRunning() {
        let client = IPCClient(path: URL(fileURLWithPath: "/tmp/cm-missing-\(UUID().uuidString.prefix(8)).sock"))
        XCTAssertFalse(client.isRunning)
        XCTAssertThrowsError(try client.send(.queryWindows, timeout: 0.5)) { error in
            XCTAssertTrue((error as? IPCError)?.isNotRunning == true, "\(error)")
        }
    }
}
