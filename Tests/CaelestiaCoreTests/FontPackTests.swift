import Foundation
import XCTest

@testable import CaelestiaCore

final class FontPackTests: XCTestCase {
    func testPackIsPinnedAndChecksummed() {
        var names = Set<String>()
        for f in FontPack.families {
            XCTAssertFalse(f.files.isEmpty, f.name)
            for a in f.files + [f.licenceFile] {
                XCTAssertTrue(names.insert(a.fileName).inserted, "duplicate \(a.fileName)")
                XCTAssertTrue(a.url.hasPrefix("https://github.com/"), a.url)
                XCTAssertFalse(a.url.contains("/main/") || a.url.contains("/master/"), "unpinned \(a.url)")
                XCTAssertEqual(a.sha256.count, 64, a.fileName)
                XCTAssertTrue(a.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase }, a.fileName)
            }
            for a in f.files { XCTAssertGreaterThan(a.bytes, 0, a.fileName) }
        }
    }

    func testEveryLicenceAllowsRedistribution() {
        for f in FontPack.families {
            XCTAssertTrue(["SIL OFL 1.1", "Apache 2.0"].contains(f.licence), "\(f.name): \(f.licence)")
        }
    }

    func testPackCoversTheConfiguredFonts() {
        let c = Config()
        let names = Set(FontPack.families.map(\.name))
        XCTAssertTrue(names.contains(c.appearance.fontSans))
        XCTAssertTrue(names.contains(c.appearance.fontMono), "v3 family name, not the v2 \"NF\" alias")
        XCTAssertTrue(names.contains(c.appearance.fontIcons))
        XCTAssertTrue(names.contains(c.apps.kittyFont))
        XCTAssertTrue(c.appearance.fontSansFallbacks.contains("Inter"))
        XCTAssertEqual(FontPack.terminalFamilies.map(\.name), ["CaskaydiaCove Nerd Font", "JetBrainsMono Nerd Font"])
    }

    func testChecksum() {
        let asset = FontPack.Asset(fileName: "x", url: "", sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", bytes: 5)
        XCTAssertTrue(FontPack.verify(Data("hello".utf8), asset))
        XCTAssertFalse(FontPack.verify(Data("hellO".utf8), asset))
    }

    func testCachedMeansTheRightSize() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fontpack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rubik = try XCTUnwrap(FontPack.families.first { $0.name == "Rubik" })
        XCTAssertFalse(FontPack.isCached(rubik, in: dir))
        try Data(count: 10).write(to: dir.appendingPathComponent(rubik.files[0].fileName))
        XCTAssertFalse(FontPack.isCached(rubik, in: dir), "truncated file")
        try Data(count: rubik.files[0].bytes).write(to: dir.appendingPathComponent(rubik.files[0].fileName))
        XCTAssertTrue(FontPack.isCached(rubik, in: dir))
    }

    func testKittyFontConfigIsValidated() throws {
        var c = Config()
        c.apps.kittyFontSize = 3
        c.apps.kittyFont = " "
        let keys = ConfigLoader.validate(c).map(\.path)
        XCTAssertTrue(keys.contains("apps.kittyFontSize"))
        XCTAssertTrue(keys.contains("apps.kittyFont"))
        XCTAssertEqual(Config().apps.kittyOptions, KittyProfile.Options())
    }
}
