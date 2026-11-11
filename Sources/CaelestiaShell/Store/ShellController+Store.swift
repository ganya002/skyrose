import AppKit
import CaelestiaCore

/// SkyStore drawer: bottom-centre, like the launcher and clipboard (key panel for the search).
extension ShellController {
    func startStore() {
        store.config = state.config.store
        store.onClose = { [weak self] in self?.close(.store) }
        store.onContentChanged = { [weak self] in self?.refreshColors() }
        store.onRevoked = { [weak self] list in
            for a in list {
                _ = self?.toast(.warn, title: "\(a.name) was revoked", message: "SkyStore switched it off: \(a.status.replacingOccurrences(of: "revoked: ", with: ""))", icon: "block")
            }
        }
        store.startBackgroundChecks()
    }

    func openStore(_ id: String, layout: DisplayLayout, reveal: Double) {
        if openDrawers.contains(.session) { close(.session) }
        if openDrawers.contains(.launcher) { close(.launcher) }
        if openDrawers.contains(.clipboard) { close(.clipboard) }
        closeTransient()
        store.config = state.config.store
        let r = theme.frameRounding
        // Never wider or taller than the display allows (the frame, a fillet each side, the bar).
        let body = CGSize(width: min(StoreModel.bodySize.width, layout.area.width - 4 * r - 2 * max(layout.thickness, theme.barWidth)),
                          height: min(StoreModel.bodySize.height, layout.area.height - 4 * r))
        let panel = storePanel ?? makeDrawerPanel(StoreDrawerView(model: store, fillet: r), name: "store", key: true)
        storePanel = panel
        store.size = body
        let size = CGSize(width: body.width + 2 * r, height: body.height)
        panel.setFrame(DisplayLayout.withRoom(layout.drawerFrame(size: size, edge: .bottom, barReveal: reveal), edge: .bottom,
                                              room: theme.overshootRoom(depth: body.height)), display: false)
        store.prepare()
        panel.onKeyBeforeField = { [weak self] event in
            MainActor.assumeIsolated { self?.store.key(event) ?? false }
        }
        present(panel)
        store.shown = true
    }

    func closeStore() {
        guard openDrawers.contains(.store) else { return }
        store.shown = false
        host?.shellKeyDrawerClosed(launched: false)
        dismiss(storePanel)
    }
}
