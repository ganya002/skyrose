import CaelestiaCore
import CaelestiaPlatform
import Darwin
import Foundation
import XCTest

@testable import CaelestiaWMKit

/// A stand-in for the scripting addition: a Unix socket that answers like payload.c and logs
/// every command line.
final class FakeSAServer: @unchecked Sendable {
    let path: String
    private var fd: Int32 = -1
    private let lock = NSLock()
    private var _log: [String] = []
    private var clients: [Int32] = []
    var caps = "alpha,shadow,level,transform,space"
    var version = "1"

    var log: [String] { lock.lock(); defer { lock.unlock() }; return _log }

    init() {
        path = NSTemporaryDirectory() + "sa-\(UInt32.random(in: 0...UInt32.max)).sock"
    }

    func start() {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let b = Array(path.utf8)
            for (i, c) in b.enumerated() { raw[i] = c }
            raw[b.count] = 0
        }
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        listen(fd, 4)
        let listenFD = fd
        Thread.detachNewThread { [weak self] in
            while true {
                let c = accept(listenFD, nil, nil)
                if c < 0 { return }
                Thread.detachNewThread { self?.serve(c) }
            }
        }
    }

    private func serve(_ c: Int32) {
        lock.lock(); clients.append(c); lock.unlock()
        var buf = [UInt8](repeating: 0, count: 4096)
        var pending = ""
        while true {
            let n = read(c, &buf, buf.count)
            if n <= 0 { close(c); return }
            pending += String(decoding: buf[0..<n], as: UTF8.self)
            while let nl = pending.firstIndex(of: "\n") {
                let line = String(pending[..<nl])
                pending.removeSubrange(...nl)
                lock.lock(); _log.append(line); lock.unlock()
                let reply = line == "hello" ? "ok skyrose-sa \(version) \(caps)\n" : "ok\n"
                _ = reply.withCString { write(c, $0, strlen($0)) }
            }
        }
    }

    func stop() {
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd) }
        fd = -1
        lock.lock(); let open = clients; clients.removeAll(); lock.unlock()
        for c in open { shutdown(c, SHUT_RDWR) }  // like the Dock going away
        unlink(path)
    }
}

final class SAProtocolTests: XCTestCase {
    func testHelloParsing() {
        let h = SAProtocol.parseHello("ok skyrose-sa 1 alpha,shadow,level,transform,space")
        XCTAssertEqual(h?.version, "1")
        XCTAssertEqual(h?.capabilities, [.alpha, .shadow, .level, .transform, .space])
        XCTAssertEqual(SAProtocol.parseHello("ok skyrose-sa 1 alpha,bogus")?.capabilities, [.alpha])
        XCTAssertEqual(SAProtocol.parseHello("ok skyrose-sa 2 none")?.capabilities, [])
        XCTAssertNil(SAProtocol.parseHello("err unknown command"))
        XCTAssertNil(SAProtocol.parseHello("ok yabai-sa 1 alpha"))
    }

    func testVisualLineAndTransformMatchThePayload() {
        let line = SAProtocol.visualLine([
            .init(id: 7, rect: CGRect(x: 10, y: 20, width: 300, height: 200)),
            .init(id: 9, rect: CGRect(x: 0, y: 0, width: 50.5, height: 40), alpha: 1.4),
        ])
        XCTAssertEqual(line, "visual 7 10.00 20.00 300.00 200.00;9 0.00 0.00 50.50 40.00 1.000")
        // Identity: a window shown where it is gets the window server's own translate(-x, -y)
        // (read back live from SLSGetWindowTransform: 1,0,0,1,-300,-324).
        let b = CGRect(x: 300, y: 324, width: 400, height: 332)
        XCTAssertEqual(SAProtocol.transform(bounds: b, visual: b), CGAffineTransform(translationX: -300, y: -324))
        // Half size at (700, 360): what the live host test showed.
        let t = SAProtocol.transform(bounds: b, visual: CGRect(x: 700, y: 360, width: 200, height: 166))
        XCTAssertEqual(t.a, 2); XCTAssertEqual(t.d, 2); XCTAssertEqual(t.tx, -1400); XCTAssertEqual(t.ty, -720)
        // A screen point at the visual's corner maps to the window's own origin.
        XCTAssertEqual(CGPoint(x: 700, y: 360).applying(t), .zero)
    }

    func testLoadCommandQuoting() {
        XCTAssertEqual(SAProtocol.loadCommand(loader: URL(fileURLWithPath: "/Applications/SkyRose.app/Contents/Resources/sa/skyrose-sa-loader")),
                       "sudo /Applications/SkyRose.app/Contents/Resources/sa/skyrose-sa-loader")
        XCTAssertEqual(SAProtocol.loadCommand(loader: URL(fileURLWithPath: "/Users/g/My Apps/x")), "sudo '/Users/g/My Apps/x'")
    }

    func testReadinessFromThisMacsCSRUtilOutput() {
        let csrutil = """
        System Integrity Protection status: unknown (Custom Configuration).

        Configuration:
        \tApple Internal: disabled
        \tKext Signing: enabled
        \tFilesystem Protections: disabled
        \tDebugging Restrictions: disabled
        \tDTrace Restrictions: enabled
        \tNVRAM Protections: disabled
        \tBaseSystem Verification: enabled
        """
        let r = SIPOffReadiness.parse(csrutil: csrutil, bootArgs: "boot-args\t-arm64e_preview_abi\n")
        XCTAssertTrue(r.filesystemOff && r.debuggingOff && r.nvramOff && r.bootArg)
        XCTAssertTrue(r.ready)
        XCTAssertTrue(r.missing.isEmpty)
        let noArg = SIPOffReadiness.parse(csrutil: csrutil, bootArgs: "boot-args\t-v")
        XCTAssertFalse(noArg.ready)
        XCTAssertEqual(noArg.missing, ["sudo nvram boot-args=-arm64e_preview_abi"])
        let on = SIPOffReadiness.parse(csrutil: "System Integrity Protection status: enabled.", bootArgs: nil)
        XCTAssertFalse(on.ready)
        XCTAssertEqual(on.missing.count, 2)
        XCTAssertTrue(SIPOffReadiness.parse(csrutil: "System Integrity Protection status: disabled.", bootArgs: "-arm64e_preview_abi").ready)
    }
}

@MainActor
final class EnhancedModeTests: XCTestCase {
    private var server: FakeSAServer!
    private var dir: URL!

    override func setUp() async throws {
        server = FakeSAServer()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("enh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: dir)
    }

    private func config(enabled: Bool = true, _ edit: (inout SIPOffConfig) -> Void = { _ in }) -> Config {
        var c = Config()
        c.sipOff.enabled = enabled
        edit(&c.sipOff)
        return c
    }

    private func makeMode() -> (EnhancedMode, RestoreManifest) {
        let manifest = RestoreManifest(url: dir.appendingPathComponent("restore-manifest.json"))
        return (EnhancedMode(client: SAClient(path: server.path), manifest: manifest), manifest)
    }

    func testTheMenuBarIsGoneOnlyWhileTheHelperAnswersAndTheSwitchIsOn() {
        let (mode, _) = makeMode()
        var sent: [Bool] = []
        mode.applyMenuBar = { sent.append($0) }
        XCTAssertTrue(Config().sipOff.hideMenuBar)
        mode.apply(config: config(enabled: true))
        XCTAssertEqual(sent, [], "no helper yet: SIP-on behaviour")
        server.start()
        mode.apply(config: config(enabled: true))
        XCTAssertTrue(mode.active)
        XCTAssertEqual(sent, [true])
        var off = config(enabled: true)
        off.sipOff.hideMenuBar = false
        mode.apply(config: off)
        XCTAssertEqual(sent, [true, false], "the switch brings it back at once")
        mode.apply(config: config(enabled: true))
        XCTAssertEqual(sent, [true, false, true])
        mode.shutdown()
        XCTAssertEqual(sent, [true, false, true, false], "quit and panic bring it back")
    }

    func testOffByDefaultAndWithoutTheSA() {
        XCTAssertFalse(Config().sipOff.enabled, "opt-in")
        let (mode, manifest) = makeMode()
        mode.apply(config: config(enabled: true))  // enabled, but no SA answers
        XCTAssertFalse(mode.active)
        XCTAssertFalse(mode.canAnimate)
        XCTAssertFalse(mode.instantWorkspaces)
        XCTAssertEqual(mode.targetAlpha(1), 1, "SIP-on: windows stay opaque")
        XCTAssertFalse(manifest.everUsed(.sipOff), "not used, no SIP reminder")
        server.start()
        mode.apply(config: config(enabled: false))
        XCTAssertFalse(mode.active, "disabled: never connects")
        XCTAssertTrue(server.log.isEmpty)
    }

    func testActivatesRecordsUseAndAppliesOpacityAndPin() throws {
        server.start()
        let (mode, manifest) = makeMode()
        var changes = 0
        mode.onChange = { changes += 1 }
        mode.apply(config: config())
        XCTAssertTrue(mode.active)
        XCTAssertTrue(mode.canAnimate)
        XCTAssertTrue(mode.instantWorkspaces)
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(manifest.everUsed(.sipOff), "the SIP reminder flag is set once the mode is really used")

        mode.layoutApplied([.init(id: 10, fullscreen: false, pinned: false), .init(id: 11, fullscreen: true, pinned: false),
                            .init(id: 12, fullscreen: false, pinned: true)])
        let log = server.log
        XCTAssertTrue(log.contains("alpha 10 0.950"))
        XCTAssertFalse(log.contains { $0.hasPrefix("alpha 11") }, "fullscreen stays opaque")
        XCTAssertTrue(log.contains("level 12 \(Int(CGWindowLevelForKey(.floatingWindow)))"), "pinned = really on top")
        XCTAssertFalse(log.contains { $0.hasPrefix("shadow") }, "shadows kept by default")

        // Nothing changed: no new commands.
        let count = server.log.count
        mode.layoutApplied([.init(id: 10, fullscreen: false, pinned: false), .init(id: 11, fullscreen: true, pinned: false),
                            .init(id: 12, fullscreen: false, pinned: true)])
        XCTAssertEqual(server.log.count, count)
        // Unpinned: level back.
        mode.layoutApplied([.init(id: 12, fullscreen: false, pinned: false)])
        XCTAssertTrue(server.log.contains("level-reset 12"))
    }

    func testPinDuringAnAnimationRaisesAtOnceButAlphaWaits() {
        server.start()
        let (mode, _) = makeMode()
        mode.apply(config: config { $0.shadows = false })
        // Pinning floats the window, which starts a move animation (live 3b: level stayed 0).
        mode.animator.animate(.init(changes: [.init(id: 7, kind: .move, from: CGRect(x: 0, y: 0, width: 300, height: 300),
                                                    to: CGRect(x: 50, y: 50, width: 200, height: 200))],
                                    windows: [], displays: [:])) {}
        XCTAssertTrue(mode.animator.isCovering(7))
        mode.layoutApplied([.init(id: 7, fullscreen: false, pinned: true)])
        let log = server.log
        XCTAssertTrue(log.contains("level 7 \(Int(CGWindowLevelForKey(.floatingWindow)))"))
        XCTAssertTrue(log.contains("shadow 7 0"))
        XCTAssertFalse(log.contains { $0.hasPrefix("alpha 7") }, "the animation's last frame sets alpha")
        mode.animator.cancel()
    }

    func testShadowSwitchAndInstantSwitchHiding() async throws {
        server.start()
        let (mode, _) = makeMode()
        mode.apply(config: config { $0.shadows = false })
        mode.layoutApplied([.init(id: 5, fullscreen: false, pinned: false)])
        XCTAssertTrue(server.log.contains("shadow 5 0"))
        mode.hideForSwitch([5, 6])
        XCTAssertTrue(server.log.contains("alpha 5 0.000"))
        XCTAssertTrue(server.log.contains("alpha 6 0.000"))
        mode.restoreAfterSwitch()
        try await Task.sleep(nanoseconds: UInt64((EnhancedMode.switchRestoreDelay + 0.15) * 1e9))
        XCTAssertEqual(server.log.filter { $0 == "alpha 6 0.950" }.count, 1, "alpha comes back after the move")
    }

    func testFallsBackSilentlyWhenTheSAGoesAway() {
        server.start()
        let (mode, _) = makeMode()
        var changes = 0
        mode.onChange = { changes += 1 }
        mode.apply(config: config())
        XCTAssertTrue(mode.active)
        server.stop()  // Dock restarted / macOS update broke it
        mode.layoutApplied([.init(id: 10, fullscreen: false, pinned: false)])
        mode.layoutApplied([.init(id: 10, fullscreen: false, pinned: false)])
        XCTAssertFalse(mode.active, "back to the SIP-on paths")
        XCTAssertFalse(mode.canAnimate)
        XCTAssertEqual(changes, 2)
    }

    func testOtherVersionIsNotUsedAndShutdownResets() {
        server.version = "2"
        server.start()
        let (mode, _) = makeMode()
        mode.apply(config: config())
        XCTAssertFalse(mode.active, "an SA of another build is ignored")
        server.stop()

        let next = FakeSAServer()
        defer { next.stop() }
        next.start()
        let m2 = EnhancedMode(client: SAClient(path: next.path), manifest: nil)
        m2.apply(config: config())
        XCTAssertTrue(m2.active)
        m2.shutdown()
        XCTAssertTrue(next.log.contains("reset"), "quit / panic undo every change")
        XCTAssertFalse(m2.active)
    }

    func testAnimatorCommitsAtOnceWhenItCannotAnimate() {
        let (mode, _) = makeMode()
        var committed = false
        mode.animator.animate(.init(changes: [.init(id: 1, kind: .open, from: nil, to: CGRect(x: 0, y: 0, width: 100, height: 100))],
                                    windows: [], displays: [:])) { committed = true }
        XCTAssertTrue(committed)
        XCTAssertFalse(mode.animator.isAnimating)
    }

    func testAnimatorFreezesCommitsAndSendsTheFirstTransform() {
        server.start()
        let (mode, _) = makeMode()
        mode.apply(config: config())
        var committed = false
        let to = CGRect(x: 100, y: 100, width: 400, height: 300)
        mode.animator.animate(.init(changes: [.init(id: 3, kind: .open, from: nil, to: to),
                                              .init(id: 4, kind: .move, from: CGRect(x: 0, y: 0, width: 200, height: 200), to: to)],
                                    windows: [], displays: [:])) { committed = true }
        XCTAssertTrue(committed)
        XCTAssertTrue(mode.animator.isCovering(3))
        let log = server.log
        let freeze = try? XCTUnwrap(log.firstIndex(of: "freeze"))
        let visual = log.firstIndex { $0.hasPrefix("visual ") }
        let thaw = log.firstIndex(of: "thaw")
        XCTAssertNotNil(freeze); XCTAssertNotNil(visual); XCTAssertNotNil(thaw)
        if let f = freeze, let v = visual, let t = thaw { XCTAssertTrue(f < v && v < t) }
        // Open pops from 80 % around the centre, invisible first.
        XCTAssertTrue(log.contains { $0.contains("3 140.00 130.00 320.00 240.00 0.000") })
        XCTAssertTrue(log.contains { $0.contains("4 0.00 0.00 200.00 200.00") })
        mode.animator.cancel()
        XCTAssertFalse(mode.animator.isAnimating)
        XCTAssertTrue(server.log.contains { $0.hasPrefix("visual-reset") })
    }
}
