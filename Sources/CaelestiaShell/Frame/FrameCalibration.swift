import AppKit
import CaelestiaCore

/// Which pair of corners `frame calibrate` is tuning (notched MacBook panels round their top
/// corners only, so the two pairs have their own radius).
public enum CalibrationCorners: String, Sendable {
    case top, bottom

    var configKey: String { self == .top ? "displayCornerRadius" : "displayBottomCornerRadius" }
    var toggled: CalibrationCorners { self == .top ? .bottom : .top }
}

/// `skyrose frame calibrate`: a key panel over one display that draws a thin bright outline
/// along the display edge with the radii being tried, while the screen frame underneath redraws
/// with them live. The radii are tuned by eye (Apple does not publish them):
///
/// - ↑ / ↓: ±0.5 pt, with ⇧: ±0.1 pt (the pair of corners being tuned)
/// - Tab: switch between the top and the bottom corners
/// - ← / →: previous / next display
/// - Return: save every changed radius to `[displays."<uuid>"] displayCornerRadius` /
///   `displayBottomCornerRadius` in config.toml
/// - Esc: cancel (nothing saved, the configured radii come back)
///
/// When the radius matches the hardware, the bright line runs around the corner at an even
/// width. Too large and the wallpaper shows in the corner outside the line; too small and the
/// line is cut off by the hardware corner.
@MainActor
final class FrameCalibration {
    let panel: ShellPanel
    let view: FrameCalibrationView
    private(set) var displayID: String
    var corners: CalibrationCorners = .top {
        didSet { view.corners = corners }
    }

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

    func setRadii(top: Double, bottom: Double) {
        view.radius = top
        view.bottomRadius = bottom
    }

    func close() {
        panel.onKeyDown = nil
        if panel.isKeyWindow { panel.resignKey() }
        let panel = panel
        panel.fadeOut(duration: 0.15) { panel.close() }
    }
}

/// The outline and the instructions.
final class FrameCalibrationView: NSView {
    /// Top corners (and bottom ones until `bottomRadius` is set).
    var radius: Double = 0 { didSet { needsDisplay = true } }
    var bottomRadius: Double? { didSet { needsDisplay = true } }
    var corners: CalibrationCorners = .top { didSet { needsDisplay = true } }
    var displayName = "" { didSet { needsDisplay = true } }
    static let dimColor = NSColor(calibratedWhite: 1, alpha: 0.35)
    /// Bright and thin so its edge against the hardware corner is easy to judge.
    static let lineWidth: Double = 1.5
    static let lineColor = NSColor(calibratedRed: 0.2, green: 1, blue: 0.75, alpha: 1)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// The outline: the display edge inset by half the line, so the line's outer edge is the
    /// rounded rectangle being tried.
    static func outline(in bounds: CGRect, radius: Double) -> CGPath {
        outline(in: bounds, top: radius, bottom: radius)
    }

    /// Per pair of corners (y-down: top = the screen's top edge).
    static func outline(in bounds: CGRect, top: Double, bottom: Double) -> CGPath {
        let w = lineWidth
        let b = bounds.insetBy(dx: w / 2, dy: w / 2)
        func r(_ v: Double) -> Double { max(0, min(v - w / 2, bounds.width / 2, bounds.height / 2)) }
        let path = CGMutablePath()
        FramePath.addRoundedPolygon([
            (CGPoint(x: b.minX, y: b.minY), r(top)), (CGPoint(x: b.maxX, y: b.minY), r(top)),
            (CGPoint(x: b.maxX, y: b.maxY), r(bottom)), (CGPoint(x: b.minX, y: b.maxY), r(bottom)),
        ], to: path)
        path.closeSubpath()
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let bottom = bottomRadius ?? radius
        // The whole outline dim, the pair being tuned bright (the two edges it sits on).
        ctx.addPath(Self.outline(in: bounds, top: radius, bottom: bottom))
        ctx.setStrokeColor(Self.dimColor.cgColor)
        ctx.setLineWidth(Self.lineWidth)
        ctx.strokePath()
        ctx.saveGState()
        let half = bounds.height / 2
        ctx.clip(to: corners == .top ? CGRect(x: 0, y: 0, width: bounds.width, height: half)
                                     : CGRect(x: 0, y: half, width: bounds.width, height: half))
        ctx.addPath(Self.outline(in: bounds, top: radius, bottom: bottom))
        ctx.setStrokeColor(Self.lineColor.cgColor)
        ctx.strokePath()
        ctx.restoreGState()

        let value = corners == .top ? radius : bottom
        let title = String(format: "%@ corner radius  %.2f pt", corners == .top ? "Top" : "Bottom", value)
        let help = "\(displayName)\n↑ ↓  ±0.5 pt    ⇧ ↑ ↓  ±0.1 pt    Tab  top / bottom corners    ← →  other display\n"
            + "Too large: wallpaper shows outside the line.  Too small: the corner cuts the line.\nReturn  save    Esc  cancel"
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 3
        let text = NSMutableAttributedString(string: title + "\n", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: para,
        ])
        text.append(NSAttributedString(string: help, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white.withAlphaComponent(0.8), .paragraphStyle: para,
        ]))
        let size = text.boundingRect(with: CGSize(width: 760, height: 400), options: [.usesLineFragmentOrigin]).size
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
    /// The configured top corner radius of `display` (`frame.displayCornerRadius`, per-display
    /// override, auto default).
    func configuredCornerRadius(_ display: DisplayInfo) -> Double {
        configuredCornerRadius(display, corners: .top)
    }

    func configuredCornerRadius(_ display: DisplayInfo, corners: CalibrationCorners) -> Double {
        let f = state.config.resolved(forDisplay: display.id).frame
        return corners == .top ? f.cornerRadius(isBuiltIn: display.isBuiltIn, hasNotch: display.hasNotch)
                               : f.bottomCornerRadius(isBuiltIn: display.isBuiltIn, hasNotch: display.hasNotch)
    }

    private func trials(_ corners: CalibrationCorners) -> [String: Double] {
        corners == .top ? cornerRadiusTrials : bottomCornerRadiusTrials
    }

    private func setTrial(_ v: Double?, _ corners: CalibrationCorners, _ id: String) {
        if corners == .top { cornerRadiusTrials[id] = v } else { bottomCornerRadiusTrials[id] = v }
    }

    /// The radius the frame draws now: a value being calibrated, else the configured one. A saved
    /// trial is dropped once the reloaded config carries the same value.
    func displayCornerRadius(for display: DisplayInfo, corners: CalibrationCorners = .top) -> Double {
        let configured = configuredCornerRadius(display, corners: corners)
        guard let trial = trials(corners)[display.id] else { return configured }
        if calibration == nil, abs(trial - configured) < 0.001 {
            setTrial(nil, corners, display.id)
            return configured
        }
        return trial
    }

    public var isCalibratingFrame: Bool { calibration != nil }

    /// Opens the calibration on `display` (id or name; default: the one under the pointer).
    /// Returns the display id and its top corner radius.
    @discardableResult
    public func startFrameCalibration(display query: String? = nil) -> Result<(String, Double), FrameCalibrationError> {
        guard isRunning else { return .failure(FrameCalibrationError(message: "the shell is not running")) }
        let target: DisplayInfo?
        if let query, !query.isEmpty {
            target = state.displays.first { $0.id == query || $0.name.caseInsensitiveCompare(query) == .orderedSame }
            guard target != nil else { return .failure(FrameCalibrationError(message: "no display \"\(query)\"; see `skyrose query monitors`")) }
        } else {
            target = state.displays.first { $0.id == pointerDisplayID() } ?? state.displays.first
        }
        guard let d = target else { return .failure(FrameCalibrationError(message: "no display")) }
        let radius = displayCornerRadius(for: d)
        let bottom = displayCornerRadius(for: d, corners: .bottom)
        let frame = state.converter.toBottomLeft(d.frame)
        if let c = calibration {
            c.move(to: d.id, frame: frame, name: d.name, radius: radius)
        } else {
            let c = FrameCalibration(displayID: d.id, frame: frame, name: d.name, radius: radius)
            c.panel.onKeyDown = { [weak self] e in self?.calibrationKey(e) ?? false }
            calibration = c
        }
        calibration?.setRadii(top: radius, bottom: bottom)
        calibration.map { present($0.panel) }
        return .success((d.id, radius))
    }

    /// Key handling of the calibration panel. Returns true when the key was used.
    func calibrationKey(_ e: NSEvent) -> Bool {
        let fine = e.modifierFlags.contains(.shift)
        switch e.keyCode {
        case 126: stepCalibration(by: fine ? 0.1 : 0.5)
        case 125: stepCalibration(by: fine ? -0.1 : -0.5)
        case 48: calibration?.corners = calibration?.corners.toggled ?? .top
        case 123: switchCalibrationDisplay(by: -1)
        case 124: switchCalibrationDisplay(by: 1)
        case 36, 76: finishCalibration(save: true)
        case 53: finishCalibration(save: false)
        default: return false
        }
        return true
    }

    /// Changes the tried radius of the corners being tuned on the display being calibrated
    /// (clamped to 0...max).
    public func stepCalibration(by delta: Double) {
        guard let c = calibration, let d = state.displays.first(where: { $0.id == c.displayID }) else { return }
        let current = displayCornerRadius(for: d, corners: c.corners)
        let next = min(FrameConfig.maxRadius, max(0, ((current + delta) * 100).rounded() / 100))
        setTrial(next, c.corners, d.id)
        c.setRadii(top: displayCornerRadius(for: d), bottom: displayCornerRadius(for: d, corners: .bottom))
        rebuildSurfaces()
    }

    func switchCalibrationDisplay(by step: Int) {
        guard let c = calibration, state.displays.count > 1,
              let i = state.displays.firstIndex(where: { $0.id == c.displayID }) else { return }
        let next = state.displays[(i + step + state.displays.count) % state.displays.count]
        startFrameCalibration(display: next.id)
    }

    /// Return saves every radius that was changed; Esc forgets them.
    public func finishCalibration(save: Bool) {
        guard let c = calibration else { return }
        calibration = nil
        c.close()
        guard save else {
            cornerRadiusTrials.removeAll()
            bottomCornerRadiusTrials.removeAll()
            rebuildSurfaces()
            return
        }
        var saved: [String] = []
        for corners in [CalibrationCorners.top, .bottom] {
            for (id, radius) in trials(corners).sorted(by: { $0.key < $1.key }) {
                do {
                    try ConfigFileEditor.set(corners.configKey, to: ConfigFileEditor.number(radius),
                                             inTable: ConfigFileEditor.displayTable(id), file: configFileURL)
                    let name = state.displays.first { $0.id == id }?.name ?? id
                    saved.append("\(name) \(corners.rawValue): \(ConfigFileEditor.number(radius)) pt")
                } catch {
                    toast(.error, title: "Corner radius not saved", message: error.localizedDescription)
                    return
                }
            }
        }
        // The trials stay drawn until the config watcher reloads the same values.
        rebuildSurfaces()
        if !saved.isEmpty {
            toast(.success, title: "Corner radius saved", message: saved.joined(separator: ", "), icon: "checkmark.circle")
        }
    }
}
