import AppKit
import CaelestiaCore
import CaelestiaServices
import SwiftUI

/// Shell part 2: dashboard, sidebar (notifications + utilities), bar popouts, wallpaper picker and
/// dynamic colours.
extension ShellController {
    var partTwoPanels: [ShellPanel?] { [dashboardPanel, sidebarPanel, utilitiesPanel, popoutPanel, wallpaperPanel, dimPanel] }

    func dropPartTwoPanels() {
        dashboardPanel = nil; sidebarPanel = nil; utilitiesPanel = nil; popoutPanel = nil; wallpaperPanel = nil; dimPanel = nil
        dashboard.shown = false; sidebar.shown = false; utilities.shown = false; popout.shown = false; wallpaperPicker.shown = false
        hoverOpened.removeAll()
        hoverPending = nil
        popoutKind = nil
        stopStatsTimer()
        media.isObserved = false
    }

    // MARK: Wiring

    func wirePartTwo() {
        guard !partTwoWired else { return }
        partTwoWired = true
        dashboard.tab = DashboardTab(config: state.config.dashboard.defaultTab)
        dashboard.onPlayPause = { [weak self] in self?.media.playPause() }
        dashboard.onNext = { [weak self] in self?.media.next() }
        dashboard.onPrevious = { [weak self] in self?.media.previous() }
        dashboard.onSeek = { [weak self] time in
            self?.media.seek(to: time)
            // Players report the new position late, and the lyric list should follow the click now.
            self?.dashboard.lyricClock.position = time
            self?.dashboard.lyricClock.at = Date()
        }

        sidebar.onDismiss = { [weak self] id in self?.dismissNotification(id) }
        sidebar.onClear = { [weak self] in self?.clearNotifications() }
        sidebar.onToggle = { [weak self] id in self?.quickToggle(id) }
        sidebar.onVolume = { [weak self] v in self?.audio.setVolume(v) }
        sidebar.onBrightness = { [weak self] v in self?.brightness.set(v) }
        sidebar.onKeepAwake = { [weak self] on in self?.keepAwake.set(on: on) }
        sidebar.onKeepAwakeFor = { [weak self] d in self?.keepAwake.set(on: true, duration: d) }
        sidebar.onClamshell = { [weak self] on in self?.lidSleep.setClamshell(on) }
        sidebar.onWallpaper = { [weak self] in self?.open(.wallpaper) }
        sidebar.onRecord = { [weak self] in self?.toggleRecording() }
        sidebar.onRevealRecording = { url in NSWorkspace.shared.activateFileViewerSelecting([url]) }
        sidebar.onTrashRecording = { [weak self] url in
            NSWorkspace.shared.recycle([url]) { _, _ in DispatchQueue.main.async { self?.refreshRecordings() } }
        }

        popout.onSetOutput = { [weak self] id in
            self?.audio.setOutputDevice(id)
            self?.popout.devices = self?.audio.outputDevices() ?? []
        }
        popout.onVolume = { [weak self] v in self?.audio.setVolume(v) }
        popout.onMute = { [weak self] in self?.audio.toggleMuted() }
        popout.onMicMute = { [weak self] in self?.audio.toggleMicMuted() }
        popout.onWifi = { [weak self] on in self?.setWifi(on) }
        popout.onScan = { [weak self] in self?.scanNetworks() }
        popout.onOpenSettings = { [weak self] kind in self?.openSettings(for: kind) }

        wallpaperPicker.onPick = { [weak self] url in self?.transitionWallpaper(url) }
        wallpaperPicker.onRandom = { [weak self] in self?.randomWallpaper() }
        wallpaperPicker.onNeedThumb = { [weak self] url in
            guard let self, self.wallpaperPicker.thumbs[url] == nil else { return }
            self.wallpaper.thumbnail(for: url) { img in if let img { self.wallpaperPicker.thumbs[url] = img } }
        }
    }

    func startPartTwoServices() {
        clipboard.start()
        media.onChange = { [weak self] m in self?.applyMedia(m) }
        media.start()
        keepAwake.onChange = { [weak self] on in
            guard let self else { return }
            self.state.keepAwake = on
            self.state.keepAwakeUntil = self.keepAwake.until
            self.state.keepAwakeDuration = self.keepAwake.duration
            // A keep-awake also survives closing the lid (SleepDisabled 1 while it runs).
            if self.state.clamshell.hasLid { self.lidSleep.setKeepAwake(on) }
        }
        bluetooth.onChange = { [weak self] b in self?.applyBluetooth(b) }
        bluetooth.start()
        clamshell.onChange = { [weak self] f in self?.state.clamshell = f }
        clamshell.keepAwakeWhenClosed = state.config.clamshell.keepAwake
        clamshell.start()
        state.clamshell = clamshell.facts
        lidSleep.onChange = { [weak self] in
            guard let self else { return }
            self.state.lidSleep = self.lidSleep.status
            self.clamshell.refresh()
        }
        if clamshell.facts.hasLid {
            lidSleep.start()
            state.lidSleep = lidSleep.status
            clamshell.refresh()
        }
        weatherController.configure(state.config.weather)
        state.systemDarkMode = Self.readDarkMode()
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.state.systemDarkMode = Self.readDarkMode() } })
    }

    static func readDarkMode() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    private func applyMedia(_ m: MediaState) {
        var info = MediaInfo()
        info.available = m.available
        info.title = m.title; info.artist = m.artist; info.album = m.album
        info.isPlaying = m.isPlaying; info.position = m.position; info.duration = m.duration
        info.artworkPath = m.artworkURL; info.player = m.player
        if info != state.media { state.media = info }
        mediaStage.sync(media: info, dashboard: dashboard, config: state.config.dashboard)
    }

    private func applyBluetooth(_ b: BluetoothState) {
        state.status.bluetoothAvailable = b.unavailableReason == nil
        state.status.bluetoothOn = b.poweredOn
        state.status.bluetoothDevices = b.connectedDevices
    }

    // MARK: Drawers

    /// Closes the part-2 drawers that a click elsewhere or another drawer should dismiss.
    func closeTransient(includingSidebar: Bool = false) {
        if openDrawers.contains(.dashboard) { close(.dashboard) }
        if openDrawers.contains(.wallpaper) { close(.wallpaper) }
        if popoutKind != nil { closePopout() }
        if includingSidebar, openDrawers.contains(.sidebar) { close(.sidebar) }
    }

    func openDashboard(_ id: String, layout: DisplayLayout, reveal: Double) {
        if openDrawers.contains(.launcher) { close(.launcher) }
        if openDrawers.contains(.session) { close(.session) }
        if popoutKind != nil { closePopout() }
        let fillet = theme.frameRounding
        let panel = dashboardPanel ?? makeDrawerPanel(DashboardView(model: dashboard, state: state, fillet: fillet), name: "dashboard", key: false)
        dashboardPanel = panel
        let (fit, clearance, size) = dashboardFit(layout: layout, reveal: reveal)
        dashboard.scale = fit.scale
        dashboard.topInset = clearance
        dashboard.now = Date()
        dashboard.monthOffset = 0
        dashboard.tab = DashboardTab(config: state.config.dashboard.defaultTab)
        panel.setFrame(DisplayLayout.withRoom(layout.drawerFrame(size: size, edge: .top, barReveal: reveal), edge: .top,
                                              room: theme.overshootRoom(depth: size.height)), display: false)
        hideOSD(animated: true)
        present(panel)
        dashboard.shown = true
        media.isObserved = true
        mediaStage.sync(media: state.media, dashboard: dashboard, config: state.config.dashboard)
        startStatsTimer()
        weatherController.refreshIfStale()
    }

    /// The dashboard's fit on `layout`: scale, notch clearance and panel size (fillets included).
    func dashboardFit(layout: DisplayLayout, reveal: Double) -> (fit: (scale: Double, body: CGSize), clearance: Double, size: CGSize) {
        let fillet = theme.frameRounding
        let inner = layout.inner(barReveal: reveal)
        // A notch under the drawer: the drawer still grows out of the top band and covers the
        // band's dip, but its content starts below it.
        let clearance = layout.topClearance(minX: inner.minX, maxX: inner.maxX)
        var room = inner
        room.size.height -= clearance
        let fit = ShellSizing.dashboard(inner: room, fillet: fillet)
        return (fit, clearance, CGSize(width: fit.body.width + 2 * fillet, height: fit.body.height + clearance))
    }

    // MARK: Session dim

    /// How dark the scrim behind the session menu is: the capture's wallpaper drops to ~55 %
    /// brightness while the menu is open (session_open frames 1 → 9).
    static let sessionDimAlpha: Double = 0.45

    /// Fades a click-through black scrim over the whole display under the session drawer.
    func showSessionDim(_ id: String) {
        guard let layout = layouts[id] else { return }
        let centre = CGPoint(x: layout.area.midX, y: layout.area.midY)
        let frame = NSScreen.screens.first { $0.frame.contains(centre) }?.frame ?? layout.area
        let panel = dimPanel ?? {
            // Under the frame: drawer backgrounds live in the frame's liquid surface, so a scrim above
            // it would dim the session menu's own background.
            let level = theme.liquidSurface ? NSWindow.Level(rawValue: ShellLevel.frame.rawValue - 1) : NSWindow.Level(rawValue: ShellLevel.drawer.rawValue - 1)
            let p = ShellPanel(frame: frame, level: level, clickThrough: true, name: "session-dim")
            let v = NSView(frame: CGRect(origin: .zero, size: frame.size))
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.sessionDimAlpha).cgColor
            v.autoresizingMask = [.width, .height]
            p.contentView = v
            return p
        }()
        dimPanel = panel
        panel.setFrame(frame, display: false)
        // Opacity: an Effects token (slowEffects, 240 ms at 0.8) on the liquid surface.
        panel.fadeIn(duration: theme.liquidSurface ? theme.tokenSeconds(CaelestiaTokens.Duration.slowEffects) : theme.drawerOpenSeconds)
    }

    // MARK: Utilities (bottom-right corner)

    /// The standalone utilities drawer's size on `layout` (fillets included): the sidebar's
    /// column width, the controls' height. Cached per width (the probe lays out SwiftUI).
    func utilitiesSize(layout: DisplayLayout, reveal: Double) -> CGSize {
        let width = ShellSizing.sidebarWidth(inner: layout.inner(barReveal: reveal))
        // Everything that changes the controls' height: the recorder list and the lid line wrap.
        let lid = state.clamshell.hasLid ? Clamshell.summary(state.clamshell, lid: state.lidSleep) : ""
        let key = "\(width)|\(sidebar.brightnessAvailable)|\(min(3, state.recorder.recordings.count))|\(lid)"
        if let cached = utilitiesSizeCache[key] { return cached }
        let size = UtilitiesDrawerView.size(bodyWidth: width, fillet: theme.frameRounding, sidebar: sidebar, state: state, theme: theme)
        utilitiesSizeCache = [key: size]
        return size
    }

    func openUtilities(_ id: String, layout: DisplayLayout, reveal: Double) {
        let fillet = theme.frameRounding
        let panel = utilitiesPanel ?? makeDrawerPanel(UtilitiesDrawerView(model: utilities, sidebar: sidebar, state: state, fillet: fillet),
                                                      name: "utilities", key: false)
        utilitiesPanel = panel
        sidebar.brightnessAvailable = brightness.state.unavailableReason == nil
        let size = utilitiesSize(layout: layout, reveal: reveal)
        utilities.bodyHeight = size.height
        panel.setFrame(DisplayLayout.withRoom(layout.cornerDrawerFrame(size: size, barReveal: reveal), edge: .bottom,
                                              room: theme.overshootRoom(depth: size.height)), display: false)
        present(panel)
        utilities.shown = true
        launcherDisplay = id
    }

    func closeUtilities() {
        guard utilities.shown else { return }
        utilities.shown = false
        dismissAfter(utilitiesPanel) { [weak self] in self?.utilities.shown == false }
    }

    func closeDashboard() {
        guard dashboard.shown else { return }
        dashboard.shown = false
        media.isObserved = false
        mediaStage.stop()
        dashboard.bongoPaw = nil
        stopStatsTimer()
        dismissAfter(dashboardPanel) { [weak self] in self?.dashboard.shown == false }
    }

    func openSidebar(_ id: String, layout: DisplayLayout, reveal: Double) {
        let fillet = theme.frameRounding
        let panel = sidebarPanel ?? makeDrawerPanel(SidebarView(model: sidebar, state: state, fillet: fillet), name: "sidebar", key: false)
        sidebarPanel = panel
        let inner = layout.inner(barReveal: reveal)
        let width = ShellSizing.sidebarWidth(inner: inner)
        sidebar.width = width
        sidebar.brightnessAvailable = brightness.state.unavailableReason == nil
        // Keep clear of a cutout above the sidebar's column (none on current Macs).
        let clear = layout.topClearance(minX: inner.maxX - width, maxX: inner.maxX)
        var frame = layout.drawerFrame(size: CGSize(width: width, height: inner.height - clear), edge: .right, barReveal: reveal)
        frame.origin.y = inner.minY
        panel.setFrame(DisplayLayout.withRoom(frame, edge: .right, room: theme.overshootRoom(depth: width)), display: false)
        present(panel)
        sidebar.shown = true
        shoveRightDrawers()
        bluetooth.refresh()
    }

    func closeSidebar() {
        guard sidebar.shown else { return }
        sidebar.shown = false
        shoveRightDrawers()
        openDrawers.remove(.utilities)
        dismissAfter(sidebarPanel) { [weak self] in self?.sidebar.shown == false }
    }

    func openWallpaper(_ id: String, layout: DisplayLayout, reveal: Double) {
        if openDrawers.contains(.launcher) { close(.launcher) }
        if popoutKind != nil { closePopout() }
        let fillet = theme.frameRounding
        let inner = layout.inner(barReveal: reveal)
        let body = ShellSizing.wallpaperBody(inner: inner)
        let panel = wallpaperPanel ?? makeDrawerPanel(WallpaperPickerView(model: wallpaperPicker, fillet: fillet, bodySize: body), name: "wallpaper", key: false)
        wallpaperPanel = panel
        panel.setFrame(DisplayLayout.withRoom(layout.drawerFrame(size: CGSize(width: body.width + 2 * fillet, height: body.height), edge: .bottom, barReveal: reveal),
                                              edge: .bottom, room: theme.overshootRoom(depth: body.height)), display: false)
        wallpaperPicker.current = displayedWallpaper
        wallpaperPicker.loading = true
        wallpaper.scan(folder: state.config.appearance.wallpaperFolder) { [weak self] result in
            guard let self else { return }
            self.wallpaperPicker.items = result.urls
            self.wallpaperPicker.groups = result.groups
            self.wallpaperPicker.message = result.message
            self.wallpaperPicker.loading = false
            self.state.wallpapers = result.urls
        }
        present(panel)
        wallpaperPicker.shown = true
    }

    func closeWallpaper() {
        guard wallpaperPicker.shown else { return }
        wallpaperPicker.shown = false
        dismissAfter(wallpaperPanel) { [weak self] in self?.wallpaperPicker.shown == false }
    }

    private func dismissAfter(_ panel: ShellPanel?, stillClosed: @escaping () -> Bool) {
        guard let panel else { return }
        if panel.isKeyWindow { panel.resignKey() }
        let duration = theme.drawerCloseSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in if stillClosed() { self?.retract(panel, duration: duration) } }
    }

    // MARK: Popouts

    func statusIconClicked(_ icon: String, display: String, windowMidY: Double) {
        Log.shell.debug("status icon \(icon, privacy: .public) clicked at y=\(windowMidY, privacy: .public)")
        guard let kind = PopoutKind.forStatusIcon(icon), let bar = bars[display], let layout = layouts[display] else { return }
        if popoutKind == kind, popoutDisplay == display, !popoutByHover { closePopout(); return }
        let midY = bar.panel.frame.maxY - windowMidY
        openPopout(kind, display: display, layout: layout, anchorMidY: midY)
        popoutByHover = false
    }

    /// `shell drawers toggle popout.audio|network|bluetooth|battery`: toggles a bar popout without a click.
    /// Hovering a bar item (Caelestia bar popouts): opens its popout, or morphs the open one to
    /// it; leaving starts the close check. Drawers that own the screen (launcher, dashboard,
    /// session, wallpaper) are left alone.
    func barItemHovered(_ item: String?, display: String, windowMidY: Double) {
        guard let item else {
            if popoutByHover { scheduleHoverClose() }
            return
        }
        guard let kind = PopoutKind.forBarItem(item), let bar = bars[display], let layout = layouts[display] else { return }
        if popoutKind != nil, !popoutByHover { return }
        if [.launcher, .session, .dashboard, .wallpaper].contains(where: openDrawers.contains) { return }
        popoutLeaveTimer?.invalidate()
        popoutLeaveTimer = nil
        if popoutKind == kind, popoutDisplay == display { return }
        openPopout(kind, display: display, layout: layout, anchorMidY: bar.panel.frame.maxY - windowMidY)
        popoutByHover = true
    }

    /// Where a hover-opened popout may be without closing: the bar and the popout's body
    /// (screen space), with a little slack for the seam between them.
    func popoutHoverZone() -> [CGRect] {
        var zone: [CGRect] = []
        if let d = popoutDisplay, let bar = bars[d] { zone.append(bar.panel.frame.insetBy(dx: -4, dy: -4)) }
        if let panel = popoutPanel {
            if let body = panel.blobBody {
                let f = panel.frame
                zone.append(CGRect(x: f.minX + body.minX, y: f.maxY - body.maxY, width: body.width, height: body.height).insetBy(dx: -8, dy: -8))
            } else {
                zone.append(panel.frame)
            }
        }
        return zone
    }

    private func scheduleHoverClose() {
        guard popoutLeaveTimer == nil else { return }
        popoutLeaveTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.popoutByHover, self.popoutKind != nil else {
                    self.popoutLeaveTimer?.invalidate()
                    self.popoutLeaveTimer = nil
                    return
                }
                let p = NSEvent.mouseLocation
                if !self.popoutHoverZone().contains(where: { $0.contains(p) }) { self.closePopout() }
            }
        }
    }

    public func togglePopout(_ kind: PopoutKind, display: String? = nil) {
        if popoutKind == kind { closePopout(); return }
        guard let id = display ?? pointerDisplayID() ?? state.displays.first?.id, let layout = layouts[id] else { return }
        let bar = bars[id]?.panel.frame
        // Roughly where the item sits: the active window high up, the status icons near the bottom.
        let anchor = bar.map { $0.minY + $0.height * (kind == .activeWindow ? 0.7 : 0.2) } ?? layout.inner(barReveal: 1).midY
        openPopout(kind, display: id, layout: layout, anchorMidY: anchor)
        popoutByHover = false
    }

    public func openPopout(_ kind: PopoutKind, display: String, layout: DisplayLayout, anchorMidY: Double) {
        if openDrawers.contains(.launcher) { close(.launcher) }
        if openDrawers.contains(.session) { close(.session) }
        if openDrawers.contains(.dashboard) { close(.dashboard) }
        if openDrawers.contains(.wallpaper) { close(.wallpaper) }
        let fillet = theme.frameRounding
        let panel = popoutPanel ?? makeDrawerPanel(PopoutView(model: popout, state: state, fillet: fillet), name: "popout", key: false)
        popoutPanel = panel
        popout.kind = kind
        if kind == .activeWindow { capturePreview() }
        if kind == .audio { popout.devices = audio.outputDevices() }
        if kind == .bluetooth { bluetooth.refresh() }
        if kind == .network { popout.networks = []; popout.scanMessage = nil }
        let reveal = bars[display]?.reveal.target ?? 0
        let inner = layout.inner(barReveal: max(reveal, 1))
        let size = CGSize(width: kind.width, height: popout.bodyHeight(for: kind) + 2 * fillet)
        panel.setFrame(DisplayLayout.withRoom(ShellSizing.popoutFrame(size: size, anchorMidY: anchorMidY, inner: inner), edge: .left,
                                              room: theme.overshootRoom(depth: kind.width)), display: false)
        present(panel)
        popout.shown = true
        popoutKind = kind
        popoutDisplay = display
        // A popout grows out of the bar (Caelestia only opens them from it): show the bar if it is
        // auto-hidden (IPC / keybind opens), and hold it while the popout is open.
        revealBar(display)
        launcherDisplay = display
    }

    /// Captures the focused window for the active-window popout (needs Screen Recording; without
    /// it the popout shows the icon and title only).
    func capturePreview() {
        previewTask?.cancel()
        popout.window = state.activeWindow
        // Never ask for Screen Recording from a hover: without it the popout shows icon + title.
        guard let id = state.activeWindow?.windowID, id != 0, CGPreflightScreenCaptureAccess() else { popout.preview = nil; return }
        if popout.preview != nil, popout.previewWindowID != id { popout.preview = nil }
        previewTask = Task { @MainActor [weak self] in
            let image = try? await ScreenshotController.captureWindow(CGWindowID(id))
            guard let self, !Task.isCancelled, self.popoutKind == .activeWindow else { return }
            self.popout.preview = image
            self.popout.previewWindowID = id
        }
    }

    public func closePopout() {
        guard popoutKind != nil else { return }
        popoutByHover = false
        popoutLeaveTimer?.invalidate()
        popoutLeaveTimer = nil
        previewTask?.cancel()
        popout.shown = false
        popoutKind = nil
        popoutDisplay = nil
        dismissAfter(popoutPanel) { [weak self] in self?.popout.shown == false }
        // Re-check the pointer: a bar shown only for this popout hides once it is away.
        pointerMoved(NSEvent.mouseLocation)
    }

    private func openSettings(for kind: PopoutKind) {
        let pane: String
        switch kind {
        case .network: pane = "x-apple.systempreferences:com.apple.Network-Settings.extension"
        case .bluetooth: pane = "x-apple.systempreferences:com.apple.BluetoothSettings"
        case .battery: pane = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        case .audio: pane = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
        case .activeWindow: closePopout(); return
        }
        closePopout()
        if let url = URL(string: pane) { openURL(url) }
    }

    private func setWifi(_ on: Bool) {
        do { try network.setWifi(on: on) }
        catch { toast(.error, title: "Wi-Fi", message: error.localizedDescription) }
    }

    private func scanNetworks() {
        guard !popout.scanning else { return }
        popout.scanning = true
        popout.scanMessage = nil
        Task { @MainActor in
            do {
                popout.networks = try await network.availableNetworks()
                if popout.networks.isEmpty { popout.scanMessage = "No networks found" }
            } catch ServiceError.permissionMissing {
                popout.scanMessage = "Network names are hidden until SkyRose is allowed to use Location (System Settings > Privacy & Security)."
            } catch {
                popout.scanMessage = error.localizedDescription
            }
            popout.scanning = false
            if let kind = popoutKind, let d = popoutDisplay, let layout = layouts[d], let panel = popoutPanel {
                let fillet = theme.frameRounding
                let inner = layout.inner(barReveal: 1)
                let size = CGSize(width: kind.width, height: popout.bodyHeight(for: kind) + 2 * fillet)
                panel.setFrame(DisplayLayout.withRoom(ShellSizing.popoutFrame(size: size, anchorMidY: panel.frame.midY, inner: inner), edge: .left,
                                                      room: theme.overshootRoom(depth: kind.width)), display: true)
            }
        }
    }

    // MARK: Quick toggles

    func quickToggle(_ id: String) {
        switch id {
        case "wifi": setWifi(!state.status.wifiEnabled)
        case "bluetooth": bluetooth.openSettings()
        case "dnd": setDoNotDisturb(!state.doNotDisturb)
        case "darkmode":
            if let url = URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension") { openURL(url) }
        default: break
        }
    }

    public func setDoNotDisturb(_ on: Bool) {
        state.doNotDisturb = on
        if on { popups.queue = ToastQueue() }
    }

    // MARK: Notifications

    /// Loads the history from `file` and saves every later change to it.
    public func useNotificationHistory(_ file: NotificationHistoryFile) {
        notificationHistory = file
        notificationStore = NotificationStore(items: file.load(limit: notificationStore.limit))
        state.notifications = notificationStore.items
    }

    func notificationsChanged() {
        state.notifications = notificationStore.items
        notificationHistory?.save(notificationStore.items)
    }

    func recordNotification(kind: ToastKind, title: String, message: String, icon: String) {
        let n = ShellNotification(
            appName: "skyrose-shell", summary: title, body: message, icon: icon.isEmpty ? kind.defaultIcon : icon,
            urgency: kind == .error ? "critical" : "normal")
        notificationStore.add(n)
        notificationsChanged()
    }

    /// `skyrose notify` and test notifications: history entry plus a toast (unless DND).
    @discardableResult
    public func notify(title: String, body: String = "", app: String = "skyrose-shell", icon: String = "") -> UUID {
        let n = ShellNotification(appName: app.isEmpty ? "skyrose-shell" : app, summary: title, body: body, icon: icon)
        notificationStore.add(n)
        notificationsChanged()
        toast(.info, title: title, message: body, icon: icon, record: false, popup: true)
        return n.id
    }

    public func dismissNotification(_ id: UUID) {
        notificationStore.dismiss(id)
        notificationsChanged()
    }

    public func clearNotifications() {
        notificationStore.clear()
        notificationsChanged()
        sidebar.expanded.removeAll()
    }

    // MARK: Performance sampling (1 Hz, only while the dashboard is open)

    func startStatsTimer() {
        guard statsTimer == nil else { return }
        sampleStats()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sampleStats() } }
        RunLoop.main.add(t, forMode: .common)
        statsTimer = t
    }

    func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
        throughput.reset()
    }

    func sampleStats() {
        let s = sampler.sample()
        let net = throughput.sample()
        var p = state.performance
        p.cpuPercent = s.cpu * 100
        p.gpuPercent = s.gpu
        p.memoryUsedBytes = s.memoryUsed
        p.memoryTotalBytes = s.memoryTotal
        p.storageUsedBytes = s.diskUsed
        p.storageTotalBytes = s.diskTotal
        p.uptimeSeconds = s.uptime
        p.thermalState = s.thermal
        p.temperatureC = s.temperatures.cpuC
        p.cpuMaxTemperatureC = s.temperatures.cpuMaxC
        p.gpuTemperatureC = s.temperatures.gpuC
        p.batteryTemperatureC = s.temperatures.batteryC
        p.ssdTemperatureC = s.temperatures.ssdC
        if let t = s.temperatures.cpuC { p.temperatureHistory = SysInfo.appended(p.temperatureHistory, t) }
        p.networkUpBytesPerSec = net.uploadBytesPerSecond
        p.networkDownBytesPerSec = net.downloadBytesPerSecond
        p.cpuHistory = SysInfo.appended(p.cpuHistory, p.cpuPercent)
        p.memoryHistory = SysInfo.appended(p.memoryHistory, s.memoryTotal > 0 ? Double(s.memoryUsed) / Double(s.memoryTotal) * 100 : 0)
        p.networkDownHistory = SysInfo.appended(p.networkDownHistory, net.downloadBytesPerSecond)
        p.networkUpHistory = SysInfo.appended(p.networkUpHistory, net.uploadBytesPerSecond)
        state.performance = p
        dashboard.now = Date()
    }

    // MARK: Wallpaper and dynamic colours

    public func setWallpaper(_ url: URL) {
        if WallpaperLibrary.isLive(url) { return setLiveWallpaper(url) }
        if let failure = wallpaper.apply(url) {
            toast(.error, title: "Wallpaper not set", message: failure)
            return
        }
        liveWallpaper.stop()
        wallpaperPicker.current = url
        state.currentWallpaper = url
        refreshColors()
    }

    /// A video: its first frame becomes the desktop picture (lock screen, colours), then the
    /// video loops above it.
    func setLiveWallpaper(_ video: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let still = LiveWallpaperStill.makeStill(for: video)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let still else {
                        self.toast(.error, title: "Live wallpaper not set", message: "Could not read a frame of \(video.lastPathComponent)")
                        return
                    }
                    if let failure = self.wallpaper.apply(still) {
                        self.toast(.error, title: "Wallpaper not set", message: failure)
                        return
                    }
                    self.liveWallpaper.play(video: video, still: still)
                    self.wallpaperPicker.current = video
                    self.state.currentWallpaper = still
                    self.refreshColors()
                }
            }
        }
    }

    /// After a WM / shell restart: loop the live wallpaper again if macOS still shows its still.
    func resumeLiveWallpaper() {
        guard liveWallpaper.video == nil, let record = liveWallpaper.record else { return }
        let desktop = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        guard record.isCurrent(desktopPicture: desktop) else {
            liveWallpaper.stop()  // forgets the record
            return
        }
        liveWallpaper.play(video: URL(fileURLWithPath: record.video), still: URL(fileURLWithPath: record.still))
        liveWallpaper.update(battery: battery.state)
        wallpaperPicker.current = liveWallpaper.video
    }

    /// The wallpaper as the user picked it: the video when a live wallpaper loops.
    public var displayedWallpaper: URL? { liveWallpaper.video ?? wallpaper.current() }

    public func randomWallpaper() {
        wallpaper.scan(folder: state.config.appearance.wallpaperFolder) { [weak self] result in
            guard let self else { return }
            var rng = SystemRandomNumberGenerator()
            guard let url = WallpaperLibrary.random(from: result.urls, excluding: self.displayedWallpaper, using: &rng) else {
                self.toast(.warn, title: "No wallpapers", message: result.message ?? "The wallpaper folder is empty")
                return
            }
            self.transitionWallpaper(url)
        }
    }

    /// The desktop cross-fade length (Caelestia 600 ms; short under Reduce Motion).
    var wallpaperCrossfade: Double { theme.reduceMotion ? 0.2 : WallpaperPreview.crossfade }

    /// Sets a wallpaper through the 600 ms cross-fade: the new picture fades in over the desktop,
    /// then becomes the real desktop picture underneath and the overlay leaves.
    public func transitionWallpaper(_ url: URL) {
        guard url != displayedWallpaper else { return }
        wallpaperPreview.show(url, crossfade: wallpaperCrossfade) { [weak self] in
            guard let self else { return }
            self.setWallpaper(url)
            self.wallpaperPreview.finish(after: WallpaperLibrary.isLive(url) ? 2 : 0.8)
        }
    }

    /// The carousel's centred item changed: show it on the desktop (nothing is set yet).
    func previewWallpaper(_ url: URL) {
        if !carouselPreviewing, url == displayedWallpaper { return }
        carouselPreviewing = true
        wallpaperPreview.show(url, crossfade: wallpaperCrossfade)
    }

    /// Enter / click in the carousel: keep the previewed wallpaper.
    func pickCarouselWallpaper(_ url: URL) {
        let previewing = carouselPreviewing
        carouselPreviewing = false
        close(.launcher)
        if url == displayedWallpaper {
            if previewing { wallpaperPreview.revert(crossfade: wallpaperCrossfade) }
            return
        }
        setWallpaper(url)
        if previewing {
            wallpaperPreview.finish(after: WallpaperLibrary.isLive(url) ? 2 : 0.8)
        }
    }

    /// Applies the scheme for the current config and wallpaper: static, or a palette extracted from
    /// the wallpaper (off the main thread, cached by file).
    public func refreshColors() {
        let a = state.config.appearance
        let base = SchemeResolver.staticScheme(a) ?? ShellTheme.fallbackScheme
        guard SchemeResolver.isDynamic(a) else { applyScheme(base); return }
        let url = wallpaper.current()
        state.currentWallpaper = url
        guard let url, a.accentOverride.isEmpty else {
            applyScheme(SchemeResolver.resolve(appearance: a, base: base, wallpaperSource: nil))
            return
        }
        if let hit = wallpaperColors.cached(for: url) {
            applyScheme(SchemeResolver.resolve(appearance: a, base: base, wallpaperSource: hit))
            return
        }
        wallpaperColors.source(for: url) { [weak self] source in
            guard let self else { return }
            let now = self.state.config.appearance
            guard SchemeResolver.isDynamic(now), self.wallpaper.current() == url else { return }
            self.applyScheme(SchemeResolver.resolve(appearance: now, base: SchemeResolver.staticScheme(now) ?? base, wallpaperSource: source))
        }
    }

    func applyScheme(_ scheme: Scheme) {
        guard scheme != state.scheme else { return }
        state.scheme = scheme
        stateChanged()
        onSchemeChange?(scheme)
    }
}
