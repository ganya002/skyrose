import AppKit
import CaelestiaCore
import CaelestiaPlatform

/// `bar.hideOverFullscreen`: while the focused app covers a display (native or borderless
/// fullscreen) or is tagged `game`, the bar and the frame fade out there and its hover zones,
/// edge drags and bar hot zone stay off, so nothing of ours sits above the game or takes its
/// clicks. They fade back when the app loses focus, leaves fullscreen or quits. Other displays
/// are untouched.
extension ShellController {
    func startCoverWatch() {
        guard coverObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            coverObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshCover()
                    // A Space switch or a fullscreen transition is still moving the windows.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshCover() }
                }
            })
        }
        // shortcut: polls once a second for a window going (borderless) fullscreen without an app
        // switch; an AX resize observer on the focused app could replace it.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCover() }
        }
        RunLoop.main.add(t, forMode: .common)
        coverTimer = t
        refreshCover()
    }

    func stopCoverWatch() {
        let center = NSWorkspace.shared.notificationCenter
        for o in coverObservers { center.removeObserver(o) }
        coverObservers.removeAll()
        coverTimer?.invalidate()
        coverTimer = nil
        coveredDisplays.removeAll()
    }

    /// Recomputes the covered displays and fades the surfaces of those that changed.
    func refreshCover() {
        guard isRunning else { return }
        let next = state.config.bar.hideOverFullscreen ? currentCover() : []
        guard next != coveredDisplays else { return }
        let added = next.subtracting(coveredDisplays)
        let removed = coveredDisplays.subtracting(next)
        coveredDisplays = next
        Log.shell.notice("fullscreen cover: [\(next.sorted().joined(separator: ","), privacy: .public)]")
        let fade = state.reduceMotion ? 0.12 : 0.25
        for id in added { stepAside(id, fade: fade) }
        for id in removed { stepBack(id, fade: fade) }
    }

    /// The focused app's on-screen windows against the displays.
    func currentCover() -> Set<String> {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return [] }
        let pid = app.processIdentifier
        let own = CGWindowSnapshot.current(onScreenOnly: true).filter { $0.pid == pid }
        let windows = own.filter { $0.isNormalLayer && $0.alpha >= 0.05 }.map(\.bounds)
        guard !windows.isEmpty else { return [] }
        let displays = state.displays.map { d in
            FullscreenCover.Display(id: d.id, frame: d.frame, notchInset: d.hasNotch ? max(d.menuBarHeight, d.topCutouts.map { $0.maxY - d.frame.minY }.max() ?? 0) : 0)
        }
        return FullscreenCover.covered(displays: displays, windows: windows, backdrops: own.filter { $0.layer < 0 }.map(\.bounds),
                                       isGame: isGameApp(app))
    }

    private func stepAside(_ id: String, fade: TimeInterval) {
        // Drawers and popouts on that display would sit above the game.
        if launcherDisplay == id {
            hoverOpened.removeAll()
            closeTransient(includingSidebar: true)
            if openDrawers.contains(.utilities) { close(.utilities) }
        }
        if popoutDisplay == id, popoutKind != nil { closePopout() }
        hoverPending = nil
        if visibility[id]?.persistent == false { setBarShown(false, display: id) }
        frames[id]?.panel.fadeOut(duration: fade)
        bars[id]?.panel.fadeOut(duration: fade)
    }

    private func stepBack(_ id: String, fade: TimeInterval) {
        frames[id]?.panel.fadeIn(duration: fade)
        bars[id]?.panel.fadeIn(duration: fade)
    }
}
