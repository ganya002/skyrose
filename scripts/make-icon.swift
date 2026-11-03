// Draws the Caelestia for Mac app icon (night-sky squircle, crescent moon, tiled-window grid)
// and writes Packaging/CaelestiaWM.icns.  Usage: /usr/bin/swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("CaelestiaWM.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // Squircle body, inset like Apple's icon grid.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.07, blue: 0.24, alpha: 1),
                        NSColor(srgbRed: 0.28, green: 0.16, blue: 0.52, alpha: 1)])!.draw(in: shape, angle: 90)
    // Stars.
    NSColor(white: 1, alpha: 0.85).setFill()
    for (x, y, r) in [(250.0, 760.0, 9.0), (380, 830, 6), (170, 470, 7), (450, 700, 5), (860, 380, 6), (600, 840, 5)] {
        NSBezierPath(ovalIn: NSRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)).fill()
    }
    // Tiled windows: one tall tile on the left, two stacked on the right.
    NSColor(srgbRed: 0.80, green: 0.74, blue: 1.0, alpha: 0.92).setFill()
    for r in [NSRect(x: 220, y: 220, width: 270, height: 390), NSRect(x: 520, y: 430, width: 280, height: 180),
              NSRect(x: 520, y: 220, width: 280, height: 180)] {
        NSBezierPath(roundedRect: NSRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s),
                     xRadius: 34 * s, yRadius: 34 * s).fill()
    }
    // Crescent moon, top right.
    // Moon disc minus an offset disc: clip to the disc, fill everything outside the bite.
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: NSRect(x: 560 * s, y: 620 * s, width: 230 * s, height: 230 * s)).addClip()
    let outsideBite = NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size))
    outsideBite.append(NSBezierPath(ovalIn: NSRect(x: 625 * s, y: 675 * s, width: 210 * s, height: 210 * s)))
    outsideBite.windingRule = .evenOdd
    NSColor(srgbRed: 1.0, green: 0.86, blue: 0.55, alpha: 1).setFill()
    outsideBite.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("Packaging/CaelestiaWM.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
