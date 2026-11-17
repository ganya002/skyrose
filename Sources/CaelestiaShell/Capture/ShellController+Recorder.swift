import AppKit
import CaelestiaCore

/// The screen recorder behind the utilities card, `record.screen`, `record.region` and
/// `skyrose record [-r]`: one recording at a time (the main display, or a picked region) into the
/// capture folder; `state.recorder` mirrors it.
extension ShellController {
    public var recordingsFolder: URL { CaptureGeometry.folderURL(state.config.capture.folder) }

    /// Starts a recording, or stops the running one (then a toast says where it went).
    /// `region`: pick a rectangle (or a window, or click the desktop for its display) first;
    /// pressed again while the picker is open, it cancels the picker. `rect` (global top-left
    /// points) records that region without the picker.
    public func toggleRecording(region: Bool = false, rect: CGRect? = nil) {
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
        if let rect {
            startRecording(region: rect)
            return
        }
        if region {
            guard !screenshots.isActive else {
                screenshots.cancel()
                return
            }
            screenshots.pickRegion { [weak self] rect in
                guard let self, let rect else { return }
                // Let the picker leave the screen before the first frame.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.startRecording(region: rect) }
            }
            return
        }
        startRecording(region: nil)
    }

    private func startRecording(region: CGRect?) {
        guard !movieRecorder.isRecording else { return }
        let folder = recordingsFolder
        state.recorder.state = .recording
        state.recorder.startedAt = Date()
        Task { @MainActor in
            do {
                _ = try await movieRecorder.start(folder: folder, region: region)
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
