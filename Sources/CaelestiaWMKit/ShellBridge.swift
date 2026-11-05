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

    public init(wm: WindowManager, scheme: Scheme = SchemeLoader.builtIn(named: "skyrose-dynamic-dark") ?? ShellTheme.gabby.scheme) {
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

    /// Starts the shell, unless the config says WM-only mode or the shell is switched off (then
    /// only the colour scheme is resolved, for the borders and the Settings app).
    public func start() {
        sync()
        if state.config.shellOff {
            controller.refreshColors()
        } else {
            controller.start()
        }
    }

    /// Applies a new (effective) config live: switching to WM-only mode or turning the shell off
    /// closes every shell surface and releases the bar's reserved space; switching back starts
    /// the shell again. Nothing restarts the process.
    public func apply(config: Config) {
        let wasOff = state.config.shellOff
        state.config = config
        if config.shellOff {
            if controller.isRunning { controller.stop() }
            controller.refreshColors()
            return
        }
        if wasOff || !controller.isRunning {
            controller.start()
            return
        }
        controller.stateChanged()
        controller.refreshColors()
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
        case .shellDashboard, .shellShowAll: controller.toggle(.dashboard); return ok()
        case .shellSidebar: controller.toggle(.sidebar); return ok()
        case .shellClearNotifs, .shellNotifsClear: controller.clearNotifications(); return ok()
        case .shellNotifsToggleDnd: controller.setDoNotDisturb(!state.doNotDisturb); return ok()
        case .shellNotifsEnableDnd: controller.setDoNotDisturb(true); return ok()
        case .shellNotifsDisableDnd: controller.setDoNotDisturb(false); return ok()
        case .shellNotifsIsDndEnabled: return ok(.string(state.doNotDisturb ? "true" : "false"))
        case .notify:
            guard let title = request.string("title"), !title.isEmpty else { return fail("title is required") }
            let id = controller.notify(title: title, body: request.string("body") ?? "", app: request.string("app") ?? "", icon: request.string("icon") ?? "")
            return ok(.object(["id": .string(id.uuidString)]))
        case .shellWallpaperGet:
            return ok(.string(controller.displayedWallpaper?.path ?? ""))
        case .shellWallpaperList:
            let folder = WallpaperLibrary.folderURL(state.config.appearance.wallpaperFolder)
            return ok(.string(WallpaperLibrary.scan(folder: folder).urls.map(\.path).joined(separator: "\n")))
        case .shellWallpaperSet:
            guard let path = request.string("path") else { return fail("path is required") }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return fail("no such file: \(url.path)") }
            controller.setWallpaper(url)
            return ok()
        case .wallpaperRandom:
            controller.randomWallpaper()
            return ok()
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
        case .shellDrawersToggle where (request.string("drawer") ?? "").lowercased().hasPrefix("popout."):
            let name = String((request.string("drawer") ?? "").lowercased().dropFirst("popout.".count))
            guard let kind = PopoutKind(rawValue: name) else { return fail("unknown popout \(name); use audio, network, bluetooth or battery") }
            controller.togglePopout(kind)
            return ok()
        case .shellDrawersToggle:
            guard let d = drawer() else { return fail("unknown drawer \(request.string("drawer") ?? ""); see `shell drawers list`") }
            controller.toggle(d)
            return ok()
        // Keep awake (Caelestia's idle inhibitor): the sidebar toggle's power assertion.
        case .shellIdleInhibitorToggle: controller.keepAwake.toggle(); return ok(.string(controller.keepAwake.isEnabled ? "true" : "false"))
        case .shellIdleInhibitorEnable: controller.keepAwake.set(on: true); return ok(.string(controller.keepAwake.isEnabled ? "true" : "false"))
        case .shellIdleInhibitorDisable: controller.keepAwake.set(on: false); return ok(.string("false"))
        case .shellIdleInhibitorIsEnabled: return ok(.string(controller.keepAwake.isEnabled ? "true" : "false"))
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
        case .frameCalibrate:
            switch controller.startFrameCalibration(display: request.string("display")) {
            case .success(let (id, radius)):
                return ok(.object(["display": .string(id), "radius": .number(radius)]))
            case .failure(let e):
                return fail(e.message)
            }
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

    public func shellKeyDrawerClosed(launched: Bool) {
        wm?.keyDrawerClosed(launched: launched)
    }
}
