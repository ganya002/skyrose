import Foundation
import XCTest

@testable import CaelestiaIPC

/// One WM per user: a restart waits for the old socket, a second live instance is refused, and a
/// socket file removed from under a running server is rebound (Settings showed "SkyRose is not
/// running" while the WM ran without a reachable socket).
final class IPCInstanceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: "/tmp").appendingPathComponent("cm-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func server(_ path: URL, tag: Double) -> IPCServer {
        IPCServer(path: path) { req in .success(for: req, result: .number(tag)) }
    }

    func testRestartWaitsForThePreviousInstanceToLetGo() throws {
        let path = dir.appendingPathComponent("ipc.sock")
        let old = server(path, tag: 1)
        try old.start()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { old.stop() }
        let new = server(path, tag: 2)
        try new.start(waitingForPreviousInstance: 5, interval: 0.05)
        defer { new.stop() }
        XCTAssertEqual(try IPCClient(path: path).call(.queryState), .number(2))
    }

    func testASecondLiveInstanceIsRefused() throws {
        let path = dir.appendingPathComponent("ipc.sock")
        let first = server(path, tag: 1)
        try first.start()
        defer { first.stop() }
        let second = server(path, tag: 2)
        XCTAssertThrowsError(try second.start(waitingForPreviousInstance: 0.3, interval: 0.05)) { error in
            guard case .alreadyRunning = error as? IPCError else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(second.isRunning)
        XCTAssertEqual(try IPCClient(path: path).call(.queryState), .number(1), "the first keeps its socket")
    }

    func testARemovedSocketIsRebound() throws {
        let path = dir.appendingPathComponent("ipc.sock")
        let s = server(path, tag: 3)
        try s.start()
        defer { s.stop() }
        XCTAssertTrue(s.ownsSocketFile)
        XCTAssertFalse(try s.rebindIfLost(), "nothing to do while the file is ours")
        unlink(path.path)
        XCTAssertFalse(s.ownsSocketFile)
        XCTAssertFalse(IPCClient(path: path).isRunning)
        XCTAssertTrue(try s.rebindIfLost())
        XCTAssertTrue(s.ownsSocketFile)
        XCTAssertEqual(try IPCClient(path: path).call(.queryState), .number(3))
    }

    func testStoppingTheOldInstanceLeavesTheNewSocketAlone() throws {
        let path = dir.appendingPathComponent("ipc.sock")
        let old = server(path, tag: 1)
        try old.start()
        unlink(path.path)  // as if a new instance had replaced it
        let new = server(path, tag: 2)
        try new.start()
        defer { new.stop() }
        old.stop()
        XCTAssertTrue(new.ownsSocketFile)
        XCTAssertEqual(try IPCClient(path: path).call(.queryState), .number(2))
    }
}
