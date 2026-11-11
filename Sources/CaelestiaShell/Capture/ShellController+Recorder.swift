import AppKit
import CaelestiaCore

/// The screen recorder behind the utilities card, `record.screen` and `skyrose record`: one
/// full-display recording at a time into the capture folder; `state.recorder` mirrors it.
extension ShellController {
    public var recordingsFolder: URL { CaptureGeometry.folderURL(state.config.capture.folder) }

    /// Starts a recording, or stops the running one (then a toast says where it went).
    public func toggleRecording() {
        if movieRecorder.isRecording {
            Task { @MainActor in
                let url = await movieRecorder.stop()
                state.recorder.state = .ready
                state.recorder.startedAt = nil
                refreshRecordings()
                if let url { toast(.success, title: "Recording saved", message: url.lastPathComponent, icon: "screen_record") }
            }
            return
        }
        let folder = recordingsFolder
        state.recorder.state = .recording
        state.recorder.startedAt = Date()
        Task { @MainActor in
            do {
                _ = try await movieRecorder.start(folder: folder)
            } catch {
                state.recorder.state = .ready
                state.recorder.startedAt = nil
                toast(.error, title: "Screen recording failed", message: error.localizedDescription)
            }
        }
    }

    /// The recordings in the capture folder, newest first.
    public func refreshRecordings() {
        let files = (try? FileManager.default.contentsOfDirectory(at: recordingsFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        state.recorder.recordings = Self.recordings(in: files)
    }

    /// SkyRose's own recordings (`skyrose-<unix time>.mov`), newest first.
    static func recordings(in files: [URL]) -> [URL] {
        files.filter { $0.lastPathComponent.hasPrefix("skyrose-") && $0.pathExtension == "mov" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }
}
