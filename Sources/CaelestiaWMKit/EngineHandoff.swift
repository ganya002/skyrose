import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
import Foundation

/// Which workspace each window was on when a window engine quit (SkyRose's own or CatWM), so the
/// next start, maybe on the other engine after `[wm] engine` changed, puts the windows back. It is
/// read once and deleted; one from an earlier boot is ignored (window ids don't survive a reboot).
public struct EngineHandoff: Codable, Equatable, Sendable {
    public var bootTime: Double
    /// Window id -> workspace name (`"3"`, `"special:term"`).
    public var workspaces: [String: String]

    public static var defaultURL: URL {
        Paths.sessionSnapshot.deletingLastPathComponent().appendingPathComponent("engine-handoff.json")
    }

    public static func write(_ workspaces: [UInt32: String], to url: URL = defaultURL) {
        let handoff = EngineHandoff(bootTime: BootTime.current,
                                    workspaces: Dictionary(uniqueKeysWithValues: workspaces.map { (String($0.key), $0.value) }))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(handoff).write(to: url, options: .atomic)
        } catch {
            Log.wm.error("engine handoff not written: \(String(describing: error), privacy: .public)")
        }
    }

    /// The saved workspaces, removing the file. Empty when there is none or it is from another boot.
    public static func take(from url: URL = defaultURL) -> [UInt32: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        try? FileManager.default.removeItem(at: url)
        guard let handoff = try? JSONDecoder().decode(EngineHandoff.self, from: data),
              abs(handoff.bootTime - BootTime.current) < 2 else { return [:] }
        return Dictionary(handoff.workspaces.compactMap { key, value in UInt32(key).map { ($0, value) } },
                          uniquingKeysWith: { a, _ in a })
    }
}

extension WindowManager {
    /// Own engine: moves every window the handoff names to its workspace (the session snapshot
    /// already did when the last run was ours too).
    func applyHandoff(_ workspaces: [UInt32: String]) {
        var moved = 0
        for (id, name) in workspaces.sorted(by: { $0.key < $1.key }) {
            guard let target = WorkspaceID(parsing: name), let current = state.workspace(of: id), current != target,
                  state.moveWindow(id, to: target, follow: false, env: environment) else { continue }
            moved += 1
        }
        if moved > 0 { Log.wm.notice("put \(moved) window(s) back on their workspaces from the engine handoff") }
    }
}
