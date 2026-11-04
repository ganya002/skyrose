import AppKit
import CaelestiaCore

/// `caelestia frame calibrate`: a key panel over one display that draws a thin bright outline
/// along the display edge with the radius being tried, while the screen frame underneath redraws
/// with it live. The radius is tuned by eye (Apple does not publish it):
///
/// - ↑ / ↓: ±0.5 pt, with ⇧: ±0.1 pt
/// - ← / →: previous / next display
/// - Return: save every tried display to `[displays."<uuid>"] displayCornerRadius` in config.toml
/// - Esc: cancel (nothing saved, the configured radii come back)
///
/// When the radius matches the hardware, the bright line runs around each corner at an even
/// width; too small and it vanishes into the corner, too large and a dark gap opens outside it.
@MainActor
final class FrameCalibration {
    let panel: ShellPanel
    let view: FrameCalibrationView
    private(set) var displayID: String

    init(displayID: String, frame: CGRect, name: String, radius: Double) {
        self.displayID = displayID
        panel = ShellPanel(frame: frame, level: ShellLevel.osd, clickThrough: true, name: "frame-calibration")
        panel.acceptsKey = true
        view = FrameCalibrationView(frame: CGRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.radius = radius
        view.displayName = name
        panel.contentView = view
    }

    func move(to displayID: String, frame: CGRect, name: String, radius: Double) {
        self.displayID = displayID
        panel.setFrame(frame, display: true)
        view.displayName = name
        view.radius = radius
    }

    func close() {
        panel.onKeyDown = nil
        if panel.isKeyWindow { panel.resignKey() }
        panel.orderOut(nil)
        panel.close()
    }
}

/// The outline and the instructions.
final class FrameCalibrationView: NSView {
    var radius: Double = 0 { didSet { needsDisplay = true } }
    var displayName = "" { didSet { needsDisplay = true } }
    /// Bright and thin so its edge against the hardware corner is easy to judge.
    static let lineWidth: Double = 1.5
    static let lineColor = NSColor(calibratedRed: 0.2, green: 1, blue: 0.75, alpha: 1)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// The outline: the display edge inset by half the line, so the line's outer edge is the
    /// rounded rectangle being tried.
    static func outline(in bounds: CGRect, radius: Double) -> CGPath {
        let w = lineWidth
        let r = max(0, min(radius - w / 2, bounds.width / 2, bounds.height / 2))
        return CGPath(roundedRect: bounds.insetBy(dx: w / 2, dy: w / 2), cornerWidth: r, cornerHeight: r, transform: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.addPath(Self.outline(in: bounds, radius: radius))
        ctx.setStrokeColor(Self.lineColor.cgColor)
        ctx.setLineWidth(Self.lineWidth)
        ctx.strokePath()

        let title = String(format: "Display corner radius  %.2f pt", radius)
        let help = "\(displayName)\n↑ ↓  ±0.5 pt    ⇧ ↑ ↓  ±0.1 pt    ← →  other display\nReturn  save    Esc  cancel"
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 3
        let text = NSMutableAttributedString(string: title + "\n", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: para,
        ])
        text.append(NSAttributedString(string: help, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white.withAlphaComponent(0.8), .paragraphStyle: para,
        ]))
        let size = text.boundingRect(with: CGSize(width: 520, height: 400), options: [.usesLineFragmentOrigin]).size
        let box = CGRect(x: bounds.midX - size.width / 2 - 22, y: bounds.midY - size.height / 2 - 16,
                         width: size.width + 44, height: size.height + 32)
        NSColor(calibratedWhite: 0.08, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16).fill()
        text.draw(with: box.insetBy(dx: 22, dy: 16), options: [.usesLineFragmentOrigin])
    }
}

public struct FrameCalibrationError: Error, Equatable {
    public var message: String
}

extension ShellController {
    /// The configured corner radius of `display` (`frame.displayCornerRadius`, per-display
    /// override, auto default).
    func configuredCornerRadius(_ display: DisplayInfo) -> Double {
        state.config.resolved(forDisplay: display.id).frame.cornerRadius(isBuiltIn: display.isBuiltIn)
    }

    /// The radius the frame draws now: a value being calibrated, else the configured one. A saved
    /// trial is dropped once the reloaded config carries the same value.
    func displayCornerRadius(for display: DisplayInfo) -> Double {
        let configured = configuredCornerRadius(display)
        guard let trial = cornerRadiusTrials[display.id] else { return configured }
        if calibration == nil, abs(trial - configured) < 0.001 {
            cornerRadiusTrials[display.id] = nil
            return configured
        }
        return trial
    }

    public var isCalibratingFrame: Bool { calibration != nil }

    /// Opens the calibration on `display` (id or name; default: the one under the pointer).
    @discardableResult
    public func startFrameCalibration(display query: String? = nil) -> Result<(String, Double), FrameCalibrationError> {
        guard isRunning else { return .failure(FrameCalibrationError(message: "the shell is not running")) }
        let target: DisplayInfo?
        if let query, !query.isEmpty {
            target = state.displays.first { $0.id == query || $0.name.caseInsensitiveCompare(query) == .orderedSame }
            guard target != nil else { return .failure(FrameCalibrationError(message: "no display \"\(query)\"; see `caelestia query monitors`")) }
        } else {
            target = state.displays.first { $0.id == pointerDisplayID() } ?? state.displays.first
        }
        guard let d = target else { return .failure(FrameCalibrationError(message: "no display")) }
        let radius = displayCornerRadius(for: d)
        let frame = state.converter.toBottomLeft(d.frame)
        if let c = calibration {
            c.move(to: d.id, frame: frame, name: d.name, radius: radius)
        } else {
            let c = FrameCalibration(displayID: d.id, frame: frame, name: d.name, radius: radius)
            c.panel.onKeyDown = { [weak self] e in self?.calibrationKey(e) ?? false }
            calibration = c
        }
        calibration.map { present($0.panel) }
        return .success((d.id, radius))
    }

    /// Key handling of the calibration panel. Returns true when the key was used.
    func calibrationKey(_ e: NSEvent) -> Bool {
        let fine = e.modifierFlags.contains(.shift)
        switch e.keyCode {
        case 126: stepCalibration(by: fine ? 0.1 : 0.5)
        case 125: stepCalibration(by: fine ? -0.1 : -0.5)
        case 123: switchCalibrationDisplay(by: -1)
        case 124: switchCalibrationDisplay(by: 1)
        case 36, 76: finishCalibration(save: true)
        case 53: finishCalibration(save: false)
        default: return false
        }
        return true
    }

    /// Changes the tried radius of the display being calibrated (clamped to 0...max).
    public func stepCalibration(by delta: Double) {
        guard let c = calibration, let d = state.displays.first(where: { $0.id == c.displayID }) else { return }
        let current = displayCornerRadius(for: d)
        let next = min(FrameConfig.maxRadius, max(0, ((current + delta) * 100).rounded() / 100))
        cornerRadiusTrials[d.id] = next
        c.view.radius = next
        rebuildSurfaces()
    }

    func switchCalibrationDisplay(by step: Int) {
        guard let c = calibration, state.displays.count > 1,
              let i = state.displays.firstIndex(where: { $0.id == c.displayID }) else { return }
        let next = state.displays[(i + step + state.displays.count) % state.displays.count]
        startFrameCalibration(display: next.id)
    }

    /// Return saves every display whose radius was changed; Esc forgets them.
    public func finishCalibration(save: Bool) {
        guard let c = calibration else { return }
        calibration = nil
        c.close()
        guard save else {
            cornerRadiusTrials.removeAll()
            rebuildSurfaces()
            return
        }
        var saved: [String] = []
        for (id, radius) in cornerRadiusTrials.sorted(by: { $0.key < $1.key }) {
            do {
                try ConfigFileEditor.set("displayCornerRadius", to: ConfigFileEditor.number(radius),
                                         inTable: ConfigFileEditor.displayTable(id), file: configFileURL)
                let name = state.displays.first { $0.id == id }?.name ?? id
                saved.append("\(name): \(ConfigFileEditor.number(radius)) pt")
            } catch {
                toast(.error, title: "Corner radius not saved", message: error.localizedDescription)
                return
            }
        }
        // The trials stay drawn until the config watcher reloads the same values.
        rebuildSurfaces()
        if !saved.isEmpty {
            toast(.success, title: "Corner radius saved", message: saved.joined(separator: ", "), icon: "checkmark.circle")
        }
    }
}
