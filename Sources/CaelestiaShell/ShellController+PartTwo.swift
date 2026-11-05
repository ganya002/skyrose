import AppKit
import CaelestiaCore
import CaelestiaServices
import SwiftUI

/// Shell part 2: dashboard, sidebar (notifications + utilities), bar popouts, wallpaper picker and
/// dynamic colours.
extension ShellController {
    var partTwoPanels: [ShellPanel?] { [dashboardPanel, sidebarPanel, popoutPanel, wallpaperPanel] }

    func dropPartTwoPanels() {
        dashboardPanel = nil; sidebarPanel = nil; popoutPanel = nil; wallpaperPanel = nil
        dashboard.shown = false; sidebar.shown = false; popout.shown = false; wallpaperPicker.shown = false
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

        sidebar.onDismiss = { [weak self] id in self?.dismissNotification(id) }
        sidebar.onClear = { [weak self] in self?.clearNotifications() }
        sidebar.onToggle = { [weak self] id in self?.quickToggle(id) }
        sidebar.onVolume = { [weak self] v in self?.audio.setVolume(v) }
        sidebar.onBrightness = { [weak self] v in self?.brightness.set(v) }
        sidebar.onKeepAwake = { [weak self] on in self?.keepAwake.set(on: on) }
        sidebar.onWallpaper = { [weak self] in self?.open(.wallpaper) }

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

        wallpaperPicker.onPick = { [weak self] url in self?.setWallpaper(url) }
        wallpaperPicker.onRandom = { [weak self] in self?.randomWallpaper() }
        wallpaperPicker.onNeedThumb = { [weak self] url in
            guard let self, self.wallpaperPicker.thumbs[url] == nil else { return }
            self.wallpaper.thumbnail(for: url) { img in if let img { self.wallpaperPicker.thumbs[url] = img } }
        }
    }

    func startPartTwoServices() {
        media.onChange = { [weak self] m in self?.applyMedia(m) }
        media.start()
        keepAwake.onChange = { [weak self] on in self?.state.keepAwake = on }
        bluetooth.onChange = { [weak self] b in self?.applyBluetooth(b) }
        bluetooth.start()
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
        let inner = layout.inner(barReveal: reveal)
        // A notch under the drawer: the drawer still grows out of the top band and covers the
        // band's dip, but its content starts below it.
        let clearance = layout.topClearance(minX: inner.minX, maxX: inner.maxX)
        var room = inner
        room.size.height -= clearance
        let fit = ShellSizing.dashboard(inner: room, fillet: fillet)
        dashboard.scale = fit.scale
        dashboard.topInset = clearance
        dashboard.now = Date()
        dashboard.monthOffset = 0
        dashboard.tab = DashboardTab(config: state.config.dashboard.defaultTab)
        let size = CGSize(width: fit.body.width + 2 * fillet, height: fit.body.height + clearance)
        panel.setFrame(layout.drawerFrame(size: size, edge: .top, barReveal: reveal), display: false)
        hideOSD(animated: true)
        present(panel)
        dashboard.shown = true
        media.isObserved = true
        startStatsTimer()
    }

    func closeDashboard() {
        guard dashboard.shown else { return }
        dashboard.shown = false
        media.isObserved = false
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
        panel.setFrame(frame, display: false)
        hideOSD(animated: true)
        present(panel)
        sidebar.shown = true
        bluetooth.refresh()
    }

    func closeSidebar() {
        guard sidebar.shown else { return }
        sidebar.shown = false
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
        panel.setFrame(layout.drawerFrame(size: CGSize(width: body.width + 2 * fillet, height: body.height), edge: .bottom, barReveal: reveal), display: false)
        wallpaperPicker.current = wallpaper.current()
        wallpaperPicker.loading = true
        wallpaper.scan(folder: state.config.appearance.wallpaperFolder) { [weak self] result in
            guard let self else { return }
            self.wallpaperPicker.items = result.urls
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { if stillClosed() { panel.fadeOut(duration: duration) } }
    }

    // MARK: Popouts

    func statusIconClicked(_ icon: String, display: String, windowMidY: Double) {
        Log.shell.debug("status icon \(icon, privacy: .public) clicked at y=\(windowMidY, privacy: .public)")
        guard let kind = PopoutKind.forStatusIcon(icon), let bar = bars[display], let layout = layouts[display] else { return }
        if popoutKind == kind, popoutDisplay == display { closePopout(); return }
        let midY = bar.panel.frame.maxY - windowMidY
        openPopout(kind, display: display, layout: layout, anchorMidY: midY)
    }

    /// `shell drawers toggle popout.audio|network|bluetooth|battery`: toggles a bar popout without a click.
    public func togglePopout(_ kind: PopoutKind, display: String? = nil) {
        if popoutKind == kind { closePopout(); return }
        guard let id = display ?? pointerDisplayID() ?? state.displays.first?.id, let layout = layouts[id] else { return }
        let bar = bars[id]?.panel.frame
        let anchor = bar.map { $0.minY + $0.height * 0.2 } ?? layout.inner(barReveal: 1).midY
        openPopout(kind, display: id, layout: layout, anchorMidY: anchor)
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
        if kind == .audio { popout.devices = audio.outputDevices() }
        if kind == .bluetooth { bluetooth.refresh() }
        if kind == .network { popout.networks = []; popout.scanMessage = nil }
        let reveal = bars[display]?.reveal.target ?? 0
        let inner = layout.inner(barReveal: max(reveal, 1))
        let size = CGSize(width: ShellSizing.popoutWidth, height: popout.bodyHeight(for: kind) + 2 * fillet)
        panel.setFrame(ShellSizing.popoutFrame(size: size, anchorMidY: anchorMidY, inner: inner), display: false)
        present(panel)
        popout.shown = true
        popoutKind = kind
        popoutDisplay = display
        launcherDisplay = display
    }

    public func closePopout() {
        guard popoutKind != nil else { return }
        popout.shown = false
        popoutKind = nil
        popoutDisplay = nil
        dismissAfter(popoutPanel) { [weak self] in self?.popout.shown == false }
    }

    private func openSettings(for kind: PopoutKind) {
        let pane: String
        switch kind {
        case .network: pane = "x-apple.systempreferences:com.apple.Network-Settings.extension"
        case .bluetooth: pane = "x-apple.systempreferences:com.apple.BluetoothSettings"
        case .battery: pane = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        case .audio: pane = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
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
                let size = CGSize(width: ShellSizing.popoutWidth, height: popout.bodyHeight(for: kind) + 2 * fillet)
                panel.setFrame(ShellSizing.popoutFrame(size: size, anchorMidY: panel.frame.midY, inner: inner), display: true)
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
        if on { toasts.queue = ToastQueue() }
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
        toast(.info, title: title, message: body, icon: icon, record: false)
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
        if let failure = wallpaper.apply(url) {
            toast(.error, title: "Wallpaper not set", message: failure)
            return
        }
        wallpaperPicker.current = url
        state.currentWallpaper = url
        refreshColors()
    }

    public func randomWallpaper() {
        wallpaper.scan(folder: state.config.appearance.wallpaperFolder) { [weak self] result in
            guard let self else { return }
            var rng = SystemRandomNumberGenerator()
            guard let url = WallpaperLibrary.random(from: result.urls, excluding: self.wallpaper.current(), using: &rng) else {
                self.toast(.warn, title: "No wallpapers", message: result.message ?? "The wallpaper folder is empty")
                return
            }
            self.setWallpaper(url)
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
