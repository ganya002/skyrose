import AppKit
import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaPlatform
import CaelestiaShell
import Foundation

/// The SkyRose WM process (SkyRose.app): loads config/keymap/rules, wires the AX window system, the display
/// monitor, the event tap (hotkeys + panic chord) and the IPC server to one `WindowManager`, and
/// runs the AppKit main loop. Every exit path (panic chord, `wm.quit`, `wm.panic`, SIGTERM/SIGINT/
/// SIGHUP) restores every window before the process ends; a crash is covered by the journal
/// replay on the next launch.
@MainActor
public final class WMDaemon {
    public let wm: WindowManager
    public let matcher: ChordMatcher
    public let tap: EventTap
    private var ipc: IPCServer?
    private var configWatcher: ConfigWatcher?
    private var keymapWatcher: KeymapWatcher?
    private var signalSources: [DispatchSourceSignal] = []
    private var accessibilityTimer: Timer?
    private var decorations: OverlayDecorations?
    private var shell: ShellBridge?
    private var permissionTimer: Timer?
    private var permissionHistory = PermissionHistory.load()

    public init() {
        // One-time move of a pre-rename install (~/.config/caelestia-mac, …/CaelestiaMac) before
        // anything reads the new folders. Skipped while an old CaelestiaWM still runs.
        let legacyRunning = LaunchChecks.runningProcessNames().contains("CaelestiaWM")
        let migration = LegacyMigration().run(legacyWMRunning: legacyRunning)
        if migration.outcome == .migrated {
            Log.config.notice("migrated from Caelestia for Mac: \(migration.moved.count) moved, \(migration.keptAside.count) kept aside")
        }
        let (config, configWarnings) = ConfigLoader.loadUserOrDefault()
        let (keymap, keymapWarnings) = KeymapLoader.loadUserOrDefault()
        let (rules, rulesWarnings) = RulesLoader.loadUserOrDefault()
        for w in configWarnings + keymapWarnings + rulesWarnings {
            Log.config.warning("\(w, privacy: .public)")
        }
        matcher = ChordMatcher(keymap: keymap, input: config.effective.input)
        tap = EventTap(matcher: matcher, queue: .main)
        wm = WindowManager(
            windowSystem: AXWindowSystem(), displayProvider: DisplayMonitor(), config: config.effective, rules: rules, keymap: keymap
        )
    }

    /// Never returns.
    public func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Launched with `open` there is no terminal: every reason not to start must be visible.
        let competitors = LaunchChecks.competingWindowManagers(processNames: LaunchChecks.runningProcessNames())
        if !competitors.isEmpty {
            let message = LaunchChecks.competingWindowManagerMessage(competitors)
            Log.wm.error("not starting: \(message, privacy: .public)")
            FileHandle.standardError.write(Data((message + "\n").utf8))
            showAlert(title: "Another window manager is running", message: message, buttons: ["Quit"])
            exit(3)
        }

        // IPC first: the onboarding asks this process for its permission status (TCC is per
        // process) while it still waits for Accessibility.
        wm.onConfigReload = { [weak self] in self?.reloadConfigAndKeymap() ?? [] }
        let tap = tap
        wm.onPauseHotkeys = { seconds in tap.pauseHotkeys(for: seconds) }
        startIPC()
        let firstRun = !OnboardingState.load().completed
        let snapshot = wm.permissionSnapshot()
        _ = permissionHistory.observe(snapshot)
        permissionHistory.save()
        if firstRun {
            // First run (or after `skyrose onboarding`): the onboarding walks through the mode and
            // the permissions; it opens even when everything is granted already.
            if !SettingsLauncher.open(.firstRun) { Log.wm.error("SkyRose Settings not found; no onboarding") }
        }
        if snapshot.accessibility {
            startManaging()
        } else {
            Log.wm.error("waiting for Accessibility access")
            FileHandle.standardError.write(Data((LaunchChecks.accessibilityMessage + "\n").utf8))
            if !firstRun, !SettingsLauncher.open(.repair([.accessibility])) {
                // No Settings app: the old alert is the fallback.
                _ = Permissions.request(.accessibility)
                let choice = showAlert(
                    title: "SkyRose needs Accessibility access", message: LaunchChecks.accessibilityMessage,
                    buttons: ["Open System Settings", "Quit"]
                )
                if choice == 1 { exit(2) }
                Permissions.openSettings(for: .accessibility)
            }
            waitForAccessibility()
        }
        startPermissionWatch()
        app.run()
        exit(0)
    }

    /// Polls once a second until Accessibility is granted, then starts.
    private func waitForAccessibility() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAccessibilityGranted() }
        }
        accessibilityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkAccessibilityGranted() {
        guard wm.permissionSnapshot().accessibility else { return }
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        Log.wm.notice("Accessibility granted; starting")
        startManaging()
    }

    /// Shows a modal alert in front of every app and returns the index of the button pressed.
    @discardableResult
    private func showAlert(title: String, message: String, buttons: [String]) -> Int {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        for b in buttons { alert.addButton(withTitle: b) }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    private func startManaging() {
        wm.onQuit = { [weak self] in self?.terminate() }
        // Native shell part 1: frame, bar, launcher, session menu, OSDs, toasts (CaelestiaShell).
        let shell = ShellBridge(wm: wm)
        self.shell = shell
        shell.controller.useNotificationHistory(NotificationHistoryFile(url: Paths.appSupport.appendingPathComponent("notifications.json")))
        wm.onLayoutApplied = { [weak shell] in shell?.sync() }
        wm.shellResponder = { [weak shell] request, command in shell?.respond(to: request, command: command) }
        wm.onUnhandledAction = { [weak self, weak shell] action in
            if AppLauncher.handle(action, apps: self?.wm.config.apps ?? AppsConfig()) { return }
            if shell?.handle(action) != true {
                Log.wm.info("action \(action.description, privacy: .public) is not handled yet")
            }
        }
        wm.onRulesReload = { [weak self] in self?.reloadRules() ?? [] }
        // Per-app rules API: saved into config.toml [appRules] (one line, comments kept).
        wm.appRulePersister = { bundle, mode in
            if mode == .auto {
                try ConfigFileEditor.remove(bundle, inTable: "appRules", file: Paths.configFile)
            } else {
                try ConfigFileEditor.set(bundle, to: ConfigFileEditor.string(mode.rawValue), inTable: "appRules", file: Paths.configFile)
            }
        }
        wm.runningApps = {
            NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
        }
        // Media keys: the tap swallows the ones Caelestia can do itself (CoreAudio volume,
        // DisplayServices brightness) so Apple's HUD never shows next to ours.
        let mediaKeys = tap.mediaKeys
        mediaKeys.update(enabled: wm.config.input.interceptMediaKeys)
        shell.controller.onMediaCapabilities = { volume, brightness in
            mediaKeys.update(volumeControllable: volume, brightnessControllable: brightness)
            Log.input.notice("media keys: volume \(volume ? "SkyRose" : "macOS", privacy: .public), brightness \(brightness ? "SkyRose" : "macOS", privacy: .public)")
        }

        // Borders, group bars, workspace slide, debug overlay (CaelestiaOverlay).
        let deco = OverlayDecorations(config: wm.config)
        decorations = deco
        wm.decorations = deco
        wm.windowAnimator = deco.animator
        shell.controller.onSchemeChange = { [weak deco] scheme in
            deco?.apply(scheme: scheme)
            // The Settings app draws itself in the same colours (static or dynamic).
            try? Data(SchemeLoader.serialize(scheme).utf8).write(to: Paths.currentScheme, options: .atomic)
        }

        wm.start()
        shell.start()
        startEventTap()
        startWatchers()
        installSignalHandlers()
        Log.wm.notice("SkyRose WM \(CaelestiaVersion.string, privacy: .public) managing \(self.wm.managedWindowIDs.count) window(s)")
    }

    private func startEventTap() {
        let wm = wm
        tap.onFired = { fired in
            MainActor.assumeIsolated { wm.handle(fired: fired) }
        }
        tap.onLeftMouse = { down, location in
            MainActor.assumeIsolated { down ? wm.pointerPressed(at: location) : wm.pointerReleased(at: location) }
        }
        let shell = shell
        tap.onMediaKey = { event in
            MainActor.assumeIsolated { shell?.controller.handleMediaKey(event) }
        }
        tap.onSecureInputChanged = { active, appName in
            Log.input.notice("secure input \(active ? "on" : "off", privacy: .public) (\(appName ?? "unknown", privacy: .public)): hotkeys \(active ? "paused" : "resumed", privacy: .public)")
        }
        do {
            try tap.start()
        } catch {
            // Without the tap there are no hotkeys and no panic chord; `skyrose wm panic` and
            // SIGTERM still restore every window.
            Log.input.error("event tap failed: \(String(describing: error), privacy: .public); grant Input Monitoring")
        }
    }

    private func startIPC() {
        let wm = wm
        let server = IPCServer { request in
            let (response, quit) = await MainActor.run { wm.respond(to: request) }
            if quit {
                // Let the response reach the client before the process exits.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    MainActor.assumeIsolated { _ = wm.shutdown() }
                }
            }
            return response
        }
        do {
            try server.start()
            ipc = server
        } catch {
            Log.ipc.error("IPC server failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    private func startWatchers() {
        let wm = wm
        let matcher = matcher
        configWatcher = ConfigWatcher(initial: wm.config) { event in
            MainActor.assumeIsolated {
                switch event {
                case .loaded(let config, let warnings):
                    for w in warnings { Log.config.warning("\(w, privacy: .public)") }
                    let config = config.effective
                    matcher.update(input: config.input)
                    self.tap.mediaKeys.update(enabled: config.input.interceptMediaKeys)
                    wm.apply(config: config)
                    self.decorations?.apply(config: config)
                    self.shell?.apply(config: config)
                case .failed(let error, _):
                    Log.config.error("config.toml not applied: \(String(describing: error), privacy: .public)")
                }
            }
        }
        configWatcher?.start()
        keymapWatcher = KeymapWatcher(
            fallback: KeymapLoader.loadDefault(),
            onChange: { keymap, _ in
                matcher.update(keymap: keymap)
                DispatchQueue.main.async { MainActor.assumeIsolated { wm.apply(keymap: keymap) } }
            },
            onError: { error in Log.config.error("keymap.toml not applied: \(error.description, privacy: .public)") }
        )
        keymapWatcher?.start(deliverInitial: false)
    }

    private func reloadConfigAndKeymap() -> [String] {
        let (written, warnings) = ConfigLoader.loadUserOrDefault()
        let config = written.effective
        let (keymap, keymapWarnings) = KeymapLoader.loadUserOrDefault()
        matcher.update(input: config.input)
        tap.mediaKeys.update(enabled: config.input.interceptMediaKeys)
        matcher.update(keymap: keymap)
        wm.apply(config: config)
        wm.apply(keymap: keymap)
        decorations?.apply(config: config)
        shell?.apply(config: config)
        return warnings + keymapWarnings
    }

    private func reloadRules() -> [String] {
        let (rules, warnings) = RulesLoader.loadUserOrDefault()
        wm.apply(rules: rules)
        return warnings
    }

    // MARK: Permissions

    /// Every 2 s: a permission seen granted before and missing now (an update dropped it, or it
    /// was unticked) reopens just that onboarding step, once per loss. Input Monitoring granted
    /// after launch starts the event tap without a restart.
    private func startPermissionWatch() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermissions() }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkPermissions() {
        let snapshot = wm.permissionSnapshot()
        let before = permissionHistory
        let lost = permissionHistory.observe(snapshot)
        if permissionHistory != before { permissionHistory.save() }
        if !lost.isEmpty, OnboardingState.load().completed {
            Log.wm.notice("permission lost: \(lost.map(\.rawValue).joined(separator: ", "), privacy: .public); reopening onboarding")
            SettingsLauncher.open(.repair(lost))
        }
        if snapshot.inputMonitoring, wm.isManaging, !tap.isRunning {
            do {
                try tap.start()
                Log.input.notice("Input Monitoring granted; event tap started")
            } catch {
                Log.input.error("event tap still failing: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            let wm = wm
            source.setEventHandler {
                MainActor.assumeIsolated {
                    Log.wm.notice("signal \(sig): restoring windows and quitting")
                    _ = wm.shutdown()
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func terminate() {
        tap.stop()
        ipc?.stop()
        configWatcher?.stop()
        keymapWatcher?.stop()
        exit(0)
    }
}
