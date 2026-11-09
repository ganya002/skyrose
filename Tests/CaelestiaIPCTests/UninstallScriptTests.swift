import CaelestiaCore
import Foundation
import XCTest

@testable import CaelestiaIPC

/// `scripts/uninstall.sh` against a fixture HOME: a restore manifest written by the real
/// `BackupJournal`, fake apps, links and data, and stub system commands first on PATH that only
/// log their arguments. Nothing here can reach the real account: the script refuses sandbox runs
/// whose HOME is the real one or whose `defaults` is the real binary (tested below).
final class UninstallScriptTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var script: URL { repo.appendingPathComponent("scripts/uninstall.sh") }

    var home: URL!
    var bin: URL!
    var log: URL { home.appendingPathComponent("calls.log") }
    let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("skyrose-uninstall-\(UUID().uuidString)", isDirectory: true)
        bin = home.appendingPathComponent(".stubs", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        // Every stub logs "name args..." and succeeds. A few answer like the real tool.
        let stubs: [String: String] = [
            "defaults": """
            if [ "$1" = read ]; then exit 0; fi
            if [ "$1" = export ]; then
              src="$HOME/Library/Preferences/$2.plist"
              if [ -f "$src" ]; then cp "$src" "$3"; exit 0; fi
              exit 1
            fi
            if [ "$1" = import ]; then
              mkdir -p "$HOME/Library/Preferences"
              cp "$3" "$HOME/Library/Preferences/$2.plist"
              exit 0
            fi
            """,
            "hidutil": "", "pmset": "", "sudo": "", "osascript": "cat >/dev/null", "launchctl": #"[ "$1" = print ] && exit 1"#,
            "killall": "", "open": "",
            "csrutil": #"echo "System Integrity Protection status: disabled.""#,
            "pgrep": "exit 1",
            "security": #"[ "$1" = find-certificate ] && exit 1"#,
            "trash": #"mkdir -p "$HOME/.Trash"; d="$HOME/.Trash/$(basename "$1")"; while [ -e "$d" ] || [ -L "$d" ]; do d="$d.1"; done; mv "$1" "$d""#,
            "skyrose-cli": "",
        ]
        for (name, body) in stubs {
            let url = bin.appendingPathComponent(name)
            let logName = name == "skyrose-cli" ? "skyrose" : name
            try "#!/bin/sh\necho \"\(logName) $*\" >> \"$HOME/calls.log\"\n\(body)\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    override func tearDownWithError() throws {
        if let home, home.path.hasPrefix(fm.temporaryDirectory.path) { try? fm.removeItem(at: home) }
    }

    // MARK: Fixture

    var support: URL { home.appendingPathComponent("Library/Application Support/SkyRose") }
    func path(_ p: String) -> URL { home.appendingPathComponent(p) }

    func makeFixture() throws {
        let journal = BackupJournal(url: support.appendingPathComponent("restore-manifest.json"))
        // Dock auto-hide did not exist before; the user changed it twice (the first entry wins).
        try journal.append(BackupEntry(domain: "com.apple.dock", key: "autohide", oldValue: .absent, newValue: .bool(true)))
        try journal.append(BackupEntry(domain: "NSGlobalDomain", key: "_HIHideMenuBar", oldValue: .bool(false), newValue: .bool(true)))
        try journal.append(BackupEntry(domain: "com.apple.dock", key: "autohide", oldValue: .bool(true), newValue: .bool(false)))
        try journal.append(BackupEntry(domain: "com.apple.dock", key: "autohide-delay", oldValue: .double(0.5), newValue: .double(0)))
        try journal.append(BackupEntry(domain: "hidutil", key: "UserKeyMapping", oldValue: .string(#"{"UserKeyMapping":[]}"#),
                                       newValue: .string("x"), kind: .hidutil))
        let oldPicture = path("Pictures/old.jpg")
        try fm.createDirectory(at: oldPicture.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("jpg".utf8).write(to: oldPicture)
        try journal.append(BackupEntry(domain: "UUID-1", key: "wallpaper", oldValue: .string(oldPicture.path), newValue: .string("/w/a.jpg"), kind: .wallpaper))
        try journal.append(BackupEntry(domain: "UUID-1", key: "wallpaper", oldValue: .string(oldPicture.path), newValue: .string("/w/b.jpg"), kind: .wallpaper))
        try RestoreManifest(journal: journal, flagDirectory: support).recordModeUsed(.sipOff)
        try Data().write(to: support.appendingPathComponent("sleep-disabled-by-skyrose"))
        for app in ["Applications/SkyRose.app/Contents", "Applications/SkyRose Settings.app/Contents", "Applications/TestWindows.app/Contents",
                    ".config/skyrose", "Library/Logs/SkyRose", ".local/bin"] {
            try fm.createDirectory(at: path(app), withIntermediateDirectories: true)
        }
        try fm.createSymbolicLink(atPath: path(".local/bin/skyrose").path, withDestinationPath: path("Applications/SkyRose.app/Contents/MacOS/skyrose").path)
        try fm.createSymbolicLink(atPath: path(".local/bin/other").path, withDestinationPath: "/usr/bin/true")
        try "x = 1\n".write(to: path(".config/skyrose/config.toml"), atomically: true, encoding: .utf8)
        // uuid, display number, picture currently on that display. The script must not ask the live desktop.
        try "UUID-1\t1\t/w/b.jpg\n".write(to: home.appendingPathComponent("screens.tsv"), atomically: true, encoding: .utf8)
    }

    func scriptEnvironment(home h: String? = nil, path p: String? = nil, sandbox: Bool = true) -> [String: String] {
        let root = h ?? home.path
        var env = ["HOME": root, "PATH": p ?? "\(bin.path):/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": NSTemporaryDirectory(),
                   "SKYROSE_CLI": bin.appendingPathComponent("skyrose-cli").path]
        if sandbox { env["SKYROSE_UNINSTALL_SANDBOX"] = "1" }
        let screens = URL(fileURLWithPath: root).appendingPathComponent("screens.tsv")
        if fm.fileExists(atPath: screens.path) { env["SKYROSE_WALLPAPER_SCREENS"] = screens.path }
        return env
    }

    @discardableResult
    func runScript(_ args: [String], home h: String? = nil, path p: String? = nil, sandbox: Bool = true, stdin: String? = nil) throws -> (status: Int32, out: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [Self.script.path] + args
        proc.environment = scriptEnvironment(home: h, path: p, sandbox: sandbox)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        if let stdin {
            let input = Pipe()
            proc.standardInput = input
            try proc.run()
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        } else {
            proc.standardInput = FileHandle.nullDevice
            try proc.run()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    var calls: [String] { ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }

    // MARK: Tests

    func testRestoresTheManifestAndTrashesTheAppsButKeepsConfigAndFonts() throws {
        try makeFixture()
        let r = try runScript(["--yes", "--no-color"])
        XCTAssertEqual(r.status, 0, r.out)
        let c = calls
        // Originals, not the later values: autohide did not exist, so it is deleted.
        XCTAssertTrue(c.contains("defaults delete com.apple.dock autohide"), c.joined(separator: "\n") + "\n---\n" + r.out)
        XCTAssertTrue(c.contains("defaults write -g _HIHideMenuBar -bool false"))
        XCTAssertTrue(c.contains { $0.hasPrefix("defaults write com.apple.dock autohide-delay -float 0.5") }, c.joined(separator: "\n"))
        XCTAssertFalse(c.contains { $0.hasPrefix("defaults write com.apple.dock autohide ") }, "a later value must not win")
        XCTAssertTrue(c.contains(#"hidutil property --set {"UserKeyMapping":[]}"#))
        XCTAssertTrue(c.contains("sudo -n /usr/bin/pmset disablesleep 0"))
        XCTAssertTrue(c.contains("killall Dock"))
        XCTAssertTrue(c.contains { $0.hasPrefix("osascript -l JavaScript - 1 ") && $0.hasSuffix("Pictures/old.jpg") },
                      "wallpaper restored on the recorded display, not on every screen showing the same picture")
        XCTAssertTrue(c.contains("skyrose wm quit") == false, "the WM was not running (pgrep stub)")
        // SIP-off mode was used and SIP is off: the reminder opens before the apps and data go.
        let reminder = try XCTUnwrap(c.firstIndex { $0.hasPrefix("open -W -n -a") && $0.hasSuffix("--sip-reminder") })
        let settingsTrash = try XCTUnwrap(c.firstIndex { $0.hasPrefix("trash") && $0.contains("SkyRose Settings.app") })
        let supportTrash = try XCTUnwrap(c.firstIndex { $0.hasPrefix("trash") && $0.hasSuffix("Application Support/SkyRose") })
        XCTAssertLessThan(reminder, settingsTrash)
        XCTAssertLessThan(reminder, supportTrash)
        // Apps and our link to the Trash; TestWindows was not put there by the installer: kept.
        XCTAssertFalse(fm.fileExists(atPath: path("Applications/SkyRose.app").path))
        XCTAssertFalse(fm.fileExists(atPath: path("Applications/SkyRose Settings.app").path))
        XCTAssertTrue(fm.fileExists(atPath: path(".Trash/SkyRose.app").path))
        XCTAssertTrue(fm.fileExists(atPath: path("Applications/TestWindows.app").path))
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: path(".local/bin/skyrose").path))
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: path(".local/bin/other").path), "a link that is not ours stays")
        // --yes defaults: config kept; data and logs to the Trash.
        XCTAssertTrue(fm.fileExists(atPath: path(".config/skyrose/config.toml").path))
        XCTAssertFalse(fm.fileExists(atPath: support.path))
        XCTAssertFalse(fm.fileExists(atPath: path("Library/Logs/SkyRose").path))
        XCTAssertTrue(r.out.contains("Report"))
    }

    func testRemovesConfigWhenAskedAndTestWindowsWhenTheInstallerPutItThere() throws {
        try makeFixture()
        try "app \(path("Applications/TestWindows.app").path)\n".write(to: support.appendingPathComponent("install-record.txt"), atomically: true, encoding: .utf8)
        let r = try runScript(["--yes", "--remove-config", "--no-color"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertFalse(fm.fileExists(atPath: path(".config/skyrose").path))
        XCTAssertFalse(fm.fileExists(atPath: path("Applications/TestWindows.app").path))
    }

    func testDryRunChangesNothing() throws {
        try makeFixture()
        let r = try runScript(["--dry-run", "--yes", "--no-color"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("would run: defaults delete com.apple.dock autohide"), r.out)
        XCTAssertTrue(r.out.contains("would run: to_trash"))
        XCTAssertFalse(calls.contains { $0.hasPrefix("defaults write") || $0.hasPrefix("defaults delete") || $0.hasPrefix("trash")
                || $0.hasPrefix("hidutil") || $0.hasPrefix("sudo") || $0.hasPrefix("open") }, calls.joined(separator: "\n"))
        XCTAssertTrue(fm.fileExists(atPath: path("Applications/SkyRose.app").path))
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("restore-manifest.json").path))
    }

    func testSecondRunIsANoOp() throws {
        try makeFixture()
        XCTAssertEqual(try runScript(["--yes", "--no-color"]).status, 0)
        try? fm.removeItem(at: log)
        let r = try runScript(["--yes", "--no-color"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("no macOS settings to put back"), r.out)
        XCTAssertFalse(calls.contains { $0.hasPrefix("defaults write") || $0.hasPrefix("trash") }, calls.joined(separator: "\n"))
    }

    func testProgressLinesForTheUninstallWindow() throws {
        try makeFixture()
        let r = try runScript(["--progress"], stdin: "ack\n")
        XCTAssertEqual(r.status, 0, r.out)
        let lines = r.out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.filter { $0.hasPrefix("::stage ") }.count, 9)
        XCTAssertTrue(lines.contains("::stage 1 9 windows Stopping the window manager"))
        XCTAssertTrue(lines.contains("::sip"), "the window shows the reminder itself")
        XCTAssertFalse(calls.contains { $0.hasPrefix("open") }, "no second reminder window")
        XCTAssertEqual(lines.last, "::finished")
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("::") }, lines.filter { !$0.hasPrefix("::") }.joined(separator: "\n"))
    }

    func testRefusesTheRealAccount() throws {
        // A sandbox run with the real HOME is refused before anything (dry run anyway, to be safe).
        let real = try runScript(["--dry-run", "--yes"], home: NSHomeDirectory())
        XCTAssertEqual(real.status, 4, real.out)
        XCTAssertTrue(real.out.contains("refused"))
        // A fixture HOME but the real `defaults` first on PATH: refused as well.
        try makeFixture()
        let unstubbed = try runScript(["--dry-run", "--yes"], path: "/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(unstubbed.status, 4, unstubbed.out)
    }

    func testStopsWhenTheWindowManagerWillNotQuit() throws {
        try makeFixture()
        let pgrep = bin.appendingPathComponent("pgrep")
        try "#!/bin/sh\necho \"pgrep $*\" >> \"$HOME/calls.log\"\nexit 0\n".write(to: pgrep, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pgrep.path)
        let r = try runScript(["--yes", "--no-color"])
        XCTAssertNotEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("still running"), r.out)
        XCTAssertTrue(fm.fileExists(atPath: path("Applications/SkyRose.app").path), "apps stay when the WM is still running")
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("restore-manifest.json").path))
        XCTAssertFalse(calls.contains { $0.hasPrefix("defaults ") || $0.hasPrefix("trash ") || $0.hasPrefix("hidutil") }, calls.joined(separator: "\n"))
    }

    func testKeepsTheManifestAndFailsWhenARestoreFails() throws {
        try makeFixture()
        let defaults = bin.appendingPathComponent("defaults")
        try "#!/bin/sh\necho \"defaults $*\" >> \"$HOME/calls.log\"\nif [ \"$1\" = read ]; then exit 0; fi\nexit 1\n"
            .write(to: defaults, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: defaults.path)
        let r = try runScript(["--yes", "--no-color"])
        XCTAssertNotEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("defaults write failed") || r.out.contains("defaults delete failed"), r.out)
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("restore-manifest.json").path),
                      "a failed restore must not throw the manifest away")
        XCTAssertTrue(r.out.contains("kept Application Support"), r.out)
    }

    func testRestoresStructuredDefaultsHotkeysAndOneWallpaperPerDisplay() throws {
        try makeFixture()
        let journal = BackupJournal(url: support.appendingPathComponent("restore-manifest.json"))
        try journal.append(BackupEntry(domain: "com.apple.dock", key: "persistent-apps",
                                        oldValue: .array([.string("Finder"), .int(2), .bool(true)]),
                                        newValue: .array([.string("SkyRose")]), kind: .defaults))
        try journal.append(BackupEntry(domain: "com.example", key: "opts",
                                        oldValue: .dict(["name": .string("a b"), "n": .int(3), "flag": .bool(false)]),
                                        newValue: .dict(["name": .string("x")]), kind: .defaults))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-09T10:43:00Z"))
        try journal.append(BackupEntry(domain: "NSGlobalDomain", key: "AppleDate", oldValue: .date(date), newValue: .date(date), kind: .defaults))
        try journal.append(BackupEntry(
            domain: "com.apple.symbolichotkeys", key: "28",
            oldValue: .dict(["enabled": .bool(true), "value": .dict(["type": .string("standard"), "parameters": .array([.int(65535), .int(20), .int(1179648)])])]),
            newValue: .dict(["enabled": .bool(false)]), kind: .symbolichotkeys))
        try journal.append(BackupEntry(domain: "com.apple.symbolichotkeys", key: "184", oldValue: .absent,
                                        newValue: .dict(["enabled": .bool(true)]), kind: .symbolichotkeys))
        let old2 = path("Pictures/old2.jpg")
        try Data("jpg".utf8).write(to: old2)
        try journal.append(BackupEntry(domain: "UUID-2", key: "wallpaper", oldValue: .string(old2.path), newValue: .string("/w/b.jpg"), kind: .wallpaper))
        let old3 = path("Pictures/old3.jpg")
        try Data("jpg".utf8).write(to: old3)
        try journal.append(BackupEntry(domain: "UUID-3", key: "wallpaper", oldValue: .string(old3.path), newValue: .string("/w/c.jpg"), kind: .wallpaper))
        let replaced = path("Pictures/replaced.txt")
        let saved = path("Pictures/saved-copy.txt")
        try "NEW".write(to: replaced, atomically: true, encoding: .utf8)
        try "OLD".write(to: saved, atomically: true, encoding: .utf8)
        try journal.append(BackupEntry(domain: "files", key: replaced.path, oldValue: .string(saved.path), newValue: .string("NEW"), kind: .file))
        let created = path("Pictures/created-by-skyrose.txt")
        try "x".write(to: created, atomically: true, encoding: .utf8)
        try journal.append(BackupEntry(domain: "files", key: created.path, oldValue: .absent, newValue: .string("x"), kind: .file))
        let prefsDir = path("Library/Preferences")
        try fm.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        let current: [String: Any] = [
            "AppleSymbolicHotKeys": [
                "28": ["enabled": false, "value": ["type": "standard", "parameters": [1, 2, 3]]],
                "184": ["enabled": true],
                "30": ["enabled": true, "value": ["type": "standard", "parameters": [9, 9, 9]]],
            ] as [String: Any],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: current, format: .xml, options: 0)
        let prefs = prefsDir.appendingPathComponent("com.apple.symbolichotkeys.plist")
        try data.write(to: prefs)
        try """
        UUID-1\t1\t/w/b.jpg
        UUID-2\t2\t/w/b.jpg
        UUID-3\t3\t/not-skyrose.jpg
        """.write(to: home.appendingPathComponent("screens.tsv"), atomically: true, encoding: .utf8)

        let r = try runScript(["--yes", "--no-color"])
        XCTAssertEqual(r.status, 0, r.out)
        let c = calls
        XCTAssertTrue(c.contains("defaults write com.apple.dock persistent-apps -array -string Finder -int 2 -bool true"), c.joined(separator: "\n"))
        XCTAssertTrue(c.contains("defaults write com.example opts -dict flag -bool false n -int 3 name -string a b"), c.joined(separator: "\n"))
        XCTAssertTrue(c.contains("defaults write -g AppleDate -date 2026-11-09 10:43:00 +0000"), c.joined(separator: "\n"))
        let restored = try PropertyListSerialization.propertyList(from: Data(contentsOf: prefs), options: [], format: nil) as? [String: Any]
        let hotkeys = try XCTUnwrap(restored?["AppleSymbolicHotKeys"] as? [String: Any])
        let shortcut28 = try XCTUnwrap(hotkeys["28"] as? [String: Any])
        XCTAssertEqual((shortcut28["enabled"] as? NSNumber)?.boolValue, true)
        let parameters = ((shortcut28["value"] as? [String: Any])?["parameters"] as? [Any])?.map { ($0 as? NSNumber)?.intValue }
        XCTAssertEqual(parameters, [65535, 20, 1179648])
        XCTAssertNil(hotkeys["184"], "a shortcut SkyRose added is removed, and only that one")
        XCTAssertNotNil(hotkeys["30"], "a shortcut SkyRose never touched stays")
        let wall = c.filter { $0.hasPrefix("osascript -l JavaScript - ") }
        XCTAssertEqual(wall.filter { $0.contains(" - 1 ") && $0.hasSuffix("Pictures/old.jpg") }.count, 1, wall.joined(separator: "\n"))
        XCTAssertEqual(wall.filter { $0.contains(" - 2 ") && $0.hasSuffix("Pictures/old2.jpg") }.count, 1, wall.joined(separator: "\n"))
        XCTAssertTrue(wall.allSatisfy { !$0.contains(" - 3 ") }, "a display that no longer shows SkyRose's picture is left alone: \(wall)")
        XCTAssertTrue(r.out.contains("no longer shows SkyRose's picture"), r.out)
        XCTAssertEqual(try String(contentsOf: replaced, encoding: .utf8), "OLD")
        XCTAssertFalse(fm.fileExists(atPath: created.path))
    }

    func testDoesNotTrashAnythingUntilTheSIPReminderIsAcknowledged() throws {
        try makeFixture()
        let ignored = try runScript(["--progress"])
        XCTAssertNotEqual(ignored.status, 0, ignored.out)
        XCTAssertTrue(ignored.out.contains("::sip"), ignored.out)
        XCTAssertFalse(ignored.out.contains("::finished"), ignored.out)
        XCTAssertTrue(ignored.out.contains("not acknowledged"), ignored.out)
        XCTAssertFalse(calls.contains { $0.hasPrefix("trash") || $0.hasPrefix("open") }, calls.joined(separator: "\n"))
        XCTAssertTrue(fm.fileExists(atPath: path("Applications/SkyRose.app").path))
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("restore-manifest.json").path))

        // A real acknowledgement, and only after ::sip, is what lets removal start.
        try? fm.removeItem(at: log)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [Self.script.path, "--progress"]
        proc.environment = scriptEnvironment()
        let input = Pipe()
        let output = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = output
        try proc.run()
        let handle = output.fileHandleForReading
        let box = SIPReadBox()
        let started = Date()
        DispatchQueue.global().async {
            var text = ""
            while !text.contains("::sip"), Date().timeIntervalSince(started) < 8 {
                let data = handle.availableData
                if data.isEmpty { break }
                text += String(decoding: data, as: UTF8.self)
            }
            box.text = text
            box.done.signal()
        }
        if box.done.wait(timeout: .now() + 10) != .success {
            proc.terminate()
            XCTFail("timed out waiting for ::sip\n\(box.text)")
            return
        }
        var text = box.text
        XCTAssertTrue(text.contains("::sip"), text)
        XCTAssertFalse(calls.contains { $0.hasPrefix("trash") }, "nothing is trashed before the reminder is acknowledged\n\(calls.joined(separator: "\n"))")
        XCTAssertTrue(fm.fileExists(atPath: path("Applications/SkyRose.app").path))
        input.fileHandleForWriting.write(Data("ack\n".utf8))
        try? input.fileHandleForWriting.close()
        text += String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("::finished"), text)
        XCTAssertFalse(fm.fileExists(atPath: path("Applications/SkyRose.app").path))
        let sip = text.split(separator: "\n").firstIndex { $0 == "::sip" }
        let trashed = text.split(separator: "\n").firstIndex { $0.contains("SkyRose.app to the Trash") }
        XCTAssertNotNil(sip)
        XCTAssertNotNil(trashed)
        XCTAssertLessThan(sip ?? 0, trashed ?? 0)
    }

    func testTerminalReminderMustOpenBeforeAnythingIsTrashed() throws {
        try makeFixture()
        let open = bin.appendingPathComponent("open")
        try "#!/bin/sh\necho \"open $*\" >> \"$HOME/calls.log\"\nexit 1\n".write(to: open, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: open.path)
        let r = try runScript(["--yes", "--no-color"])
        XCTAssertNotEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("could not be shown"), r.out)
        XCTAssertFalse(calls.contains { $0.hasPrefix("trash") }, calls.joined(separator: "\n"))
        XCTAssertTrue(fm.fileExists(atPath: path("Applications/SkyRose.app").path))
        XCTAssertTrue(fm.fileExists(atPath: support.path))
    }

    func testRestoresTheDockRemovalKeysAndRestartsTheDock() throws {
        let journal = BackupJournal(url: support.appendingPathComponent("restore-manifest.json"))
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try journal.append(BackupEntry(domain: "com.apple.dock", key: "autohide", oldValue: .bool(false), newValue: .bool(true)))
        try journal.append(BackupEntry(domain: "com.apple.dock", key: "autohide-delay", oldValue: .absent, newValue: .double(1000)))
        try journal.append(BackupEntry(domain: "com.apple.dock", key: "autohide-time-modifier", oldValue: .double(0.5), newValue: .double(0)))
        try journal.append(BackupEntry(domain: "com.apple.dock", key: "tilesize", oldValue: .int(48), newValue: .int(16)))
        let r = try runScript(["--yes", "--no-color"])
        XCTAssertEqual(r.status, 0, r.out)
        let c = calls
        XCTAssertTrue(c.contains("defaults write com.apple.dock autohide -bool false"), c.joined(separator: "\n"))
        XCTAssertTrue(c.contains("defaults delete com.apple.dock autohide-delay"), c.joined(separator: "\n"))
        XCTAssertTrue(c.contains { $0.hasPrefix("defaults write com.apple.dock autohide-time-modifier -float 0.5") }, c.joined(separator: "\n"))
        XCTAssertTrue(c.contains("defaults write com.apple.dock tilesize -int 48"), c.joined(separator: "\n"))
        XCTAssertTrue(c.contains("killall Dock"), c.joined(separator: "\n"))
    }

    func testDockCommandParses() throws {
        let inv = try CLIParser.parse(["dock", "hide"])
        XCTAssertEqual(inv.kind, .local(.dock(.hide)))
    }

    func testCLIPassesTheFlagsThrough() throws {
        let inv = try CLIParser.parse(["uninstall", "--dry-run", "--remove-fonts", "--yes"])
        XCTAssertEqual(inv.kind, .local(.uninstall(flags: ["--dry-run", "--remove-fonts"])))
        XCTAssertTrue(inv.yes)
    }
}

/// Holds text read on a background thread until `::sip` arrives, so a stuck engine fails the test
/// instead of blocking the suite.
private final class SIPReadBox: @unchecked Sendable {
    var text = ""
    let done = DispatchSemaphore(value: 0)
}
