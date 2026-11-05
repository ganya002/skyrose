import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
import Foundation

/// The workspace model as it was when the WM last ran (`Paths.sessionSnapshot`), so a WM restart
/// puts every window back on its workspace, in its place in the dwindle tree (same side, same
/// split ratios, same group tabs), with the same workspace visible on each display.
///
/// Windows are matched by CGWindowID, which stays valid while the app lives; the pid and bundle id
/// must match too, and the snapshot is ignored after a reboot (window ids start over), so a new
/// window can never inherit an old one's place. Written atomically on every model change
/// (debounced) and on quit; never needed for safety (that is the parking journal).
public struct SessionSnapshot: Codable, Hashable, Sendable {
    public static let formatVersion = 1

    public struct Identity: Codable, Hashable, Sendable {
        public var windowID: WindowID
        public var pid: Int32
        public var bundleID: String
    }

    public var version = Self.formatVersion
    /// `kern.boottime` of the session that wrote it.
    public var bootTime: Double
    public var savedAt: Date
    public var state: WorkspaceState
    /// Every window in `state`, plus minimized/hidden ones (`suspended`).
    public var windows: [Identity]
    /// Minimized / hidden-app windows and the workspace they come back to.
    public var suspended: [String: WorkspaceID]

    public static var currentBootTime: Double { BootTime.current }
}

public final class SessionSnapshotStore: @unchecked Sendable {
    public let url: URL

    public init(url: URL = Paths.sessionSnapshot) { self.url = url }

    public func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let s = try? decoder.decode(SessionSnapshot.self, from: data), s.version == SessionSnapshot.formatVersion else {
            Log.wm.error("session snapshot unreadable; ignoring it")
            return nil
        }
        return s
    }

    public func save(_ snapshot: SessionSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    public func remove() { try? FileManager.default.removeItem(at: url) }
}

extension WindowManager {
    /// Snapshot of the current model.
    func makeSessionSnapshot() -> SessionSnapshot {
        var ids: [SessionSnapshot.Identity] = []
        for (id, h) in handles.sorted(by: { $0.key < $1.key }) where state.workspace(of: id) != nil || suspended[id] != nil {
            ids.append(.init(windowID: id, pid: h.pid, bundleID: descriptors[id]?.bundleID ?? ""))
        }
        return SessionSnapshot(
            bootTime: SessionSnapshot.currentBootTime, savedAt: now(), state: state, windows: ids,
            suspended: Dictionary(uniqueKeysWithValues: suspended.map { (String($0.key), $0.value) })
        )
    }

    /// Saves the model when it changed since the last save (debounced on the main queue; at once
    /// under manual scheduling and on quit).
    func saveSessionIfChanged(immediately: Bool = false) {
        guard let store = sessionStore, state != lastSavedSession || suspended != lastSavedSuspended else { return }
        let write = { [weak self] in
            guard let self, self.state != self.lastSavedSession || self.suspended != self.lastSavedSuspended else { return }
            do {
                try store.save(self.makeSessionSnapshot())
                self.lastSavedSession = self.state
                self.lastSavedSuspended = self.suspended
            } catch {
                Log.wm.error("session snapshot not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
        if immediately || scheduling == .manual {
            sessionSaveScheduled = false
            write()
            return
        }
        guard !sessionSaveScheduled else { return }
        sessionSaveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sessionSaveDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.sessionSaveScheduled else { return }
                self.sessionSaveScheduled = false
                if self.isManaging { write() }
            }
        }
    }

    /// After discovery at start: windows the snapshot knows go back to their workspace and tree
    /// position; windows it does not know keep the place discovery gave them (the visible
    /// workspace of the display they are on). Returns the number of windows put back.
    @discardableResult
    func restoreSession() -> Int {
        guard let store = sessionStore, let snap = store.load() else { return 0 }
        guard abs(snap.bootTime - SessionSnapshot.currentBootTime) < 2 else {
            Log.wm.notice("session snapshot is from an earlier boot; not used")
            return 0
        }
        // Same window id, same app: the window the snapshot saw.
        var alive = Set<WindowID>()
        for i in snap.windows {
            guard let h = handles[i.windowID], h.pid == i.pid, descriptors[i.windowID]?.bundleID == i.bundleID else { continue }
            alive.insert(i.windowID)
        }
        for (key, ws) in snap.suspended {
            guard let id = WindowID(key), snap.windows.contains(where: { $0.windowID == id }) else { continue }
            restoreTargets[id] = ws
        }
        let displayIDs = displays.map(\.id)
        guard !displayIDs.isEmpty else { return 0 }
        let saved = snap.state.restored(keeping: alive.filter { state.workspace(of: $0) != nil }, displays: displayIDs)
        let keptCount = saved.workspaces.values.reduce(0) { $0 + $1.windows.count }
        guard keptCount > 0 else { return 0 }

        // Windows discovery placed that the snapshot does not hold: add them where discovery put
        // them (the visible workspace of their display), floating ones keep their frame.
        var next = saved
        let current = state
        for id in current.workspaces.values.flatMap(\.windows).sorted() where next.workspace(of: id) == nil {
            guard let wsID = current.workspace(of: id), let ws = current[wsID] else { continue }
            let target = next.activeWorkspace(forDisplay: ws.displayID)
            next.addWindow(id, to: target, floating: ws.floating[id], size: current.naturalSizes[id], focus: false, env: environment)
        }
        state = next
        lastSavedSession = nil
        for id in handles.keys { applied[id] = nil }
        Log.wm.notice("restored \(keptCount) window(s) to their workspaces from the session snapshot")
        return keptCount
    }
}
