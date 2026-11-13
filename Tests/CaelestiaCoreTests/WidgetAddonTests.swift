import Foundation
import XCTest
@testable import CaelestiaCore

/// SkyStore `widget` addons: the manifest checks, the policy, the call format and the sandbox profile.
final class WidgetAddonTests: XCTestCase {
    func manifest(_ w: WidgetEntry?, permissions: [String] = [], files: [String: String]? = nil) -> AddonManifest {
        AddonManifest(id: "dev.someone.clock", name: "Clock", author: "Someone", version: "1.0.0", minSkyRose: "0.7.0", kind: .widget,
                      summary: "A clock", licence: "MIT", permissions: permissions, entry: .init(widget: w),
                      files: files ?? ["widget.sh": String(repeating: "a", count: 64)])
    }

    func testValidWidgetPassesPolicyFromAnyAuthor() {
        XCTAssertEqual(AddonPolicy.current.issues(manifest(WidgetEntry(script: "widget.sh", interpreter: "sh"), permissions: ["notifications", "media"])), [])
    }

    func testWidgetChecks() {
        XCTAssertTrue(manifest(nil).issues().contains { $0.contains("entry.widget must name") })
        XCTAssertTrue(manifest(WidgetEntry(script: "widget.sh", interpreter: "node")).issues().contains { $0.contains("interpreter must be one of") })
        XCTAssertTrue(manifest(WidgetEntry(script: "../x.sh", interpreter: "sh")).issues().contains { $0.contains("must be relative") })
        XCTAssertTrue(manifest(WidgetEntry(script: "other.sh", interpreter: "sh")).issues().contains { $0.contains("is not in files") })
    }

    func testWidgetsGetNoNetworkOrWindowsYet() {
        let w = WidgetEntry(script: "widget.sh", interpreter: "sh")
        XCTAssertEqual(AddonPolicy.current.issues(manifest(w, permissions: ["network:api.example.com"])), ["a widget addon cannot ask for network:api.example.com"])
        XCTAssertEqual(AddonPolicy.current.issues(manifest(w, permissions: ["windows"])), ["a widget addon cannot ask for windows"])
    }

    func testMessages() {
        XCTAssertEqual(WidgetMessage.parse(#"{"set":{"text":"21 °C","icon":"sunny"}}"#), .set(title: nil, text: "21 °C", icon: "sunny"))
        XCTAssertEqual(WidgetMessage.parse(#"{"toast":{"title":"Hi"}}"#), .toast(title: "Hi", message: ""))
        XCTAssertEqual(WidgetMessage.parse(#"{"get":"media"}"#), .getMedia)
        XCTAssertNil(WidgetMessage.parse(#"{"get":"windows"}"#))
        XCTAssertNil(WidgetMessage.parse(#"{"run":"rm -rf ~"}"#))
        XCTAssertNil(WidgetMessage.parse("not json"))
        XCTAssertNil(WidgetMessage.parse(#"{"set":{"text":"a"},"toast":{"title":"b"}}"#), "one call per line")
        guard case .set(_, let long, _) = WidgetMessage.parse(#"{"set":{"text":"\#(String(repeating: "x", count: 1000))"}}"#) else { return XCTFail() }
        XCTAssertEqual(long.count, WidgetMessage.maxText)
        XCTAssertNil(WidgetMessage.set(title: nil, text: "", icon: nil).permission)
        XCTAssertEqual(WidgetMessage.toast(title: "", message: "").permission, .notifications)
        XCTAssertEqual(WidgetMessage.getMedia.permission, .media)
    }

    func testProfileDeniesByDefaultAndHidesHome() {
        let p = WidgetSandbox.profile(addonDir: URL(fileURLWithPath: "/a/dev.x/1.0.0"), dataDir: URL(fileURLWithPath: "/a/dev.x/data"),
                                      home: URL(fileURLWithPath: "/Users/someone"), interpreterDir: nil)
        XCTAssertTrue(p.contains("(deny default)"))
        XCTAssertTrue(p.contains(#"(deny file-read* (subpath "/Users/someone"))"#))
        XCTAssertTrue(p.contains(#"(allow file-write* (subpath "/a/dev.x/data") (literal "/dev/null"))"#))
        XCTAssertFalse(p.contains("network"))
        XCTAssertFalse(p.contains("mach-lookup"))
        XCTAssertFalse(p.contains("osascript"))
        // A quote in a path cannot end the string and add rules.
        let q = WidgetSandbox.profile(addonDir: URL(fileURLWithPath: "/a/x\") (allow default"), dataDir: URL(fileURLWithPath: "/d"),
                                      home: URL(fileURLWithPath: "/h"), interpreterDir: nil)
        XCTAssertTrue(q.contains(#"(subpath "/a/x\") (allow default")"#), q)
    }
}
