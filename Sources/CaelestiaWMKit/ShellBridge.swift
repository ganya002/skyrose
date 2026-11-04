import AppKit
import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaPlatform
import CaelestiaShell
import Foundation

/// Connects the native shell (CaelestiaShell) to the WM: it mirrors the WM's workspaces, focused
/// window and displays into `ShellState` after every layout pass, forwards shell keybinds and
/// `shell.*` IPC to the `ShellController`, and turns the bar's reveal into reserved space.
@MainActor
public final class ShellBridge: ShellHost {
    public let state: ShellState
    public let controller: ShellController
    private weak var wm: WindowManager?

    public init(wm: WindowManager, scheme: Scheme = SchemeLoader.builtIn(named: "caelestia-dynamic-dark") ?? ShellTheme.gabby.scheme) {
        self.wm = wm
        let converter = (wm.displayProvider as? DisplayMonitor)?.converter
            ?? CoordinateConverter(primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0))
        state = ShellState(
            scheme: scheme, config: wm.config, animations: AnimationTable.from(config: wm.config.animations, reduceMotion: false),
            displays: wm.displays, converter: converter
        )
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        controller = ShellController(state: state, host: nil)
        controller.host = self
    }

    public func start() {
        sync()
        controller.start()
    }

    public func apply(config: Config) {
        state.config = config
        controller.stateChanged()
    }

    /// Mirrors the WM into `ShellState` (cheap; called after each layout pass).
    public func sync() {
        guard let wm else { return }
        let converter = (wm.displayProvider as? DisplayMonitor)?.converter ?? state.converter
        let displaysChanged = wm.displays != state.displays || converter != state.converter
        if displaysChanged {
            state.displays = wm.displays
            state.converter = converter
        }
        var pills: [String: [WorkspacePill]] = [:]
        var special: [String: String] = [:]
        for d in wm.displays {
            pills[d.id] = Self.pills(state: wm.state, display: d.id, shown: wm.config.wm.workspacesShown)
            if let s = wm.state.openSpecial(onDisplay: d.id) { special[d.id] = s }
        }
        if pills != state.workspaces { state.workspaces = pills }
        if special != state.openSpecial { state.openSpecial = special }
        let focusedDisplay = wm.state.focusedDisplay
        if focusedDisplay != state.focusedDisplayID { state.focusedDisplayID = focusedDisplay }
        var active: ActiveWindowInfo?
        if let f = wm.state.focusedWindow, let h = wm.handle(for: f) {
            let d = h.descriptor()
            active = ActiveWindowInfo(windowID: f, title: h.title, appName: d.appName, bundleID: h.bundleID, displayID: wm.state.display(of: f) ?? "")
        }
        if active != state.activeWindow { state.activeWindow = active }
        if displaysChanged { controller.stateChanged() }
    }

    /// The bar's workspace pills: the `shown` workspaces of the group the active one is in
    /// (Caelestia `workspaces.shown`), occupied = has windows.
    public static func pills(state: WorkspaceState, display: String, shown: Int) -> [WorkspacePill] {
        let n = max(1, shown)
        let active = state.activeNumberedWorkspace(forDisplay: display) ?? 1
        let group = (active - 1) / n
        return (1...n).map { i in
            let id = group * n + i
            let count = state[.numbered(id)]?.windows.count ?? 0
            return WorkspacePill(id: id, name: String(id), occupied: count > 0, active: id == active, windowCount: count)
        }
    }

    // MARK: Actions and IPC

    /// Keybind actions the WM does not own. True when the shell took it.
    public func handle(_ action: Action) -> Bool { controller.handle(action) }

    public func respond(to request: IPCRequest, command: IPCCommand) -> IPCResponse? {
        func ok(_ v: JSONValue? = nil) -> IPCResponse { .success(for: request, result: v) }
        func fail(_ e: String) -> IPCResponse { .failure(for: request, error: e) }
        func drawer() -> Drawer? { request.string("drawer").flatMap { Drawer(rawValue: $0.lowercased()) } }
        func toast(_ kind: ToastKind) -> IPCResponse {
            controller.toast(kind, title: request.string("title") ?? "", message: request.string("message") ?? "", icon: request.string("icon") ?? "")
            return ok()
        }
        switch command {
        case .shellLauncher: controller.toggle(.launcher); return ok()
        case .shellSession: controller.toggle(.session); return ok()
        case .shellKill: controller.stop(); return ok()
        case .shellRestart: controller.restart(); return ok()
        case .shellToasterError: return toast(.error)
        case .shellToasterWarn: return toast(.warn)
        case .shellToasterInfo: return toast(.info)
        case .shellToasterSuccess: return toast(.success)
        case .shellDrawersList:
            return ok(.string(Drawer.allCases.map(\.rawValue).joined(separator: "\n")))
        case .shellDrawersIsOpen:
            guard let d = drawer() else { return fail("unknown drawer \(request.string("drawer") ?? ""); see `shell drawers list`") }
            return ok(.string(controller.isOpen(d) ? "true" : "false"))
        case .shellDrawersToggle:
            guard let d = drawer() else { return fail("unknown drawer \(request.string("drawer") ?? ""); see `shell drawers list`") }
            guard [.launcher, .session, .osd].contains(d) else { return fail("the \(d.rawValue) is not built yet (shell part 1: launcher, session, osd)") }
            controller.toggle(d)
            return ok()
        case .shellBrightnessGet:
            return ok(JSONValue(controller.brightness.state.value))
        case .shellBrightnessSet:
            guard let raw = request.string("value") else { return fail("value is required") }
            let current = controller.brightness.state.value
            let v: Double?
            if raw.hasSuffix("%+") || raw.hasSuffix("%-") {
                v = Double(raw.dropLast(2)).map { current + ($0 / 100) * (raw.hasSuffix("+") ? 1 : -1) }
            } else if raw.hasSuffix("%") {
                v = Double(raw.dropLast()).map { $0 / 100 }
            } else {
                v = Double(raw)
            }
            guard let v else { return fail("value must be 0..1, N%, N%+ or N%-") }
            controller.brightness.set(min(1, max(0, v)))
            controller.showOSD()
            return ok(.string(String(format: "%.2f", controller.brightness.state.value)))
        default:
            return nil
        }
    }

    // MARK: ShellHost

    public func shellFocusWorkspace(_ number: Int, display: String) {
        guard let wm else { return }
        wm.state.focusWorkspace(.numbered(number), display: display)
        wm.setNeedsLayout()
    }

    public func shellCycleWorkspace(_ delta: Int, display: String) {
        guard let wm, let current = wm.state.activeNumberedWorkspace(forDisplay: display) else { return }
        let next = max(1, current + delta)
        guard next != current else { return }
        shellFocusWorkspace(next, display: display)
    }

    public func shellBarReservation(display: String, reserved: Bool) {
        wm?.setBarRevealed(reserved, display: display)
    }
}
