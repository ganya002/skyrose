import CryptoKit
import Foundation
import XCTest
@testable import CaelestiaCore

/// SkyStore against a local, signed fake index (file:// only; nothing touches the network).
/// Every entry here is a clearly labelled test dummy.
final class SkyStoreTests: XCTestCase {
    var tmp: URL!
    var key: Curve25519.Signing.PrivateKey!
    var pub: String { key.publicKey.rawRepresentation.base64EncodedString() }

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skystore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        key = Curve25519.Signing.PrivateKey()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    // MARK: Fixtures

    func schemeTOML(_ name: String) -> String {
        var s = SchemeLoader.builtIn(named: "skyrose-default")!
        s.name = name
        return SchemeLoader.serialize(s)
    }

    /// A `.skyaddon` zip built by hand (not by `pack`), so tests can break it on purpose.
    func bundle(id: String = "test.dummy.scheme", version: String = "1.0.0", kind: AddonKind = .scheme, permissions: [String] = [],
                manifestVersion: String? = nil, unlisted: Bool = false, badFileHash: Bool = false) throws -> (url: URL, sha: String, size: Int) {
        let dir = tmp.appendingPathComponent("src-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("schemes"), withIntermediateDirectories: true)
        let body = Data(schemeTOML("dummy").utf8)
        try body.write(to: dir.appendingPathComponent("schemes/dummy.toml"))
        if unlisted { try Data("x".utf8).write(to: dir.appendingPathComponent("extra.txt")) }
        let m = AddonManifest(id: id, name: "Test Dummy Scheme", author: "SkyStore tests", version: manifestVersion ?? version, minSkyRose: "0.1.0",
                              kind: kind, summary: "Dummy entry for tests only", licence: "MIT", permissions: permissions,
                              entry: .init(schemes: ["schemes/dummy.toml"]),
                              files: ["schemes/dummy.toml": badFileHash ? String(repeating: "0", count: 64) : body.sha256Hex])
        try m.encoded().write(to: dir.appendingPathComponent(AddonManifest.fileName))
        let out = tmp.appendingPathComponent("\(id)-\(version)-\(UUID().uuidString).skyaddon")
        XCTAssertEqual(AddonBundle.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", dir.path, out.path]).status, 0)
        let data = try Data(contentsOf: out)
        return (out, data.sha256Hex, data.count)
    }

    func version(_ b: (url: URL, sha: String, size: Int), _ v: String = "1.0.0", permissions: [String] = [], sha: String? = nil,
                 revoked: String? = nil) -> StoreVersion {
        StoreVersion(version: v, minSkyRose: "0.1.0", url: b.url, sha256: sha ?? b.sha, size: b.size, permissions: permissions,
                     released: "2026-11-11", revoked: revoked)
    }

    func entry(_ versions: [StoreVersion], id: String = "test.dummy.scheme", revoked: String? = nil) -> StoreEntry {
        StoreEntry(id: id, name: "Test Dummy Scheme", author: "SkyStore tests", summary: "Dummy entry for tests only", kind: .scheme,
                   licence: "MIT", revoked: revoked, versions: versions)
    }

    /// Writes and signs `index.json`; returns a source that trusts only the test key.
    func publish(_ entries: [StoreEntry], signWith signer: Curve25519.Signing.PrivateKey? = nil, tamper: Bool = false, serial: Int? = nil) throws -> StoreSource {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        let data = try e.encode(StoreIndex(addons: entries, serial: serial))
        let url = tmp.appendingPathComponent("index.json")
        try (tamper ? data + Data(" ".utf8) : data).write(to: url)
        try (try (signer ?? key).signature(for: data)).base64EncodedString().write(to: tmp.appendingPathComponent("index.json.sig"), atomically: true, encoding: .utf8)
        return StoreSource(indexURL: url, keys: [pub], allowFileURLs: true)
    }

    func store(_ policy: AddonPolicy = .current) -> AddonStore { AddonStore(root: tmp.appendingPathComponent("addons"), policy: policy) }

    func yes(_: PermissionDiff) -> Bool { true }

    // MARK: Manifest

    func testManifestRoundTripAndIssues() throws {
        let m = AddonManifest(id: "dev.you.rose", name: "Rose", author: "You", version: "1.2.0", minSkyRose: "0.4.0", kind: .scheme,
                              summary: "A theme", licence: "MIT", entry: .init(schemes: ["schemes/rose.toml"]),
                              files: ["schemes/rose.toml": String(repeating: "a", count: 64)])
        XCTAssertEqual(try AddonManifest.decode(m.encoded()), m)
        XCTAssertEqual(AddonPolicy.current.issues(m), [])
    }

    func testManifestMissingKeyIsNamed() {
        XCTAssertThrowsError(try AddonManifest.decode(Data(#"{"schema":1,"id":"a.b"}"#.utf8))) { e in
            guard case StoreError.badManifest(let why) = e else { return XCTFail("\(e)") }
            XCTAssertTrue(why.hasPrefix("missing "), why)
        }
        XCTAssertThrowsError(try AddonManifest.decode(Data("not json".utf8)))
    }

    func testManifestRejectsBadFields() {
        var m = AddonManifest(id: "Bad ID", name: "", author: "x", version: "1.x", minSkyRose: "0.4", kind: .scheme, summary: "s", licence: "MIT",
                              homepage: "http://example.com", permissions: ["network", "telepathy"], entry: .init(schemes: ["../evil.toml"]))
        let issues = m.issues().joined(separator: "\n")
        for needle in ["id 'Bad ID'", "name must not be empty", "version '1.x'", "homepage must be an https", "unknown permission 'network'",
                       "unknown permission 'telepathy'", "path '../evil.toml'", "is not in files"] {
            XCTAssertTrue(issues.contains(needle), "missing: \(needle)\n\(issues)")
        }
        m.kind = .wallpaper
        XCTAssertTrue(m.issues().contains("entry.wallpapers must list at least one image or video"))
    }

    func testPolicyRefusesCodeKindsAndPermissionsOnDataKinds() {
        XCTAssertTrue(AddonPolicy.current.issues(kind: .widget, permissions: [])[0].contains("run code"))
        XCTAssertTrue(AddonPolicy.current.issues(kind: .keymap, permissions: [])[0].contains("run code"))
        XCTAssertEqual(AddonPolicy.current.issues(kind: .scheme, permissions: [AddonPermission(.notifications)]),
                       ["a scheme addon is data only and cannot ask for permissions"])
        XCTAssertEqual(AddonPolicy.current.issues(kind: .wallpaper, permissions: []), [])
    }

    func testSafePaths() {
        for p in ["a.toml", "schemes/a.toml", "a/b/c.png"] { XCTAssertTrue(AddonManifest.isSafePath(p), p) }
        for p in ["", "/etc/passwd", "../a", "a/../../b", "~/x", "a//b", "./a", "a\\b"] { XCTAssertFalse(AddonManifest.isSafePath(p), p) }
    }

    // MARK: Permissions

    func testPermissionParsing() {
        XCTAssertEqual(AddonPermission("network:api.example.com"), AddonPermission(.network, scope: "api.example.com"))
        XCTAssertEqual(AddonPermission("notifications"), AddonPermission(.notifications))
        XCTAssertNil(AddonPermission("network"))
        XCTAssertNil(AddonPermission("notifications:x"))
        XCTAssertNil(AddonPermission("files:"))
        XCTAssertNil(AddonPermission("root"))
    }

    func testPermissionDiff() {
        let n = AddonPermission(.notifications), m = AddonPermission(.media), net = AddonPermission(.network, scope: "a.com")
        let d = PermissionDiff(granted: [n, m], requested: [n, net])
        XCTAssertEqual(d.added, [net])
        XCTAssertEqual(d.removed, [m])
        XCTAssertEqual(d.kept, [n])
        XCTAssertTrue(d.grows)
        XCTAssertFalse(PermissionDiff(granted: [n, m], requested: [m]).grows)
        XCTAssertFalse(PermissionDiff(granted: [], requested: []).grows)
    }

    // MARK: Index verification

    func testSignedIndexLoads() throws {
        let b = try bundle()
        let index = try publish([entry([version(b)])]).loadIndex()
        XCTAssertEqual(index.addons.map(\.id), ["test.dummy.scheme"])
    }

    func testTamperedIndexIsRefused() throws {
        let b = try bundle()
        XCTAssertThrowsError(try publish([entry([version(b)])], tamper: true).loadIndex()) { XCTAssertEqual($0 as? StoreError, .badSignature) }
    }

    func testIndexSignedByOtherKeyIsRefused() throws {
        let b = try bundle()
        XCTAssertThrowsError(try publish([entry([version(b)])], signWith: Curve25519.Signing.PrivateKey()).loadIndex()) {
            XCTAssertEqual($0 as? StoreError, .badSignature)
        }
    }

    func testNoTrustedKeyRefusesEverything() throws {
        var source = try publish([])
        source.keys = []
        XCTAssertThrowsError(try source.loadIndex()) { XCTAssertEqual($0 as? StoreError, .noTrustedKey) }
        XCTAssertFalse(StoreSource.trustedKeys.isEmpty, "Gabby's maintainer key is built in")
        XCTAssertTrue(StoreSource.trustedKeys.allSatisfy { Data(base64Encoded: $0).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) } != nil })
    }

    func testOlderIndexIsRefused() throws {
        let serials = tmp.appendingPathComponent("serial")
        var newer = try publish([], serial: 5)
        newer.serialFile = serials
        XCTAssertNoThrow(try newer.loadIndex())
        XCTAssertNoThrow(try newer.loadIndex(), "the same index again is fine")
        var replay = try publish([], serial: 4)
        replay.serialFile = serials
        XCTAssertThrowsError(try replay.loadIndex()) { XCTAssertEqual($0 as? StoreError, .staleIndex(got: 4, seen: 5)) }
        var legacy = try publish([])
        legacy.serialFile = serials
        XCTAssertThrowsError(try legacy.loadIndex(), "no serial counts as 0")
        var next = try publish([], serial: 6)
        next.serialFile = serials
        XCTAssertNoThrow(try next.loadIndex())
    }

    func testOnlyHTTPSOutsideCreatorMode() throws {
        var c = StoreConfig()
        XCTAssertEqual(StoreSource.from(c).indexURL.absoluteString, StoreSource.defaultIndexURL)
        c.indexURL = "file:///tmp/index.json"
        c.trustedKeys = [pub]
        let s = StoreSource.from(c)
        XCTAssertThrowsError(try s.check(s.indexURL)) { XCTAssertEqual($0 as? StoreError, .insecureURL("file:///tmp/index.json")) }
        XCTAssertEqual(s.keys, StoreSource.trustedKeys, "extra keys only count in creator mode")
        c.creatorMode = true
        XCTAssertNoThrow(try StoreSource.from(c).check(URL(string: "file:///tmp/index.json")!))
        XCTAssertEqual(StoreSource.from(c).keys, StoreSource.trustedKeys + [pub])
        XCTAssertThrowsError(try StoreSource.from(c).check(URL(string: "http://example.com/a.skyaddon")!))
    }

    func testIndexWithRepeatedIDIsRefused() throws {
        let b = try bundle()
        XCTAssertThrowsError(try publish([entry([version(b)]), entry([version(b)])]).loadIndex()) {
            guard case StoreError.badIndex = $0 else { return XCTFail("\($0)") }
        }
    }

    // MARK: Install / update / rollback

    func testInstallVerifiesAndExposesTheScheme() throws {
        let b = try bundle()
        let source = try publish([entry([version(b)])])
        let s = store()
        var steps: [StoreProgress.Step] = []
        let a = try s.install(try source.loadIndex().addons[0], source: source, approve: { _ in XCTFail("no permissions to ask for"); return false },
                              progress: { steps.append($0.step) })
        XCTAssertEqual(steps, StoreProgress.Step.allCases)
        XCTAssertEqual(a.version, "1.0.0")
        XCTAssertTrue(a.enabled)
        XCTAssertEqual(s.installed().map(\.id), ["test.dummy.scheme"])
        XCTAssertEqual(s.schemes().map(\.theme), ["test.dummy.scheme/dummy"])
        XCTAssertEqual(s.scheme(named: "test.dummy.scheme/dummy")?.name, "dummy")
        XCTAssertNil(s.scheme(named: "skyrose-default"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: s.root.path).filter { $0.hasPrefix(".staging") }
        XCTAssertEqual(leftovers, [])
    }

    func testChecksumMismatchInstallsNothing() throws {
        let b = try bundle()
        let source = try publish([entry([version(b, sha: String(repeating: "f", count: 64))])])
        let s = store()
        XCTAssertThrowsError(try s.install(try source.loadIndex().addons[0], source: source, approve: yes)) {
            guard case StoreError.checksumMismatch = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(s.installed(), [])
    }

    func testBundleThatDisagreesWithTheIndexIsRefused() throws {
        let b = try bundle(manifestVersion: "9.9.9")
        let source = try publish([entry([version(b)])])
        let s = store()
        XCTAssertThrowsError(try s.install(try source.loadIndex().addons[0], source: source, approve: yes)) {
            guard case StoreError.mismatch = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(s.installed(), [])
    }

    func testUnlistedFileAndBadFileHashAreRefused() throws {
        for (b, expect) in [(try bundle(unlisted: true), "unsafe"), (try bundle(badFileHash: true), "checksum")] {
            let source = try publish([entry([version(b)])])
            let s = store()
            XCTAssertThrowsError(try s.install(try source.loadIndex().addons[0], source: source, approve: yes)) { e in
                switch (e as? StoreError, expect) {
                case (.unsafeBundle?, "unsafe"), (.checksumMismatch?, "checksum"): break
                default: XCTFail("\(e)")
                }
            }
            XCTAssertEqual(s.installed(), [])
        }
    }

    func testNotAZipIsRefused() throws {
        let junk = tmp.appendingPathComponent("junk.skyaddon")
        try Data("not a zip".utf8).write(to: junk)
        let data = try Data(contentsOf: junk)
        let source = try publish([entry([version((junk, data.sha256Hex, data.count))])])
        XCTAssertThrowsError(try store().install(try source.loadIndex().addons[0], source: source, approve: yes)) {
            XCTAssertEqual($0 as? StoreError, .unsafeBundle("not a zip archive"))
        }
    }

    func testUpdateReplacesTheOldVersion() throws {
        let b1 = try bundle(version: "1.0.0"), b2 = try bundle(version: "1.1.0")
        let s = store()
        var source = try publish([entry([version(b1)])])
        let v1 = try s.install(try source.loadIndex().addons[0], source: source, approve: yes)
        source = try publish([entry([version(b1), version(b2, "1.1.0")])])
        let index = try source.loadIndex()
        XCTAssertEqual(s.updates(index).map(\.version.version), ["1.1.0"])
        let v2 = try s.install(index.addons[0], source: source, approve: yes)
        XCTAssertEqual(s.installed(id: "test.dummy.scheme")?.version, "1.1.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.directory(for: v1).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.directory(for: v2).path))
        XCTAssertEqual(s.updates(index).count, 0)
    }

    func testFailedUpdateRollsBackToTheInstalledVersion() throws {
        let b1 = try bundle(version: "1.0.0"), bad = try bundle(version: "1.1.0", badFileHash: true)
        let s = store()
        var source = try publish([entry([version(b1)])])
        let v1 = try s.install(try source.loadIndex().addons[0], source: source, approve: yes)
        source = try publish([entry([version(b1), version(bad, "1.1.0")])])
        XCTAssertThrowsError(try s.install(try source.loadIndex().addons[0], source: source, approve: yes))
        XCTAssertEqual(s.installed(), [v1])
        XCTAssertEqual(s.schemes().map(\.theme), ["test.dummy.scheme/dummy"], "the old files still work")
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.root.appendingPathComponent("test.dummy.scheme/1.1.0").path))
    }

    func testPermissionGrowthAsksAgainAndDeclineKeepsTheOldVersion() throws {
        // A policy that lets schemes ask for a permission, so the prompt path runs end to end.
        let policy = AddonPolicy(installable: [.scheme: [.network, .notifications]])
        let s = store(policy)
        let b1 = try bundle(version: "1.0.0", permissions: ["notifications"])
        let b2 = try bundle(version: "2.0.0", permissions: ["notifications", "network:api.example.com"])
        var source = try publish([entry([version(b1, permissions: ["notifications"])])])
        var asked: [PermissionDiff] = []
        _ = try s.install(try source.loadIndex().addons[0], source: source, approve: { asked.append($0); return true })
        XCTAssertEqual(asked.map(\.added), [[AddonPermission(.notifications)]], "a first install asks for everything")

        source = try publish([entry([version(b1, permissions: ["notifications"]), version(b2, "2.0.0", permissions: ["notifications", "network:api.example.com"])])])
        asked = []
        XCTAssertThrowsError(try s.install(try source.loadIndex().addons[0], source: source, approve: { asked.append($0); return false })) {
            XCTAssertEqual($0 as? StoreError, .permissionsDeclined)
        }
        XCTAssertEqual(asked.first?.added, [AddonPermission(.network, scope: "api.example.com")])
        XCTAssertEqual(asked.first?.kept, [AddonPermission(.notifications)])
        XCTAssertEqual(s.installed(id: "test.dummy.scheme")?.version, "1.0.0")

        _ = try s.install(try source.loadIndex().addons[0], source: source, approve: yes)
        XCTAssertEqual(s.installed(id: "test.dummy.scheme")?.permissions, ["network:api.example.com", "notifications"])
    }

    func testCurrentPolicyRefusesAPermissionOnAScheme() throws {
        let b = try bundle(permissions: ["notifications"])
        let source = try publish([entry([version(b, permissions: ["notifications"])])])
        XCTAssertThrowsError(try store().install(try source.loadIndex().addons[0], source: source, approve: yes)) {
            guard case StoreError.notInstallable = $0 else { return XCTFail("\($0)") }
        }
    }

    func testTooNewVersionIsSkipped() throws {
        let b = try bundle()
        var v = version(b)
        v.minSkyRose = "99.0.0"
        XCTAssertNil(entry([v]).latest(for: "0.4.0"))
        let source = try publish([entry([v])])
        XCTAssertThrowsError(try store().install(try source.loadIndex().addons[0], source: source, approve: yes)) {
            guard case StoreError.incompatible = $0 else { return XCTFail("\($0)") }
        }
    }

    // MARK: Kill switch, panic, uninstall

    func testRevocationDisablesAndCannotBeUndone() throws {
        let b = try bundle()
        let s = store()
        var source = try publish([entry([version(b)])])
        _ = try s.install(try source.loadIndex().addons[0], source: source, approve: yes)
        source = try publish([entry([version(b)], revoked: "malware (test)")])
        let hit = s.applyRevocations(try source.loadIndex())
        XCTAssertEqual(hit.map(\.id), ["test.dummy.scheme"])
        XCTAssertEqual(s.installed(id: "test.dummy.scheme")?.disabled, .revoked("malware (test)"))
        XCTAssertEqual(s.schemes().count, 0)
        XCTAssertThrowsError(try s.setEnabled("test.dummy.scheme", true)) { XCTAssertEqual($0 as? StoreError, .revoked("malware (test)")) }
        XCTAssertThrowsError(try s.install(try source.loadIndex().addons[0], source: source, approve: yes))
        XCTAssertEqual(s.applyRevocations(try source.loadIndex()), [], "only reported once")
    }

    func testRevokedVersionOnly() throws {
        let b = try bundle()
        let s = store()
        var source = try publish([entry([version(b)])])
        _ = try s.install(try source.loadIndex().addons[0], source: source, approve: yes)
        source = try publish([entry([version(b, revoked: "broken build")])])
        XCTAssertEqual(s.applyRevocations(try source.loadIndex()).count, 1)
    }

    func testPanicDisablesEverythingAndEnableTurnsItBack() throws {
        let b = try bundle()
        let s = store()
        let source = try publish([entry([version(b)])])
        _ = try s.install(try source.loadIndex().addons[0], source: source, approve: yes)
        XCTAssertEqual(s.disableAll(), 1)
        XCTAssertEqual(s.installed(id: "test.dummy.scheme")?.disabled, .panic)
        XCTAssertEqual(s.schemes().count, 0)
        XCTAssertEqual(s.disableAll(), 0)
        try s.setEnabled("test.dummy.scheme", true)
        XCTAssertEqual(s.schemes().count, 1)
        XCTAssertEqual(AddonStore(root: tmp.appendingPathComponent("none")).disableAll(), 0, "no addons: nothing to do, no throw")
    }

    func testUninstallRemovesFiles() throws {
        let b = try bundle()
        let s = store()
        let source = try publish([entry([version(b)])])
        let a = try s.install(try source.loadIndex().addons[0], source: source, approve: yes)
        try s.uninstall(a.id)
        XCTAssertEqual(s.installed(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.root.appendingPathComponent(a.id).path))
        XCTAssertThrowsError(try s.uninstall(a.id)) { XCTAssertEqual($0 as? StoreError, .notFound(a.id)) }
    }

    func testSchemeResolverFindsBuiltInsFirst() {
        var a = AppearanceConfig()
        a.theme = "catppuccin-mocha"
        XCTAssertEqual(SchemeResolver.staticScheme(a)?.name, SchemeLoader.builtIn(named: "catppuccin-mocha")?.name)
        a.theme = "not.installed/x"
        XCTAssertEqual(SchemeResolver.staticScheme(a)?.name, SchemeLoader.builtIn(named: "skyrose-dynamic")?.name)
    }

    // MARK: Creator mode

    func testCreatorScaffoldValidatePackSubmit() throws {
        let dir = try AddonCreator.scaffold(id: "test.dummy.creator", kind: .scheme, in: tmp)
        XCTAssertThrowsError(try AddonCreator.scaffold(id: "test.dummy.creator", kind: .scheme, in: tmp))
        let first = AddonCreator.validate(dir)
        XCTAssertTrue(first.contains("author must not be empty"), "\(first)")
        XCTAssertTrue(first.contains("summary must not be empty"), "\(first)")

        let mURL = dir.appendingPathComponent(AddonManifest.fileName)
        var m = try AddonManifest.decode(Data(contentsOf: mURL))
        m.author = "SkyStore tests"
        m.summary = "Dummy entry for tests only"
        try m.encoded().write(to: mURL)
        try Data().write(to: dir.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(AddonCreator.validate(dir), [])

        let packed = try AddonCreator.pack(dir)
        XCTAssertEqual(packed.bundle.lastPathComponent, "test.dummy.creator-1.0.0.skyaddon")
        XCTAssertEqual(Updater.expectedHash(try String(contentsOfFile: packed.bundle.path + ".sha256", encoding: .utf8)), packed.sha256)
        XCTAssertEqual(AddonCreator.validate(dir), [], "dist/ is not part of the bundle")
        try Data("tampered".utf8).write(to: packed.bundle)
        XCTAssertTrue(AddonCreator.validate(dir).contains { $0.contains(".sha256 does not match") })
        let repacked = try AddonCreator.pack(dir)

        // The packed bundle installs from a fake index.
        let source = try publish([StoreEntry(id: m.id, name: m.name, author: m.author, summary: m.summary, kind: .scheme, licence: "MIT",
                                             versions: [version((repacked.bundle, repacked.sha256, repacked.size))])])
        let a = try store().install(try source.loadIndex().addons[0], source: source, approve: yes)
        XCTAssertEqual(store().schemes().map(\.theme), ["test.dummy.creator/creator"])
        XCTAssertEqual(a.sha256, repacked.sha256)

        let sub = try AddonCreator.submission(repacked, repo: "someone/my-addons", released: Date(timeIntervalSince1970: 1_794_355_200))
        XCTAssertEqual(Array(sub.releaseCommand.prefix(4)), ["gh", "release", "create", "test.dummy.creator-v1.0.0"])
        XCTAssertTrue(sub.releaseCommand.contains("someone/my-addons"))
        let q = URLComponents(url: sub.pullRequestURL, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(q.path, "/ganya002/skystore-index/new/main")
        XCTAssertEqual(q.queryItems?.first { $0.name == "filename" }?.value, "submissions/test.dummy.creator-1.0.0.json")
        let posted = try JSONDecoder().decode(StoreEntry.self, from: Data((q.queryItems?.first { $0.name == "value" }?.value ?? "").utf8))
        XCTAssertEqual(posted.versions.first?.url.absoluteString,
                       "https://github.com/someone/my-addons/releases/download/test.dummy.creator-v1.0.0/test.dummy.creator-1.0.0.skyaddon")
        XCTAssertEqual(posted.versions.first?.sha256, repacked.sha256)
        XCTAssertEqual(posted.versions.first?.released, "2026-11-11")
        XCTAssertThrowsError(try AddonCreator.submission(repacked, repo: "not a repo"))
    }

    func testScaffoldRefusesCodeKinds() {
        XCTAssertThrowsError(try AddonCreator.scaffold(id: "test.dummy.widget", kind: .widget, in: tmp))
        XCTAssertThrowsError(try AddonCreator.scaffold(id: "Bad", kind: .scheme, in: tmp))
    }

    // MARK: Builtin features

    func testBuiltinFeaturesSeedOnceAndUninstallSticks() throws {
        let s = store()
        XCTAssertTrue(s.featureEnabled(BuiltinFeature.clamshell.id), "on after an update")
        XCTAssertEqual(s.installed().filter { $0.kind == .feature }.count, BuiltinFeature.all.count)
        try s.uninstall(BuiltinFeature.clamshell.id)
        s.seedBuiltinFeatures()
        XCTAssertFalse(s.featureEnabled(BuiltinFeature.clamshell.id), "an uninstall is not undone by the next seed")
        try s.installBuiltin(BuiltinFeature.clamshell.id)
        XCTAssertTrue(s.featureEnabled(BuiltinFeature.clamshell.id))
        try s.setEnabled(BuiltinFeature.clamshell.id, false)
        XCTAssertFalse(s.featureEnabled(BuiltinFeature.clamshell.id))
        try s.installBuiltin(BuiltinFeature.clamshell.id)
        XCTAssertFalse(s.featureEnabled(BuiltinFeature.clamshell.id), "install keeps a switched-off record off")
        try s.setEnabled(BuiltinFeature.clamshell.id, true)
        XCTAssertEqual(s.disableAll(), BuiltinFeature.all.count)
        XCTAssertFalse(s.featureEnabled(BuiltinFeature.colorPicker.id), "panic switches features off too")
        XCTAssertThrowsError(try s.installBuiltin("skyrose.nope"))
    }

}

private extension AddonStore {
    func installed(id: String) -> InstalledAddon? { installed(id) }
}
