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
        let apps = AppIndex.scan(roots: [root], pinned: [], counts: ["com.test.one": 7])
        XCTAssertEqual(Set(apps.map(\.bundleID)), ["com.test.top", "com.test.one", "com.test.two"])
        XCTAssertEqual(apps.count, 3, "deduped by bundle id")
        XCTAssertEqual(apps.first { $0.bundleID == "com.test.one" }?.launchCount, 7)
        XCTAssertEqual(apps.first { $0.bundleID == "com.test.top" }?.launchCount, 0)
        XCTAssertTrue(apps.contains { $0.bundleID == "com.test.two" }, "sub-folders are scanned")
    }

    func testScanStopsAtMaxDepthAndNeverEntersBundles() throws {
        var dir = root!
        for level in 0...AppIndex.maxDepth {
            try makeApp(in: dir, file: "L\(level)", name: "Level \(level)", id: "com.test.l\(level)")
            dir = dir.appendingPathComponent("sub\(level)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try makeApp(in: dir, file: "TooDeep", name: "Too Deep", id: "com.test.deep")
        let host = try makeApp(in: root, file: "Host", name: "Host", id: "com.test.host")
        try makeApp(in: host.appendingPathComponent("Contents/Applications"), file: "Inner", name: "Inner", id: "com.test.inner")
        let ids = Set(AppIndex.scan(roots: [root], pinned: []).map(\.bundleID))
        for level in 0...AppIndex.maxDepth { XCTAssertTrue(ids.contains("com.test.l\(level)")) }
        XCTAssertFalse(ids.contains("com.test.deep"))
        XCTAssertFalse(ids.contains("com.test.inner"), "apps inside another app are not listed")
    }

    func testOwnAppsAreListedEvenAsAgentsAndWinDuplicates() throws {
        let own = root.appendingPathComponent("own")
        let apps = root.appendingPathComponent("apps")
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let sky = try makeApp(in: own, file: "SkyRose", name: "SkyRose", id: AppIndex.skyRoseBundleID, extra: ["LSUIElement": true])
        let settings = try makeApp(in: own, file: "SkyRose Settings", name: "SkyRose Settings", id: AppIndex.settingsBundleID)
        try makeApp(in: apps, file: "SkyRose Settings", name: "Old Settings", id: AppIndex.settingsBundleID)
        XCTAssertEqual(AppIndex.settingsAppURL(near: sky)?.standardizedFileURL, settings.standardizedFileURL)
        XCTAssertEqual(AppIndex.ownApps(own: sky).map(\.lastPathComponent), ["SkyRose.app", "SkyRose Settings.app"])
        let list = AppIndex.scan(roots: [apps], pinned: [], own: AppIndex.ownApps(own: sky))
        XCTAssertEqual(list.map(\.name), ["SkyRose", "SkyRose Settings"])
        XCTAssertEqual(list.first { $0.bundleID == AppIndex.settingsBundleID }?.url.standardizedFileURL, settings.standardizedFileURL)
        XCTAssertEqual(list.first?.description, "Tiling window manager and shell")
        let found = LauncherSearch.results(for: "skyrose set", apps: list)
        XCTAssertEqual(found.first?.title, "SkyRose Settings")
    }

    func testSpotlightResultsAreMergedAfterRoots() throws {
        let apps = root.appendingPathComponent("apps")
        let elsewhere = root.appendingPathComponent("Projects/dist")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try makeApp(in: apps, file: "One", name: "One", id: "com.test.one")
        let dup = try makeApp(in: elsewhere, file: "One", name: "One elsewhere", id: "com.test.one")
        let other = try makeApp(in: elsewhere, file: "Other", name: "Other", id: "com.test.other")
        let hidden = root.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        let trashed = try makeApp(in: hidden, file: "Gone", name: "Gone", id: "com.test.gone")
        let list = AppIndex.scan(roots: [apps], pinned: [], extra: [dup, other, trashed])
        XCTAssertEqual(list.map(\.name), ["One", "Other"])
    }

    func testIndexableFilter() {
        XCTAssertTrue(AppIndex.isIndexable(path: "/Applications/Safari.app"))
        XCTAssertTrue(AppIndex.isIndexable(path: "/Users/g/Projects/caelestia-mac/dist/SkyRose.app"))
        XCTAssertTrue(AppIndex.isIndexable(path: "/System/Library/CoreServices/Finder.app"))
        XCTAssertTrue(AppIndex.isIndexable(path: "/System/Library/CoreServices/Applications/Archive Utility.app"))
        XCTAssertFalse(AppIndex.isIndexable(path: "/System/Library/CoreServices/Siri.app"))
        XCTAssertFalse(AppIndex.isIndexable(path: "/Applications/Xcode.app/Contents/Applications/Instruments.app"))
        XCTAssertFalse(AppIndex.isIndexable(path: "/Users/g/.Trash/Old.app"))
        XCTAssertFalse(AppIndex.isIndexable(path: "/Users/g/Projects/x/.build/debug/X.app"))
        XCTAssertFalse(AppIndex.isIndexable(path: "/Users/g/Library/Developer/Xcode/DerivedData/X/Build/X.app"))
        XCTAssertFalse(AppIndex.isIndexable(path: "/Users/g/Library/Application Support/Zoom/Updater.app"))
        XCTAssertFalse(AppIndex.isIndexable(path: "/Volumes/Installer/Thing.app"))
        XCTAssertFalse(AppIndex.isIndexable(path: "/Applications/NotAnApp"))
    }

    func testSettingsCommandOpensSettings() {
        XCTAssertEqual(LauncherCommand.all.first { $0.name == "settings" }?.effect, .openSettings)
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
        let apps = AppIndex.scan(roots: [r1, r2, root.appendingPathComponent("missing")], pinned: [])
        XCTAssertEqual(apps.map(\.name), ["Apple", "banana", "Cherry"])
    }

    func testAppsWithoutBundleIDUsePathAsID() throws {
        let url = try makeApp(in: root, file: "NoID", name: "NoID")
        let app = try XCTUnwrap(AppIndex.read(url))
        XCTAssertEqual(app.bundleID, "")
        XCTAssertEqual(app.id, url.path)
    }
}
