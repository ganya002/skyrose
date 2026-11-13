import AppKit
import CaelestiaCore
import CaelestiaPlatform
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
    /// A key drawer (launcher / session menu) closed. macOS gives focus back to the previously
    /// active app; unless `launched`, that is not a reason to follow it to another workspace.
    func shellKeyDrawerClosed(launched: Bool)
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
    /// Top corner radii being tried in `skyrose frame calibrate` (display id → pt), drawn
    /// instead of the configured value until saved or cancelled.
    var cornerRadiusTrials: [String: Double] = [:]
    /// The same for the bottom corners.
    var bottomCornerRadiusTrials: [String: Double] = [:]
    var calibration: FrameCalibration?
    /// Where `frame calibrate` saves (the user's config.toml).
    public var configFileURL: URL = Paths.configFile

    // Drawers.
    public let launcher = LauncherModel()
    /// Desktop cross-fades: the `>wallpaper` carousel preview and every wallpaper change.
    public let wallpaperPreview = WallpaperPreview()
    /// The carousel is previewing (closing the launcher without a pick reverts the desktop).
    var carouselPreviewing = false
    public let appWatcher = AppIndexWatcher()
    public let session = SessionModel()
    public let osd = OSDModel()
    /// Toasts and notification popups: one drawer out of the top-right corner.
    public let popups = ToastModel()
    /// The screenshot tool (capture.* binds, `skyrose screenshot`).
    public let screenshots = ScreenshotController()
    /// The screen recorder (utilities card, `record.screen`, `skyrose record`).
    public let movieRecorder = DisplayMovieRecorder()
    private var launcherPanel: ShellPanel?
    private var clipboardPanel: ShellPanel?
    private var sessionPanel: ShellPanel?
    private var osdPanel: ShellPanel?
    private var popupPanel: ShellPanel?
    /// The SIP-off helper card (ShellController+HelperCard).
    public let helperCard = HelperCardModel()
    var helperPanel: ShellPanel?
    /// Root loaded the helper: the WM should probe for it now.
    public var onHelperLoaded: () -> Void = {}
    // Part 2.
    public let dashboard = DashboardModel()
    public let sidebar = SidebarModel()
    public let widgetHost = WidgetHost()
    public let popout = PopoutModel()
    public let wallpaperPicker = WallpaperModel()
    var dashboardPanel: ShellPanel?
    var sidebarPanel: ShellPanel?
    public let utilities = UtilitiesDrawerModel()
    var utilitiesPanel: ShellPanel?
    /// Drawers opened by hovering their edge or corner: they close when the pointer leaves
    /// (keybind-opened ones stay until toggled).
    public internal(set) var hoverOpened: Set<Drawer> = []
    /// A closed hover zone the pointer entered, and when (opens after `HoverReveal.dwell`).
    var hoverPending: (target: HoverReveal.Target, display: String, since: TimeInterval)?
    var utilitiesSizeCache: [String: CGSize] = [:]
    var lastHoverPointer: CGPoint?
    /// Drag / swipe from the right edge (session menu, sidebar).
    var edgeDrag = EdgeDrag()
    var edgeDragDisplay: String?
    /// The scrim behind the session menu (Caelestia dims the screen while it is open).
    var dimPanel: ShellPanel?
    var popoutPanel: ShellPanel?
    var wallpaperPanel: ShellPanel?
    /// SkyStore (ShellController+Store).
    public let store = StoreModel()
    var storePanel: ShellPanel?
    public internal(set) var popoutKind: PopoutKind?
    var popoutDisplay: String?
    /// The popout was opened by hovering a bar item (it closes when the pointer leaves the bar
    /// and the popout); a click-opened popout stays until clicked away.
    var popoutByHover = false
    var popoutLeaveTimer: Timer?
    var previewTask: Task<Void, Never>?
    /// "display/item" under the pointer (bar hover popouts).
    var hoveredBarItem: String?
    public var notificationStore = NotificationStore()
    /// Where the history is persisted (set by the daemon; nil in tests: memory only).
    public internal(set) var notificationHistory: NotificationHistoryFile?
    public let wallpaper = WallpaperService()
    public let liveWallpaper = LiveWallpaperController()
    let wallpaperColors = WallpaperColors()
    public let media = MediaService()
    let mediaStage = MediaStage()
    public let clipboard = ClipboardSession()
    public let bluetooth = BluetoothService()
    public let keepAwake = KeepAwakeService()
    /// Lid state + the optional lid-closed keep-awake (`[clamshell]`).
    public let clamshell = ClamshellMonitor()
    /// `pmset disablesleep` while Clamshell or a keep-awake is on (lid closed on battery / built-in only).
    public let lidSleep = LidSleepControl()
    /// Open-Meteo weather for the dashboard (`[weather]`).
    public private(set) lazy var weatherController = WeatherController(state: state)
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

    /// A drawer or popout is open, or a toast sits under the point (top-left coordinates).
    public func blocksPointerFocus(at point: CGPoint) -> Bool {
        if !openDrawers.isEmpty || popoutKind != nil { return true }
        guard let main = NSScreen.screens.first else { return false }
        let p = CGPoint(x: point.x, y: main.frame.height - point.y)
        return popupPanel?.isVisible == true && popupPanel!.frame.contains(p)
    }

    // Services.
    public let audio = AudioService()
    public let brightness = BrightnessService()
    public let network = NetworkService()
    public let battery = BatteryService()
    public let keyboard = KeyboardLayoutService()
    public let nightShift = NightShiftService()
    private let counts = LaunchCounts()
    public var runSession: (SessionAction) -> Void = SessionCommands.run

    private var monitors: [Any] = []
    var observers: [NSObjectProtocol] = []
    private var timers: [Timer] = []
    private var hideTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    public private(set) var isRunning = false
    private var servicesStarted = false
    /// Counters for `query shell` and the R5 test.
    public private(set) var reasserts = 0

    public init(state: ShellState, host: ShellHost?) {
        self.state = state
        self.host = host
        theme = Self.makeTheme(state)
        launcher.onActivate = { [weak self] in self?.activate($0) }
        launcher.onClose = { [weak self] in self?.close(.launcher) }
        launcher.onPreview = { [weak self] url in self?.previewWallpaper(url) }
        launcher.onPickWallpaper = { [weak self] url in self?.pickCarouselWallpaper(url) }
        launcher.onNeedThumb = { [weak self] url in
            guard let self, self.launcher.thumbs[url] == nil else { return }
            self.wallpaper.thumbnail(for: url, maxPixel: WallpaperService.carouselThumbnailSize) { img in
                if let img { self.launcher.thumbs[url] = img }
            }
        }
        session.onRun = { [weak self] action in
            self?.close(.session)
            Log.wm.notice("session: \(action.rawValue, privacy: .public)")
            self?.runSession(action)
        }
        session.onClose = { [weak self] in self?.close(.session) }
        osd.onSetVolume = { [weak self] v in self?.audio.setVolume(v); self?.pokeOSD() }
        osd.onSetBrightness = { [weak self] v in self?.brightness.set(v); self?.pokeOSD() }
        osd.onStepVolume = { [weak self] d in self?.audio.step(Double(d) * AudioService.volumeStep); self?.pokeOSD() }
        osd.onStepBrightness = { [weak self] d in self?.brightness.step(up: d > 0); self?.pokeOSD() }
        wirePartTwo()
    }

    // MARK: Lifecycle

    public func start(services startServices: Bool = true) {
        guard !isRunning else { return }
        isRunning = true
        rebuildSurfaces()
        // Services and monitors start once per process: a later start() (WM-only mode switched
        // back off) only rebuilds the surfaces.
        if startServices, !servicesStarted {
            servicesStarted = true
            startServicesAndMonitors()
        }
        if appWatcher.onChange == nil {
            appWatcher.onChange = { [weak self] in self?.reloadApps() }
            appWatcher.start()
        }
        reloadApps()
        refreshColors()
        resumeLiveWallpaper()
        startWidgets()
    }

    /// Widget addons: their cards go to the sidebar, their toasts are named after them.
    func startWidgets() {
        widgetHost.onChange = { [weak self] cards in self?.state.widgets = cards }
        widgetHost.onToast = { [weak self] name, title, message in _ = self?.toast(.info, title: "\(name): \(title)", message: message, icon: "widgets") }
        widgetHost.media = { [weak self] in self?.state.media ?? MediaInfo() }
        sidebar.onWidget = { [weak self] id in self?.widgetHost.click(id) }
        widgetHost.start()
    }

    /// `shell.kill`: every surface goes; services keep running.
    public func stop() {
        liveWallpaper.stop(clearRecord: false)
        widgetHost.stop()
        calibration?.close()
        calibration = nil
        cornerRadiusTrials.removeAll()
        bottomCornerRadiusTrials.removeAll()
        for (_, f) in frames { f.close() }
        for (_, b) in bars { b.close() }
        frames.removeAll()
        bars.removeAll()
        for p in [launcherPanel, clipboardPanel, sessionPanel, osdPanel, popupPanel, helperPanel] + partTwoPanels { p?.orderOut(nil); p?.close() }
        launcherPanel = nil; clipboardPanel = nil; sessionPanel = nil; osdPanel = nil; popupPanel = nil; helperPanel = nil
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
        let newTheme = Self.makeTheme(state)
        let themeChanged = newTheme != theme
        theme = newTheme
        guard isRunning else { return }
        if servicesStarted {
            weatherController.configure(state.config.weather)
            clipboard.setLimits(maxEntries: state.config.clipboard.maxEntries, maxBytes: state.config.clipboard.maxBytes)
            refreshFeatures()
        }
        closeDisabledDrawers()
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
        hoverReveal(p, at: now)
        barHover(p)
    }

    /// Hit-tests the pointer against the shown bars' popout items (`BarModel.itemFrames`).
    func barHover(_ p: CGPoint) {
        var hit: (item: String, display: String, midY: Double)?
        for (id, bar) in bars where bar.model.reveal > 0.5 {
            let f = bar.panel.frame
            guard f.contains(p) else { continue }
            let local = CGPoint(x: p.x - f.minX, y: f.maxY - p.y)
            if let item = bar.model.itemFrames.first(where: { $0.value.insetBy(dx: -3, dy: -3).contains(local) }) {
                hit = (item.key, id, item.value.midY)
            }
        }
        let key = hit.map { "\($0.display)/\($0.item)" }
        guard key != hoveredBarItem else { return }
        hoveredBarItem = key
        if let hit {
            barItemHovered(hit.item, display: hit.display, windowMidY: hit.midY)
        } else {
            barItemHovered(nil, display: popoutDisplay ?? "", windowMidY: 0)
        }
    }

    // MARK: Edge drags (Caelestia Interactions.qml)

    func edgeZone(_ p: CGPoint) -> (display: String, zone: EdgeDrag.Zone)? {
        guard isRunning else { return nil }
        for (id, layout) in layouts {
            let sessionH = SessionModel.bodySize.height + 2 * theme.frameRounding
            if let z = EdgeDrag.zone(at: p, layout: layout, barReveal: bars[id]?.reveal.target ?? 0, sessionHeight: sessionH) {
                let moduleOn = z == .session ? isModuleOn(.session) : isModuleOn(.sidebar)
                return moduleOn ? (id, z) : nil
            }
        }
        return nil
    }

    func edgeDragBegin(_ p: CGPoint) {
        let hit = edgeZone(p)
        edgeDrag.begin(at: p, zone: hit?.zone)
        edgeDragDisplay = hit?.display
    }

    func edgeDragMoved(_ p: CGPoint) {
        if let z = edgeDrag.drag(to: p) { edgeOpen(z) }
    }

    func edgeSwipe(_ e: NSEvent) {
        guard e.hasPreciseScrollingDeltas else { return }
        if e.phase.contains(.began) {
            let p = NSEvent.mouseLocation
            let hit = edgeZone(p)
            edgeDrag.begin(at: p, zone: hit?.zone)
            edgeDragDisplay = hit?.display
        }
        if e.phase.contains(.changed) {
            let dx = EdgeDrag.fingerDelta(scrollingDeltaX: e.scrollingDeltaX, invertedFromDevice: e.isDirectionInvertedFromDevice)
            let dy = EdgeDrag.fingerDelta(scrollingDeltaX: e.scrollingDeltaY, invertedFromDevice: e.isDirectionInvertedFromDevice)
            if let z = edgeDrag.swipe(fingerDX: dx, fingerDY: dy) { edgeOpen(z) }
        }
        if e.phase.contains(.ended) || e.phase.contains(.cancelled) { edgeDrag.end() }
    }

    func edgeOpen(_ z: EdgeDrag.Zone) {
        let d: Drawer = z == .session ? .session : .sidebar
        Log.shell.debug("edge drag opens \(d.rawValue, privacy: .public)")
        guard !openDrawers.contains(d) else { return }
        open(d, display: edgeDragDisplay)
    }

    // MARK: Hover reveals (Caelestia Interactions.qml)

    static func drawer(for t: HoverReveal.Target) -> Drawer {
        switch t {
        case .dashboard: return .dashboard
        case .utilities: return .utilities
        case .osd: return .osd
        }
    }

    static func target(for d: Drawer) -> HoverReveal.Target? {
        switch d {
        case .dashboard: return .dashboard
        case .utilities: return .utilities
        case .osd: return .osd
        default: return nil
        }
    }

    func hoverSizes(_ layout: DisplayLayout, reveal: Double) -> HoverReveal.Sizes {
        let body = OSDModel.maxBodySize
        return HoverReveal.Sizes(
            dashboard: dashboardFit(layout: layout, reveal: reveal).size,
            utilities: utilitiesSize(layout: layout, reveal: reveal),
            osd: CGSize(width: body.width, height: body.height + 2 * theme.frameRounding))
    }

    /// Whether hovering may open `t` now: never over a drawer the user opened on purpose.
    private func hoverMayOpen(_ t: HoverReveal.Target) -> Bool {
        let d = Self.drawer(for: t)
        guard isModuleOn(d), !openDrawers.contains(d), !openDrawers.contains(.session) else { return false }
        switch t {
        case .dashboard: return !openDrawers.contains(.launcher) && !openDrawers.contains(.wallpaper)
        case .utilities: return !openDrawers.contains(.sidebar) && !openDrawers.contains(.launcher)
        case .osd: return true
        }
    }

    /// One pointer position: closes hover-opened drawers the pointer left, and opens the drawer
    /// whose closed zone it has rested in for `HoverReveal.dwell`.
    func hoverReveal(_ p: CGPoint, at now: TimeInterval) {
        guard isRunning else { return }
        lastHoverPointer = p
        let here = layouts.first { $0.value.area.insetBy(dx: -2, dy: -2).contains(p) }
        let r = theme.frameRounding
        let sizes = here.map { hoverSizes($0.value, reveal: bars[$0.key]?.reveal.target ?? 0) }

        for d in hoverOpened {
            guard let t = Self.target(for: d) else { continue }
            var inside = false
            if let here, let sizes, launcherDisplay == here.key || d == .osd {
                inside = HoverReveal.contains(p, target: t, layout: here.value, barReveal: bars[here.key]?.reveal.target ?? 0,
                                              sizes: sizes, rounding: r, open: true)
            }
            if inside { continue }
            hoverOpened.remove(d)
            if d == .osd { pokeOSD() } else { close(d) }
        }

        guard let here, let sizes else { hoverPending = nil; return }
        let reveal = bars[here.key]?.reveal.target ?? 0
        let target = HoverReveal.Target.allCases.first { t in
            hoverMayOpen(t) && HoverReveal.contains(p, target: t, layout: here.value, barReveal: reveal, sizes: sizes, rounding: r, open: false)
        }
        guard let target else { hoverPending = nil; return }
        if let pending = hoverPending, pending.target == target, pending.display == here.key {
            guard now - pending.since >= HoverReveal.dwell else { return }
            hoverPending = nil
            let d = Self.drawer(for: target)
            Log.shell.debug("hover reveal \(d.rawValue, privacy: .public)")
            open(d, display: here.key)
            if openDrawers.contains(d) { hoverOpened.insert(d) }
        } else {
            hoverPending = (target, here.key, now)
            // The pointer may rest there without moving again.
            DispatchQueue.main.asyncAfter(deadline: .now() + HoverReveal.dwell + 0.01) { [weak self] in
                guard let self, let p = self.lastHoverPointer, self.hoverPending != nil else { return }
                self.hoverReveal(p, at: ProcessInfo.processInfo.systemUptime)
            }
        }
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

    /// Shows an auto-hidden bar and holds it (a popout opened without hovering the bar).
    func revealBar(_ id: String) {
        guard var vis = visibility[id], !vis.isShown else { return }
        vis.set(shown: true)
        vis.pinned = true
        visibility[id] = vis
        applyVisibility(id, vis)
    }

    private func applyVisibility(_ id: String, _ vis: BarVisibility) {
        guard let bar = bars[id] else { return }
        let shown = vis.isShown
        if theme.liquidSurface {
            // Caelestia BarWrapper: both ways on expressiveDefaultSpatial (500 ms × scale); the
            // swing past 1 swells the band a little, past 0 it is clamped.
            bar.setReveal(shown ? 1 : 0, animated: true, curve: .expressiveDefaultSpatial, ms: CaelestiaTokens.Duration.defaultSpatial, theme: theme, token: true)
        } else if shown {
            bar.setReveal(1, animated: true, curve: .expressiveDefaultSpatial, ms: 400, theme: theme, liquid: true)
        } else {
            bar.setReveal(0, animated: true, curve: .emphasizedAccel, ms: 250, theme: theme)
        }
        if !vis.persistent { host?.shellBarReservation(display: id, reserved: shown) }
    }

    // MARK: Drawers

    public func isOpen(_ d: Drawer) -> Bool { openDrawers.contains(d) }

    /// Whether the Settings switch for the module behind `d` is on (`[shell]`).
    public func isModuleOn(_ d: Drawer) -> Bool {
        let m = state.config.shell
        switch d {
        case .launcher: return m.isOn("launcher")
        case .dashboard: return m.isOn("dashboard")
        case .sidebar, .utilities: return m.isOn("sidebar")
        case .session: return m.isOn("session")
        case .osd: return m.isOn("osd")
        case .wallpaper: return m.isOn("wallpaperPicker")
        case .clipboard: return m.isOn("launcher")
        case .store: return true
        }
    }

    /// Closes every open drawer whose module was just switched off.
    func closeDisabledDrawers() {
        for d in openDrawers where !isModuleOn(d) {
            if d == .osd { hideOSD(animated: true) } else { close(d) }
        }
    }

    public func toggle(_ d: Drawer, display: String? = nil) {
        if openDrawers.contains(d) { close(d) } else { open(d, display: display) }
    }

    public func open(_ d: Drawer, display: String? = nil) {
        guard isRunning, isModuleOn(d) else { return }
        let id = display ?? pointerDisplayID() ?? state.displays.first?.id
        guard let id, let layout = layouts[id] else { return }
        let reveal = bars[id]?.reveal.target ?? 0
        // The recorder card lists the capture folder as it is now (sizes are measured on open).
        if d == .utilities || d == .sidebar { refreshRecordings() }
        switch d {
        case .clipboard:
            if openDrawers.contains(.session) { close(.session) }
            if openDrawers.contains(.launcher) { close(.launcher) }
            closeTransient()
            let panel = clipboardPanel ?? makeDrawerPanel(ClipboardDrawerView(session: clipboard, fillet: theme.frameRounding), name: "clipboard", key: true)
            clipboardPanel = panel
            let body = ClipboardSession.bodySize
            let size = CGSize(width: min(body.width + 2 * theme.frameRounding, layout.area.width), height: body.height)
            panel.setFrame(DisplayLayout.withRoom(layout.drawerFrame(size: size, edge: .bottom, barReveal: reveal), edge: .bottom,
                                                  room: theme.overshootRoom(depth: body.height)), display: false)
            clipboard.prepare()
            clipboard.onClose = { [weak self] in self?.close(.clipboard) }
            panel.onKeyBeforeField = { [weak self] event in
                MainActor.assumeIsolated { self?.clipboard.key(event) ?? false }
            }
            present(panel)
            clipboard.shown = true
        case .launcher:
            if openDrawers.contains(.session) { close(.session) }
            if openDrawers.contains(.clipboard) { close(.clipboard) }
            closeTransient()
            let panel = launcherPanel ?? makeDrawerPanel(LauncherView(model: launcher, fillet: theme.frameRounding), name: "launcher", key: true)
            launcherPanel = panel
            // Caelestia: the carousel may use the screen minus 4 × rounding and the bar on both sides.
            let room = layout.area.width - 4 * theme.frameRounding - 2 * max(layout.thickness, theme.barWidth)
            launcher.carouselRoom = room
            let body = LauncherModel.maxBodySize(carouselRoom: room)
            let size = CGSize(width: min(body.width + 2 * theme.frameRounding, layout.area.width), height: body.height)
            panel.setFrame(DisplayLayout.withRoom(layout.drawerFrame(size: size, edge: .bottom, barReveal: reveal), edge: .bottom,
                                                  room: theme.overshootRoom(depth: body.height)), display: false)
            launcher.reset()
            launcher.apps = state.apps
            launcher.options = LauncherCommand.options(state.config.appearance,
                                                       addonSchemes: AddonStore().schemes().map { ($0.theme, $0.title) })
            launcher.currentWallpaper = displayedWallpaper
            launcher.wallpapers = state.wallpapers
            carouselPreviewing = false
            wallpaper.scan(folder: state.config.appearance.wallpaperFolder) { [weak self] result in
                guard let self else { return }
                self.state.wallpapers = result.urls
                self.launcher.wallpapers = result.urls
            }
            present(panel)
            launcher.shown = true
        case .session:
            if openDrawers.contains(.launcher) { close(.launcher) }
            closeTransient()
            let panel = sessionPanel ?? makeDrawerPanel(SessionView(model: session, fillet: theme.frameRounding), name: "session", key: true)
            sessionPanel = panel
            let body = SessionModel.bodySize
            let size = CGSize(width: body.width, height: body.height + 2 * theme.frameRounding)
            panel.setFrame(DisplayLayout.withRoom(layout.drawerFrame(size: size, edge: .right, barReveal: reveal), edge: .right,
                                                  room: theme.overshootRoom(depth: body.width)), display: false)
            panel.shove = 0
            session.reset()
            session.setImage(path: state.config.appearance.sessionImage)
            hideOSD(animated: true)
            showSessionDim(id)
            session.shown = true
            shoveBySidebar(panel)
            present(panel)
        case .osd:
            showOSD(display: id)
            return
        case .dashboard: openDashboard(id, layout: layout, reveal: reveal)
        case .sidebar:
            // The sidebar carries the utilities at its bottom (upstream shows both together).
            if utilities.shown { closeUtilities() }
            openSidebar(id, layout: layout, reveal: reveal)
            openDrawers.insert(.utilities)
            launcherDisplay = id
            openDrawers.insert(.sidebar)
            return
        case .utilities:
            guard !openDrawers.contains(.sidebar) else { return }
            openUtilities(id, layout: layout, reveal: reveal)
        case .wallpaper: openWallpaper(id, layout: layout, reveal: reveal)
        case .store: openStore(id, layout: layout, reveal: reveal)
        }
        launcherDisplay = id
        openDrawers.insert(d)
    }

    public func close(_ d: Drawer) {
        switch d {
        case .launcher:
            guard openDrawers.contains(.launcher) else { return }
            launcher.shown = false
            // Closed without a pick: the desktop goes back (Caelestia Wallpapers.stopPreview).
            if carouselPreviewing {
                carouselPreviewing = false
                wallpaperPreview.revert(crossfade: wallpaperCrossfade)
            }
            host?.shellKeyDrawerClosed(launched: false)
            dismiss(launcherPanel)
        case .clipboard:
            guard openDrawers.contains(.clipboard) else { return }
            clipboard.shown = false
            host?.shellKeyDrawerClosed(launched: false)
            dismiss(clipboardPanel)
        case .session:
            guard openDrawers.contains(.session) else { return }
            session.shown = false
            host?.shellKeyDrawerClosed(launched: false)
            session.disarm()
            dismiss(sessionPanel)
            dimPanel?.fadeOut(duration: theme.liquidSurface ? theme.tokenSeconds(CaelestiaTokens.Duration.defaultEffects) : theme.drawerCloseSeconds)
        case .osd:
            hideOSD(animated: true)
        case .dashboard: closeDashboard()
        case .sidebar: closeSidebar()
        case .utilities:
            if sidebar.shown {
                closeSidebar()
                openDrawers.remove(.sidebar)
            } else {
                closeUtilities()
            }
        case .wallpaper: closeWallpaper()
        case .store: closeStore()
        }
        openDrawers.remove(d)
        hoverOpened.remove(d)
    }

    public func closeAll() {
        for d in openDrawers { close(d) }
    }

    /// The shell theme for `state`; drawers go on the liquid surface when Metal is available
    /// (`SKYROSE_LIQUID=0` turns it off for debugging).
    static func makeTheme(_ state: ShellState) -> ShellTheme {
        var t = ShellTheme(scheme: state.scheme, config: state.config, reduceMotion: state.reduceMotion)
        t.liquidSurface = ProcessInfo.processInfo.environment["SKYROSE_LIQUID"] != "0" && LiquidSurface.isSupported
        return t
    }

    /// Which edge each drawer slides from and its jelly (Caelestia ContentWindow.qml PanelBg).
    static func blobStyle(_ name: String) -> (edge: ShellEdge, deform: Double, ms: (open: Double, close: Double)) {
        let a = CaelestiaTokens.DeformAmount.self
        let t = CaelestiaTokens.DrawerMs.self
        switch name {
        case "launcher", "clipboard": return (.bottom, a.launcher, t.launcher)
        case "wallpaper", "store": return (.bottom, a.launcher, t.launcher)
        case "dashboard": return (.top, a.dashboard, t.dashboard)
        case "session": return (.right, a.session, t.session)
        case "osd": return (.right, a.osd, t.osd)
        case "sidebar": return (.right, a.sidebar, t.sidebar)
        case "utilities": return (.bottom, a.utilities, t.utilities)
        case "popout": return (.left, a.popoutOpen, t.other)
        case "popups": return (.top, a.notifications, t.notifications)
        default: return (.bottom, a.notifications, t.other)
        }
    }

    /// Moves `panel` clear of the open sidebar on its display, or back when the sidebar closes.
    /// The surface morphs the drawer to the new place, so it looks shoved.
    func shoveBySidebar(_ panel: ShellPanel) {
        let target = sidebar.shown && sidebarPanel?.screen == panel.screen ? sidebar.width : 0
        guard target != panel.shove else { return }
        panel.setFrame(panel.frame.offsetBy(dx: panel.shove - target, dy: 0), display: false)
        panel.shove = target
        surface(for: panel)?.bodyChanged(panel)
    }

    func shoveRightDrawers() {
        if session.shown, let p = sessionPanel { shoveBySidebar(p) }
        if osd.shown, let p = osdPanel { shoveBySidebar(p) }
    }

    func makeDrawerPanel<V: View>(_ view: V, name: String, key: Bool, clickThrough: Bool = false) -> ShellPanel {
        let panel = ShellPanel(frame: .zero, level: ShellLevel.drawer, clickThrough: clickThrough, name: name)
        panel.acceptsKey = key
        let style = Self.blobStyle(name)
        panel.blobEdge = style.edge
        panel.blobDeformAmount = style.deform
        panel.blobMs = style.ms
        // Reports made before the host has its size (the first layout runs at .zero) are noise.
        weak var weakHost: NSView?
        let report: @MainActor (CGRect) -> Void = { [weak panel] r in
            guard let h = weakHost, h.bounds.width > 0, h.bounds.height > 0 else { return }
            panel?.blobBody = r
        }
        let host = ShellHostingView(rootView: AnyView(view.environment(\.shellTheme, theme).environment(\.blobReporter, report)))
        weakHost = host
        let container = DrawerContentView(frame: .zero)
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container
        host.frame = container.bounds
        panel.onBlobBodyChange = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.surface(for: panel)?.bodyChanged(panel)
        }
        return panel
    }

    /// The liquid surface of the display `panel` is on (nil: frosted panels, the old path).
    func surface(for panel: ShellPanel) -> LiquidSurface? {
        guard theme.liquidSurface else { return nil }
        let c = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let f = frames.values.first(where: { $0.surface?.contains(panel) == true }) { return f.surface }
        return frames.values.first { $0.layout.area.contains(c) }?.surface ?? frames.values.first?.surface
    }

    /// Hides a drawer panel: back into its edge on the liquid surface, else the panel fade.
    func retract(_ panel: ShellPanel, duration: Double, completion: (() -> Void)? = nil) {
        if let s = surface(for: panel), s.contains(panel) {
            s.close(panel, seconds: theme.tokenSeconds(panel.blobMs.close), completion: completion)
        } else {
            panel.fadeOut(duration: duration, completion: completion)
        }
    }

    private func rebuildDrawers() {
        closeAll()
        for f in frames.values { f.surface?.removeAll() }
        for p in [launcherPanel, clipboardPanel, sessionPanel, osdPanel, popupPanel, helperPanel] + partTwoPanels { p?.orderOut(nil); p?.close() }
        launcherPanel = nil; clipboardPanel = nil; sessionPanel = nil; osdPanel = nil; popupPanel = nil; helperPanel = nil
        dropPartTwoPanels()
    }

    /// Shows a drawer panel: SwiftUI evaluates the view in its hidden state first (a freshly
    /// created panel otherwise rendered straight at "shown" and appeared without its slide), then
    /// the panel is ordered in and fades in while the caller's `shown = true` slides the content.
    func present(_ panel: ShellPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        if let s = surface(for: panel) {
            // The panel may have moved displays: leave the old surface first.
            for f in frames.values where f.surface !== s { f.surface?.remove(panel) }
            s.open(panel, edge: panel.blobEdge, deformAmount: panel.blobDeformAmount, seconds: theme.tokenSeconds(panel.blobMs.open))
            s.bodyChanged(panel)
        } else {
            panel.fadeIn(duration: theme.panelFadeInSeconds)
        }
    }

    /// Hides a drawer panel: it slides (SwiftUI, `shown = false` set by the caller) and fades out
    /// together, then is ordered out, unless it was re-opened meanwhile.
    func dismiss(_ panel: ShellPanel?) {
        guard let panel else { return }
        if panel.isKeyWindow { panel.resignKey() }
        let reopened: () -> Bool = { [weak self] in
            guard let self else { return false }
            if panel === self.launcherPanel, self.launcher.shown { return true }
            if panel === self.clipboardPanel, self.clipboard.shown { return true }
            if panel === self.storePanel, self.store.shown { return true }
            if panel === self.sessionPanel, self.session.shown { return true }
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            if !reopened() { self.retract(panel, duration: self.theme.drawerCloseSeconds) }
        }
    }

    private func activate(_ item: LauncherItem) {
        switch item {
        case .app(let app):
            close(.launcher)
            host?.shellKeyDrawerClosed(launched: true)
            counts.bump(app.id)
            if let i = state.apps.firstIndex(where: { $0.id == app.id }) { state.apps[i].launchCount += 1 }
            // SkyRose is already running (it is this process) and has no window: its entry opens Settings.
            let url = app.bundleID == AppIndex.skyRoseBundleID ? (AppIndex.settingsAppURL() ?? app.url) : app.url
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
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
            case .autocomplete(let name):
                launcher.query = ">\(name) "
            case .openSettings:
                close(.launcher)
                guard let url = AppIndex.settingsAppURL() else {
                    toast(.error, title: "SkyRose Settings not found", message: "Put SkyRose Settings.app next to SkyRose.app")
                    return
                }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            case .fill(let text):
                launcher.query = text
            case .setConfig(let values):
                close(.launcher)
                do {
                    try ConfigAPI().set(values.map { ($0.path, $0.value) })
                } catch {
                    toast(.error, title: c.name, message: error.localizedDescription)
                }
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
        let own = AppIndex.ownApps()
        let extra = appWatcher.spotlightURLs
        DispatchQueue.global(qos: .utility).async {
            let apps = AppIndex.scan(own: own, extra: extra, counts: counts)
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
        guard isRunning, state.config.shell.isOn("osd"), !openDrawers.contains(.session) else { return }
        let id = display ?? pointerDisplayID() ?? state.displays.first?.id
        guard let id, let layout = layouts[id] else { return }
        let panel = osdPanel ?? makeDrawerPanel(OSDView(model: osd, fillet: theme.frameRounding), name: "osd", key: false)
        panel.level = ShellLevel.osd
        osdPanel = panel
        osd.brightnessAvailable = brightness.state.unavailableReason == nil
        let body = OSDModel.maxBodySize
        let size = CGSize(width: body.width, height: body.height + 2 * theme.frameRounding)
        let reveal = bars[id]?.reveal.target ?? 0
        panel.setFrame(DisplayLayout.withRoom(layout.drawerFrame(size: size, edge: .right, barReveal: reveal), edge: .right,
                                              room: theme.overshootRoom(depth: body.width)), display: false)
        panel.shove = 0
        let wasShown = panel.isVisible && osd.shown
        osd.shown = true
        shoveBySidebar(panel)
        if !wasShown { present(panel) }
        openDrawers.insert(.osd)
        pokeOSD()
    }

    private func pokeOSD() {
        osdTimer.changed(at: ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + OSDModel.hideDelay + 0.02) { [weak self] in
            guard let self else { return }
            let hovered = self.osd.hovered || self.hoverOpened.contains(.osd)
            if self.osdTimer.shouldHide(at: ProcessInfo.processInfo.systemUptime, hovered: hovered) {
                self.hideOSD(animated: true)
            } else if self.osd.shown, hovered {
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
            if self?.osd.shown == false { self?.retract(panel, duration: duration) }
        }
    }

    // MARK: Toasts

    /// A toast or notification popup (`popup` only tells them apart in the log). Both land in the
    /// top-right drawer, which grows out of the frame on the liquid surface.
    @discardableResult
    public func toast(_ kind: ToastKind, title: String, message: String, icon: String = "", record: Bool = true, imagePath: String = "", popup: Bool = false) -> UUID {
        let model = popups
        let id = model.queue.add(Toast(kind: kind, title: title, message: message, icon: icon, createdAt: ProcessInfo.processInfo.systemUptime, imagePath: imagePath))
        if record { recordNotification(kind: kind, title: title, message: message, icon: icon) }
        guard isRunning, state.config.shell.isOn("notifications"), !state.doNotDisturb else {
            if state.doNotDisturb { model.queue.dismiss(id) }
            return id
        }
        let displayID = pointerDisplayID() ?? state.displays.first?.id
        if let displayID, let layout = layouts[displayID] {
            let panel = popupPanel ?? makeDrawerPanel(ToastsView(model: model), name: "popups", key: false, clickThrough: true)
            panel.level = ShellLevel.osd
            popupPanel = panel
            let inner = layout.inner(barReveal: bars[displayID]?.reveal.target ?? 0)
            let w = ToastsView.width
            let h = min(520, inner.height)
            let frame = CGRect(x: inner.maxX - w, y: inner.maxY - h, width: w, height: h)
            if panel.frame != frame { panel.setFrame(frame, display: false) }
            // Already out: the new card just grows the body (the surface morphs it).
            let open = surface(for: panel).map { $0.isShown(panel) } ?? panel.isVisible
            if !open { present(panel) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + model.queue.timeout + 0.05) { [weak self] in
            guard let self else { return }
            model.queue.expire(at: ProcessInfo.processInfo.systemUptime)
            guard model.queue.isEmpty, let p = self.popupPanel else { return }
            self.retract(p, duration: self.theme.drawerCloseSeconds)
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
            notify(title: "Test notification", body: "Sent from the keybind. Notifications from SkyRose appear here.", app: "skyrose-shell", icon: "info")
        case .clipboardOpen: toggle(.clipboard)
        case .clipboardDelete:
            // Arch opens a delete picker: closed, this shows the list, and it never removes unseen.
            if openDrawers.contains(.clipboard) { clipboard.deleteSelected() } else { open(.clipboard) }
        case .clipboardTypeLatest: clipboard.pasteNewest()
        case .menuBarPeek:
            SystemMenuBar.peek()
        case .shellKill: stop()
        case .shellRestart: restart()
        case .recordScreen: toggleRecording()
        case .captureRegion: takeScreenshot(.region)
        case .captureFull: takeScreenshot(.full)
        case .captureFreeze: takeScreenshot(.freeze)
        case .pickerColor: pickColor()
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
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            guard let self else { return }
            if self.openDrawers.contains(.launcher) { self.close(.launcher) }
            if self.openDrawers.contains(.clipboard) { self.close(.clipboard) }
            if self.openDrawers.contains(.store) { self.close(.store) }
            if self.openDrawers.contains(.session) { self.close(.session) }
            self.closeTransient(includingSidebar: true)
            if e.type == .leftMouseDown { self.edgeDragBegin(NSEvent.mouseLocation) }
        }) { monitors.append(m) }
        // Right-edge drags and two-finger swipes (watched only: the frame stays click-through).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { [weak self] e in
            guard let self else { return }
            if e.type == .leftMouseUp { self.edgeDrag.end() } else { self.edgeDragMoved(NSEvent.mouseLocation) }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            self?.edgeSwipe(e)
        }) { monitors.append(m) }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reassertSoon() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reassertSoon()
                self?.liveWallpaper.screensChanged()
            }
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
        state.status.wifiPercent = s.rssi.map(NetworkState.percent(fromRSSI:)) ?? (s.wifiConnected ? 100 : 0)
        state.status.wifiFrequencyMHz = s.frequencyMHz
        state.status.ethernetConnected = s.ethernetConnected
    }

    private func applyBattery(_ s: BatteryState) {
        liveWallpaper.update(battery: s)
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
        media.stop(); bluetooth.stop(); clamshell.stop()
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

    /// `liquid`: the reveal springs (overshoots ~8 %, the band swells and settles) unless Reduce
    /// Motion is on, where the Bézier `curve` is kept.
    func setReveal(_ value: Double, animated: Bool, curve: ShellCurve = .standard, ms: Double = 0, theme: ShellTheme? = nil, liquid: Bool = false,
                   token: Bool = false) {
        if animated, let theme, token {
            // Reduce Motion: the short standard fade instead of the overshooting curve.
            if theme.reduceMotion {
                reveal.animate(to: value, duration: theme.seconds(ms), curve: .standard)
            } else {
                reveal.animate(to: value, duration: theme.tokenSeconds(ms), curve: curve)
            }
        } else if animated, let theme, liquid, let s = theme.barRevealSpring {
            reveal.animate(to: value, spring: s)
        } else if animated, let theme, theme.seconds(ms) > 0 {
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
