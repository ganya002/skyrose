import AppKit
import CaelestiaCore
import CaelestiaPlatform
import Foundation

/// Reads SkyRose's permissions without the WM: launches `SkyRose.app --permissions-probe <file>`
/// through Launch Services (TCC answers for SkyRose that way, not for Settings), waits for the
/// file, decodes it. The probe process exits at once and never starts the window manager.
@MainActor
public final class PermissionProber {
    public let appURL: () -> URL?
    private(set) var inFlight = false
    /// Probe processes this prober launched (same bundle id as the WM, so the running-status
    /// check must not mistake them for it).
    public private(set) var probePIDs: Set<pid_t> = []
    private let directory: URL

    public init(appURL: @escaping () -> URL? = { PermissionProber.defaultAppURL() },
                directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("skyrose-settings", isDirectory: true)) {
        self.appURL = appURL
        self.directory = directory
    }

    /// SkyRose.app next to Settings (dist/), else wherever Launch Services has it.
    public nonisolated static func defaultAppURL() -> URL? {
        SkyRoseApp.locate()
    }

    /// One probe; `completion` gets nil when SkyRose.app is missing or the probe did not answer
    /// within `timeout`. Calls while one is running are dropped.
    public func probe(requesting: SkyRosePermission? = nil, timeout: TimeInterval = 4,
                      completion: @escaping @MainActor (PermissionSnapshot?) -> Void) {
        guard !inFlight, let app = appURL() else {
            if appURL() == nil { completion(nil) }
            return
        }
        inFlight = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let out = directory.appendingPathComponent("probe-\(UUID().uuidString).json")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = Self.arguments(output: out, requesting: requesting)
        config.createsNewApplicationInstance = true
        config.activates = false
        config.addsToRecentItems = false
        config.hides = true
        config.promptsUserIfNeeded = false
        NSWorkspace.shared.openApplication(at: app, configuration: config) { [weak self] running, _ in
            guard let pid = running?.processIdentifier else { return }
            Task { @MainActor in self?.recordProbe(pid) }
        }
        let started = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll(out, started: started, timeout: timeout) }
        }
        pending = completion
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func recordProbe(_ pid: pid_t) {
        probePIDs.insert(pid)
        // Forget it later (a reused pid is then a different process); probes exit within seconds.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.probePIDs.remove(pid)
        }
    }

    private var timer: Timer?
    private var pending: (@MainActor (PermissionSnapshot?) -> Void)?

    private func poll(_ out: URL, started: Date, timeout: TimeInterval) {
        let snap = (try? Data(contentsOf: out)).flatMap(Self.decode)
        guard snap != nil || Date().timeIntervalSince(started) > timeout else { return }
        timer?.invalidate()
        timer = nil
        try? FileManager.default.removeItem(at: out)
        inFlight = false
        let done = pending
        pending = nil
        done?(snap)
    }

    /// The probe's command line (pure, for tests).
    public nonisolated static func arguments(output: URL, requesting: SkyRosePermission?) -> [String] {
        var a = ["--permissions-probe", output.path]
        if let requesting { a += ["--request", requesting.rawValue] }
        return a
    }

    public nonisolated static func decode(_ data: Data) -> PermissionSnapshot? {
        try? JSONDecoder().decode(PermissionSnapshot.self, from: data)
    }
}
