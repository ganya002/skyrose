import CaelestiaCore
import Foundation
import XCTest
@testable import CaelestiaShell

/// A real widget process under the sandbox: it can talk to SkyRose and write its data folder, and
/// it cannot read the home folder, write elsewhere or reach the network.
@MainActor
final class WidgetHostTests: XCTestCase {
    func testSandboxedWidgetTalksAndIsContained() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent("dev.x.test/1.0.0", isDirectory: true)
        let data = root.appendingPathComponent("dev.x.test/data", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let home = fm.homeDirectoryForCurrentUser.path
        try """
        r=""
        ls "\(home)" >/dev/null 2>&1 && r="$r home-LEAK" || r="$r home-blocked"
        echo x > "$HOME/ok" && r="$r data-ok" || r="$r data-blocked"
        echo x > "\(root.path)/escape" 2>/dev/null && r="$r write-LEAK" || r="$r write-blocked"
        printf '{"set":{"text":"%s"}}\\n' "$r"
        echo '{"toast":{"title":"no permission"}}'
        read line
        printf '{"set":{"text":"got %s"}}\\n' "$line"
        sleep 30
        """.write(to: dir.appendingPathComponent("w.sh"), atomically: true, encoding: .utf8)

        let r = Runner(id: "dev.x.test", dir: dir, data: data, script: "w.sh", interpreter: URL(fileURLWithPath: "/bin/sh"),
                       interpreterDir: nil, permissions: [])
        var lines: [String] = []
        let first = expectation(description: "first line"), echoed = expectation(description: "echo")
        r.onLine = { line in
            lines.append(line)
            if lines.count == 1 { first.fulfill() }
            if line.contains("got") { echoed.fulfill() }
        }
        r.start()
        wait(for: [first], timeout: 10)
        r.send(["event": "click"])
        wait(for: [echoed], timeout: 10)
        r.stop()

        XCTAssertEqual(WidgetMessage.parse(lines[0]), .set(title: nil, text: " home-blocked data-ok write-blocked", icon: nil))
        XCTAssertEqual(WidgetMessage.parse(lines[1])?.permission, .notifications, "the host refuses it: not declared")
        XCTAssertTrue(lines.contains { $0.contains(#"got {"event":"click"}"#) }, "\(lines)")
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("escape").path))
        XCTAssertTrue(fm.fileExists(atPath: data.appendingPathComponent("ok").path))
    }
}
