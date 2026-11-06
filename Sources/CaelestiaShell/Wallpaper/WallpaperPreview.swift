import AppKit
import CaelestiaCore
import QuartzCore

/// Desktop-level image windows that show a wallpaper before (or instead of) macOS's own desktop
/// picture: the `>wallpaper` carousel previews through it and every wallpaper change cross-fades
/// through it (Caelestia `background.wallpaperTransition`, default crossfade, 600 ms).
///
/// The windows sit just above the live-wallpaper video and below the desktop icons and every app
/// window, ignore the mouse, and are on all Spaces. Nothing here changes the real desktop picture:
/// `finish()` is called after the caller set it underneath, `revert()` fades back to whatever the
/// desktop shows.
@MainActor
public final class WallpaperPreview {
    /// Caelestia's default transition length.
    public static let crossfade: Double = 0.6
    public static let windowLevel = NSWindow.Level(rawValue: LiveWallpaperController.windowLevel.rawValue + 1)

    /// The wallpaper being shown (or loading), nil when idle.
    public private(set) var url: URL?
    public var isActive: Bool { url != nil || !windows.isEmpty }
    private var windows: [NSWindow] = []
    /// Bumped by every request so a slow decode never lands after a newer one.
    private var generation = 0

    public init() {}

    /// Cross-fades the desktop to `url` (a still, or a live wallpaper's first frame). `shown` runs
    /// once the fade is complete (not if a newer request or a revert came first).
    public func show(_ url: URL, crossfade: Double = WallpaperPreview.crossfade, shown: (() -> Void)? = nil) {
        guard url != self.url else { return }
        self.url = url
        generation += 1
        let g = generation
        let maxPixel = Int(NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 2560)
        DispatchQueue.global(qos: .userInitiated).async {
            let image = WallpaperService.thumbnailImage(url, maxPixel: maxPixel)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard g == self.generation else { return }
                    // Undecodable: no fade, but the caller still sets it (and reports any error).
                    guard let image else { self.url = nil; shown?(); return }
                    self.present(image, crossfade: crossfade)
                    guard let shown else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + crossfade) { if g == self.generation { shown() } }
                }
            }
        }
    }

    /// Fades the preview out, back to the real desktop picture (cancel).
    public func revert(crossfade: Double = WallpaperPreview.crossfade) {
        generation += 1
        url = nil
        fadeOut(after: 0, duration: crossfade)
    }

    /// The real desktop picture now matches the preview: drop the windows once macOS has drawn it.
    public func finish(after delay: Double = 0.8) {
        generation += 1
        url = nil
        fadeOut(after: delay, duration: 0.25)
    }

    private func present(_ image: CGImage, crossfade: Double) {
        if windows.isEmpty {
            build(image)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = crossfade
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for w in windows { w.animator().alphaValue = 1 }
            }
            return
        }
        for w in windows {
            // An interrupted fade-out (cancel, then a new preview) comes back up from where it is.
            if w.alphaValue < 1 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = crossfade
                    w.animator().alphaValue = 1
                }
            }
            guard let layer = w.contentView?.layer else { continue }
            let fade = CATransition()
            fade.type = .fade
            fade.duration = crossfade
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "crossfade")
            layer.contents = image
        }
    }

    private func build(_ image: CGImage) {
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = Self.windowLevel
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.ignoresMouseEvents = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.animationBehavior = .none
            w.title = "wallpaper-preview"
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.contentsGravity = .resizeAspectFill
            view.layer?.masksToBounds = true
            view.layer?.contents = image
            w.contentView = view
            w.setFrame(screen.frame, display: false)
            w.alphaValue = 0
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    private func fadeOut(after delay: Double, duration: Double) {
        let leaving = windows
        windows.removeAll()
        guard !leaving.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for w in leaving { w.animator().alphaValue = 0 }
            } completionHandler: {
                MainActor.assumeIsolated { for w in leaving { w.orderOut(nil); w.close() } }
            }
        }
    }
}
