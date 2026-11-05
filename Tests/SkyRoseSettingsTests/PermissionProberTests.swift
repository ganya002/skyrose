import CaelestiaCore
import XCTest
@testable import SkyRoseSettingsKit

final class PermissionProberTests: XCTestCase {
    func testArguments() {
        let out = URL(fileURLWithPath: "/tmp/x/probe.json")
        XCTAssertEqual(PermissionProber.arguments(output: out, requesting: nil), ["--permissions-probe", "/tmp/x/probe.json"])
        XCTAssertEqual(PermissionProber.arguments(output: out, requesting: .inputMonitoring),
                       ["--permissions-probe", "/tmp/x/probe.json", "--request", "inputMonitoring"])
    }

    func testDecodesProbeOutput() throws {
        let snap = PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: true)
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(PermissionProber.decode(data), snap)
        XCTAssertNil(PermissionProber.decode(Data("{}".utf8)))
        XCTAssertNil(PermissionProber.decode(Data("not json".utf8)))
    }

    /// A WM that accepts but does not answer is busy, not stopped.
    func testTimeoutIsBusyNotStopped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sr-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("s.sock").path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in path.utf8.enumerated() where i < buf.count - 1 { buf[i] = b }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(Darwin.listen(fd, 4), 0)
        // Listening, never answering.
        let r = WMConnection(socket: URL(fileURLWithPath: path)).callSync(.permissionsStatus, timeout: 0.3)
        XCTAssertEqual(r, .failure(.busy))
        // No socket at all: not running.
        let r2 = WMConnection(socket: dir.appendingPathComponent("none.sock")).callSync(.permissionsStatus, timeout: 0.3)
        XCTAssertEqual(r2, .failure(.notRunning))
    }
}
