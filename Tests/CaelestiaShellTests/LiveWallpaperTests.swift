import AVFoundation
import CaelestiaServices
import CoreVideo
import Foundation
import XCTest

@testable import CaelestiaShell

final class WallpaperGroupsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wp-groups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func touch(_ rel: String) {
        let url = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data([0]))
    }

    /// Gabby's layout: notes at the top, pictures in Static/, videos in Live/.
    func testSubfoldersAreGroupedAndNotesSkipped() {
        for f in ["AGENTS.md", "CLAUDE.md", "top.png", "Static/b.jpg", "Static/a.jpeg", "Static/.hidden.png",
                  "Live/Rain.mp4", "Live/Aurora.MOV", "Live/notes.md", "Live/Anime/Snow.m4v", ".secret/x.jpg"] {
            touch(f)
        }
        let r = WallpaperLibrary.scan(folder: root)
        XCTAssertNil(r.message)
        XCTAssertEqual(r.groups.map(\.name), ["", "Live", "Live/Anime", "Static"])
        XCTAssertEqual(r.groups.map(\.title), ["Wallpapers", "Live", "Live/Anime", "Static"])
        XCTAssertEqual(r.groups.first { $0.name == "Static" }?.urls.map(\.lastPathComponent), ["a.jpeg", "b.jpg"])
        XCTAssertEqual(r.groups.first { $0.name == "Live" }?.urls.map(\.lastPathComponent), ["Aurora.MOV", "Rain.mp4"])
        XCTAssertEqual(r.groups.first { $0.name == "Live" }?.liveCount, 2)
        XCTAssertEqual(r.urls.count, 6, "every group, flattened; .md and hidden files skipped")
        XCTAssertFalse(r.urls.contains { $0.pathExtension == "md" })
    }

    func testDepthIsLimitedAndLiveDetection() {
        touch("1/2/3/deep.jpg")
        touch("1/2/3/4/too-deep.jpg")
        let names = WallpaperLibrary.scan(folder: root).urls.map(\.lastPathComponent)
        XCTAssertEqual(names, ["deep.jpg"])
        XCTAssertTrue(WallpaperLibrary.isLive(URL(fileURLWithPath: "/a/b.MP4")))
        XCTAssertTrue(WallpaperLibrary.isLive(URL(fileURLWithPath: "/a/b.mov")))
        XCTAssertFalse(WallpaperLibrary.isLive(URL(fileURLWithPath: "/a/b.gif")))
    }

    func testScanResultWithoutGroupsIsOneGroup() {
        let r = WallpaperLibrary.ScanResult(urls: [URL(fileURLWithPath: "/a.jpg")])
        XCTAssertEqual(r.groups.count, 1)
        XCTAssertEqual(WallpaperLibrary.ScanResult(urls: []).groups, [])
    }
}

final class LiveWallpaperTests: XCTestCase {
    func testPolicyPausesOnBatteryLowPowerCoverAndSleep() {
        var p = LiveWallpaperPolicy()
        XCTAssertTrue(p.shouldPlay)
        XCTAssertNil(p.pauseReason)
        var b = BatteryState()
        b.hasBattery = true
        b.isPluggedIn = false
        p.apply(battery: b)
        XCTAssertFalse(p.shouldPlay)
        XCTAssertEqual(p.pauseReason, "on battery")
        b.isPluggedIn = true
        p.apply(battery: b)
        XCTAssertTrue(p.shouldPlay)
        b.isLowPowerMode = true
        p.apply(battery: b)
        XCTAssertEqual(p.pauseReason, "Low Power Mode")
        p.apply(battery: BatteryState())  // a desktop Mac: no battery, plays
        XCTAssertTrue(p.shouldPlay)
        p.fullyCovered = true
        XCTAssertEqual(p.pauseReason, "covered by windows")
        p.fullyCovered = false
        p.screensAsleep = true
        XCTAssertFalse(p.shouldPlay)
    }

    func testRecordOnlyResumesWhileMacOSStillShowsTheStill() {
        let r = LiveWallpaperRecord(video: "/w/Live/rain.mp4", still: "/s/abc.jpg")
        let exists: (String) -> Bool = { _ in true }
        XCTAssertTrue(r.isCurrent(desktopPicture: URL(fileURLWithPath: "/s/abc.jpg"), fileExists: exists))
        XCTAssertFalse(r.isCurrent(desktopPicture: URL(fileURLWithPath: "/w/other.jpg"), fileExists: exists), "picked elsewhere")
        XCTAssertFalse(r.isCurrent(desktopPicture: nil, fileExists: exists))
        XCTAssertFalse(r.isCurrent(desktopPicture: URL(fileURLWithPath: "/s/abc.jpg"), fileExists: { $0 != r.video }), "video deleted")
    }

    func testFirstFrameAndStillFromAVideo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("red.mov")
        try Self.writeVideo(to: video, width: 64, height: 36, frames: 6)

        let frame = try XCTUnwrap(LiveWallpaperStill.firstFrame(video))
        XCTAssertEqual(frame.width, 64)
        XCTAssertEqual(frame.height, 36)
        let small = try XCTUnwrap(LiveWallpaperStill.firstFrame(video, maxPixel: 32))
        XCTAssertLessThanOrEqual(max(small.width, small.height), 32)
        XCTAssertNotNil(WallpaperService.thumbnailImage(video, maxPixel: 32), "video thumbnails use the first frame")

        let stills = dir.appendingPathComponent("stills")
        let still = try XCTUnwrap(LiveWallpaperStill.makeStill(for: video, in: stills))
        XCTAssertEqual(still.pathExtension, "jpg")
        XCTAssertEqual(LiveWallpaperStill.makeStill(for: video, in: stills), still, "cached by file")
        // The still is what colour extraction reads: it must be the red first frame.
        let pixels = try XCTUnwrap(WallpaperColors.loadPixels(still, maxPixel: 8))
        XCTAssertGreaterThan(Int(pixels[0]), 200)
        XCTAssertLessThan(Int(pixels[1]), 60)
        XCTAssertNil(LiveWallpaperStill.firstFrame(dir.appendingPathComponent("missing.mp4")))
    }

    /// A tiny solid-red H.264 movie.
    static func writeVideo(to url: URL, width: Int, height: Int, frames: Int) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let b = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(b, [])
            let base = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(b)
            for y in 0..<height {
                for x in 0..<width {
                    let p = base + y * row + x * 4
                    p[0] = 0; p[1] = 0; p[2] = 255; p[3] = 255  // BGRA red
                }
            }
            CVPixelBufferUnlockBaseAddress(b, [])
            adaptor.append(b, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + 10)
        XCTAssertEqual(writer.status, .completed)
    }
}
