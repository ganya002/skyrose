import Foundation
import XCTest

@testable import CaelestiaShell

final class AppIndexTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("caelestia-appindex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeApp(in dir: URL, file: String, name: String? = nil, id: String? = nil, category: String? = nil,
                         extra: [String: Any] = [:]) throws -> URL {
        let app = dir.appendingPathComponent("\(file).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundlePackageType": "APPL"]
        if let name { info["CFBundleName"] = name }
        if let id { info["CFBundleIdentifier"] = id }
        if let category { info["LSApplicationCategoryType"] = category }
        for (k, v) in extra { info[k] = v }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func testCategoryName() {
        XCTAssertEqual(AppIndex.categoryName("public.app-category.developer-tools"), "Developer Tools")
        XCTAssertEqual(AppIndex.categoryName("public.app-category.music"), "Music")
        XCTAssertEqual(AppIndex.categoryName("games"), "Games")
        XCTAssertEqual(AppIndex.categoryName(""), "")
    }

    func testReadBundle() throws {
        let url = try makeApp(in: root, file: "Fake", name: "Fake Name", id: "com.test.fake", category: "public.app-category.developer-tools")
        let app = try XCTUnwrap(AppIndex.read(url))
        XCTAssertEqual(app.name, "Fake Name")
        XCTAssertEqual(app.bundleID, "com.test.fake")
        XCTAssertEqual(app.id, "com.test.fake")
        XCTAssertEqual(app.description, "Developer Tools")
        XCTAssertTrue(app.keywords.contains("Developer Tools"))
        XCTAssertTrue(app.keywords.contains("Fake"), "file name differs from the display name")
        XCTAssertEqual(app.launchCount, 0)
    }

    func testReadFallsBackToFileNameAndSkipsDuplicateKeyword() throws {
        let url = try makeApp(in: root, file: "NoName", id: "com.test.noname")
        let app = try XCTUnwrap(AppIndex.read(url))
        XCTAssertEqual(app.name, "NoName")
        XCTAssertEqual(app.keywords, [])
        XCTAssertEqual(app.description, "")
    }

    func testReadKnownDescription() throws {
        let url = try makeApp(in: root, file: "FF", name: "FF", id: "org.mozilla.firefox")
        XCTAssertEqual(AppIndex.read(url)?.description, "Fast and private browser")
    }

    func testAgentAndBackgroundAppsSkipped() throws {
        let a = try makeApp(in: root, file: "Agent", name: "Agent", id: "com.test.agent", extra: ["LSUIElement": true])
        let b = try makeApp(in: root, file: "AgentS", name: "AgentS", id: "com.test.agents", extra: ["LSUIElement": "1"])
        let c = try makeApp(in: root, file: "Bg", name: "Bg", id: "com.test.bg", extra: ["LSBackgroundOnly": true])
        XCTAssertNil(AppIndex.read(a))
        XCTAssertNil(AppIndex.read(b))
        XCTAssertNil(AppIndex.read(c))
    }

    func testReadNonBundleIsNil() {
        XCTAssertNil(AppIndex.read(root.appendingPathComponent("nothing.app")))
    }

    func testScanDepthDedupeAndCounts() throws {
        try makeApp(in: root, file: "Top", name: "Top", id: "com.test.top")
        let folder = root.appendingPathComponent("Folder")
        let deeper = folder.appendingPathComponent("Deeper")
        try FileManager.default.createDirectory(at: deeper, withIntermediateDirectories: true)
        try makeApp(in: folder, file: "OneDeep", name: "One Deep", id: "com.test.one")
        try makeApp(in: deeper, file: "TwoDeep", name: "Two Deep", id: "com.test.two")
        try makeApp(in: folder, file: "TopDup", name: "Top Copy", id: "com.test.top")  // same bundle id
        try makeApp(in: root, file: "UIElement", name: "Hidden", id: "com.test.hidden", extra: ["LSUIElement": true])
        let apps = AppIndex.scan(roots: [root], counts: ["com.test.one": 7])
        XCTAssertEqual(Set(apps.map(\.bundleID)), ["com.test.top", "com.test.one"])
        XCTAssertEqual(apps.count, 2, "deduped by bundle id")
        XCTAssertEqual(apps.first { $0.bundleID == "com.test.one" }?.launchCount, 7)
        XCTAssertEqual(apps.first { $0.bundleID == "com.test.top" }?.launchCount, 0)
        XCTAssertFalse(apps.contains { $0.bundleID == "com.test.two" }, "two levels deep is not scanned")
    }

    func testScanSortedByNameAndMultipleRootsDedupe() throws {
        let r1 = root.appendingPathComponent("first")
        let r2 = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: r1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: r2, withIntermediateDirectories: true)
        try makeApp(in: r1, file: "b", name: "banana", id: "com.test.b")
        try makeApp(in: r1, file: "a", name: "Apple", id: "com.test.a")
        try makeApp(in: r2, file: "a2", name: "Apple again", id: "com.test.a")
        try makeApp(in: r2, file: "c", name: "Cherry", id: "com.test.c")
        let apps = AppIndex.scan(roots: [r1, r2, root.appendingPathComponent("missing")])
        XCTAssertEqual(apps.map(\.name), ["Apple", "banana", "Cherry"])
    }

    func testAppsWithoutBundleIDUsePathAsID() throws {
        let url = try makeApp(in: root, file: "NoID", name: "NoID")
        let app = try XCTUnwrap(AppIndex.read(url))
        XCTAssertEqual(app.bundleID, "")
        XCTAssertEqual(app.id, url.path)
    }
}
