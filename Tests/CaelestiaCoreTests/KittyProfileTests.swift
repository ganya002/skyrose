import Foundation
import XCTest

@testable import CaelestiaCore

final class KittyProfileTests: XCTestCase {
    private var dir: URL!
    private let scheme = SchemeLoader.builtIn(named: "skyrose-dynamic")!
    private let other = SchemeLoader.builtIn(named: "skyrose-default")!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("kitty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private var archConf: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("fixtures/ref/kitty/kitty.conf")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    // MARK: Profile text

    func testProfileCarriesGabbysArchSettings() throws {
        let text = KittyProfile.render()
        XCTAssertTrue(text.hasPrefix(KittyThemeWriter.headerMarker))
        let arch = try archConf
        // Every Arch setting that is not a colour or a Linux-only value is copied verbatim.
        for key in ["font_family", "font_size", "window_padding_width", "background_opacity", "cursor_shape", "cursor_trail",
                    "confirm_os_window_close", "enable_audio_bell", "tab_bar_style", "tab_powerline_style"] {
            let archLine = arch.split(separator: "\n").first { $0.hasPrefix(key + " ") }.map(String.init)
            let ourLine = text.split(separator: "\n").first { $0.hasPrefix(key + " ") }.map(String.init)
            XCTAssertNotNil(archLine, key)
            XCTAssertEqual(archLine.map { $0.split(whereSeparator: \.isWhitespace).dropFirst().joined(separator: " ") },
                           ourLine.map { $0.split(whereSeparator: \.isWhitespace).dropFirst().joined(separator: " ") }, key)
        }
        XCTAssertTrue(text.contains("background_blur 32"))
        XCTAssertTrue(text.contains("hide_window_decorations titlebar-only"))
        XCTAssertTrue(text.hasSuffix("include \(KittyProfile.themeFileName)\n"), "the scheme colours come last")
        XCTAssertFalse(text.contains("#1E1E2E"), "no static Catppuccin colours")
    }

    func testProfileFontIsAnOption() {
        let text = KittyProfile.render(.init(fontFamily: "CaskaydiaCove Nerd Font", fontSize: 12.5))
        XCTAssertTrue(text.contains("font_family      CaskaydiaCove Nerd Font\n"))
        XCTAssertTrue(text.contains("font_size        12.5\n"))
    }

    // MARK: Include line

    func testIncludeDetection() {
        XCTAssertTrue(KittyProfile.includes("include skyrose.conf"))
        XCTAssertTrue(KittyProfile.includes("  include\t./skyrose.conf  "))
        XCTAssertTrue(KittyProfile.includes("include ~/.config/kitty/skyrose-theme.conf"))
        XCTAssertFalse(KittyProfile.includes("# include skyrose.conf"))
        XCTAssertFalse(KittyProfile.includes("include skyrose.conf.bak"))
        XCTAssertFalse(KittyProfile.includes("includeskyrose.conf"))
        XCTAssertFalse(KittyProfile.includes(nil))
    }

    func testAddAndRemoveIncludeRoundTrips() throws {
        let original = try archConf
        let added = KittyProfile.addingInclude(to: original)
        XCTAssertTrue(added.hasPrefix(original))
        XCTAssertTrue(added.hasSuffix("\(KittyProfile.includeLine)\n"), "last, so it wins over themes/noctalia.conf")
        XCTAssertEqual(KittyProfile.addingInclude(to: added), added, "idempotent")
        XCTAssertEqual(KittyProfile.removingInclude(from: added), original)
        XCTAssertFalse(KittyProfile.isOnlyOurs(added))
    }

    func testNewKittyConfIsOnlyOurs() {
        let created = KittyProfile.addingInclude(to: nil)
        XCTAssertTrue(KittyProfile.includes(created))
        XCTAssertTrue(KittyProfile.isOnlyOurs(created))
    }

    // MARK: Setup on disk

    func testInstallAndUninstallRestoreTheUsersFile() throws {
        let setup = KittySetup(directory: dir)
        let original = try archConf
        try Data(original.utf8).write(to: setup.kittyConf)
        let journal = BackupJournal(url: dir.appendingPathComponent("backup/backup.json"))

        let notes = try setup.install(scheme: scheme, journal: journal)
        XCTAssertFalse(notes.isEmpty)
        XCTAssertEqual(setup.status(), .init(included: true, kittyConfExists: true, profileWritten: true, themeWritten: true, foreignFile: nil))
        XCTAssertEqual(KittyThemeWriter.parse(read(setup.themeFile) ?? "")["background"], scheme[.surface])
        let entry = try XCTUnwrap(journal.entries().first)
        XCTAssertEqual(entry.kind, .kittyConfig)
        guard case .string(let copy) = entry.oldValue else { return XCTFail("original not copied") }
        XCTAssertEqual(read(URL(fileURLWithPath: copy)), original)

        XCTAssertTrue(try setup.install(scheme: scheme, journal: journal).count == 1, "second install only rewrites our files")
        XCTAssertEqual(try journal.entries().count, 1)

        try setup.uninstall()
        XCTAssertEqual(read(setup.kittyConf), original)
        XCTAssertNil(read(setup.profileFile))
        XCTAssertNil(read(setup.themeFile))
    }

    func testInstallWithoutKittyConfCreatesAndRemovesIt() throws {
        let setup = KittySetup(directory: dir.appendingPathComponent("fresh"))
        try setup.install(scheme: scheme)
        XCTAssertTrue(setup.status().included)
        try setup.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.kittyConf.path))
    }

    func testInstallRefusesAForeignProfile() throws {
        let setup = KittySetup(directory: dir)
        try Data("font_size 20\n".utf8).write(to: setup.profileFile)
        XCTAssertEqual(setup.status().foreignFile, setup.profileFile.path)
        XCTAssertThrowsError(try setup.install(scheme: scheme))
        XCTAssertEqual(read(setup.profileFile), "font_size 20\n")
        XCTAssertNil(read(setup.kittyConf))
        try setup.uninstall()
        XCTAssertEqual(read(setup.profileFile), "font_size 20\n", "uninstall leaves files it did not write")
    }

    func testSymlinkedKittyConfStaysALink() throws {
        let setup = KittySetup(directory: dir)
        let real = dir.appendingPathComponent("dotfiles-kitty.conf")
        try Data("font_size 13\n".utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: setup.kittyConf, withDestinationURL: real)
        try setup.install(scheme: scheme)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: setup.kittyConf.path))
        XCTAssertTrue(KittyProfile.includes(read(real)))
    }

    func testSyncOnlyWhenKittyUsesTheProfile() throws {
        let setup = KittySetup(directory: dir)
        XCTAssertFalse(try setup.syncTheme(scheme: scheme))
        XCTAssertNil(read(setup.themeFile), "nothing is written for a kitty that does not include us")
        try setup.install(scheme: scheme)
        XCTAssertFalse(try setup.syncTheme(scheme: scheme), "unchanged colours: no reload")
        XCTAssertTrue(try setup.syncTheme(scheme: other))
        XCTAssertEqual(KittyThemeWriter.parse(read(setup.themeFile) ?? "")["background"], other[.surface])
    }

    // MARK: Terminal choices

    func testPresetsCoverTheBriefsTerminals() {
        XCTAssertEqual(TerminalChoice.presets.map(\.name), ["kitty", "Rex", "Terminal", "iTerm2", "Ghostty", "WezTerm"])
        XCTAssertEqual(TerminalChoice(config: Config().apps.terminal).preset?.name, "kitty", "kitty is the default")
        for p in TerminalChoice.presets {
            XCTAssertEqual(TerminalChoice(config: p.choice.configValue).preset, p, p.name)
        }
        XCTAssertNil(TerminalChoice(config: "wezterm start").preset)
        XCTAssertEqual(TerminalChoice(config: "COM.GOOGLECODE.ITERM2").preset?.name, "iTerm2")
    }
}
