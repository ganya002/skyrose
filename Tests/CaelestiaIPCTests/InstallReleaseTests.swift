import Foundation
import XCTest

/// `scripts/install-release.sh` against a temporary HOME and a locally built zip. It never downloads
/// and never writes the real account: a sandbox run whose HOME is the real one is refused.
final class InstallReleaseTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var script: URL { repo.appendingPathComponent("scripts/install-release.sh") }

    var home: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("skyrose-install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home, home.path.hasPrefix(fm.temporaryDirectory.path) { try? fm.removeItem(at: home) }
    }

    func makeZip() throws -> (zip: URL, sha: String) {
        let payload = home.appendingPathComponent("payload", isDirectory: true)
        for (app, exe) in [("SkyRose.app", "skyrose"), ("SkyRose Settings.app", "SkyRoseSettings")] {
            let mac = payload.appendingPathComponent("\(app)/Contents/MacOS", isDirectory: true)
            try fm.createDirectory(at: mac, withIntermediateDirectories: true)
            let bin = mac.appendingPathComponent(exe)
            try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: bin)
            let info = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleExecutable</key><string>\(exe)</string>
            <key>CFBundleIdentifier</key><string>com.skyrose.test.\(exe)</string>
            <key>CFBundleName</key><string>\(app)</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            </dict></plist>
            """
            try info.write(to: payload.appendingPathComponent("\(app)/Contents/Info.plist"), atomically: true, encoding: .utf8)
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--sign", "-", "--force", payload.appendingPathComponent(app).path]
            try sign.run()
            sign.waitUntilExit()
            XCTAssertEqual(sign.terminationStatus, 0)
        }
        let zip = home.appendingPathComponent("SkyRose.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.currentDirectoryURL = payload
        ditto.arguments = ["-c", "-k", ".", zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)
        let sum = Process()
        sum.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        sum.arguments = ["-a", "256", zip.path]
        let pipe = Pipe()
        sum.standardOutput = pipe
        try sum.run()
        sum.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (zip, text.split(separator: " ").first.map(String.init) ?? "")
    }

    @discardableResult
    func runScript(_ args: [String], env extra: [String: String] = [:], home h: String? = nil) throws -> (status: Int32, out: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [Self.script.path] + args
        var env = ["HOME": h ?? home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": NSTemporaryDirectory(), "SKYROSE_INSTALL_SANDBOX": "1"]
        extra.forEach { env[$0.key] = $0.value }
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.standardInput = FileHandle.nullDevice
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testInstallsACheckedZipAndRefusesABadHash() throws {
        let built = try makeZip()
        let ok = try runScript(["--yes", "--no-open", "--no-cli", "--no-color"], env: ["SKYROSE_RELEASE_ZIP": built.zip.path, "SKYROSE_RELEASE_SHA256": built.sha])
        XCTAssertEqual(ok.status, 0, ok.out)
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Applications/SkyRose.app").path))
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Applications/SkyRose Settings.app").path))
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(".local/bin/skyrose").path), "the CLI stays off unless asked")
        XCTAssertTrue(ok.out.contains("not notarized") || ok.out.contains("local identity"), ok.out)
        let record = try String(contentsOf: home.appendingPathComponent("Library/Application Support/SkyRose/install-record.txt"), encoding: .utf8)
        XCTAssertTrue(record.contains("SkyRose.app"))

        let bad = try runScript(["--yes", "--no-open", "--no-color"], env: ["SKYROSE_RELEASE_ZIP": built.zip.path, "SKYROSE_RELEASE_SHA256": String(repeating: "ab", count: 32)])
        XCTAssertEqual(bad.status, 4, bad.out)
        XCTAssertTrue(bad.out.contains("SHA-256"), bad.out)
    }

    func testDryRunChangesNothing() throws {
        let built = try makeZip()
        let r = try runScript(["--dry-run", "--yes", "--no-color"], env: ["SKYROSE_RELEASE_ZIP": built.zip.path, "SKYROSE_RELEASE_SHA256": built.sha])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("would install SkyRose.app"), r.out)
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent("Applications/SkyRose.app").path))
    }

    func testProgressLinesComeFromTheScript() throws {
        let built = try makeZip()
        let r = try runScript(["--progress", "--no-open"], env: ["SKYROSE_RELEASE_ZIP": built.zip.path, "SKYROSE_RELEASE_SHA256": built.sha])
        XCTAssertEqual(r.status, 0, r.out)
        let lines = r.out.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains { $0.hasPrefix("::stage ") && $0.contains(" verify ") }, r.out)
        XCTAssertEqual(lines.last, "::finished")
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("::") }, lines.filter { !$0.hasPrefix("::") }.joined(separator: "\n"))
    }

    func testRefusesTheRealAccount() throws {
        let r = try runScript(["--dry-run", "--yes"], home: NSHomeDirectory())
        XCTAssertEqual(r.status, 4, r.out)
        XCTAssertTrue(r.out.contains("refused"))
    }

    func testFromSourceDryRunPrintsThePlan() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [Self.repo.appendingPathComponent("scripts/install.sh").path, "--dry-run"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0, out)
        XCTAssertTrue(out.contains("would run scripts/build.sh"), out)
        XCTAssertTrue(out.contains("nothing is changed"), out)
    }
}
