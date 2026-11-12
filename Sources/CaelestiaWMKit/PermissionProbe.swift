import CaelestiaCore
import CaelestiaPlatform
import Foundation

/// `SkyRoseWM --permissions-probe <file>`: writes this app's permission status as JSON and exits,
/// without starting the window manager.
///
/// TCC answers per app, so only a process of SkyRose.app itself can tell whether SkyRose has
/// Accessibility, Input Monitoring and Screen Recording. SkyRose Settings launches the probe
/// through Launch Services (so SkyRose, not Settings, is the responsible app) whenever the WM is
/// not running or too busy to answer, and the permission cards stay live either way.
public enum PermissionProbe {
    public static let flag = "--permissions-probe"
    /// `--permissions-probe <file> --request <kind>`: also asks macOS for `kind` first (adds
    /// SkyRose to that System Settings list and shows the system prompt once), then reports.
    public static let requestFlag = "--request"

    /// Runs the probe and exits when `arguments` ask for it; returns otherwise.
    public static func runIfRequested(_ arguments: [String] = CommandLine.arguments) {
        guard let i = arguments.firstIndex(of: flag) else { return }
        if let r = arguments.firstIndex(of: requestFlag), r + 1 < arguments.count,
            let kind = Permissions.Kind(rawValue: arguments[r + 1]) {
            _ = Permissions.request(kind)
        }
        if let r = arguments.firstIndex(of: requestFlag), r + 1 < arguments.count,
            let kind = Permissions.Kind(rawValue: arguments[r + 1]), kind == .location || kind == .bluetooth {
            // The answer to these prompts arrives later: wait for it (up to a minute).
            let deadline = Date().addingTimeInterval(60)
            while Permissions.undecided(kind), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            }
        }
        let s = Permissions.status()
        let snapshot = PermissionSnapshot(accessibility: s.accessibility, inputMonitoring: s.inputMonitoring,
                                          screenRecording: s.screenRecording, location: s.location, bluetooth: s.bluetooth)
        let data = (try? encode(snapshot)) ?? Data("{}".utf8)
        if i + 1 < arguments.count, !arguments[i + 1].hasPrefix("--") {
            let url = URL(fileURLWithPath: arguments[i + 1])
            // Written whole, then renamed, so the reader never sees half a file.
            let tmp = url.appendingPathExtension("partial")
            do {
                try data.write(to: tmp)
                _ = try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: tmp, to: url)
            } catch {
                FileHandle.standardError.write(Data("permissions probe: \(error)\n".utf8))
                exit(1)
            }
        } else {
            FileHandle.standardOutput.write(data)
        }
        exit(0)
    }

    public static func encode(_ snapshot: PermissionSnapshot) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(snapshot)
    }

    public static func decode(_ data: Data) -> PermissionSnapshot? {
        try? JSONDecoder().decode(PermissionSnapshot.self, from: data)
    }
}
