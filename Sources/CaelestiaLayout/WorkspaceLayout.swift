import Foundation
import CoreGraphics
import CaelestiaCore

/// Turns one workspace into placements for every window on it.
public enum WorkspaceLayout {
    /// Lays out `workspace` inside `area` (the display's usable area: frame minus menu bar/Dock
    /// minus the shell's reserved zones).
    ///
    /// - Tiled windows: the dwindle tree with the config's gaps/border (zero in game mode); the
    ///   single-window gaps apply on numbered workspaces only (rule `w[tv1]s[false]`).
    /// - Floating windows keep their stored frame, clamped to `area`; pinned ones are `.pinned`.
    /// - The maximized window fills `area` inset by `gapsOutSingle` then the border.
    /// - The true-fullscreen window gets `fullFrame` (the whole display: covers bar and gaps) with
    ///   no border. Every other window is still laid out (`hidden = false`); the WM keeps them
    ///   below it.
    /// - Inactive group tabs come back `hidden = true`; `groupBarHeight` is reserved above grouped
    ///   windows for the WM's group bar.
    /// - `minSizes`: a tiled window smaller than its min size gets the min size centred in its
    ///   slot; nothing else moves, so the layout is stable across passes.
    ///
    /// Pure and deterministic: identical inputs give identical placements in a fixed order
    /// (tree order, then floating windows bottom → top).
    public static func compute(
        _ workspace: Workspace, area: CGRect, fullFrame: CGRect, config: WMConfig, minSizes: [WindowID: CGSize] = [:],
        groupBarHeight: Double = 0
    ) -> [Placement] {
        let params = LayoutParams(wm: config, singleWindowGaps: !workspace.id.isSpecial, groupBarHeight: groupBarHeight)
        let border = params.borderSize
        var placements = workspace.tree.layout(area: area, params: params, minSizes: minSizes)
        if !workspace.pseudo.isEmpty {
            for i in placements.indices {
                guard let size = workspace.pseudo[placements[i].window] else { continue }
                let frame = pseudoFrame(size, in: placements[i].frame)
                let bar = placements[i].frame.minY - placements[i].borderFrame.minY - border
                placements[i].frame = frame
                placements[i].borderFrame = CGRect(x: frame.minX - border, y: frame.minY - bar - border,
                                                   width: frame.width + 2 * border, height: frame.height + bar + 2 * border)
            }
        }

        for window in workspace.floatingOrder {
            guard let stored = workspace.floating[window] else { continue }
            let frame = HyprGeometry.clamp(stored, to: area)
            placements.append(Placement(
                window: window, frame: frame, borderFrame: frame.insetBy(dx: -border, dy: -border),
                kind: workspace.pinned.contains(window) ? .pinned : .floating, hidden: false
            ))
        }

        if let maximized = workspace.maximized, let index = placements.firstIndex(where: { $0.window == maximized }) {
            let outer = params.gapsOutSingle ?? params.gapsOut
            let frame = area.insetBy(Insets.uniform(outer + border))
            placements[index] = Placement(
                window: maximized, frame: frame, borderFrame: frame.insetBy(dx: -border, dy: -border),
                kind: .maximized, hidden: false
            )
        }

        if let fullscreen = workspace.fullscreen, let index = placements.firstIndex(where: { $0.window == fullscreen }) {
            placements[index] = Placement(window: fullscreen, frame: fullFrame, borderFrame: fullFrame, kind: .fullscreen, hidden: false)
        }

        return placements
    }

    /// Hyprland's pseudotile maths: the window keeps `size` centred in `slot`; when it does not
    /// fit it is scaled down (aspect kept) to fit, then centred. Integral points.
    public static func pseudoFrame(_ size: CGSize, in slot: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return slot }
        var w = size.width, h = size.height
        if w > slot.width || h > slot.height {
            var scale = 1.0
            if w > slot.width { scale = slot.width / w }
            if h * scale > slot.height { scale = slot.height / h }
            w *= scale
            h *= scale
        }
        w = w.rounded(.down)
        h = h.rounded(.down)
        return CGRect(x: (slot.minX + (slot.width - w) / 2).rounded(), y: (slot.minY + (slot.height - h) / 2).rounded(), width: w, height: h)
    }
}
