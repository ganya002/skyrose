import AppKit
import CaelestiaCore
import QuartzCore

/// What the debug overlay shows (spec P1/P4): per display its usable area, every visible managed
/// window's target frame with a label, and a counters panel.
public struct DebugSnapshot: Equatable, Sendable {
    public struct Display: Equatable, Sendable {
        public var frame: CGRect
        public var usableArea: CGRect
        public var label: String
        public init(frame: CGRect, usableArea: CGRect, label: String) {
            self.frame = frame
            self.usableArea = usableArea
            self.label = label
        }
    }

    public struct Window: Equatable, Sendable {
        public var frame: CGRect
        public var label: String
        public var isFocused: Bool
        public init(frame: CGRect, label: String, isFocused: Bool) {
            self.frame = frame
            self.label = label
            self.isFocused = isFocused
        }
    }

    public var displays: [Display]
    public var windows: [Window]
    public var lines: [String]

    public init(displays: [Display] = [], windows: [Window] = [], lines: [String] = []) {
        self.displays = displays
        self.windows = windows
        self.lines = lines
    }
}

/// Click-through windows above everything (one per display) that draw a `DebugSnapshot`.
/// Off by default; `skyrose debug overlay` toggles it. Excluded from workspace-slide stills
/// (it belongs to our process).
@MainActor
public final class DebugOverlay {
    public private(set) var isVisible = false
    private var windows: [NSPanel] = []

    public init() {}

    public func show(_ snapshot: DebugSnapshot) {
        isVisible = true
        while windows.count > snapshot.displays.count { windows.removeLast().close() }
        while windows.count < snapshot.displays.count { windows.append(Self.makeWindow()) }
        for (window, display) in zip(windows, snapshot.displays) {
            draw(display, windows: snapshot.windows.filter { display.frame.intersects($0.frame) },
                 lines: display == snapshot.displays.first ? snapshot.lines : [], in: window)
        }
    }

    public func hide() {
        isVisible = false
        for w in windows { w.orderOut(nil); w.close() }
        windows = []
    }

    private static func makeWindow() -> NSPanel {
        let w = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary, .stationary]
        w.title = "SkyRose debug overlay"
        let v = NSView()
        v.wantsLayer = true
        w.contentView = v
        return w
    }

    private func draw(_ display: DebugSnapshot.Display, windows list: [DebugSnapshot.Window], lines: [String], in window: NSPanel) {
        let frame = ScreenSpace.cocoa(display.frame)
        window.setFrame(frame, display: false)
        guard let host = window.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.sublayers = nil
        // AppKit owns the flip of a view's backing layer; draw in a flipped sublayer (top-left
        // origin, like the AX frames) instead.
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        root.isGeometryFlipped = true
        host.addSublayer(root)
        let origin = display.frame.origin
        func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }

        let area = CAShapeLayer()
        area.path = CGPath(rect: local(display.usableArea).insetBy(dx: 0.5, dy: 0.5), transform: nil)
        area.fillColor = nil
        area.strokeColor = CGColor(srgbRed: 1, green: 0.6, blue: 0.2, alpha: 0.9)
        area.lineWidth = 1
        area.lineDashPattern = [6, 4]
        root.addSublayer(area)
        root.addSublayer(Self.label("\(display.label)  usable \(Self.rect(display.usableArea))", at: local(display.usableArea).origin, color: area.strokeColor!))

        for w in list {
            let box = CAShapeLayer()
            box.path = CGPath(rect: local(w.frame).insetBy(dx: 2.5, dy: 2.5), transform: nil)
            box.fillColor = nil
            box.strokeColor = w.isFocused ? CGColor(srgbRed: 0.3, green: 1, blue: 0.4, alpha: 0.95) : CGColor(srgbRed: 0.3, green: 0.8, blue: 1, alpha: 0.8)
            box.lineWidth = 1
            root.addSublayer(box)
            root.addSublayer(Self.label(w.label, at: local(w.frame).origin.applying(.init(translationX: 6, y: 6)), color: box.strokeColor!))
        }
        if !lines.isEmpty {
            let panel = Self.label(lines.joined(separator: "\n"), at: CGPoint(x: frame.width - 330, y: 40),
                                   color: CGColor(gray: 1, alpha: 0.95), width: 320)
            root.addSublayer(panel)
        }
        CATransaction.commit()
        window.orderFrontRegardless()
    }

    private static func label(_ text: String, at point: CGPoint, color: CGColor, width: Double = 520) -> CATextLayer {
        let l = CATextLayer()
        l.string = text
        l.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        l.fontSize = 11
        l.foregroundColor = color
        l.backgroundColor = CGColor(gray: 0, alpha: 0.55)
        l.cornerRadius = 4
        l.contentsScale = 2
        let lines = max(1, text.split(separator: "\n").count)
        l.frame = CGRect(x: point.x, y: point.y, width: width, height: Double(lines) * 14 + 4)
        return l
    }

    static func rect(_ r: CGRect) -> String {
        "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))"
    }
}
