import CryptoKit
import Foundation
import XCTest
@testable import CaelestiaCore

/// SkyStore `app` addons: the recipe checks, the policy, and a real out-of-process setup of a tiny
/// test app (built with the Xcode toolchain from a source archive, started, stopped, removed).
/// Everything lives in a temporary folder with a fake home; launchd is never touched.
final class AppAddonTests: XCTestCase {
    var tmp: URL!
    var home: URL!
    var key: Curve25519.Signing.PrivateKey!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skystore-app-\(UUID().uuidString)", isDirectory: true)
        home = tmp.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        key = Curve25519.Signing.PrivateKey()
    }

    override func tearDownWithError() throws {
        let host = AppHost(root: tmp.appendingPathComponent("addons"), home: home, live: false)
        for p in AppHost.pids(inside: host.folder("dev.gabby.test-app")) { kill(p, SIGKILL) }
        try? FileManager.default.removeItem(at: tmp)
    }

    func app(downloads: [AppEntry.Download] = [], launchAgent: Bool? = true) -> AppEntry {
        AppEntry(bundleID: "dev.gabby.test-app", appName: "TestApp", source: "source.tar.gz", products: ["TestApp"],
                 infoPlist: "Info.plist", copy: [.init(from: "source:Resources/hello.txt", to: "Contents/Resources/hello.txt")],
                 downloads: downloads, diskBytes: 50_000_000, cli: [.init(from: "source:bin/testctl", to: "testctl")],
                 stop: ["quit"], launchAgent: launchAgent, dataPaths: ["Library/Application Support/TestApp"])
    }

    func manifest(_ app: AppEntry, id: String = "dev.gabby.test-app", permissions: [String] = ["login"], files: [String: String] = [:]) -> AddonManifest {
        AddonManifest(id: id, name: "Test App", author: "SkyStore tests", version: "1.0.0", minSkyRose: "0.1.0", kind: .app,
                      summary: "Dummy app for tests only", licence: "MIT", permissions: permissions, entry: .init(app: app),
                      files: files.isEmpty ? ["source.tar.gz": String(repeating: "a", count: 64)] : files)
    }

    // MARK: Recipe and policy

    func testValidAppManifestPassesPolicy() {
        XCTAssertEqual(AddonPolicy.current.issues(manifest(app())), [])
    }

    func testRecipeChecks() {
        let d = AppEntry.Download(id: "rt", title: "Runtime", url: "https://example.com/rt.tar.gz", sha256: String(repeating: "b", count: 64),
                                  size: 10, unpack: "tar.gz", into: "deps/rt")
        XCTAssertTrue(manifest(app(downloads: [d])).issues().contains { $0.contains("declare network:example.com") })
        XCTAssertEqual(manifest(app(downloads: [d]), permissions: ["login", "network:example.com"]).issues(), [])
        var bad = app()
        bad.architectures = ["x86_64"]
        bad.minMacOS = "13.0"
        bad.copy = [.init(from: "/etc/passwd", to: "Contents/x"), .init(from: "source:a", to: "MacOS/x")]
        bad.dataPaths = ["Documents", "Library/Application Support/"]
        bad.requires = ["homebrew"]
        let issues = manifest(bad).issues()
        for needle in ["arm64", "minMacOS", "from '/etc/passwd'", "to 'MacOS/x'", "'Documents'", "homebrew"] {
            XCTAssertTrue(issues.contains { $0.contains(needle) }, needle)
        }
        XCTAssertTrue(manifest(app(), permissions: []).issues().contains { $0.contains("launchAgent needs the login permission") })
        var http = d
        http.url = "http://example.com/rt.tar.gz"
        XCTAssertTrue(manifest(app(downloads: [http]), permissions: ["login", "network:example.com"]).issues().contains { $0.contains("https") })
    }

    func testAppKindIsFirstPartyOnlyAndKeepsDataKindsUnchanged() {
        XCTAssertTrue(AddonPolicy.current.issues(manifest(app(), id: "dev.someone.app")).contains { $0.contains("first-party only") })
        XCTAssertTrue(AddonPolicy.current.issues(kind: .app, permissions: [AddonPermission(.clipboard)], id: "dev.gabby.x")[0].contains("cannot ask for clipboard"))
        XCTAssertEqual(AddonPolicy.current.issues(kind: .scheme, permissions: [AddonPermission(.microphone)]),
                       ["a scheme addon is data only and cannot ask for permissions"])
        XCTAssertTrue(AddonPolicy.current.issues(kind: .widget, permissions: [])[0].contains("run code"))
    }

    func testUnknownKindInIndexDoesNotBreakDecoding() throws {
        let json = #"{"schema":1,"addons":[{"id":"dev.x.future","name":"F","author":"A","summary":"S","kind":"hologram","licence":"MIT","versions":[]}]}"#
        let index = try StoreIndex.decode(Data(json.utf8))
        XCTAssertEqual(index.addons.first?.kind, .unknown)
        XCTAssertFalse(AddonPolicy.current.issues(kind: .unknown, permissions: []).isEmpty)
    }

    func testNewPermissionsParse() {
        for p in ["microphone", "accessibility", "keychain", "login"] { XCTAssertNotNil(AddonPermission(p), p) }
        XCTAssertNil(AddonPermission("microphone:x"))
    }

    func testArchiveEntrySafety() throws {
        for ok in ["a", "./a/b", "dir/", "."] { XCTAssertTrue(AppInstaller.isSafeEntry(ok), ok) }
        for bad in ["/etc/x", "../x", "a/../../x"] { XCTAssertFalse(AppInstaller.isSafeEntry(bad), bad) }
        let dir = tmp.appendingPathComponent("links", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("A"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("Current").path, withDestinationPath: "A")
        XCTAssertNoThrow(try AppInstaller.refuseEscapingLinks(dir))
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("evil").path, withDestinationPath: "../../etc")
        XCTAssertThrowsError(try AppInstaller.refuseEscapingLinks(dir))
    }

    func testBuildCounterAndProgressDetail() {
        XCTAssertEqual(AppInstaller.buildCounter("[12/340] Compiling Sky main.swift").map { [$0.0, $0.1] }, [12, 340])
        XCTAssertEqual(AppInstaller.buildCounter("[16 / 21] Sky-product").map { [$0.0, $0.1] }, [16, 21])
        XCTAssertNil(AppInstaller.buildCounter("Compiling"))
        XCTAssertNil(AppInstaller.buildCounter("[Planning deferred tasks]"))
        let e = AppSetupEvent(.download, "x", fraction: 0.2, bytes: 5_000_000, total: 10_000_000, bytesPerSecond: 1_000_000, eta: 5)
        XCTAssertEqual(e.detail?.contains("s left"), true)
        XCTAssertEqual(try JSONDecoder().decode(AppSetupEvent.self, from: Data(e.jsonLine.utf8)), e)
    }

    // MARK: Install → setup → stop → uninstall (real build)

    /// A tiny SwiftPM app: runs until SIGTERM, or until `TestApp quit` (the declared stop) is run.
    func makeBundle() throws -> (url: URL, sha: String, size: Int) {
        let fm = FileManager.default
        let src = tmp.appendingPathComponent("pkg", isDirectory: true)
        try fm.createDirectory(at: src.appendingPathComponent("Sources/TestApp"), withIntermediateDirectories: true)
        try fm.createDirectory(at: src.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: src.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try """
        // swift-tools-version:5.10
        import PackageDescription
        let package = Package(name: "TestApp", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "TestApp")])
        """.write(to: src.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import Foundation
        let flag = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("skystore-testapp-quit")
        if CommandLine.arguments.dropFirst().first == "quit" { FileManager.default.createFile(atPath: flag.path, contents: nil); exit(0) }
        try? FileManager.default.removeItem(at: flag)
        while !FileManager.default.fileExists(atPath: flag.path) { Thread.sleep(forTimeInterval: 0.1) }
        try? FileManager.default.removeItem(at: flag)
        """.write(to: src.appendingPathComponent("Sources/TestApp/main.swift"), atomically: true, encoding: .utf8)
        try "hello".write(to: src.appendingPathComponent("Resources/hello.txt"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho testctl\n".write(to: src.appendingPathComponent("bin/testctl"), atomically: true, encoding: .utf8)
        let plist: [String: Any] = ["CFBundleIdentifier": "dev.gabby.test-app", "CFBundleExecutable": "TestApp", "CFBundleName": "TestApp",
                                    "CFBundlePackageType": "APPL", "LSUIElement": true, "LSMinimumSystemVersion": "14.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: src.appendingPathComponent("Info.plist"))
        let staging = tmp.appendingPathComponent("bundle", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        XCTAssertEqual(AddonBundle.run("/usr/bin/tar", ["-czf", staging.appendingPathComponent("source.tar.gz").path, "-C", src.path, "."]).status, 0)
        let archive = try Data(contentsOf: staging.appendingPathComponent("source.tar.gz"))
        let m = manifest(app(), permissions: ["login"], files: ["source.tar.gz": archive.sha256Hex])
        try m.encoded().write(to: staging.appendingPathComponent(AddonManifest.fileName))
        let out = tmp.appendingPathComponent("dev.gabby.test-app-1.0.0.skyaddon")
        XCTAssertEqual(AddonBundle.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", staging.path, out.path]).status, 0)
        let data = try Data(contentsOf: out)
        return (out, data.sha256Hex, data.count)
    }

    func signedSource(_ b: (url: URL, sha: String, size: Int)) throws -> (StoreSource, StoreEntry) {
        let v = StoreVersion(version: "1.0.0", minSkyRose: "0.1.0", url: b.url, sha256: b.sha, size: b.size, permissions: ["login"], released: "2026-11-12")
        let e = StoreEntry(id: "dev.gabby.test-app", name: "Test App", author: "SkyStore tests", summary: "Dummy app for tests only", kind: .app,
                           licence: "MIT", versions: [v])
        let data = try JSONEncoder().encode(StoreIndex(addons: [e], serial: 1))
        try data.write(to: tmp.appendingPathComponent("index.json"))
        try key.signature(for: data).base64EncodedString().write(to: tmp.appendingPathComponent("index.json.sig"), atomically: true, encoding: .utf8)
        let source = StoreSource(indexURL: tmp.appendingPathComponent("index.json"), keys: [key.publicKey.rawRepresentation.base64EncodedString()], allowFileURLs: true)
        return (source, try source.loadIndex().entry("dev.gabby.test-app")!)
    }

    func testPreflightRefusesIntelOldMacOSAndLowDiskBeforeWriting() throws {
        let b = try makeBundle()
        let (source, entry) = try signedSource(b)
        let root = tmp.appendingPathComponent("addons")
        let store = AddonStore(root: root, apps: AppHost(root: root, home: home, live: false))
        try store.install(entry, source: source, approve: { _ in true })
        XCTAssertEqual(store.installed("dev.gabby.test-app")?.setup, InstalledAddon.setupPending)
        let cases: [(AppInstaller.Machine, String)] = [
            (.init(arm64: false, macOS: .init(majorVersion: 15, minorVersion: 0, patchVersion: 0)) { _ in 1 << 40 }, "Apple Silicon"),
            (.init(arm64: true, macOS: .init(majorVersion: 13, minorVersion: 6, patchVersion: 0)) { _ in 1 << 40 }, "macOS 14.0 or newer"),
            (.init(arm64: true, macOS: .init(majorVersion: 15, minorVersion: 0, patchVersion: 0)) { _ in 1_000 }, "Not enough free disk"),
        ]
        for (machine, needle) in cases {
            var events: [AppSetupEvent] = []
            let installer = AppInstaller(store: store, host: store.apps) { events.append($0) }
            installer.machine = machine
            XCTAssertThrowsError(try installer.setup("dev.gabby.test-app")) { XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains(needle) == true, needle) }
            XCTAssertEqual(events.last?.step, .failed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("dev.gabby.test-app/build").path))
            XCTAssertTrue(store.installed("dev.gabby.test-app")?.setup?.hasPrefix("failed: ") == true)
        }
    }

    func testSetupBuildsStartsStopsAndUninstallsTheApp() throws {
        let b = try makeBundle()
        let (source, entry) = try signedSource(b)
        let root = tmp.appendingPathComponent("addons")
        let host = AppHost(root: root, home: home, live: false)
        let store = AddonStore(root: root, apps: host)
        try store.install(entry, source: source, approve: { _ in true })
        var events: [AppSetupEvent] = []
        let installer = AppInstaller(store: store, host: host) { events.append($0) }
        installer.installTools = false
        let appURL = try installer.setup("dev.gabby.test-app")

        // Progress is ordered and ends at 1.
        XCTAssertEqual(events.last?.step, .done)
        XCTAssertEqual(events.last?.fraction, 1)
        XCTAssertEqual(events.map(\.fraction), events.map(\.fraction).sorted())
        XCTAssertTrue(events.contains { $0.step == .build && $0.title.contains("step") })
        // The app: signed, the declared files, the helper, the LaunchAgent (written, not loaded).
        XCTAssertEqual(AddonBundle.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path]).status, 0)
        XCTAssertEqual(try String(contentsOf: appURL.appendingPathComponent("Contents/Resources/hello.txt"), encoding: .utf8), "hello")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: host.binURL("dev.gabby.test-app").appendingPathComponent("testctl").path))
        let a = try XCTUnwrap(store.installed("dev.gabby.test-app"))
        XCTAssertEqual(a.setup, InstalledAddon.setupReady)
        XCTAssertEqual(a.status, "on")
        let agent = host.launchAgentURL(app())
        let plist = try XCTUnwrap(NSDictionary(contentsOf: agent))
        XCTAssertEqual(plist["Label"] as? String, "dev.gabby.test-app")
        XCTAssertEqual((plist["ProgramArguments"] as? [String])?.first, host.executableURL("dev.gabby.test-app", app()).path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("dev.gabby.test-app/build").path))

        // Running as its own process; panic stops it and removes the LaunchAgent.
        let p = Process()
        p.executableURL = host.executableURL("dev.gabby.test-app", app())
        try p.run()
        let deadline = Date().addingTimeInterval(5)
        while !host.isRunning("dev.gabby.test-app", app()), Date() < deadline { usleep(50_000) }
        XCTAssertTrue(host.isRunning("dev.gabby.test-app", app()))
        XCTAssertEqual(store.disableAll(), 1)
        p.waitUntilExit()
        XCTAssertFalse(host.isRunning("dev.gabby.test-app", app()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.path))
        XCTAssertEqual(store.installed("dev.gabby.test-app")?.status, "off (panic)")

        // On again: the LaunchAgent comes back. The declared stop command quits it cleanly.
        try store.setEnabled("dev.gabby.test-app", true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.path))
        let q = Process()
        q.executableURL = host.executableURL("dev.gabby.test-app", app())
        try q.run()
        while !host.isRunning("dev.gabby.test-app", app()), Date() < deadline.addingTimeInterval(5) { usleep(50_000) }
        try store.setEnabled("dev.gabby.test-app", false)
        q.waitUntilExit()
        XCTAssertEqual(q.terminationReason, .exit, "stopped by its own quit command, not a signal")

        // Uninstall --purge: app, folder, LaunchAgent and the declared data are gone.
        let data = home.appendingPathComponent("Library/Application Support/TestApp")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try store.uninstall("dev.gabby.test-app", purge: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("dev.gabby.test-app").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: data.path))
    }
}
