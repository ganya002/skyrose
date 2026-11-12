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
    /// Windows that were tiled. A tile can be squeezed below CatWM's small-window size (500×500),
    /// so a fresh start would float it; these are tiled again.
    public var tiled: [String]? = nil

    public struct Restore: Equatable, Sendable {
        public var workspaces: [UInt32: String] = [:]
        public var tiled: Set<UInt32> = []
        public init(workspaces: [UInt32: String] = [:], tiled: Set<UInt32> = []) {
            (self.workspaces, self.tiled) = (workspaces, tiled)
        }
    }

    public static var defaultURL: URL {
        Paths.sessionSnapshot.deletingLastPathComponent().appendingPathComponent("engine-handoff.json")
    }

    public static func write(_ restore: Restore, to url: URL = defaultURL) {
        let handoff = EngineHandoff(bootTime: BootTime.current,
                                    workspaces: Dictionary(uniqueKeysWithValues: restore.workspaces.map { (String($0.key), $0.value) }),
                                    tiled: restore.tiled.sorted().map(String.init))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(handoff).write(to: url, options: .atomic)
        } catch {
            Log.wm.error("engine handoff not written: \(String(describing: error), privacy: .public)")
        }
    }

    /// What was saved, removing the file. Empty when there is none or it is from another boot.
    public static func take(from url: URL = defaultURL) -> Restore {
        guard let data = try? Data(contentsOf: url) else { return Restore() }
        try? FileManager.default.removeItem(at: url)
        guard let handoff = try? JSONDecoder().decode(EngineHandoff.self, from: data),
              abs(handoff.bootTime - BootTime.current) < 2 else { return Restore() }
        return Restore(workspaces: Dictionary(handoff.workspaces.compactMap { key, value in UInt32(key).map { ($0, value) } },
                                              uniquingKeysWith: { a, _ in a }),
                       tiled: Set((handoff.tiled ?? []).compactMap { UInt32($0) }))
    }
}

extension WindowManager {
    /// Own engine: moves every window the handoff names to its workspace (the session snapshot
    /// already did when the last run was ours too).
    func applyHandoff(_ restore: EngineHandoff.Restore) {
        var moved = 0
        for id in restore.tiled.sorted() where state.workspace(of: id).flatMap({ state[$0]?.isFloating(id) }) == true {
            if state.setFloating(id, false, env: environment) { moved += 1 }
        }
        for (id, name) in restore.workspaces.sorted(by: { $0.key < $1.key }) {
            guard let target = WorkspaceID(parsing: name), let current = state.workspace(of: id), current != target,
                  state.moveWindow(id, to: target, follow: false, env: environment) else { continue }
            moved += 1
        }
        if moved > 0 { Log.wm.notice("put \(moved) window(s) back on their workspaces from the engine handoff") }
    }
}
