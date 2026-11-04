import AppKit
import CaelestiaCore
import CaelestiaServices
import Combine
import SwiftUI

/// What the shell asks of the WM (implemented by CaelestiaWMKit's `ShellBridge`).
@MainActor
public protocol ShellHost: AnyObject {
    func shellFocusWorkspace(_ number: Int, display: String)
    /// Scroll on the workspaces: previous (-1) / next (+1) workspace of that display.
    func shellCycleWorkspace(_ delta: Int, display: String)
    /// An auto-hidden bar was revealed / hidden on `display`: reserve its width (Caelestia's
    /// exclusive zone follows the bar's visibility).
    func shellBarReservation(display: String, reserved: Bool)
}

/// The native shell, part 1 (spec 5.1, 5.2, 5.3, 5.7, 5.9): screen frame and bar per display,
/// launcher, session menu, OSDs and toasts. Lives in the WM process and is driven by
/// `ShellState`; panels never take focus except the launcher and the session menu while open.
@MainActor
public final class ShellController {
    public let state: ShellState
    public weak var host: ShellHost?
    public private(set) var theme: ShellTheme

    // Per display.
    public private(set) var frames: [String: ScreenFrameWindow] = [:]
    public private(set) var bars: [String: BarSurface] = [:]
    public private(set) var visibility: [String: BarVisibility] = [:]
    var layouts: [String: DisplayLayout] = [:]
    /// Top corner radii being tried in `caelestia frame calibrate` (display id → pt), drawn
    /// instead of the configured value until saved or cancelled.
    var cornerRadiusTrials: [String: Double] = [:]
    /// The same for the bottom corners.
    var bottomCornerRadiusTrials: [String: Double] = [:]
    var calibration: FrameCalibration?
    /// Where `frame calibrate` saves (the user's config.toml).
    public var configFileURL: URL = Paths.configFile

    // Drawers.
    public let launcher = LauncherModel()
    public let session = SessionModel()
    public let osd = OSDModel()
    public let toasts = ToastModel()
    private var launcherPanel: ShellPanel?
    private var sessionPanel: ShellPanel?
    private var osdPanel: ShellPanel?
    private var toastPanel: ShellPanel?
    // Part 2.
    public let dashboard = DashboardModel()
    public let sidebar = SidebarModel()
    public let popout = PopoutModel()
    public let wallpaperPicker = WallpaperModel()
    var dashboardPanel: ShellPanel?
    var sidebarPanel: ShellPanel?
    var popoutPanel: ShellPanel?
    var wallpaperPanel: ShellPanel?
    public internal(set) var popoutKind: PopoutKind?
    var popoutDisplay: String?
    public var notificationStore = NotificationStore()
    /// Where the history is persisted (set by the daemon; nil in tests: memory only).
    public internal(set) var notificationHistory: NotificationHistoryFile?
    public let wallpaper = WallpaperService()
    let wallpaperColors = WallpaperColors()
    public let media = MediaService()
    public let bluetooth = BluetoothService()
    public let keepAwake = KeepAwakeService()
    let sampler = SystemStatsSampler()
    let throughput = NetworkThroughputSampler()
    var statsTimer: Timer?
    var partTwoWired = false
    /// Called with every scheme the shell applies (the WM pushes it to the border overlay).
    public var onSchemeChange: ((Scheme) -> Void)?
    /// What the media-key interceptor may take over: (output volume settable, brightness
    /// controllable). Called whenever either changes.
    public var onMediaCapabilities: ((_ volume: Bool, _ brightness: Bool) -> Void)?
    private var lastMediaCapabilities: (Bool, Bool)?
    public var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var launcherDisplay: String?
    private var osdTimer = OSDTimer()
    public internal(set) var openDrawers: Set<Drawer> = []

    // Services.
    public let audio = AudioService()
    public let brightness = BrightnessService()
    public let network = NetworkService()
    public let battery = BatteryService()
    public let keyboard = KeyboardLayoutService()
    private let counts = LaunchCounts()
    public var runSession: (SessionAction) -> Void = SessionCommands.run

    private var monitors: [Any] = []
    var observers: [NSObjectProtocol] = []
    private var timers: [Timer] = []
    private var hideTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    public private(set) var isRunning = false
    /// Counters for `query shell` and the R5 test.
    public private(set) var reasserts = 0

    public init(state: ShellState, host: ShellHost?) {
        self.state = state
        self.host = host
        theme = ShellTheme(scheme: state.scheme, config: state.config, reduceMotion: state.reduceMotion)
        launcher.onActivate = { [weak self] in self?.activate($0) }
        launcher.onClose = { [weak self] in self?.close(.launcher) }
        session.onRun = { [weak self] action in
            self?.close(.session)
            Log.wm.notice("session: \(action.rawValue, privacy: .public)")
            self?.runSession(action)
        }
        session.onClose = { [weak self] in self?.close(.session) }
        osd.onSetVolume = { [weak self] v in self?.audio.setVolume(v); self?.pokeOSD() }
        osd.onSetBrightness = { [weak self] v in self?.brightness.set(v); self?.pokeOSD() }
        wirePartTwo()
    }

    // MARK: Lifecycle

    public func start(services startServices: Bool = true) {
        guard !isRunning else { return }
        isRunning = true
        rebuildSurfaces()
        if startServices { startServicesAndMonitors() }
        reloadApps()
        refreshColors()
    }

    /// `shell.kill`: every surface goes; services keep running.
    public func stop() {
        calibration?.close()
        calibration = nil
        cornerRadiusTrials.removeAll()
        bottomCornerRadiusTrials.removeAll()
        for (_, f) in frames { f.close() }
        for (_, b) in bars { b.close() }
        frames.removeAll()
        bars.removeAll()
        for p in [launcherPanel, sessionPanel, osdPanel, toastPanel] + partTwoPanels { p?.orderOut(nil); p?.close() }
        launcherPanel = nil; sessionPanel = nil; osdPanel = nil; toastPanel = nil
        dropPartTwoPanels()
        openDrawers.removeAll()
        for d in visibility.keys where visibility[d]?.isShown == true && visibility[d]?.persistent == false {
            host?.shellBarReservation(display: d, reserved: false)
        }
        visibility.removeAll()
        isRunning = false
    }

    /// `shell.restart`.
    public func restart() {
        stop()
        isRunning = true
        rebuildSurfaces()
    }

    /// Config / scheme / display changes from the WM.
    public func stateChanged() {
        let newTheme = ShellTheme(scheme: state.scheme, config: state.config, reduceMotion: state.reduceMotion)
        let themeChanged = newTheme != theme
        theme = newTheme
        guard isRunning else { return }
        if themeChanged { rebuildDrawers() }
        rebuildSurfaces()
    }

    // MARK: Frame + bar per display (R5)

    /// Creates, updates or removes the frame and bar of every display and orders them front.
    public func rebuildSurfaces() {
        guard isRunning else { return }
        reasserts += 1
        let ids = Set(state.displays.map(\.id))
        for id in Array(frames.keys) where !ids.contains(id) { frames.removeValue(forKey: id)?.close() }
        for id in Array(bars.keys) where !ids.contains(id) { bars.removeValue(forKey: id)?.close() }
        for id in Array(visibility.keys) where !ids.contains(id) { visibility[id] = nil }
        for d in state.displays {
            let layout = DisplayLayout(display: d, converter: state.converter, thickness: theme.frameThickness, barWidth: theme.barWidth,
                                       displayCornerRadius: displayCornerRadius(for: d),
                                       bottomCornerRadius: displayCornerRadius(for: d, corners: .bottom))
            layouts[d.id] = layout
            var vis = visibility[d.id] ?? BarVisibility(persistent: state.config.bar.persistent, showOnHover: state.config.bar.showOnHover)
            if vis.persistent != state.config.bar.persistent { vis.setPersistent(state.config.bar.persistent) }
            vis.showOnHover = state.config.bar.showOnHover
            visibility[d.id] = vis
            if state.config.wm.screenFrame {
                if let f = frames[d.id] { f.update(layout: layout, theme: theme) } else {
                    frames[d.id] = ScreenFrameWindow(displayID: d.id, layout: layout, theme: theme)
                }
                frames[d.id]?.show()
            } else {
                frames.removeValue(forKey: d.id)?.close()
            }
            if state.config.bar.enabled {
                let bar = bars[d.id] ?? makeBar(d.id, layout: layout)
                bars[d.id] = bar
                bar.update(layout: layout, theme: theme)
                let shown = vis.isShown
                bar.setReveal(shown ? 1 : bar.reveal.target, animated: false)
                bar.show()
                frames[d.id]?.setBarReveal(bar.reveal.value)
            } else {
                bars.removeValue(forKey: d.id)?.close()
            }
        }
    }

    private func makeBar(_ id: String, layout: DisplayLayout) -> BarSurface {
        let bar = BarSurface(displayID: id, layout: layout, state: state, theme: theme)
        bar.model.onLogo = { [weak self] in self?.toggle(.launcher, display: id) }
        bar.model.onPower = { [weak self] in self?.toggle(.session, display: id) }
        bar.model.onWorkspace = { [weak self] n in self?.host?.shellFocusWorkspace(n, display: id) }
        bar.model.onScrollWorkspace = { [weak self] d in self?.host?.shellCycleWorkspace(d, display: id) }
        bar.model.onTray = { [weak self] in self?.revealMenuBar(display: id) }
        bar.model.onClock = { [weak self] in self?.toggle(.dashboard, display: id) }
        bar.model.onStatus = { [weak self] icon, midY in self?.statusIconClicked(icon, display: id, windowMidY: midY) }
        bar.reveal.onChange = { [weak self, weak bar] v in
            bar?.model.reveal = v
            self?.frames[id]?.setBarReveal(v)
        }
        return bar
    }

    /// A bar is "shown" per R5 when its window is on screen and fully revealed.
    public func barIsShown(_ display: String) -> Bool {
        guard let b = bars[display] else { return false }
        return b.panel.isVisible && b.reveal.value >= 0.999
    }

    // MARK: Pointer → bar visibility

    func pointerMoved(_ p: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        for (id, layout) in layouts {
            guard var vis = visibility[id], !vis.persistent else { continue }
            let barStrip = layout.barFrame.insetBy(dx: 0, dy: 0)
            let over = p.x <= barStrip.maxX + BarVisibility.leaveMargin && p.x >= layout.area.minX - 1
                && p.y >= layout.area.minY && p.y <= layout.area.maxY
            vis.pinned = (openDrawers.contains(.session) && launcherDisplay == id) || (popoutKind != nil && popoutDisplay == id)
            if vis.pointer(inHotZone: layout.barHotZone(contains: p), overBar: over, at: now) {
                Log.shell.debug("bar \(vis.isShown ? "show" : "hide", privacy: .public) at \(p.x, privacy: .public),\(p.y, privacy: .public)")
                applyVisibility(id, vis)
            }
            visibility[id] = vis
        }
        scheduleHideTick()
    }

    private func scheduleHideTick() {
        let pending = visibility.values.contains { $0.hidePending }
        if pending, hideTimer == nil {
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideTick() }
            }
            RunLoop.main.add(t, forMode: .common)
            hideTimer = t
        } else if !pending {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }

    private func hideTick() {
        let now = ProcessInfo.processInfo.systemUptime
        for (id, var vis) in visibility where vis.tick(at: now) {
            Log.shell.debug("bar hide (delay) at \(NSEvent.mouseLocation.x, privacy: .public),\(NSEvent.mouseLocation.y, privacy: .public)")
            visibility[id] = vis
            applyVisibility(id, vis)
        }
        scheduleHideTick()
    }

    /// Explicit bar show/hide (IPC `shell.bar`, tests).
    public func setBarShown(_ shown: Bool, display: String) {
        guard var vis = visibility[display] else { return }
        let before = vis.isShown
        vis.set(shown: shown)
        visibility[display] = vis
        if before != vis.isShown { applyVisibility(display, vis) }
    }

    private func applyVisibility(_ id: String, _ vis: BarVisibility) {
        guard let bar = bars[id] else { return }
        let shown = vis.isShown
        if shown {
            bar.setReveal(1, animated: true, curve: .expressiveDefaultSpatial, ms: 400, theme: theme)
        } else {
            bar.setReveal(0, animated: true, curve: .emphasizedAccel, ms: 250, theme: theme)
        }
        if !vis.persistent { host?.shellBarReservation(display: id, reserved: shown) }
    }

    // MARK: Drawers

    public func isOpen(_ d: Drawer) -> Bool { openDrawers.contains(d) }

    public func toggle(_ d: Drawer, display: String? = nil) {
        if openDrawers.contains(d) { close(d) } else { open(d, display: display) }
    }

    public func open(_ d: Drawer, display: String? = nil) {
        guard isRunning else { return }
        let id = display ?? pointerDisplayID() ?? state.displays.first?.id
        guard let id, let layout = layouts[id] else { return }
        let reveal = bars[id]?.reveal.target ?? 0
        switch d {
        case .launcher:
            if openDrawers.contains(.session) { close(.session) }
            closeTransient()
            let panel = launcherPanel ?? makeDrawerPanel(LauncherView(model: launcher, fillet: theme.frameRounding), name: "launcher", key: true)
            launcherPanel = panel
            let body = LauncherModel.maxBodySize
            let size = CGSize(width: body.width + 2 * theme.frameRounding, height: body.height)
            panel.setFrame(layout.drawerFrame(size: size, edge: .bottom, barReveal: reveal), display: false)
            launcher.reset()
            launcher.apps = state.apps
            present(panel)
            launcher.shown = true
        case .session:
            if openDrawers.contains(.launcher) { close(.launcher) }
            closeTransient()
            let panel = sessionPanel ?? makeDrawerPanel(SessionView(model: session, fillet: theme.frameRounding), name: "session", key: true)
            sessionPanel = panel
            let body = SessionModel.bodySize
            let size = CGSize(width: body.width, height: body.height + 2 * theme.frameRounding)
            panel.setFrame(layout.drawerFrame(size: size, edge: .right, barReveal: reveal), display: false)
            session.reset()
            hideOSD(animated: true)
            present(panel)
            session.shown = true
        case .osd:
            showOSD(display: id)
            return
        case .dashboard: openDashboard(id, layout: layout, reveal: reveal)
        case .sidebar, .utilities:
            openSidebar(id, layout: layout, reveal: reveal)
            openDrawers.insert(.utilities)
            launcherDisplay = id
            openDrawers.insert(.sidebar)
            return
        case .wallpaper: openWallpaper(id, layout: layout, reveal: reveal)
        }
        launcherDisplay = id
        openDrawers.insert(d)
    }

    public func close(_ d: Drawer) {
        switch d {
        case .launcher:
            guard openDrawers.contains(.launcher) else { return }
            launcher.shown = false
            dismiss(launcherPanel)
        case .session:
            guard openDrawers.contains(.session) else { return }
            session.shown = false
            session.disarm()
            dismiss(sessionPanel)
        case .osd:
            hideOSD(animated: true)
        case .dashboard: closeDashboard()
        case .sidebar, .utilities: closeSidebar()
        case .wallpaper: closeWallpaper()
        }
        openDrawers.remove(d)
    }

    public func closeAll() {
        for d in openDrawers { close(d) }
    }

    func makeDrawerPanel<V: View>(_ view: V, name: String, key: Bool, clickThrough: Bool = false) -> ShellPanel {
        let panel = ShellPanel(frame: .zero, level: ShellLevel.drawer, clickThrough: clickThrough, name: name)
        panel.acceptsKey = key
        let host = ShellHostingView(rootView: AnyView(view.environment(\.shellTheme, theme)))
        panel.contentView = host
        return panel
    }

    private func rebuildDrawers() {
        closeAll()
        for p in [launcherPanel, sessionPanel, osdPanel, toastPanel] + partTwoPanels { p?.orderOut(nil); p?.close() }
        launcherPanel = nil; sessionPanel = nil; osdPanel = nil; toastPanel = nil
        dropPartTwoPanels()
    }

    /// Shows a drawer panel: SwiftUI evaluates the view in its hidden state first (a freshly
    /// created panel otherwise rendered straight at "shown" and appeared without its slide), then
    /// the panel is ordered in and fades in while the caller's `shown = true` slides the content.
    func present(_ panel: ShellPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.fadeIn(duration: theme.drawerOpenSeconds * 0.6)
    }

    /// Hides a drawer panel: it slides (SwiftUI, `shown = false` set by the caller) and fades out
    /// together, then is ordered out, unless it was re-opened meanwhile.
    func dismiss(_ panel: ShellPanel?) {
        guard let panel else { return }
        if panel.isKeyWindow { panel.resignKey() }
        let reopened: () -> Bool = { [weak self] in
            guard let self else { return false }
            if panel === self.launcherPanel, self.launcher.shown { return true }
            if panel === self.sessionPanel, self.session.shown { return true }
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            if !reopened() { panel.fadeOut(duration: self.theme.drawerCloseSeconds) }
        }
    }

    private func activate(_ item: LauncherItem) {
        switch item {
        case .app(let app):
            close(.launcher)
            counts.bump(app.id)
            if let i = state.apps.firstIndex(where: { $0.id == app.id }) { state.apps[i].launchCount += 1 }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { _ = self.toast(.error, title: "Could not open \(app.name)", message: error.localizedDescription) }
                }
            }
        case .command(let c):
            switch c.effect {
            case .session(let a):
                close(.launcher)
                open(.session)
                if let i = SessionModel.actions.firstIndex(of: a) { session.focused = i }
                if a == .lock { close(.session); runSession(.lock) }
            case .drawer(let d):
                close(.launcher)
                open(d)
            case .randomWallpaper:
                close(.launcher)
                randomWallpaper()
            case .later(let why):
                if c.name == "calculator" { launcher.query = "=" ; return }
                close(.launcher)
                toast(.info, title: ">\(c.name)", message: why)
            }
        case .calc(_, let result):
            guard let result else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
            close(.launcher)
            toast(.success, title: "Copied \(result)", message: "")
        }
    }

    public func reloadApps() {
        let counts = counts.counts
        DispatchQueue.global(qos: .utility).async {
            let apps = AppIndex.scan(counts: counts)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.state.apps = apps
                    if self.launcher.shown { self.launcher.apps = apps }
                }
            }
        }
    }

    // MARK: OSD

    public func showOSD(display: String? = nil) {
        guard isRunning, !openDrawers.contains(.session) else { return }
        let id = display ?? pointerDisplayID() ?? state.displays.first?.id
        guard let id, let layout = layouts[id] else { return }
        let panel = osdPanel ?? makeDrawerPanel(OSDView(model: osd, fillet: theme.frameRounding), name: "osd", key: false)
        panel.level = ShellLevel.osd
        osdPanel = panel
        osd.brightnessAvailable = brightness.state.unavailableReason == nil
        let body = OSDModel.maxBodySize
        let size = CGSize(width: body.width, height: body.height + 2 * theme.frameRounding)
        let reveal = bars[id]?.reveal.target ?? 0
        panel.setFrame(layout.drawerFrame(size: size, edge: .right, barReveal: reveal), display: false)
        if !panel.isVisible || !osd.shown { present(panel) }
        osd.shown = true
        openDrawers.insert(.osd)
        pokeOSD()
    }

    private func pokeOSD() {
        osdTimer.changed(at: ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + OSDModel.hideDelay + 0.02) { [weak self] in
            guard let self else { return }
            if self.osdTimer.shouldHide(at: ProcessInfo.processInfo.systemUptime, hovered: self.osd.hovered) {
                self.hideOSD(animated: true)
            } else if self.osd.shown, self.osd.hovered {
                self.pokeOSD()
            }
        }
    }

    func hideOSD(animated: Bool) {
        guard osd.shown else { return }
        osd.shown = false
        osdTimer.reset()
        openDrawers.remove(.osd)
        guard let panel = osdPanel else { return }
        // Always animated out (slide + fade); `animated: false` only shortens it.
        let duration = animated ? theme.drawerCloseSeconds : theme.seconds(ShellTheme.reducedFadeMs)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            if self?.osd.shown == false { panel.fadeOut(duration: duration) }
        }
    }

    // MARK: Toasts

    @discardableResult
    public func toast(_ kind: ToastKind, title: String, message: String, icon: String = "", record: Bool = true) -> UUID {
        let id = toasts.queue.add(Toast(kind: kind, title: title, message: message, icon: icon, createdAt: ProcessInfo.processInfo.systemUptime))
        if record { recordNotification(kind: kind, title: title, message: message, icon: icon) }
        guard isRunning, !state.doNotDisturb else {
            if state.doNotDisturb { toasts.queue.dismiss(id) }
            return id
        }
        let displayID = pointerDisplayID() ?? state.displays.first?.id
        if let displayID, let layout = layouts[displayID] {
            let panel = toastPanel ?? makeDrawerPanel(ToastsView(model: toasts), name: "toasts", key: false, clickThrough: true)
            panel.level = ShellLevel.osd
            toastPanel = panel
            let inner = layout.inner(barReveal: bars[displayID]?.reveal.target ?? 0)
            let w = ToastModel.width + 16
            let h = min(520, inner.height)
            panel.setFrame(CGRect(x: inner.maxX - w, y: inner.maxY - h, width: w, height: h), display: false)
            if !panel.isVisible { panel.contentView?.layoutSubtreeIfNeeded() }
            panel.fadeIn(duration: theme.drawerOpenSeconds * 0.5)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + toasts.queue.timeout + 0.05) { [weak self] in
            guard let self else { return }
            self.toasts.queue.expire(at: ProcessInfo.processInfo.systemUptime)
            if self.toasts.queue.isEmpty {
                let p = self.toastPanel
                DispatchQueue.main.asyncAfter(deadline: .now() + self.theme.drawerOpenSeconds + 0.05) {
                    if self.toasts.queue.isEmpty { p?.fadeOut(duration: self.theme.drawerCloseSeconds) }
                }
            }
        }
        return id
    }

    // MARK: Actions from the WM (keybinds)

    /// Returns true when the shell handled `action`.
    @discardableResult
    public func handle(_ action: Action) -> Bool {
        switch action.kind {
        case .launcherToggle: toggle(.launcher)
        case .sessionToggle: toggle(.session)
        case .lock: runSession(.lock)
        case .dashboardToggle, .panelsShowAll: toggle(.dashboard)
        case .sidebarToggle: toggle(.sidebar)
        case .notifsClear: clearNotifications()
        case .notifyTest:
            notify(title: "Test notification", body: "Sent from the keybind. Notifications from Caelestia appear here.", app: "caelestia-shell", icon: "info")
        case .shellKill: stop()
        case .shellRestart: restart()
        case .audioVolumeUp, .audioVolumeDown:
            // Media keys reach macOS too (fireAndPass): the system steps the volume and the
            // service reports it. From IPC / another chord nothing changes, so step ourselves.
            let before = audio.state.volume
            showOSD()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.audio.state.volume == before else { return }
                self.audio.step(action.kind == .audioVolumeUp ? AudioService.volumeStep : -AudioService.volumeStep)
            }
        case .audioToggleMute:
            let before = audio.state.muted
            showOSD()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.audio.state.muted == before else { return }
                self.audio.toggleMuted()
            }
        case .brightnessUp, .brightnessDown:
            // Reached here when macOS handles the key (no brightness control, or interception
            // off): show Caelestia's OSD only when it has a brightness to show. Without one the
            // OSD used to open with just its volume slider (live finding: "brightness keys show
            // the volume OSD").
            let up = action.kind == .brightnessUp
            let route = MediaKeyRouting.route(up ? .brightnessUp : .brightnessDown, intercept: state.config.input.interceptMediaKeys,
                                              volumeControllable: audio.state.volumeSettable, brightnessControllable: brightness.isControllable)
            if route.swallow {
                // A keybind (not the F-key, which the tap swallowed already): do it ourselves.
                brightness.step(up: up)
                showOSD()
            } else if route.osd == .brightness {
                // macOS steps it; read the new value once it has.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    self?.brightness.refresh()
                    self?.showOSD()
                }
            } else {
                brightness.noteBrightnessKey(up: up)
            }
        default:
            return false
        }
        return true
    }

    /// A volume / mute / brightness key the event tap swallowed (so Apple's HUD never shows):
    /// Caelestia changes the value itself and shows only its own OSD. Holding the key repeats;
    /// ⌥⇧ gives quarter steps, as on macOS.
    public func handleMediaKey(_ e: MediaKeyEvent) {
        guard e.isDown, let command = e.command else { return }
        let fine = e.isFine
        switch command {
        case .volumeUp, .volumeDown:
            let step = fine ? BrightnessService.keyStep / 4 : BrightnessService.keyStep
            if audio.state.muted, command == .volumeUp { audio.setMuted(false) }
            audio.setVolume(BrightnessService.stepped(audio.state.volume, up: command == .volumeUp, step: step))
            showOSD()
        case .mute:
            guard !e.isRepeat else { return }
            audio.toggleMuted()
            showOSD()
        case .brightnessUp, .brightnessDown:
            brightness.step(up: command == .brightnessUp, fine: fine)
            showOSD()
        }
    }

    private func publishMediaCapabilities() {
        let now = (audio.state.volumeSettable, brightness.isControllable)
        guard lastMediaCapabilities.map({ $0 != now }) ?? true else { return }
        lastMediaCapabilities = now
        onMediaCapabilities?(now.0, now.1)
    }

    /// CGDirectDisplayID of the screen under the pointer.
    private static func pointerDisplay() -> CGDirectDisplayID? {
        let p = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: Services, monitors, R5 triggers

    private func startServicesAndMonitors() {
        audio.onChange = { [weak self] s in self?.audioChanged(s) }
        brightness.onChange = { [weak self] s in self?.brightnessChanged(s) }
        brightness.preferredDisplay = { Self.pointerDisplay() }
        network.onChange = { [weak self] s in self?.applyNetwork(s) }
        battery.onChange = { [weak self] s in self?.applyBattery(s) }
        keyboard.onChange = { [weak self] s in self?.state.status.keyboardLayout = s.name }
        audio.start(); brightness.start(); network.start(); battery.start(); keyboard.start()
        startPartTwoServices()
        audioChanged(audio.state, quiet: true)
        brightnessChanged(brightness.state, quiet: true)
        applyNetwork(network.state)
        applyBattery(battery.state)
        state.status.keyboardLayout = keyboard.state.name
        state.capsLockOn = keyboard.capsLockState()

        let move: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved(NSEvent.mouseLocation) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: move) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in move(e); return e }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.state.capsLockOn = e.modifierFlags.contains(.capsLock)
        }) { monitors.append(m) }
        // A click anywhere else closes the launcher / session menu (Caelestia: click outside).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self else { return }
            if self.openDrawers.contains(.launcher) { self.close(.launcher) }
            if self.openDrawers.contains(.session) { self.close(.session) }
            self.closeTransient(includingSidebar: true)
        }) { monitors.append(m) }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reassertSoon() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassertSoon() }
        })

        // Clock: tick on the minute.
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                for b in self.bars.values where Calendar.current.component(.minute, from: b.model.now) != Calendar.current.component(.minute, from: now) {
                    b.model.now = now
                }
            }
        }
        RunLoop.main.add(clock, forMode: .common)
        timers.append(clock)
    }

    /// R5: after wake / Space change / screen change / fullscreen, put every surface back now and
    /// once more shortly after (the window server may still be settling).
    public func reassertSoon() {
        rebuildSurfaces()
        refreshColors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.rebuildSurfaces() }
    }

    private func audioChanged(_ s: AudioState, quiet: Bool = false) {
        let changed = s.volume != state.status.volume || s.muted != state.status.muted
        state.status.volume = s.volume
        state.status.muted = s.muted
        state.status.outputDeviceName = s.outputDeviceName
        state.status.inputDeviceName = s.inputDeviceName
        state.status.micMuted = s.micMuted
        state.status.micVolume = s.micVolume
        osd.volume = s.volume
        osd.muted = s.muted
        publishMediaCapabilities()
        if changed, !quiet { showOSD() }
    }

    private func brightnessChanged(_ s: BrightnessState, quiet: Bool = false) {
        let changed = abs(s.value - state.status.brightness) > 0.001
        state.status.brightness = s.value
        osd.brightness = s.value
        osd.brightnessAvailable = s.unavailableReason == nil
        publishMediaCapabilities()
        if changed, !quiet { showOSD() }
    }

    private func applyNetwork(_ s: NetworkState) {
        state.status.wifiAvailable = s.unavailableReason == nil
        state.status.wifiEnabled = s.wifiEnabled
        state.status.wifiConnected = s.wifiConnected
        state.status.ssid = s.ssid
        state.status.wifiStrength = s.wifiStrength
        state.status.ethernetConnected = s.ethernetConnected
    }

    private func applyBattery(_ s: BatteryState) {
        state.status.hasBattery = s.hasBattery
        state.status.batteryPercent = s.percent
        state.status.batteryCharging = s.isCharging
        state.status.batteryTimeRemainingMinutes = s.timeRemainingMinutes
        state.status.batteryPluggedIn = s.isPluggedIn
        state.status.lowPowerMode = s.isLowPowerMode
    }

    /// macOS has no public API for other apps' menu extras: reveal the auto-hidden menu bar by
    /// moving the pointer to the top edge of the display (spec 5.2 tray limit).
    func revealMenuBar(display: String) {
        guard let d = state.displays.first(where: { $0.id == display }) else { return }
        CGWarpMouseCursorPosition(CGPoint(x: d.frame.midX, y: d.frame.minY + 1))
    }

    func pointerDisplayID() -> String? {
        let p = NSEvent.mouseLocation
        return layouts.first { $0.value.area.insetBy(dx: -1, dy: -40).contains(p) }?.key
    }

    public func teardown() {
        stop()
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o); NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        for t in timers { t.invalidate() }
        timers.removeAll()
        audio.stop(); brightness.stop(); network.stop(); battery.stop(); keyboard.stop()
        media.stop(); bluetooth.stop()
        stopStatsTimer()
    }
}

/// One display's bar window and its reveal tween.
@MainActor
public final class BarSurface {
    public let panel: ShellPanel
    public let model: BarModel
    public let reveal = ShellTween(0)
    private let host: ShellHostingView<AnyView>
    private var layout: DisplayLayout
    private let state: ShellState
    private var theme: ShellTheme

    init(displayID: String, layout: DisplayLayout, state: ShellState, theme: ShellTheme) {
        self.layout = layout
        self.state = state
        self.theme = theme
        model = BarModel(displayID: displayID)
        panel = ShellPanel(frame: layout.barFrame, level: ShellLevel.bar, name: "bar")
        host = ShellHostingView(rootView: AnyView(BarView(state: state, model: model).environment(\.shellTheme, theme)))
        panel.contentView = host
    }

    func update(layout: DisplayLayout, theme: ShellTheme) {
        self.layout = layout
        if panel.frame != layout.barFrame { panel.setFrame(layout.barFrame, display: true) }
        guard theme != self.theme else { return }
        self.theme = theme
        host.rootView = AnyView(BarView(state: state, model: model).environment(\.shellTheme, theme))
    }

    func setReveal(_ value: Double, animated: Bool, curve: ShellCurve = .standard, ms: Double = 0, theme: ShellTheme? = nil) {
        if animated, let theme, theme.seconds(ms) > 0 {
            reveal.animate(to: value, duration: theme.seconds(ms), curve: curve)
        } else if reveal.target != value || reveal.value != value {
            reveal.set(value)
        }
        // Hidden: let clicks reach the windows under the (now empty) strip.
        panel.ignoresMouseEvents = value <= 0
    }

    func show() { panel.orderFrontRegardless() }
    func close() {
        reveal.set(0)
        panel.orderOut(nil)
        panel.close()
    }
}
