import AVFoundation
import CaelestiaCore
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Lyrics and the bongo cat for the open dashboard. The audio tap exists only while the
/// dashboard is open, a track is playing, and the cat is enabled.
@MainActor
final class MediaStage {
    private var detector = BeatDetector()
    private var tap: OutputTap?
    private var lyricTask: Task<Void, Never>?
    private var loadedKey = ""
    private var paw = 0
    private let lyricsDirectory = Paths.appSupport.appendingPathComponent("lyrics", isDirectory: true)

    func sync(media: MediaInfo, dashboard: DashboardModel, config: DashboardConfig) {
        dashboard.lyricClock = LyricClock(position: media.position, at: Date(), playing: media.isPlaying, duration: media.duration)
        guard dashboard.shown else {
            stopListening()
            return
        }
        if config.bongoCat, media.isPlaying {
            startListening(dashboard)
        } else {
            stopListening()
            dashboard.bongoPaw = nil
        }
        guard config.lyrics, media.available, !media.title.isEmpty else {
            lyricTask?.cancel()
            dashboard.lyricLines = []
            dashboard.lyricNote = ""
            loadedKey = ""
            return
        }
        let track = LyricTrack(title: media.title, artist: media.artist, album: media.album, duration: media.duration)
        guard track.cacheKey != loadedKey else { return }
        loadedKey = track.cacheKey
        lyricTask?.cancel()
        if let cached = LyricCache.load(track: track, directory: lyricsDirectory) {
            dashboard.lyricLines = cached
            dashboard.lyricNote = ""
            return
        }
        dashboard.lyricLines = []
        dashboard.lyricNote = "Looking up lyrics…"
        lyricTask = Task { [weak dashboard] in
            let lines = await Self.fetch(track)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let dashboard else { return }
                if let lines {
                    dashboard.lyricLines = lines
                    dashboard.lyricNote = ""
                    try? LyricCache.save(lines, track: track, directory: self.lyricsDirectory)
                } else {
                    dashboard.lyricLines = []
                    dashboard.lyricNote = "No lyrics found"
                }
            }
        }
    }

    func stop() {
        loadedKey = ""
        lyricTask?.cancel()
        stopListening()
    }

    private func startListening(_ dashboard: DashboardModel) {
        guard tap == nil else { return }
        let tap = OutputTap { [weak self, weak dashboard] samples, rate in
            Task { @MainActor in
                guard let self, let dashboard else { return }
                self.detector.sampleRate = rate
                let beats = self.detector.feed(samples)
                guard !beats.isEmpty else { return }
                self.paw = self.paw == 0 ? 1 : 0
                dashboard.bongoPaw = self.paw
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 90_000_000)
                    if dashboard.bongoPaw == self.paw { dashboard.bongoPaw = nil }
                }
            }
        }
        self.tap = tap
        Task { await tap.start() }
    }

    private func stopListening() {
        tap?.stop()
        tap = nil
        detector = BeatDetector()
    }

    /// The exact track first, then looser. A synced lyric wins over a plain one found earlier.
    private static func fetch(_ track: LyricTrack) async -> [LyricLine]? {
        var plain: [LyricLine]?
        for url in Lyrics.requests(for: track) {
            guard let data = await body(of: url), let lines = Lyrics.fromLRCLIB(data) else { continue }
            if Lyrics.isSynced(lines) { return lines }
            plain = plain ?? lines
        }
        if let url = Lyrics.searchRequest(for: track), let data = await body(of: url),
           let lines = Lyrics.fromSearch(data, duration: track.duration) {
            if Lyrics.isSynced(lines) { return lines }
            plain = plain ?? lines
        }
        return plain
    }

    private static func body(of url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("SkyRose", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return data
    }
}

/// System-output audio, only the samples, and only while someone is listening.
private final class OutputTap: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onSamples: @Sendable ([Float], Double) -> Void
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.skyrose.mac.bongo")

    init(onSamples: @escaping @Sendable ([Float], Double) -> Void) { self.onSamples = onSamples }

    private var stopped = false

    func start() async {
        guard stream == nil, !stopped else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first else { return }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = 2
        cfg.height = 2
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 44100
        cfg.channelCount = 1
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try? await stream.startCapture()
        // Closed while the capture was starting: it must not keep listening.
        if stopped {
            try? await stream.stopCapture()
            return
        }
        self.stream = stream
    }

    func stop() {
        stopped = true
        let stream = stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let format = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              let buffer = CMSampleBufferGetDataBuffer(sample) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(buffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer, length > 0 else { return }
        let rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 44100
        let samples: [Float]
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            samples = Array(UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self), count: length / MemoryLayout<Float>.size))
        } else {
            let count = length / MemoryLayout<Int16>.size
            let raw = UnsafeRawPointer(pointer).assumingMemoryBound(to: Int16.self)
            samples = (0..<count).map { Float(raw[$0]) / 32768 }
        }
        onSamples(samples, rate)
    }
}
