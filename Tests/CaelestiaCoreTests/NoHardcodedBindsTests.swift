import Foundation
import XCTest

/// Spec 3.2: "No bind is hard-coded anywhere else; a test fails the build if one is." Scans every
/// Swift source outside the keymap subsystem for chord literals.
final class NoHardcodedBindsTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sourcesRoot = repoRoot.appendingPathComponent("Sources", isDirectory: true)
    private static let keymapDirectory = "Sources/CaelestiaCore/Keymap/"
    private static let optOutMarker = "// caelestia:allow-hardcoded-chord"

    /// A string literal that starts with a Linux modifier followed by " + " — a chord written as a bind.
    private static let chordLiteral = try! NSRegularExpression(pattern: #""(SUPER|ALT|CTRL|SHIFT) \+ [^"\n]+""#)
    private static let chordConstructor = "KeyChord(modifiers:"
    private static let ansiKeyCode = "kVK_ANSI_"
    private static let modifierMasks = ["maskAlternate", "maskCommand"]

    struct Finding: CustomStringConvertible {
        var file: String
        var line: Int
        var reason: String
        var description: String { "\(file):\(line): \(reason)" }
    }

    /// Replaces `//` line comments and `/* */` block comments with spaces, keeping every newline so
    /// line numbers are unchanged. String literals are honoured so `"http://x"` is not a comment.
    static func stripComments(_ source: String) -> String {
        var out = ""
        out.reserveCapacity(source.count)
        let chars = Array(source)
        var i = 0
        var inString = false
        var inLineComment = false
        var inBlockComment = false
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if inLineComment {
                if c == "\n" { inLineComment = false; out.append(c) } else { out.append(" ") }
            } else if inBlockComment {
                if c == "*" && next == "/" { inBlockComment = false; out.append("  "); i += 1 } else { out.append(c == "\n" ? "\n" : " ") }
            } else if inString {
                out.append(c)
                if c == "\\" && next != nil { out.append(next!); i += 1 } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
                out.append(c)
            } else if c == "/" && next == "/" {
                inLineComment = true
                out.append("  ")
                i += 1
            } else if c == "/" && next == "*" {
                inBlockComment = true
                out.append("  ")
                i += 1
            } else {
                out.append(c)
            }
            i += 1
        }
        return out
    }

    static func scan(file url: URL) throws -> [Finding] {
        let original = try String(contentsOf: url, encoding: .utf8)
        let relative = url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
        var findings: [Finding] = []

        func lineNumber(_ text: String, of range: Range<String.Index>) -> Int {
            text[..<range.lowerBound].reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
        }

        if let optOut = original.range(of: optOutMarker) {
            let reason = original[optOut.upperBound...].prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
            let isPanic = original.contains("wmPanic") || original.contains("wm.panic")
            if !isPanic {
                findings.append(Finding(
                    file: relative, line: lineNumber(original, of: optOut),
                    reason: "the allow-hardcoded-chord opt-out is only permitted in the wm.panic implementation (\(reason.isEmpty ? "no reason given" : reason))"
                ))
            } else if reason.isEmpty {
                findings.append(Finding(file: relative, line: lineNumber(original, of: optOut), reason: "the allow-hardcoded-chord opt-out needs a reason"))
            } else {
                return findings
            }
        }

        let text = stripComments(original)
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: chordConstructor, range: searchRange) {
            findings.append(Finding(file: relative, line: lineNumber(text, of: range), reason: "chord constructed in code; binds belong in keymap.toml"))
            searchRange = range.upperBound..<text.endIndex
        }

        let ns = text as NSString
        for match in chordLiteral.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range, in: text) else { continue }
            findings.append(Finding(file: relative, line: lineNumber(text, of: range), reason: "chord literal \(ns.substring(with: match.range)); binds belong in keymap.toml"))
        }

        if let keyCode = text.range(of: ansiKeyCode), let mask = modifierMasks.first(where: { text.contains($0) }) {
            findings.append(Finding(file: relative, line: lineNumber(text, of: keyCode), reason: "\(ansiKeyCode)* used together with CGEventFlags.\(mask); match chords through the keymap instead"))
        }
        return findings
    }

    static func swiftSources() throws -> [URL] {
        var result: [URL] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            if relative.hasPrefix(keymapDirectory) { continue }
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }

    func testNoChordIsHardcodedOutsideTheKeymap() throws {
        let files = try Self.swiftSources()
        XCTAssertFalse(files.isEmpty, "no Swift sources found under \(Self.sourcesRoot.path)")
        var findings: [Finding] = []
        for file in files { findings += try Self.scan(file: file) }
        XCTAssertTrue(findings.isEmpty, "hard-coded binds found (move them to keymap.toml):\n" + findings.map(\.description).joined(separator: "\n"))
    }

    func testScannerDetectsEveryPattern() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("caelestia-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func scan(_ contents: String) throws -> [Finding] {
            let url = dir.appendingPathComponent("Sample.swift")
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return try Self.scan(file: url)
        }
        XCTAssertEqual(try scan("let c = KeyChord(modifiers: [.superKey], key: .code(0x12))\n").map(\.line), [1])
        XCTAssertEqual(try scan("// ok\nlet s = \"SUPER + 1\"\n").map(\.line), [2])
        XCTAssertEqual(try scan("let s = \"ALT + Tab\"\nlet t = \"CTRL + ALT + Delete\"\n").map(\.line), [1, 2])
        XCTAssertTrue(try scan("let s = \"Press SUPER + K for help\"\n").isEmpty, "prose mentioning a chord is not a bind")
        XCTAssertTrue(try scan("/// Chords as written in keymap.toml (\"SUPER + 1\").\nlet x = 1 // e.g. \"ALT + Tab\"\n/* \"CTRL + 1\" */\n").isEmpty, "comments are not binds")
        XCTAssertEqual(try scan("let url = \"http://example.com\" + \"SUPER + 1\"\n").map(\.line), [1], "// inside a string literal does not start a comment")
        XCTAssertEqual(try scan("let k = kVK_ANSI_Q\nlet f = CGEventFlags.maskCommand\n").map(\.line), [1])
        XCTAssertTrue(try scan("let k = kVK_ANSI_Q\nlet f = CGEventFlags.maskShift\n").isEmpty)
        XCTAssertTrue(try scan("let k = kVK_Escape\nlet f = CGEventFlags.maskCommand\n").isEmpty)
        XCTAssertTrue(try scan("// caelestia:allow-hardcoded-chord the panic chord must work without a keymap\nlet s = \"CTRL + SUPER + ALT + SHIFT + Escape\" // wm.panic\n").isEmpty)
        let illegalOptOut = try scan("// caelestia:allow-hardcoded-chord because\nlet s = \"SUPER + 1\"\n")
        XCTAssertEqual(illegalOptOut.map(\.line), [1, 2], "opt-out outside the panic implementation is itself a finding, and the literal is still reported")
        XCTAssertTrue(illegalOptOut[0].reason.contains("only permitted"), illegalOptOut[0].reason)
        XCTAssertEqual(try scan("// caelestia:allow-hardcoded-chord\nlet s = \"SUPER + 1\" // wm.panic\n").count, 2, "opt-out without a reason")
    }

    func testStripCommentsKeepsLineNumbersAndStrings() {
        let source = "let a = \"//not a comment\" // trailing \"SUPER + 1\"\n/* block\n\"ALT + Tab\" */ let b = 2\n"
        let stripped = Self.stripComments(source)
        XCTAssertEqual(stripped.filter { $0 == "\n" }.count, source.filter { $0 == "\n" }.count)
        XCTAssertTrue(stripped.contains("\"//not a comment\""))
        XCTAssertFalse(stripped.contains("SUPER + 1"))
        XCTAssertFalse(stripped.contains("ALT + Tab"))
        XCTAssertTrue(stripped.contains("let b = 2"))
    }
}
