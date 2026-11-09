import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Writes the main display to a .mov at 60 fps or faster, from inside SkyRose (the process that
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
    public func start(folder: URL) async throws -> URL {
        if isRecording { throw RecorderError.busy }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let main = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == main }) ?? content.displays.first else {
            throw RecorderError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = Double(filter.pointPixelScale)
        let width = max(2, Int((display.frame.width * scale).rounded()) & ~1)
        let height = max(2, Int((display.frame.height * scale).rounded()) & ~1)
        let cfg = SCStreamConfiguration()
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
