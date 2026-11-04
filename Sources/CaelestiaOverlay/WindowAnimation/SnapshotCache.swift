import AppKit
import ImageIO
import CaelestiaCore
import QuartzCore
import ScreenCaptureKit

/// ScreenCaptureKit stills the overlay draws instead of real windows: one per managed window
/// (captured on its own, so overlap and position do not matter) and one desktop still per display
/// (wallpaper + desktop icons, the only things behind the windows).
///
/// A capture takes far longer than a frame (live: tens of ms per window, 60–90 ms for a display),
/// so animations never wait for one. Stills are refreshed in the background when the layout has
/// been quiet for a moment, and an animation only starts when every still it needs is already
/// here; otherwise the pass is an instant move. Shared with the workspace slide (same
/// `SCShareableContent`).
@MainActor
public final class SnapshotCache {
    public struct Still {
        public var image: CGImage
        /// Window size (points) when captured.
        public var size: CGSize
        public var capturedAt: TimeInterval
        /// The opaque part of the image (unit rect, y-down as `CALayer.contentsRect`). A window
        /// captured right after a resize can still hold its old, smaller buffer: only this part
        /// is stretched over the tile, never a small picture in a transparent corner.
        public var contentRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    public var canCapture: () -> Bool = { CGPreflightScreenCaptureAccess() }
    public private(set) var windows: [CGWindowID: Still] = [:]
    public private(set) var desktops: [CGDirectDisplayID: Still] = [:]
    /// Rolling capture timings (ms) for `query`/logs.
    public private(set) var lastWindowCaptureMs: Double = 0
    public private(set) var averageWindowCaptureMs: Double = 0
    public private(set) var lastDesktopCaptureMs: Double = 0
    public private(set) var captures = 0
    public private(set) var failures = 0

    /// Desktop stills older than this are taken again after the next animation.
    public static let desktopMaxAge: TimeInterval = 30
    /// The pixel budget of one window still (keeps memory bounded on big Retina windows).
    public static let maxPixels: Double = 4_000_000

    var content: SCShareableContent?
    private var contentAt: TimeInterval = 0
    private var inFlight: Set<CGWindowID> = []
    private var queue: [CGWindowID] = []
    private var draining = false
    private var desktopInFlight: Set<CGDirectDisplayID> = []

    public init() {}

    public func still(for id: CGWindowID) -> Still? { windows[id] }
    public func desktop(for display: CGDirectDisplayID) -> Still? { desktops[display] }

    public func forget(_ id: CGWindowID) { windows[id] = nil }

    /// Keeps only stills of `ids` (closed windows' stills are dropped once their animation used them).
    public func retain(_ ids: Set<CGWindowID>) {
        for id in Array(windows.keys) where !ids.contains(id) { windows[id] = nil }
    }

    /// Display arrangement or Space changed: every still is suspect.
    public func invalidateAll() {
        windows.removeAll()
        desktops.removeAll()
        content = nil
    }

    public func invalidateDesktops() { desktops.removeAll() }

    // MARK: Refresh

    /// Queues fresh captures of `ids` (in order). Captures run one at a time off the critical path.
    public func refresh(_ ids: [CGWindowID]) {
        guard canCapture() else { return }
        for id in ids where !queue.contains(id) && !inFlight.contains(id) { queue.append(id) }
        drain()
    }

    private func drain() {
        guard !draining, !queue.isEmpty else { return }
        draining = true
        Task { @MainActor in
            while !self.queue.isEmpty {
                let id = self.queue.removeFirst()
                self.inFlight.insert(id)
                _ = await self.captureWindow(id)
                self.inFlight.remove(id)
            }
            self.draining = false
        }
    }

    /// Captures one window now. Nil when it is not shareable, fails, or comes back black.
    @discardableResult
    public func captureWindow(_ id: CGWindowID) async -> CGImage? {
        guard canCapture() else { return nil }
        let started = CACurrentMediaTime()
        guard let window = await scWindow(id) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // The live CG bounds, not `SCWindow.frame`: shareable content is cached and a window that
        // was just resized would be captured into its old aspect (content squeezed into part of
        // the still, the rest transparent; live finding on a pop-in).
        let bounds = OverlayController.cgBounds(id) ?? window.frame
        let size = bounds.size
        // The window's own backing scale (the display it is on). `pointPixelScale` reports the
        // highest scale of any display: a 1x window captured at 2x fills only the top-left of
        // the still (live: content 0.77 of a 2201 px still for a 1693 pt window).
        var scale = Double(ScreenSpace.scale(for: bounds))
        let pixels = size.width * scale * size.height * scale
        if pixels > Self.maxPixels { scale *= (Self.maxPixels / pixels).squareRoot() }
        config.width = max(1, Int((size.width * scale).rounded()))
        config.height = max(1, Int((size.height * scale).rounded()))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let ms = (CACurrentMediaTime() - started) * 1000
            lastWindowCaptureMs = ms
            captures += 1
            averageWindowCaptureMs = captures == 1 ? ms : averageWindowCaptureMs * 0.8 + ms * 0.2
            guard !WorkspaceSlide.isBlack(image) else {
                failures += 1
                return nil
            }
            let still = Still(image: image, size: size, capturedAt: CACurrentMediaTime(), contentRect: Self.opaqueBounds(image))
            windows[id] = still
            if let dir = ProcessInfo.processInfo.environment["CAELESTIA_DUMP_STILLS"] { Self.dump(still, name: "\(id)", to: dir, ms: ms) }
            return image
        } catch {
            failures += 1
            content = nil
            return nil
        }
    }

    /// Captures the desktop (wallpaper + icons) of `display` if it is missing or old.
    public func refreshDesktop(_ display: CGDirectDisplayID, force: Bool = false) {
        guard canCapture(), !desktopInFlight.contains(display) else { return }
        if !force, let d = desktops[display], CACurrentMediaTime() - d.capturedAt < Self.desktopMaxAge { return }
        desktopInFlight.insert(display)
        Task { @MainActor in
            _ = await self.captureDesktop(display)
            self.desktopInFlight.remove(display)
        }
    }

    @discardableResult
    public func captureDesktop(_ displayID: CGDirectDisplayID) async -> CGImage? {
        guard canCapture() else { return nil }
        let started = CACurrentMediaTime()
        do {
            let content = try await shareable(maxAge: 0)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
            // Only what sits below every window: the wallpaper and the desktop icons. Including
            // (not excluding) keeps a window that opens meanwhile out of the still.
            let desktop = content.windows.filter { $0.windowLayer < 0 && $0.frame.intersects(display.frame) }
            guard !desktop.isEmpty else { return nil }
            let filter = SCContentFilter(display: display, including: desktop)
            let config = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            config.width = Int((display.frame.width * scale).rounded())
            config.height = Int((display.frame.height * scale).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            lastDesktopCaptureMs = (CACurrentMediaTime() - started) * 1000
            guard !WorkspaceSlide.isBlack(image) else { return nil }
            desktops[displayID] = Still(image: image, size: display.frame.size, capturedAt: CACurrentMediaTime())
            if let dir = ProcessInfo.processInfo.environment["CAELESTIA_DUMP_STILLS"], let d = desktops[displayID] {
                Self.dump(d, name: "desktop-\(displayID)", to: dir, ms: lastDesktopCaptureMs)
            }
            return image
        } catch {
            content = nil
            return nil
        }
    }

    /// Unit rect of the pixels with alpha in a 64×64 downsample (full rect when all are clear).
    nonisolated static func opaqueBounds(_ image: CGImage) -> CGRect {
        let n = 64
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        var minX = n, minY = n, maxX = -1, maxY = -1
        // Bitmap rows run top to bottom in memory (row 0 = top of the image).
        for row in 0..<n {
            for col in 0..<n where pixels[(row * n + col) * 4 + 3] > 128 {
                minX = min(minX, col); maxX = max(maxX, col)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let r = CGRect(x: Double(minX) / Double(n), y: Double(minY) / Double(n),
                       width: Double(maxX - minX + 1) / Double(n), height: Double(maxY - minY + 1) / Double(n))
        // Within two cells of the full image: the full image (rounded window corners are clear).
        if r.width > 1 - 3.0 / Double(n), r.height > 1 - 3.0 / Double(n) { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return r
    }

    /// Debug aid (`CAELESTIA_DUMP_STILLS=<dir>`): writes the still as PNG plus its metadata.
    static func dump(_ still: Still, name: String, to dir: String, ms: Double) {
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(Int(CACurrentMediaTime() * 1000)).png")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, still.image, nil)
        CGImageDestinationFinalize(dest)
        let meta = "image \(still.image.width)x\(still.image.height) size \(still.size) content \(still.contentRect) captureMs \(String(format: "%.1f", ms))\n"
        try? meta.write(to: url.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Shareable content

    func shareable(maxAge: TimeInterval) async throws -> SCShareableContent {
        if let content, CACurrentMediaTime() - contentAt <= maxAge { return content }
        let fresh = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        content = fresh
        contentAt = CACurrentMediaTime()
        return fresh
    }

    private func scWindow(_ id: CGWindowID) async -> SCWindow? {
        if let w = try? await shareable(maxAge: 2).windows.first(where: { $0.windowID == id }) { return w }
        return try? await shareable(maxAge: 0).windows.first(where: { $0.windowID == id })
    }
}
