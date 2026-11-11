import AppKit
import CaelestiaCore
import CaelestiaPlatform

/// The SIP-off helper card: shown while SIP-off mode is on and the helper is not loaded.
extension ShellController {
    /// The WM reports whether the helper is needed (SIP-off on, helper not answering).
    public func setHelperNeeded(_ needed: Bool) {
        helperCardEvent(.needed(needed))
    }

    /// The WM saw the helper answer.
    public func helperBecameActive() {
        helperCardEvent(.helperActive)
    }

    /// Settings or `skyrose sa enable`: show the card even after "Not now".
    public func requestHelperCard() {
        helperCardEvent(.requested)
    }

    func helperCardEvent(_ event: HelperCardFlow.Event) {
        let before = helperCard.flow
        helperCard.flow.handle(event)
        let after = helperCard.flow
        if event == .showTerminal, after.phase == .terminal { openHelperTerminal() }
        if before.phase != .waitingForPassword, after.phase == .waitingForPassword { runHelperLoader(installDaemon: after.installDaemon) }
        if after.phase == .success, before.phase != .success {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.helperCardEvent(.dismissAfterSuccess) }
        }
        if before.isVisible != after.isVisible { presentHelperCard(after.isVisible) }
    }

    private func presentHelperCard(_ visible: Bool) {
        guard isRunning else { return }
        if visible {
            let panel = helperPanel ?? makeDrawerPanel(HelperCardView(model: helperCard), name: "helperCard", key: false)
            panel.level = ShellLevel.osd
            helperPanel = panel
            helperCard.terminalCommand = SAClient.bundledLoader().map { SAProtocol.loadCommand(loader: $0) } ?? ""
            helperCard.copied = false
            helperCard.onEvent = { [weak self] in self?.helperCardEvent($0) }
            helperCard.onOpenTerminal = { [weak self] in self?.openHelperTerminal() }
            let id = state.displays.first?.id
            guard let id, let layout = layouts[id] else { return }
            let inner = layout.inner(barReveal: 0)
            let w = 480.0, h = 360.0
            // Below the notch, like the dashboard's clearance.
            let clearance = layout.topClearance(minX: inner.midX - w / 2, maxX: inner.midX + w / 2)
            panel.setFrame(CGRect(x: inner.midX - w / 2, y: inner.maxY - clearance - h, width: w, height: h), display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.fadeIn(duration: 0.01)
        } else if let panel = helperPanel {
            // The card animates out in SwiftUI; the panel goes once that is done.
            DispatchQueue.main.asyncAfter(deadline: .now() + theme.drawerCloseSeconds + 0.1) { [weak self] in
                if self?.helperCard.flow.isVisible == false { panel.orderOut(nil) }
            }
        }
    }

    private func runHelperLoader(installDaemon: Bool) {
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = HelperLoader.run(app: app, installDaemon: installDaemon)
            DispatchQueue.main.async {
                guard let self else { return }
                switch outcome {
                case .cancelled: self.helperCardEvent(.passwordCancelled)
                case .failed(let why): self.helperCardEvent(.rootFailed(why))
                case .loaded:
                    self.helperCardEvent(.rootFinished)
                    self.onHelperLoaded()
                    // The WM probes again; if it still sees nothing after 8 s, say so.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                        self?.helperCardEvent(.rootFailed("The helper loaded but SkyRose cannot reach it. Try SkyRose › Restart."))
                    }
                }
            }
        }
    }

    /// A `.command` file Terminal opens and runs: it prints what it does, then asks sudo.
    private func openHelperTerminal() {
        let cmd = helperCard.terminalCommand
        guard !cmd.isEmpty else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SkyRose", isDirectory: true)
        let file = dir.appendingPathComponent("load-sip-off-helper.command")
        let text = "#!/bin/sh\necho 'SkyRose: loading the SIP-off helper into the Dock. Type your Mac password when asked.'\necho\necho '$ \(cmd.replacingOccurrences(of: "'", with: "'\\''"))'\n\(cmd)\n"
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            toast(.error, title: "Could not open Terminal", message: error.localizedDescription, record: false)
        }
    }
}
