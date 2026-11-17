import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Writes the main display (or a region of one display) to a .mov at 60 fps or faster, from inside SkyRose (the process that
/// already has Screen Recording permission). One recording at a time. The sample callback never
/// touches the main thread.
public final class DisplayMovieRecorder: NSObject, SCStreamOutput {
    public private(set) var isRecording = false
    public private(set) var outputURL: URL?
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private let queue = DispatchQueue(label: "com.skyrose.mac.record")

    /// Starts a recording into `folder`. Returns the file that `stop` will finish.
    /// `region` (global top-left points) records only that part of the display holding its
    /// centre; nil records the main display.
    public func start(folder: URL, region: CGRect? = nil) async throws -> URL {
        if isRecording { throw RecorderError.busy }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let wanted = region.flatMap { r in
            content.displays.first { CGDisplayBounds($0.displayID).contains(CGPoint(x: r.midX, y: r.midY)) }?.displayID
        } ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == wanted }) ?? content.displays.first else {
            throw RecorderError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = Double(filter.pointPixelScale)
        let cfg = SCStreamConfiguration()
        var size = display.frame.size
        if let region {
            guard let local = Self.sourceRect(region, in: CGDisplayBounds(display.displayID)) else { throw RecorderError.noDisplay }
            cfg.sourceRect = local
            size = local.size
        }
        let width = max(2, Int((size.width * scale).rounded()) & ~1)
        let height = max(2, Int((size.height * scale).rounded()) & ~1)
        cfg.width = width
        cfg.height = height
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        cfg.queueDepth = 8
        cfg.showsCursor = true
        cfg.pixelFormat = kCVPixelFormatType_32BGRA

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("skyrose-\(Int(Date().timeIntervalSince1970)).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.cannotWrite }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotWrite }

        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        self.writer = writer
        self.input = input
        self.outputURL = url
        self.sessionStarted = false
        self.isRecording = true
        return url
    }

    /// Finishes the file. The URL is valid once this returns.
    public func stop() async -> URL? {
        let url = outputURL
        isRecording = false
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        queue.sync { input?.markAsFinished() }
        if let writer {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                writer.finishWriting { done.resume() }
            }
        }
        input = nil
        writer = nil
        sessionStarted = false
        return url
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sample), CMSampleBufferGetImageBuffer(sample) != nil else { return }
        guard let writer, writer.status == .writing, let input, input.isReadyForMoreMediaData else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
            sessionStarted = true
        }
        input.append(sample)
    }

    /// `region` clipped to `display` (both global top-left points), in display-local points and
    /// whole points; nil when they do not overlap or the rest is under 2 × 2.
    static func sourceRect(_ region: CGRect, in display: CGRect) -> CGRect? {
        let r = region.intersection(display)
        guard !r.isNull, r.width >= 2, r.height >= 2 else { return nil }
        return r.offsetBy(dx: -display.minX, dy: -display.minY).integral.intersection(CGRect(origin: .zero, size: display.size))
    }

    public enum RecorderError: LocalizedError {
        case busy, noDisplay, cannotWrite
        public var errorDescription: String? {
            switch self {
            case .busy: return "A recording is already running."
            case .noDisplay: return "No display to record."
            case .cannotWrite: return "Could not open the movie file."
            }
        }
    }
}
