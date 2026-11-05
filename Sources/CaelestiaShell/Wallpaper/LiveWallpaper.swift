import AppKit
import AVFoundation
import CaelestiaCore
import CaelestiaServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// First frames of live wallpapers: the still is what macOS shows as the desktop picture (lock
/// screen, Mission Control, colour extraction) while the video loops above it.
public enum LiveWallpaperStill {
    public static var stillsDir: URL {
        ServiceStorage.url("live-stills")
    }

    /// The first frame of `video`, at most `maxPixel` on its long side (0 = native size). Blocks;
    /// call off the main thread.
    public static func firstFrame(_ video: URL, maxPixel: Int = 0) -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        if maxPixel > 0 { generator.maximumSize = CGSize(width: maxPixel, height: maxPixel) }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var image: CGImage?
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, cg, _, result, _ in
            if result == .succeeded { image = cg }
            done.signal()
        }
        guard done.wait(timeout: .now() + 10) == .success else {
            generator.cancelAllCGImageGeneration()
            return nil
        }
        return image
    }

    /// Writes (or reuses) the full-size first frame as a JPEG in Application Support. Blocks.
    public static func makeStill(for video: URL, in dir: URL = stillsDir) -> URL? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: video.path)
        let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? Int) ?? 0
        let key = WallpaperLibrary.thumbnailKey(path: video.path, modified: modified, size: size)
        let out = dir.appendingPathComponent("\(key).jpg")
        if FileManager.default.fileExists(atPath: out.path) { return out }
        guard let cg = firstFrame(video) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out : nil
    }
}

/// When the live wallpaper may play. Pure, so the rules are testable.
public struct LiveWallpaperPolicy: Equatable, Sendable {
    /// A Mac with a battery that is not on AC power.
    public var onBattery = false
    public var lowPowerMode = false
    /// Every live-wallpaper window is fully covered (occlusion state not visible).
    public var fullyCovered = false
    /// Displays asleep, screen locked or another user's session in front.
    public var screensAsleep = false
    public init() {}

    public var shouldPlay: Bool { !onBattery && !lowPowerMode && !fullyCovered && !screensAsleep }

    /// Why it is paused, for `wallpaper get` / logs.
    public var pauseReason: String? {
        if lowPowerMode { return "Low Power Mode" }
        if onBattery { return "on battery" }
        if screensAsleep { return "screens asleep" }
        if fullyCovered { return "covered by windows" }
        return nil
    }

    public mutating func apply(battery: BatteryState) {
        onBattery = battery.hasBattery && !battery.isPluggedIn
        lowPowerMode = battery.isLowPowerMode
    }
}

/// What to resume after a restart (`live-wallpaper.json`).
public struct LiveWallpaperRecord: Codable, Equatable, Sendable {
    public var video: String
    public var still: String
    public init(video: String, still: String) {
        self.video = video
        self.still = still
    }

    /// The record still applies: both files exist and macOS still shows our still (nobody picked
    /// another wallpaper in System Settings meanwhile).
    public func isCurrent(desktopPicture: URL?, fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> Bool {
        guard fileExists(video), fileExists(still), let desktopPicture else { return false }
        return URL(fileURLWithPath: still).standardizedFileURL.path == desktopPicture.standardizedFileURL.path
    }
}

/// Loops a video muted on the desktop of every display: one borderless window per screen just
/// above the desktop picture (below the Finder's desktop icons), all fed by one AVQueuePlayer.
/// Pauses on battery, in Low Power Mode, while every window is covered and while screens sleep.
@MainActor
public final class LiveWallpaperController {
    public private(set) var video: URL?
    public private(set) var still: URL?
    public private(set) var policy = LiveWallpaperPolicy()
    public var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var windows: [NSWindow] = []
    private var announcedPause = false
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    let recordURL: URL

    public static let windowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)

    public init(recordURL: URL = ServiceStorage.url("live-wallpaper.json")) {
        self.recordURL = recordURL
    }

    public var record: LiveWallpaperRecord? { ServiceStorage.load(LiveWallpaperRecord.self, from: recordURL) }

    /// Starts looping `video`; `still` is its first frame, already set as the desktop picture.
    public func play(video: URL, still: URL) {
        stop(clearRecord: false)
        self.video = video
        self.still = still
        ServiceStorage.save(LiveWallpaperRecord(video: video.path, still: still.path), to: recordURL)
        let item = AVPlayerItem(url: video)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        rebuildWindows()
        observeWorkspace()
        evaluate()
    }

    /// Stops and removes the windows. `clearRecord` forgets it (a still wallpaper was picked).
    public func stop(clearRecord: Bool = true) {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObservers.removeAll()
        video = nil
        still = nil
        announcedPause = false
        if clearRecord { try? FileManager.default.removeItem(at: recordURL) }
    }

    public func update(battery: BatteryState) {
        policy.apply(battery: battery)
        // Live tests on a MacBook without its charger (the brief pauses on battery by default).
        if ProcessInfo.processInfo.environment["SKYROSE_LIVE_WALLPAPER_ON_BATTERY"] == "1" { policy.onBattery = false }
        evaluate()
    }

    /// Displays were added, removed or resized.
    public func screensChanged() {
        guard player != nil else { return }
        rebuildWindows()
        evaluate()
    }

    private func rebuildWindows() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
        guard let player else { return }
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = Self.windowLevel
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.ignoresMouseEvents = true
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.animationBehavior = .none
            w.title = "live-wallpaper"
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            // The still shows until the first video frame is decoded (no black flash).
            if let still, let image = NSImage(contentsOf: still) {
                view.layer?.contents = image
                view.layer?.contentsGravity = .resizeAspectFill
            }
            view.layer?.addSublayer(layer)
            w.contentView = view
            w.setFrame(screen.frame, display: false)
            w.orderFrontRegardless()
            windows.append(w)
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let asleep: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let awake: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for (names, value) in [(asleep, true), (awake, false)] {
            for name in names {
                workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.policy.screensAsleep = value
                        self?.evaluate()
                    }
                })
            }
        }
    }

    private func evaluate() {
        guard let player else { return }
        // Occlusion is only known once the windows have been on screen.
        policy.fullyCovered = !windows.isEmpty && windows.allSatisfy { !$0.occlusionState.contains(.visible) }
        if policy.shouldPlay {
            if player.rate == 0 {
                player.play()
                Log.shell.notice("live wallpaper: playing \(self.video?.lastPathComponent ?? "", privacy: .public) on \(self.windows.count) display(s)")
            }
        } else if player.rate != 0 || !announcedPause {
            player.pause()
            Log.shell.notice("live wallpaper: paused (\(self.policy.pauseReason ?? "", privacy: .public))")
        }
        announcedPause = !policy.shouldPlay
    }
}
