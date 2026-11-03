import XCTest
import CaelestiaCore
@testable import CaelestiaPlatform

/// Preset B (Caps Lock → F18) is applied without wiping other remaps and restored from the backup
/// journal (spec 3.1, 10.4). `hidutil` is faked; nothing touches the real keyboard.
final class HIDKeyMappingTests: XCTestCase {
    /// Fake hidutil that stores the last `--set` value and prints it back in hidutil's format.
    final class FakeHidutil: @unchecked Sendable {
        var pairs: [HIDKeyMapping.Pair]
        var calls: [[String]] = []
        init(_ pairs: [HIDKeyMapping.Pair]) { self.pairs = pairs }

        func run(_ args: [String]) throws -> String {
            calls.append(args)
            if args.contains("--set") {
                pairs = HIDKeyMapping.parseJSON(args.last!)
                return ""
            }
            if pairs.isEmpty { return "(null)\n" }
            let dicts = pairs.map { "    {\n        HIDKeyboardModifierMappingDst = \($0.dst);\n        HIDKeyboardModifierMappingSrc = \($0.src);\n    }" }
            return "(\n" + dicts.joined(separator: ",\n") + "\n)\n"
        }
    }

    let userRemap = HIDKeyMapping.Pair(src: 0x7_0000_0064, dst: 0x7_0000_0035) // § → `
    let caps = HIDKeyMapping.Pair(src: ModifierPresets.capsLockUsage, dst: ModifierPresets.f18Usage)

    func journal() -> BackupJournal {
        BackupJournal(url: FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString).json"))
    }

    func testParsesHidutilOutputInEitherKeyOrder() {
        let text = """
            (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            },
                {
                HIDKeyboardModifierMappingSrc = 30064771172;
                HIDKeyboardModifierMappingDst = 30064771125;
            }
            )
            """
        XCTAssertEqual(HIDKeyMapping.parse(text), [caps, userRemap])
        XCTAssertEqual(HIDKeyMapping.parse("(null)"), [])
        XCTAssertTrue(ModifierPresets.mappingIsApplied(hidutilOutput: text))
    }

    func testJSONMatchesThePresetConstant() {
        XCTAssertEqual(HIDKeyMapping.json([caps]), ModifierPresets.capsLockToF18Mapping)
        XCTAssertEqual(HIDKeyMapping.parseJSON(HIDKeyMapping.json([caps, userRemap])), [caps, userRemap])
    }

    func testApplyKeepsExistingRemapsAndRestorePutsThemBack() throws {
        let fake = FakeHidutil([userRemap])
        let j = journal()
        defer { try? FileManager.default.removeItem(at: j.url) }
        let mapping = HIDKeyMapping(journal: j, runner: fake.run)

        try mapping.apply()
        XCTAssertEqual(fake.pairs, [userRemap, caps])
        XCTAssertEqual(try j.entries().count, 1)
        XCTAssertEqual(try j.entries().first?.kind, .hidutil)

        try mapping.apply() // at the next login: no-op, no second backup entry
        XCTAssertEqual(try j.entries().count, 1)

        try mapping.restore()
        XCTAssertEqual(fake.pairs, [userRemap])
    }

    func testRestoreWithoutBackupOnlyDropsCapsLock() throws {
        let fake = FakeHidutil([userRemap, caps])
        let j = journal()
        try HIDKeyMapping(journal: j, runner: fake.run).restore()
        XCTAssertEqual(fake.pairs, [userRemap])
    }
}
