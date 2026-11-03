import CaelestiaCore
import Foundation

/// Applies and reverts the preset-B Caps Lock → F18 remap with `hidutil` (spec 3.1, 10.4). The
/// user's previous `UserKeyMapping` is recorded in the backup journal before the first change and
/// is what `restore` puts back, so other remaps the user had are never wiped. Runs as the user;
/// no root. Mappings reset on reboot, so the agent calls `apply` again at login.
public struct HIDKeyMapping {
    public struct Pair: Equatable, Sendable {
        public var src: UInt64
        public var dst: UInt64
        public init(src: UInt64, dst: UInt64) {
            self.src = src
            self.dst = dst
        }
    }

    /// Runs `hidutil` with arguments and returns stdout. Injected by tests.
    public typealias Runner = ([String]) throws -> String

    static let backupDomain = "hidutil"
    static let backupKey = "UserKeyMapping"

    public let journal: BackupJournal
    let run: Runner

    public init(journal: BackupJournal = BackupJournal(), runner: @escaping Runner = HIDKeyMapping.runHidutil) {
        self.journal = journal
        self.run = runner
    }

    /// Current user mappings.
    public func current() throws -> [Pair] {
        Self.parse(try run(Array(ModifierPresets.readMappingCommand.dropFirst())))
    }

    /// Adds Caps Lock → F18 to the existing mappings. Records the original first. No-op when the
    /// mapping is already active.
    public func apply() throws {
        let existing = try current()
        let caps = Pair(src: ModifierPresets.capsLockUsage, dst: ModifierPresets.f18Usage)
        guard !existing.contains(caps) else { return }
        if try !journal.contains(domain: Self.backupDomain, key: Self.backupKey) {
            try journal.append(BackupEntry(
                domain: Self.backupDomain, key: Self.backupKey, oldValue: .string(Self.json(existing)),
                newValue: .string(Self.json(existing.filter { $0.src != caps.src } + [caps])), kind: .hidutil,
                note: "Caps Lock → F18 (modifier preset B)"
            ))
        }
        _ = try run(["property", "--set", Self.json(existing.filter { $0.src != caps.src } + [caps])])
    }

    /// Puts back the mappings recorded before the first `apply` (or just drops Caps Lock → F18
    /// when there is no record).
    public func restore() throws {
        let original: [Pair]
        if let entry = try journal.firstEntry(domain: Self.backupDomain, key: Self.backupKey),
           case let .string(json) = entry.oldValue
        {
            original = Self.parseJSON(json)
        } else {
            original = try current().filter { $0.src != ModifierPresets.capsLockUsage }
        }
        _ = try run(["property", "--set", Self.json(original)])
    }

    // MARK: Formats

    /// `{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x…,"HIDKeyboardModifierMappingDst":0x…}]}`.
    public static func json(_ pairs: [Pair]) -> String {
        let items = pairs.map {
            "{\"HIDKeyboardModifierMappingSrc\":0x\(String($0.src, radix: 16, uppercase: true)),"
                + "\"HIDKeyboardModifierMappingDst\":0x\(String($0.dst, radix: 16, uppercase: true))}"
        }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    /// Parses our own `json` output (hex numbers, which strict JSON does not allow).
    static func parseJSON(_ text: String) -> [Pair] {
        pairs(in: text, number: "0x([0-9A-Fa-f]+)", radix: 16)
    }

    /// Parses `hidutil property --get UserKeyMapping` output: an old-style plist array of
    /// `{ HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; }`
    /// dictionaries in either key order. `(null)` means no mappings.
    public static func parse(_ text: String) -> [Pair] {
        pairs(in: text, number: "([0-9]+)", radix: 10)
    }

    private static func pairs(in text: String, number: String, radix: Int) -> [Pair] {
        var result: [Pair] = []
        // Each dictionary is the text between braces after the first one (the JSON wrapper).
        let chunks = text.split(separator: "{").map(String.init)
        for chunk in chunks {
            func value(_ key: String) -> UInt64? {
                guard let regex = try? NSRegularExpression(pattern: "\"?\(key)\"?\\s*[=:]\\s*\(number)"),
                      let m = regex.firstMatch(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)),
                      let r = Range(m.range(at: 1), in: chunk)
                else { return nil }
                return UInt64(chunk[r], radix: radix)
            }
            if let src = value("HIDKeyboardModifierMappingSrc"), let dst = value("HIDKeyboardModifierMappingDst") {
                result.append(Pair(src: src, dst: dst))
            }
        }
        return result
    }

    /// Runs `/usr/bin/hidutil`.
    public static func runHidutil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BackupError.io(path: "/usr/bin/hidutil", message: "exit status \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
