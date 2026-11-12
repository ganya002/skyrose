import CaelestiaCore
import CaelestiaShell
import CoreGraphics
import Foundation

/// One window as an external engine reports it, for the bar and the active-window readout.
public struct EngineWindow: Equatable, Sendable {
    public var id: UInt32
    public var bundleID: String?
    public var title: String
    public var workspace: String?
    public var display: String?
    public var focused: Bool
    public var floating: Bool
    /// On a shown workspace, not minimized or fullscreen: it gets a border.
    public var visible: Bool
    /// The resting frame in top-left points.
    public var frame: CGRect?

    public init(id: UInt32, bundleID: String?, title: String, workspace: String?, display: String?,
                focused: Bool, floating: Bool, visible: Bool = false, frame: CGRect? = nil) {
        (self.id, self.bundleID, self.title, self.workspace, self.display, self.focused, self.floating) =
            (id, bundleID, title, workspace, display, focused, floating)
        (self.visible, self.frame) = (visible, frame)
    }
}

/// What the shell needs to know from an external engine.
public struct EngineState: Equatable, Sendable {
    public var windows: [EngineWindow] = []
    /// Display UUID -> the workspace it shows.
    public var shown: [String: String] = [:]
    public var focusedDisplay: String?
    /// The open special workspace's name (without `special:`), shown over every display.
    public var openSpecial: String?

    public init() {}

    /// The number of the workspace `display` shows, when it is a numbered one.
    public func activeNumber(on display: String) -> Int? { shown[display].flatMap(Int.init) }

    /// The bar's pills for `display`, the same shape as `ShellBridge.pills(state:...)`.
    public func pills(display: String, shown count: Int) -> [WorkspacePill] {
        let n = max(1, count)
        let active = activeNumber(on: display) ?? 1
        let group = (active - 1) / n
        return (1...n).map { i in
            let number = group * n + i
            let members = windows.filter { $0.workspace == String(number) }
            let apps = members.prefix(WorkspacePill.maxWindowIcons).compactMap(\.bundleID)
            return WorkspacePill(id: number, name: String(number), occupied: !members.isEmpty, active: number == active,
                                 windowCount: members.count, apps: apps)
        }
    }
}

/// A window manager engine other than SkyRose's own (CatWM). SkyRose keeps the shell, the binds and
/// the IPC; the engine owns every window. Implementations live outside CaelestiaWMKit
/// (`Sources/SkyRoseCatWM`) so nothing else links the engine.
@MainActor
public protocol WindowEngine: AnyObject {
    /// Shown in logs and the About page.
    var name: String { get }
    /// Starts managing windows. `area` is SkyRose's usable area on the primary display (bar and
    /// gaps already taken out), in top-left points.
    func start(config: Config, area: CGRect?) throws
    /// A new config: the engine applies only what changed.
    func apply(config: Config, area: CGRect?)
    /// Puts every window back where the user can reach it and stops. Must return within a few
    /// seconds whatever state the engine is in (panic uses it).
    func stop()
    /// Runs a bind. nil: not a window-manager action (the shell gets it). false: it did nothing.
    func perform(_ action: Action) -> Bool?
    var state: EngineState { get }
    /// Called after the engine's windows or workspaces changed.
    var onChange: (() -> Void)? { get set }
    /// Every frame of window motion: all windows in flight (top-left points). An empty map ends it.
    var onFrames: (([UInt32: CGRect]) -> Void)? { get set }
}
