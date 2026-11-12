import AppKit
import CaelestiaCore
import CaelestiaWMKit
import CatWMKit

/// Runs CatWM (by Per William Krogstad-Østensen, @noxaur, used with permission) inside SkyRose as
/// its window manager. This file and its neighbours are the only place SkyRose imports CatWMKit.
@MainActor
public final class CatWMHost: WindowEngine {
    public let name = "CatWM"
    public var onChange: (() -> Void)?
    public var onFrames: (([UInt32: CGRect]) -> Void)?
    public private(set) var state = EngineState()
    private var engine: CatWMEngine?
    private var config = Config()
    private var area: CGRect?
    private var lastText = ""

    public init() {}

    public func start(config: Config, area: CGRect?) throws {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.noxaur.CatWM").contains(where: { !$0.isTerminated })
            || NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == "CatWM" && $0.processIdentifier != getpid() }) {
            Log.wm.warning("the CatWM app is running too; quit it so two window managers don't fight over the windows")
        }
        let engine = try CatWMEngine(name: "skyrose")
        engine.onStateChange = { [weak self] in self?.refreshState() }
        engine.onWindowFrames = { [weak self] frames in
            // Motion over: the resting frames changed, and CatWM doesn't report a state change for it.
            if frames.isEmpty { self?.refreshState() }
            self?.onFrames?(frames)
        }
        self.config = config
        self.area = area
        lastText = text()
        try engine.start(config: .text(lastText))
        self.engine = engine
        refreshState()
    }

    public func apply(config: Config, area: CGRect?) {
        self.config = config
        self.area = area
        let next = text()
        guard let engine, next != lastText else { return }
        do {
            try engine.replaceConfig(next)
            lastText = next
        } catch {
            Log.wm.error("CatWM refused the config: \(String(describing: error), privacy: .public)")
        }
    }

    public func stop(then done: @escaping @MainActor () -> Void) {
        guard let engine else { return done() }
        self.engine = nil
        Task { @MainActor in
            await engine.stop()
            done()
        }
    }

    public func perform(_ action: Action) -> Bool? {
        let current = state.focusedDisplay.flatMap { state.shown[$0] }
        guard let calls = CatWMCommands.calls(for: action, area: area, perGroup: config.wm.workspacesPerGroup,
                                              current: current) else { return nil }
        guard let engine, !calls.isEmpty else {
            if calls.isEmpty { Log.wm.info("\(action.description, privacy: .public) is not supported with CatWM yet") }
            return false
        }
        for call in calls {
            do {
                try engine.perform(call.name, call.args)
            } catch {
                Log.wm.info("CatWM \(call.name, privacy: .public): \(String(describing: error), privacy: .public)")
                return false
            }
        }
        return true
    }

    private func text() -> String {
        CatWMConfigText.make(config, area: area, visible: Self.primaryVisible())
    }

    /// The primary display's visible frame in top-left points (what CatWM tiles inside).
    static func primaryVisible() -> CGRect? {
        guard let screen = NSScreen.screens.first else { return nil }
        let v = screen.visibleFrame
        return CGRect(x: v.minX, y: screen.frame.maxY - v.maxY, width: v.width, height: v.height)
    }

    private func refreshState() {
        guard let engine else { return }
        let next = Self.state(from: engine.snapshot())
        guard next != state else { return }
        state = next
        onChange?()
    }

    nonisolated static func rect(_ json: JSON?) -> CGRect? {
        guard let x = json?["x"]?.double, let y = json?["y"]?.double,
              let width = json?["width"]?.double, let height = json?["height"]?.double else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func state(from snapshot: CatWMEngine.Snapshot) -> EngineState {
        var out = EngineState()
        out.windows = (snapshot.windows.array ?? []).compactMap { w in
            guard let id = w["id"]?.int, w["minimized"] != .bool(true) else { return nil }
            return EngineWindow(id: UInt32(clamping: id), bundleID: w["app"]?.string, title: w["title"]?.string ?? "",
                                workspace: w["workspace"]?.string, display: w["screen"]?.string,
                                focused: w["focused"]?.isTrue == true, floating: w["floating"]?.isTrue == true,
                                visible: w["visible"]?.isTrue == true && w["fullscreen"]?.isTrue != true,
                                frame: rect(w["frame"]))
        }
        for screen in snapshot.screens.array ?? [] {
            guard let uuid = screen["uuid"]?.string else { continue }
            if let ws = screen["workspace"]?.string, !ws.isEmpty { out.shown[uuid] = ws }
            if screen["focused"]?.isTrue == true { out.focusedDisplay = uuid }
        }
        return out
    }
}
