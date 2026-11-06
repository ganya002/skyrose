import AppKit
import CaelestiaCore
import ScreenCaptureKit

/// The screenshot tool (Caelestia: grim + slurp + wl-copy + swappy/notify). ScreenCaptureKit
/// captures; a selection overlay on every display picks a region (drag) or a window (click);
/// freeze mode shows a still taken first. The result goes to `capture.folder` and/or the
/// clipboard, and a toast shows a thumbnail. Needs Screen Recording (the WM has it).
@MainActor
public final class ScreenshotController {
    public enum Outcome: Equatable {
        case saved(file: URL?, copied: Bool, size: CGSize)
        case cancelled
        case failed(String)
    }

    public var config = CaptureConfig()
    /// Called once per shot; `thumbnail` is a PNG on disk the toast can show.
    public var onFinish: ((Outcome, URL?) -> Void)?
    public var theme: ShellTheme = .gabby

    public private(set) var isActive = false
    private var overlays: [SelectionPanel] = []
    private var frozen: [CGDirectDisplayID: CGImage] = [:]
    private var mode: CaptureMode = .region

    public init() {}

    // MARK: Start

    public func start(_ mode: CaptureMode) {
        guard !isActive else { return }
        isActive = true
        self.mode = mode
        switch mode {
        case .full:
            let id = Self.displayUnderPointer()
            Task { @MainActor in
                do {
                    let image = try await Self.captureDisplay(id, local: nil)
                    self.finish(image)
                } catch { self.fail(error) }
            }
        case .freeze:
            Task { @MainActor in
                var stills: [CGDirectDisplayID: CGImage] = [:]
                for (id, _) in Self.displays() {
                    if let image = try? await Self.captureDisplay(id, local: nil) { stills[id] = image }
                }
                guard !stills.isEmpty else { self.fail(CaptureError.noImage); return }
                self.frozen = stills
                self.showOverlays()
            }
        case .region, .window:
            showOverlays()
        }
    }

    /// Esc / a second start: close the picker, no shot.
    public func cancel() {
        guard isActive else { return }
        closeOverlays()
        isActive = false
        frozen = [:]
        onFinish?(.cancelled, nil)
    }

    // MARK: Picker

    private func showOverlays() {
        let windows = Self.windowCandidates()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let bounds = CGDisplayBounds(id)
            let panel = SelectionPanel(screen: screen, displayBounds: bounds, frozen: frozen[id].map { NSImage(cgImage: $0, size: bounds.size) },
                                       windows: windows, windowOnly: mode == .window, accent: theme.ns(.primary))
            panel.onPick = { [weak self] pick in self?.picked(pick) }
            panel.onCancel = { [weak self] in self?.cancel() }
            overlays.append(panel)
            panel.orderFrontRegardless()
        }
        // Key focus for Esc on the display under the pointer.
        let pointer = Self.displayUnderPointer()
        (overlays.first { $0.displayBounds == CGDisplayBounds(pointer) } ?? overlays.first)?.makeKey()
        NSCursor.crosshair.set()
    }

    private func closeOverlays() {
        for o in overlays { o.orderOut(nil) }
        overlays.removeAll()
        NSCursor.arrow.set()
    }

    private func picked(_ pick: SelectionPanel.Pick) {
        closeOverlays()
        let rect: CGRect
        var windowID: CGWindowID?
        switch pick {
        case .region(let r): rect = r
        case .window(let w):
            rect = w.bounds
            windowID = w.id
        }
        if !frozen.isEmpty {
            // Freeze: crop the still of the display holding the selection's centre.
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            guard let (id, bounds) = Self.displays().first(where: { $0.1.contains(centre) }), let still = frozen[id],
                  let local = CaptureGeometry.local(rect, in: bounds) else { fail(CaptureError.noImage); return }
            let scale = Double(still.width) / bounds.width
            frozen = [:]
            guard let crop = still.cropping(to: CaptureGeometry.pixels(local, scale: scale)) else { fail(CaptureError.noImage); return }
            finish(crop)
            return
        }
        // Live: let the overlay leave the screen, then capture.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            do {
                if let windowID {
                    self.finish(try await Self.captureWindow(windowID))
                } else {
                    let centre = CGPoint(x: rect.midX, y: rect.midY)
                    guard let (id, bounds) = Self.displays().first(where: { $0.1.contains(centre) }),
                          let local = CaptureGeometry.local(rect, in: bounds) else { throw CaptureError.noImage }
                    self.finish(try await Self.captureDisplay(id, local: local))
                }
            } catch { self.fail(error) }
        }
    }

    // MARK: Output

    private func finish(_ image: CGImage) {
        isActive = false
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail(CaptureError.noImage); return }
        var file: URL?
        if config.saveToFolder {
            let folder = CaptureGeometry.folderURL(config.folder)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = CaptureGeometry.fileName(at: Date()) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
                let url = folder.appendingPathComponent(name)
                try png.write(to: url, options: .atomic)
                file = url
            } catch {
                Log.shell.error("screenshot not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
        if config.copyToClipboard {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
            pb.setData(rep.tiffRepresentation, forType: .tiff)
        }
        let thumb = file ?? Self.writeThumbnail(png)
        onFinish?(.saved(file: file, copied: config.copyToClipboard, size: CGSize(width: image.width, height: image.height)), thumb)
    }

    private func fail(_ error: Error) {
        closeOverlays()
        isActive = false
        frozen = [:]
        onFinish?(.failed(error.localizedDescription), nil)
    }

    private static func writeThumbnail(_ png: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("skyrose-last-screenshot.png")
        return (try? png.write(to: url, options: .atomic)) == nil ? nil : url
    }

    // MARK: ScreenCaptureKit

    enum CaptureError: LocalizedError {
        case noDisplay, noWindow, noImage
        var errorDescription: String? {
            switch self {
            case .noDisplay: return "That display is not available to ScreenCaptureKit."
            case .noWindow: return "That window can no longer be captured."
            case .noImage: return "Nothing was captured (Screen Recording permission?)."
            }
        }
    }

    /// One display (or `local`, display points, of it) at its native pixel size, no cursor.
    static func captureDisplay(_ id: CGDirectDisplayID, local: CGRect?) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CaptureError.noDisplay }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        let rect = local ?? CGRect(origin: .zero, size: display.frame.size)
        cfg.sourceRect = rect
        cfg.width = max(1, Int((rect.width * scale).rounded()))
        cfg.height = max(1, Int((rect.height * scale).rounded()))
        cfg.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// One window, without its shadow (grim of a window rect has none), at its pixel size.
    static func captureWindow(_ id: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cfg = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        cfg.width = max(1, Int((window.frame.width * scale).rounded()))
        cfg.height = max(1, Int((window.frame.height * scale).rounded()))
        cfg.ignoreShadowsSingleWindow = true
        cfg.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    // MARK: Screen facts

    /// Every display: id and global top-left bounds.
    static func displays() -> [(CGDirectDisplayID, CGRect)] {
        NSScreen.screens.compactMap { s in s.displayID.map { ($0, CGDisplayBounds($0)) } }
    }

    static func displayUnderPointer() -> CGDirectDisplayID {
        let p = CGEvent(source: nil)?.location ?? .zero
        return displays().first { $0.1.contains(p) }?.0 ?? CGMainDisplayID()
    }

    /// On-screen windows front to back (global top-left points).
    static func windowCandidates() -> [CaptureGeometry.WindowCandidate] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let id = d[kCGWindowNumber as String] as? CGWindowID, let pid = d[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = d[kCGWindowLayer as String] as? Int, let b = d[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
            return CaptureGeometry.WindowCandidate(id: id, pid: pid, layer: layer, bounds: rect)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}

/// The picker on one display: dims the screen (or shows the frozen still), drag selects a
/// rectangle with its size, hovering highlights the window under the pointer, a click takes that
/// window, Esc / right click cancels.
final class SelectionPanel: NSPanel {
    enum Pick { case region(CGRect), window(CaptureGeometry.WindowCandidate) }

    let displayBounds: CGRect
    var onPick: ((Pick) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, displayBounds: CGRect, frozen: NSImage?, windows: [CaptureGeometry.WindowCandidate], windowOnly: Bool, accent: NSColor) {
        self.displayBounds = displayBounds
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        title = "screenshot"
        setFrame(screen.frame, display: false)
        let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), displayBounds: displayBounds, frozen: frozen,
                                 windows: windows, windowOnly: windowOnly, accent: accent)
        view.onPick = { [weak self] in self?.onPick?($0) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class SelectionView: NSView {
    private let displayBounds: CGRect
    private let frozen: NSImage?
    private let windows: [CaptureGeometry.WindowCandidate]
    private let windowOnly: Bool
    private let accent: NSColor
    var onPick: ((SelectionPanel.Pick) -> Void)?
    var onCancel: (() -> Void)?

    private var start: CGPoint?
    private var current: CGPoint?
    private var hovered: CaptureGeometry.WindowCandidate?

    init(frame: CGRect, displayBounds: CGRect, frozen: NSImage?, windows: [CaptureGeometry.WindowCandidate], windowOnly: Bool, accent: NSColor) {
        self.displayBounds = displayBounds
        self.frozen = frozen
        self.windows = windows
        self.windowOnly = windowOnly
        self.accent = accent
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    /// View point → global top-left point.
    private func global(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + displayBounds.minX, y: p.y + displayBounds.minY) }
    private func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY) }
    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) {
        let w = CaptureGeometry.windowUnder(global(point(event)), in: windows, excludingPID: getpid())
        if w != hovered {
            hovered = w
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        start = point(event)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !windowOnly else { return }
        current = point(event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = start else { return }
        let e = point(event)
        start = nil
        current = nil
        if windowOnly || CaptureGeometry.isClick(from: s, to: e) {
            if let w = CaptureGeometry.windowUnder(global(e), in: windows, excludingPID: getpid()) { onPick?(.window(w)) }
            else if !windowOnly { onPick?(.region(displayBounds)) }  // a click on the desktop: the whole display
            needsDisplay = true
            return
        }
        let r = CaptureGeometry.selection(from: global(s), to: global(e)).intersection(displayBounds)
        if r.width >= 2, r.height >= 2 { onPick?(.region(r)) } else { needsDisplay = true }
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        frozen?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let hole: CGRect? = {
            if let s = start, let c = current, !windowOnly, !CaptureGeometry.isClick(from: s, to: c) { return CaptureGeometry.selection(from: s, to: c) }
            return hovered.map { local($0.bounds) }
        }()
        let dim = NSBezierPath(rect: bounds)
        if let hole { dim.append(NSBezierPath(rect: hole).reversed) }
        NSColor.black.withAlphaComponent(0.4).setFill()
        dim.fill()
        guard let hole else { return }
        accent.setStroke()
        let border = NSBezierPath(rect: hole.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        border.stroke()
        if start != nil {
            let label = "\(Int(hole.width)) × \(Int(hole.height))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
            let size = label.size(withAttributes: attrs)
            let origin = CGPoint(x: hole.maxX - size.width - 8, y: min(bounds.maxY - size.height - 10, hole.maxY + 6))
            let bg = NSBezierPath(roundedRect: CGRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6), xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.7).setFill()
            bg.fill()
            label.draw(at: origin, withAttributes: attrs)
        }
    }
}
