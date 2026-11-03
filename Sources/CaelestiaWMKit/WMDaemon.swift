import AppKit
import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaPlatform
import Foundation

/// The CaelestiaWM process: loads config/keymap/rules, wires the AX window system, the display
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

    public init() {
        let (config, configWarnings) = ConfigLoader.loadUserOrDefault()
        let (keymap, keymapWarnings) = KeymapLoader.loadUserOrDefault()
        let (rules, rulesWarnings) = RulesLoader.loadUserOrDefault()
        for w in configWarnings + keymapWarnings + rulesWarnings {
            Log.config.warning("\(w, privacy: .public)")
        }
        matcher = ChordMatcher(keymap: keymap, input: config.input)
        tap = EventTap(matcher: matcher, queue: .main)
        wm = WindowManager(
            windowSystem: AXWindowSystem(), displayProvider: DisplayMonitor(), config: config, rules: rules, keymap: keymap
        )
    }

    /// Never returns.
    public func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        guard Permissions.status().accessibility else {
            _ = Permissions.request(.accessibility)
            FileHandle.standardError.write(Data((
                "CaelestiaWM needs Accessibility access to move windows.\n"
                    + "Grant it in System Settings → Privacy & Security → Accessibility, then start CaelestiaWM again.\n"
            ).utf8))
            exit(2)
        }

        wm.onQuit = { [weak self] in self?.terminate() }
        wm.onUnhandledAction = { action in
            Log.wm.info("action \(action.description, privacy: .public) is not handled by the WM yet")
        }
        wm.onConfigReload = { [weak self] in self?.reloadConfigAndKeymap() ?? [] }
        wm.onRulesReload = { [weak self] in self?.reloadRules() ?? [] }

        wm.start()
        startEventTap()
        startIPC()
        startWatchers()
        installSignalHandlers()
        Log.wm.notice("CaelestiaWM \(CaelestiaVersion.string, privacy: .public) managing \(self.wm.managedWindowIDs.count) window(s)")
        app.run()
        exit(0)
    }

    private func startEventTap() {
        let wm = wm
        tap.onFired = { fired in
            MainActor.assumeIsolated { wm.handle(fired: fired) }
        }
        tap.onSecureInputChanged = { active, appName in
            Log.input.notice("secure input \(active ? "on" : "off", privacy: .public) (\(appName ?? "unknown", privacy: .public)): hotkeys \(active ? "paused" : "resumed", privacy: .public)")
        }
        do {
            try tap.start()
        } catch {
            // Without the tap there are no hotkeys and no panic chord; `caelestia wm panic` and
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
                    matcher.update(input: config.input)
                    wm.apply(config: config)
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
        let (config, warnings) = ConfigLoader.loadUserOrDefault()
        let (keymap, keymapWarnings) = KeymapLoader.loadUserOrDefault()
        matcher.update(input: config.input)
        matcher.update(keymap: keymap)
        wm.apply(config: config)
        wm.apply(keymap: keymap)
        return warnings + keymapWarnings
    }

    private func reloadRules() -> [String] {
        let (rules, warnings) = RulesLoader.loadUserOrDefault()
        wm.apply(rules: rules)
        return warnings
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
