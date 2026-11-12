import CaelestiaCore
import XCTest

@testable import CaelestiaShell

/// The Store drawer's model on a fake, in-memory index (dummy entries for tests only).
@MainActor
final class StoreModelTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("storemodel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// A real packed scheme bundle, served from memory.
    func packed(_ id: String = "test.dummy.store") throws -> AddonCreator.Packed {
        let dir = try AddonCreator.scaffold(id: id, kind: .scheme, in: tmp)
        let url = dir.appendingPathComponent(AddonManifest.fileName)
        var m = try AddonManifest.decode(Data(contentsOf: url))
        m.author = "SkyStore tests"
        m.summary = "Dummy entry for tests only"
        try m.encoded().write(to: url)
        return try AddonCreator.pack(dir)
    }

    func model(_ entries: [StoreEntry], policy: AddonPolicy = .current) -> StoreModel {
        let m = StoreModel(addons: AddonStore(root: tmp.appendingPathComponent("addons"), policy: policy))
        let index = StoreIndex(addons: entries)
        m.loadIndex = { _ in index }
        m.source = { _ in StoreSource(indexURL: URL(string: "https://example.invalid/index.json")!, keys: [], allowFileURLs: true) }
        return m
    }

    func entry(_ p: AddonCreator.Packed, kind: AddonKind = .scheme, featured: Bool? = nil, permissions: [String] = [], category: String? = nil) -> StoreEntry {
        StoreEntry(id: p.manifest.id, name: p.manifest.name, author: "SkyStore tests", summary: "Dummy entry for tests only", kind: kind,
                   category: category, licence: "MIT", featured: featured,
                   versions: [StoreVersion(version: "1.0.0", minSkyRose: "0.1.0", url: p.bundle, sha256: p.sha256, size: p.size,
                                           permissions: permissions, released: "2026-11-11")])
    }

    func wait(_ what: String, _ done: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(done(), what)
    }

    func testRefreshListsAndFilters() throws {
        let p = try packed()
        var widget = entry(p, kind: .widget, category: "Bar modules")
        widget.id = "test.dummy.widget"
        widget.name = "Widget dummy"
        let m = model([entry(p, featured: true), widget])
        m.prepare()
        wait("index loads") { m.index != nil }
        XCTAssertEqual(m.visible.map(\.id), ["test.dummy.store"], "featured first")
        m.tab = .categories
        XCTAssertEqual(m.shelves, ["Bar modules", "Colour scheme"])
        XCTAssertEqual(m.visible.map(\.id), ["test.dummy.widget"])
        m.query = "widget"
        XCTAssertEqual(m.visible.map(\.id), ["test.dummy.widget"])
        XCTAssertEqual(m.action(for: widget), .notSupported)
        XCTAssertEqual(m.action(for: m.entry("test.dummy.store")!), .install)
    }

    func testInstallToggleUninstall() throws {
        let p = try packed()
        let m = model([entry(p)])
        var changed = 0
        m.onContentChanged = { changed += 1 }
        m.prepare()
        wait("index loads") { m.index != nil }
        let e = m.entry("test.dummy.store")!
        m.install(e)
        XCTAssertNotNil(m.busy[e.id])
        wait("installs") { m.busy[e.id] == nil }
        XCTAssertNil(m.errors[e.id])
        XCTAssertEqual(m.action(for: e), .installed)
        XCTAssertEqual(m.addons.schemes().map(\.theme), ["test.dummy.store/store"])
        m.setEnabled(e.id, false)
        XCTAssertEqual(m.installed(e.id)?.disabled, .user)
        m.uninstall(e.id)
        XCTAssertEqual(m.confirming, e.id, "first press arms")
        XCTAssertNotNil(m.installed(e.id))
        m.uninstall(e.id)
        XCTAssertNil(m.installed(e.id))
        XCTAssertGreaterThanOrEqual(changed, 3)
    }

    func testNewPermissionsNeedASecondPress() throws {
        let p = try packed()
        let m = model([entry(p, permissions: ["notifications"])], policy: AddonPolicy(installable: [.scheme: [.notifications]]))
        m.prepare()
        wait("index loads") { m.index != nil }
        let e = m.entry("test.dummy.store")!
        m.install(e)
        XCTAssertEqual(m.confirming, e.id)
        XCTAssertNil(m.busy[e.id], "nothing runs before the second press")
        XCTAssertEqual(m.permissionDiff(for: e)?.added, [AddonPermission(.notifications)])
        m.install(e)
        XCTAssertNil(m.confirming)
        wait("installs") { m.busy[e.id] == nil }
        // The manifest lists no permissions but the index does: refused as a mismatch, nothing installed.
        XCTAssertNotNil(m.errors[e.id])
        XCTAssertNil(m.installed(e.id))
    }

    func testIndexErrorIsShown() {
        let m = model([])
        m.loadIndex = { _ in throw StoreError.noTrustedKey }
        m.prepare()
        wait("fails") { !m.loading && m.indexError != nil }
        XCTAssertEqual(m.indexError, StoreError.noTrustedKey.errorDescription)
    }

    func testRevocationOnRefreshTellsTheShell() throws {
        let p = try packed()
        let m = model([entry(p)])
        m.prepare()
        wait("index loads") { m.index != nil }
        m.install(m.entry("test.dummy.store")!)
        wait("installs") { m.installed("test.dummy.store") != nil }
        var revoked = entry(p)
        revoked.revoked = "test revocation"
        let index = StoreIndex(addons: [revoked])
        m.loadIndex = { _ in index }
        var told: [String] = []
        m.onRevoked = { told = $0.map(\.id) }
        m.refresh()
        wait("revoked") { !told.isEmpty }
        XCTAssertEqual(m.action(for: revoked), .revoked("test revocation"))
    }

    func testEscapeLeavesDetailThenCloses() {
        let m = model([])
        var closed = false
        m.onClose = { closed = true }
        m.open("x")
        let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                   characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        XCTAssertTrue(m.key(esc))
        XCTAssertNil(m.selected)
        XCTAssertFalse(closed)
        XCTAssertTrue(m.key(esc))
        XCTAssertTrue(closed)
    }

    func testStoreIsALauncherCommandAndDrawer() {
        XCTAssertTrue(LauncherCommand.all.contains { $0.name == "store" && $0.effect == .drawer(.store) })
        XCTAssertEqual(Drawer(rawValue: "store"), .store)
    }

    /// App addons: the drawer runs `skyrose store setup --json` out of process and shows its lines.
    func testAppSetupRunsOutOfProcessAndShowsLiveProgress() throws {
        let m = model([])
        let lines = [AppSetupEvent(.download, "Downloading llama.cpp", fraction: 0.2, bytes: 4_000_000, total: 16_000_000, bytesPerSecond: 2_000_000, eta: 6),
                     AppSetupEvent(.done, "Test App is ready", fraction: 1)].map(\.jsonLine).joined(separator: "\n")
        let script = tmp.appendingPathComponent("fake-setup.sh")
        try "#!/bin/sh\ncat <<'JSON'\n\(lines)\nJSON\nsleep 0.5\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var asked: String?
        m.setupCommand = { id in asked = id; return (script, []) }
        m.runSetup("dev.gabby.test-app")
        XCTAssertEqual(asked, "dev.gabby.test-app")
        wait("download line shows") { m.busy["dev.gabby.test-app"]?.detail?.contains("of") == true || m.busy["dev.gabby.test-app"]?.fraction == 1 }
        wait("finishes") { m.busy["dev.gabby.test-app"] == nil }
        XCTAssertNil(m.errors["dev.gabby.test-app"])

        let failing = tmp.appendingPathComponent("fail.sh")
        try "#!/bin/sh\necho '\(AppSetupEvent(.failed, "This Mac has an Intel processor.", fraction: 0).jsonLine)'\nexit 1\n".write(to: failing, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: failing.path)
        m.setupCommand = { _ in (failing, []) }
        m.runSetup("dev.gabby.test-app")
        wait("fails") { m.busy["dev.gabby.test-app"] == nil }
        XCTAssertEqual(m.errors["dev.gabby.test-app"]?.contains("Intel"), true)
    }
}
