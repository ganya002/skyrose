import XCTest
@testable import CaelestiaCore

/// The watcher's directory handling and the window animation mode of the config.
final class ConfigWatcherDirectoryTests: XCTestCase {
    final class Box: @unchecked Sendable {
        let lock = NSLock()
        private var _events: [ConfigWatcher.Event] = []
        func add(_ e: ConfigWatcher.Event) { lock.withLock { _events.append(e) } }
        var events: [ConfigWatcher.Event] { lock.withLock { _events } }
    }

    func testPicksUpConfigCreatedInDirectoryThatDidNotExist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cfgw-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // Neither the parent nor the config directory exists yet.
        let url = root.appendingPathComponent("parent/missing-dir/config.toml")
        let box = Box()
        let loaded = expectation(description: "loaded")
        loaded.assertForOverFulfill = false
        let watcher = ConfigWatcher(url: url, debounce: 0.05) { event in
            box.add(event)
            if case .loaded = event { loaded.fulfill() }
        }
        XCTAssertTrue(watcher.start(), "watches the nearest existing ancestor")
        defer { watcher.stop() }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[wm]\ngapsIn = 9\n".utf8).write(to: url, options: .atomic)
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(watcher.lastGood.wm.gapsIn, 9)
    }

    func testPicksUpConfigCreatedLaterInExistingEmptyDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cfgw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        let loaded = expectation(description: "loaded")
        loaded.assertForOverFulfill = false
        let watcher = ConfigWatcher(url: url, debounce: 0.05) { event in
            if case .loaded = event { loaded.fulfill() }
        }
        XCTAssertTrue(watcher.start())
        defer { watcher.stop() }
        try Data("[wm]\ngapsIn = 11\n".utf8).write(to: url)
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(watcher.lastGood.wm.gapsIn, 11)
    }

    func testNearestExistingDirectoryWalksUp() {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("nope-\(UUID().uuidString)/a/b/config.toml")
        XCTAssertEqual(ConfigWatcher.nearestExistingDirectory(for: url).standardizedFileURL.path, tmp.standardizedFileURL.path)
    }

    func testStagedCreationOfDirectoriesThenFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cfgw-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("x/y/config.toml")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let loaded = expectation(description: "loaded")
        loaded.assertForOverFulfill = false
        let watcher = ConfigWatcher(url: url, debounce: 0.05) { event in
            if case .loaded = event { loaded.fulfill() }
        }
        XCTAssertTrue(watcher.start())
        defer { watcher.stop() }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("x"), withIntermediateDirectories: true)
        Thread.sleep(forTimeInterval: 0.3)  // let the watcher move down to x/
        try FileManager.default.createDirectory(at: root.appendingPathComponent("x/y"), withIntermediateDirectories: true)
        Thread.sleep(forTimeInterval: 0.3)
        try Data("[wm]\ngapsIn = 13\n".utf8).write(to: url)
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(watcher.lastGood.wm.gapsIn, 13)
    }

    // MARK: animations.windows

    func testWindowAnimationModeDefaultsToGlide() throws {
        XCTAssertEqual(Config().animations.windows, .snapshot)
        XCTAssertEqual(try ConfigLoader.loadDefaultResource().animations.windows, .snapshot)
    }

    func testAnExistingConfigWithoutTheKeyGetsGlide() throws {
        XCTAssertEqual(try ConfigLoader.parse(toml: "").animations.windows, .snapshot)
        XCTAssertEqual(try ConfigLoader.parse(toml: "[wm]\ngapsOut = 14\n").animations.windows, .snapshot)
        XCTAssertEqual(try ConfigLoader.parse(toml: "[animations]\nenabled = true\n").animations.windows, .snapshot)
    }

    func testWindowsOffParses() throws {
        let c = try ConfigLoader.parse(toml: "[animations]\nwindows = \"off\"\n")
        XCTAssertEqual(c.animations.windows, .off)
        XCTAssertEqual(try ConfigLoader.parse(toml: "[animations]\nwindows = \"snapshot\"\n").animations.windows, .snapshot)
    }

    func testWindowsModeRoundTripsThroughSerialize() throws {
        var c = Config()
        c.animations.windows = .off
        XCTAssertEqual(try ConfigLoader.parse(toml: ConfigLoader.serialize(c)).animations.windows, .off)
    }

    func testInvalidWindowsModeIsRejected() {
        XCTAssertThrowsError(try ConfigLoader.parse(toml: "[animations]\nwindows = \"wobbly\"\n"))
    }
}
