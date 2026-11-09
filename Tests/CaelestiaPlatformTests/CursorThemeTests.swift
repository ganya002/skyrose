import AppKit
import CaelestiaCore
import CoreGraphics
import XCTest
@testable import CaelestiaPlatform

/// Behaves like macOS 27's registry as measured on 2026-11-05: the legacy Arrow/IBeam names
/// accept a registration but keep the system cursor, `unregisterAll` resets only the
/// `com.apple.cursor.N` set, and the wait cursor cannot be written back once replaced.
final class FakeCursorRegistry: CursorRegistry {
    var cursors: [String: CursorImage] = [:]
    var registered: [String] = []
    var waitReplaced = false

    init() {
        for name in ["ArrowS", "IBeamS", "Arrow", "IBeam", "Move", "Copy", "Alias"] {
            cursors["com.apple.coregraphics.\(name)"] = Self.image(w: 28, h: 40, hot: 5, tint: 0.1)
        }
        cursors["com.apple.coregraphics.Wait"] = Self.image(w: 24, h: 24, hot: 12, tint: 0.2, frames: 10)
    }

    static func image(w: Double, h: Double, hot: Double, tint: CGFloat, frames: Int = 1) -> CursorImage {
        let ctx = CGContext(data: nil, width: Int(w), height: Int(h) * frames, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: tint, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h * Double(frames)))
        return CursorImage(size: CGSize(width: w, height: h), hotSpot: CGPoint(x: hot, y: hot), frameCount: frames,
                           frameDuration: frames > 1 ? 0.1 : 0, images: [ctx.makeImage()!])
    }

    func read(_ name: String) -> CursorImage? { cursors[name] }

    func register(_ name: String, _ cursor: CursorImage) -> Bool {
        registered.append(name)
        if name == "com.apple.coregraphics.Arrow" || name == "com.apple.coregraphics.IBeam" { return true }  // silently ignored
        if name == "com.apple.coregraphics.Wait" {
            if waitReplaced { return false }
            waitReplaced = true
        }
        cursors[name] = cursor
        return true
    }

    func unregisterAll() -> Bool {
        cursors = cursors.filter { !$0.key.hasPrefix("com.apple.cursor.") }
        return true
    }
}

final class CursorThemeTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func bibata() -> CursorCape {
        let arrow = FakeCursorRegistry.image(w: 24, h: 24, hot: 5.15625, tint: 0.9)
        return CursorCape(identifier: "Bibata-Modern-Classic", name: "Bibata Modern Classic", cursors: [
            "com.apple.coregraphics.Arrow": arrow,
            "com.apple.coregraphics.IBeam": FakeCursorRegistry.image(w: 24, h: 24, hot: 12, tint: 0.8),
            "com.apple.coregraphics.Move": FakeCursorRegistry.image(w: 24, h: 24, hot: 12, tint: 0.7),
            "com.apple.coregraphics.Wait": FakeCursorRegistry.image(w: 24, h: 24, hot: 12, tint: 0.6, frames: 18),
            "com.apple.cursor.13": FakeCursorRegistry.image(w: 24, h: 24, hot: 10.6875, tint: 0.5),
            "com.apple.cursor.4": FakeCursorRegistry.image(w: 24, h: 24, hot: 12, tint: 0.4, frames: 18),
        ])
    }

    private func manager(_ r: FakeCursorRegistry, boot: Double = 100) -> CursorThemeManager {
        CursorThemeManager(registry: r, backup: CursorBackupStore(folder: folder), bootTime: boot)
    }

    func testApplyUsesTheModernNamesWithTheCapesSizeAndHotspotAndNeverTheWaitCursor() throws {
        let r = FakeCursorRegistry()
        let report = try manager(r).apply(bibata())
        XCTAssertEqual(report.applied, ["com.apple.coregraphics.ArrowS", "com.apple.coregraphics.IBeamS", "com.apple.coregraphics.Move",
                                        "com.apple.cursor.13", "com.apple.cursor.4"])
        XCTAssertEqual(report.skipped, ["com.apple.coregraphics.Wait"])
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertFalse(r.registered.contains("com.apple.coregraphics.Wait"))
        XCTAssertFalse(r.registered.contains("com.apple.coregraphics.Arrow"), "legacy names are no-ops on macOS 27")
        let arrow = try XCTUnwrap(r.read("com.apple.coregraphics.ArrowS"))
        XCTAssertEqual(arrow.size, CGSize(width: 24, height: 24))
        XCTAssertEqual(arrow.hotSpot, CGPoint(x: 5.15625, y: 5.15625))
    }

    func testResetPutsBackEveryOriginal() throws {
        let r = FakeCursorRegistry()
        let before = r.cursors
        let m = manager(r)
        _ = try m.apply(bibata())
        XCTAssertNotNil(r.read("com.apple.cursor.13"))
        let report = m.reset()
        XCTAssertTrue(report.ok, "\(report.failed)")
        XCTAssertEqual(Set(r.cursors.keys), Set(before.keys), "the cursor.N set is gone again")
        for (name, original) in before {
            XCTAssertTrue(r.cursors[name]!.sameCursor(as: original), name)
        }
        XCTAssertFalse(m.backup.exists, "backup removed after a clean reset")
    }

    func testApplyingTwiceNeverBacksUpOurOwnCursors() throws {
        let r = FakeCursorRegistry()
        let original = r.cursors["com.apple.coregraphics.ArrowS"]!
        _ = try manager(r).apply(bibata())
        // A WM restart: a new manager over the same backup folder applies again.
        _ = try manager(r).apply(bibata())
        manager(r).reset()
        XCTAssertTrue(r.cursors["com.apple.coregraphics.ArrowS"]!.sameCursor(as: original))
    }

    func testTheBackupSurvivesForTheBootItWasTakenIn() throws {
        let r = FakeCursorRegistry()
        let original = r.cursors["com.apple.coregraphics.Move"]!
        _ = try manager(r, boot: 100).apply(bibata())
        // `skyrose cursor reset` in another process, same boot.
        XCTAssertTrue(manager(r, boot: 100.5).reset().ok)
        XCTAssertTrue(r.cursors["com.apple.coregraphics.Move"]!.sameCursor(as: original))
    }

    func testAResetWithNothingAppliedChangesNothing() {
        let r = FakeCursorRegistry()
        let before = r.cursors
        XCTAssertTrue(manager(r).reset().ok)
        XCTAssertEqual(Set(r.cursors.keys), Set(before.keys))
        XCTAssertTrue(r.registered.isEmpty)
    }

    func testIsAppliedNoticesWhenTheSystemDroppedTheTheme() throws {
        let r = FakeCursorRegistry()
        let m = manager(r)
        _ = try m.apply(bibata())
        XCTAssertTrue(m.isApplied(bibata()))
        _ = r.unregisterAll()  // e.g. after wake
        XCTAssertFalse(m.isApplied(bibata()))
    }

    func testTheBundledBibataCapeIsFoundAndIsTheDefault() throws {
        XCTAssertEqual(AppearanceConfig().cursor, CursorCapeLibrary.bundledIdentifier)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cape-lib-\(UUID().uuidString)", isDirectory: true)
        let library = CursorCapeLibrary(ownFolder: folder, searchFolders: [])
        let found = try XCTUnwrap(library.available().first { $0.identifier == CursorCapeLibrary.bundledIdentifier })
        XCTAssertTrue(found.url.path.contains("Cursors"))
        let cape = try CursorCape.load(found.url)
        XCTAssertEqual(cape.name, "Bibata Modern Classic")
        XCTAssertGreaterThanOrEqual(cape.cursors.count, 30)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "finding the bundled cape does not copy it into Application Support")
    }

    func testTheBibataCapeLoadsWithArchSizeAndHotspots() throws {
        let bundled = CursorCapeLibrary().url(for: CursorCapeLibrary.bundledIdentifier)
        let installed = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Mousecape/capes/Bibata-Modern-Classic.cape")
        let url = bundled ?? installed
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "Bibata cape not bundled or installed")
        let cape = try CursorCape.load(url)
        XCTAssertEqual(cape.identifier, "Bibata-Modern-Classic")
        let arrow = try XCTUnwrap(cape.cursors["com.apple.coregraphics.Arrow"])
        // XCURSOR_SIZE 24 on Arch at 1x; Bibata's left_ptr hotspot (55, 17) on its 256 px canvas.
        XCTAssertEqual(arrow.size, CGSize(width: 24, height: 24))
        XCTAssertEqual(arrow.hotSpot.x, 55.0 / 256 * 24, accuracy: 0.01)
        XCTAssertEqual(arrow.hotSpot.y, 17.0 / 256 * 24, accuracy: 0.01)
        XCTAssertEqual(cape.cursors["com.apple.coregraphics.IBeam"]?.hotSpot, CGPoint(x: 12, y: 12))
        XCTAssertGreaterThanOrEqual(cape.cursors.count, 30)
    }
}
