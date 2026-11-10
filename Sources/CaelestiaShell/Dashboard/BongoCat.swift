import AppKit
import SwiftUI

/// The Bongo Cat sprite from Caelestia, driven by detected beats instead of looping the gif. A beat
/// shows the slap with its motion ticks and swaps paws; between beats, or with nothing playing, the
/// cat holds its last pose without ticks.
struct BongoCat: View {
    /// The paw on the drum right now. Nil between beats.
    var paw: Int?
    var playing: Bool
    @State private var pose = 0

    var body: some View {
        let slap = playing ? paw : nil
        Group {
            if let image = BongoSprite.image(pose: slap ?? pose, slapping: slap != nil) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            }
        }
        .onChange(of: paw) { _, new in if let new { pose = new } }
        .accessibilityIdentifier("dashboard.bongo")
    }
}

/// The four frames, decoded once. They are 4x the gif (800 × 504), so they stay sharp on Retina.
enum BongoSprite {
    private static let frames: [String: NSImage] = {
        let root = Bundle.module.resourceURL
        var out: [String: NSImage] = [:]
        for name in ["slap-left", "slap-right", "rest-left", "rest-right"] {
            let url = [root?.appendingPathComponent("BongoCat/\(name).png"),
                       root?.appendingPathComponent("Resources/BongoCat/\(name).png")]
                .compactMap { $0 }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            if let url, let image = NSImage(contentsOf: url) { out[name] = image }
        }
        return out
    }()

    static func image(pose: Int, slapping: Bool) -> NSImage? {
        frames["\(slapping ? "slap" : "rest")-\(pose == 0 ? "left" : "right")"]
    }
}
