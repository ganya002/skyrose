import AppKit

// TestWindows: harness for the Riko regression suite (spec 12.2). Spawns plain NSWindows with
// known titles and solid, never-black colours. Options:
//   --windows N            open N windows (default 3)
//   --min WxH              give every window this minimum content size
//   --min-index I          apply --min only to window I (0-based)
//   --slow MS              block the main thread MS ms on every resize (simulates a laggy app)
//   --stubborn I           window I snaps back to its original size after each resize
//   --control PATH         watch PATH for commands, one per line: "open", "close N", "quit"
//   --title PREFIX         window title prefix (default "TestWindow")
// Each window shows its index and title; colours cycle through a fixed palette.

@MainActor
final class TestWindowsApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var minSize: NSSize?
    var minIndex: Int?
    var slowMs: Int = 0
    var stubbornIndex: Int?
    var stubbornSize: NSSize?
    var titlePrefix = "TestWindow"
    var controlPath: String?
    var controlTimer: Timer?
    var controlOffset = 0
    let palette: [NSColor] = [
        NSColor(calibratedRed: 0.73, green: 0.77, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.87, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.71, green: 0.80, blue: 0.73, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.44, alpha: 1),
        NSColor(calibratedRed: 0.76, green: 0.78, blue: 0.87, alpha: 1),
        NSColor(calibratedRed: 0.58, green: 0.67, blue: 0.80, alpha: 1),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        var count = 3
        var i = 1
        while i < args.count {
            let a = args[i]
            func next() -> String? { i + 1 < args.count ? args[i + 1] : nil }
            switch a {
            case "--windows": count = Int(next() ?? "") ?? count; i += 1
            case "--min":
                if let v = next() { let p = v.split(separator: "x"); if p.count == 2, let w = Double(p[0]), let h = Double(p[1]) { minSize = NSSize(width: w, height: h) } }
                i += 1
            case "--min-index": minIndex = Int(next() ?? ""); i += 1
            case "--slow": slowMs = Int(next() ?? "") ?? 0; i += 1
            case "--stubborn": stubbornIndex = Int(next() ?? ""); i += 1
            case "--control": controlPath = next(); i += 1
            case "--title": titlePrefix = next() ?? titlePrefix; i += 1
            default: break
            }
            i += 1
        }
        for _ in 0..<count { openWindow() }
        if let path = controlPath {
            FileManager.default.createFile(atPath: path, contents: Data())
            controlTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollControl() }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    func openWindow() -> NSWindow {
        let index = windows.count
        let w = NSWindow(
            contentRect: NSRect(x: 100 + 30 * index, y: 100 + 30 * index, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "\(titlePrefix) \(index)"
        w.isReleasedWhenClosed = false
        w.delegate = self
        let color = palette[index % palette.count]
        let view = NSView(frame: w.contentView!.bounds)
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.autoresizingMask = [.width, .height]
        let label = NSTextField(labelWithString: "\(w.title)\n\(color.hexString)")
        label.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .semibold)
        label.textColor = .black
        label.alignment = .center
        label.frame = NSRect(x: 0, y: view.bounds.midY - 40, width: view.bounds.width, height: 80)
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        view.addSubview(label)
        w.contentView = view
        if let m = minSize, minIndex == nil || minIndex == index { w.contentMinSize = m }
        if stubbornIndex == index { stubbornSize = w.frame.size }
        windows.append(w)
        w.makeKeyAndOrderFront(nil)
        return w
    }

    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if slowMs > 0 { usleep(UInt32(slowMs) * 1000) }
        if let idx = windows.firstIndex(of: w), idx == stubbornIndex, let size = stubbornSize, w.frame.size != size {
            DispatchQueue.main.async { w.setContentSize(size) }
        }
    }

    func pollControl() {
        guard let path = controlPath, let data = FileManager.default.contents(atPath: path), data.count > controlOffset else { return }
        let chunk = data.subdata(in: controlOffset..<data.count)
        controlOffset = data.count
        for line in String(decoding: chunk, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ")
            switch parts.first.map(String.init) {
            case "open": openWindow()
            case "close":
                if parts.count > 1, let n = Int(parts[1]), n < windows.count { windows[n].close() }
            case "quit": NSApp.terminate(nil)
            default: break
            }
        }
    }
}

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.deviceRGB) ?? self
        return String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

let app = NSApplication.shared
let delegate = TestWindowsApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
