// Builds the SkyRose app icons from the artwork in Branding/:
//   Branding/SkyRose-Main.png → Packaging/SkyRose.icns    (SkyRose.app, SkyRose Settings.app)
//   Branding/SkyRose-WM.png   → Packaging/SkyRoseWM.icns  (the WM: WM-only mode, mode pickers)
//
// The artwork is an opaque square: a dark squircle on pure black corners. This script makes the
// corners transparent (flood fill from the four corners over near-black pixels, then an
// anti-aliased edge from the luminance ratio against the squircle body), places the squircle on
// Apple's macOS icon grid (824 px body centred on a 1024 px canvas, like every other Dock icon)
// with a soft drop shadow, and writes every iconset size plus a 1024 px PNG next to the .icns.
//
// Usage: /usr/bin/swift scripts/make-icons.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()

/// The artwork with transparent corners, at its own resolution (RGBA, premultiplied).
func cutOut(_ source: URL) -> CGImage {
    guard let rep = NSBitmapImageRep(data: try! Data(contentsOf: source)), let cg = rep.cgImage else {
        fatalError("cannot read \(source.path)")
    }
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    func lum(_ i: Int) -> Double { (Double(px[i * 4]) + Double(px[i * 4 + 1]) + Double(px[i * 4 + 2])) / 3 }

    // Body colour/luminance: the median of a strip just inside the left edge, mid-height.
    var strip: [Int] = []
    for y in (h / 2 - 40)..<(h / 2 + 40) { for x in 4..<16 { strip.append(y * w + x) } }
    let sorted = strip.sorted { lum($0) < lum($1) }
    let ref = sorted[sorted.count / 2]
    let bodyLum = lum(ref)
    let body = (Double(px[ref * 4]), Double(px[ref * 4 + 1]), Double(px[ref * 4 + 2]))

    // Outside = 4-connected near-black region reachable from the corners.
    let threshold = bodyLum * 0.45
    var outside = [Bool](repeating: false, count: w * h)
    var stack = [0, w - 1, (h - 1) * w, h * w - 1]
    while let i = stack.popLast() {
        guard !outside[i], lum(i) < threshold else { continue }
        outside[i] = true
        let x = i % w, y = i / w
        if x > 0 { stack.append(i - 1) }
        if x < w - 1 { stack.append(i + 1) }
        if y > 0 { stack.append(i - w) }
        if y < h - 1 { stack.append(i + w) }
    }
    // Edge band: pixels within 3 px of the outside get coverage = luminance / body luminance
    // and the body colour (the artwork was anti-aliased against black).
    var alpha = [Double](repeating: 1, count: w * h)
    for i in 0..<(w * h) where outside[i] { alpha[i] = 0 }
    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            guard !outside[i] else { continue }
            var near = false
            outer: for dy in -3...3 {
                for dx in -3...3 {
                    let xx = x + dx, yy = y + dy
                    if xx >= 0, xx < w, yy >= 0, yy < h, outside[yy * w + xx] { near = true; break outer }
                }
            }
            if near { alpha[i] = min(1, lum(i) / bodyLum) }
        }
    }
    for i in 0..<(w * h) {
        let a = alpha[i]
        if a >= 1 { continue }
        px[i * 4] = UInt8(body.0 * a)
        px[i * 4 + 1] = UInt8(body.1 * a)
        px[i * 4 + 2] = UInt8(body.2 * a)
        px[i * 4 + 3] = UInt8((a * 255).rounded())
    }
    return ctx.makeImage()!
}

/// The cut-out squircle on Apple's grid at `size` px, with a soft shadow.
func render(_ art: CGImage, size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    if size >= 64 {
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 20 * s, color: CGColor(gray: 0, alpha: 0.30))
    }
    ctx.draw(art, in: body)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func build(_ artwork: String, _ name: String) throws {
    let art = cutOut(root.appendingPathComponent("Branding/\(artwork)"))
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let file = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            try render(art, size: base * scale).write(to: iconset.appendingPathComponent(file))
        }
    }
    let out = root.appendingPathComponent("Packaging/\(name).icns")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("iconutil failed for \(name)") }
    try render(art, size: 1024).write(to: root.appendingPathComponent("Packaging/\(name)-1024.png"))
    print("wrote \(out.path)")
}

try build("SkyRose-Main.png", "SkyRose")
try build("SkyRose-WM.png", "SkyRoseWM")
