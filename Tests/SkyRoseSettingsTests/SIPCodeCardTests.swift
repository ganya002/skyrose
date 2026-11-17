import AppKit
import CaelestiaCore
import SwiftUI
import XCTest

@testable import SkyRoseSettingsKit

@MainActor
final class SIPCodeCardTests: XCTestCase {
    /// The code is a plain bitmap. An `NSCIImageRep` ignored SwiftUI's frame and drew at its own
    /// 8x size over the next steps and the sidebar.
    func testTheCodeIsABitmapAndTheCardFitsItsWidth() throws {
        let image = try XCTUnwrap(SIPCode.image(SIPAssistant.script(SIPAssistant.enable(appleSilicon: true, loader: "sudo /x/skyrose-sa-loader"))))
        XCTAssertGreaterThan(image.width, 100)
        var r = SIPOffReadiness()
        r.appleSilicon = true
        for width in [380.0, 560.0, 900.0] {
            let card = SIPAssistantCard(readiness: r, loader: "sudo /x/skyrose-sa-loader")
                .frame(width: width)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            let out = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(Double(out.width) / 2, width, accuracy: 1, "the card stays inside the content width")
            if let dir = ProcessInfo.processInfo.environment["SKYROSE_SNAPSHOT_DIR"] {
                let rep = NSBitmapImageRep(cgImage: out)
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("sip-card-\(Int(width)).png"))
            }
        }
    }
}
