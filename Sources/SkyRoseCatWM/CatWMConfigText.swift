import CaelestiaCore
import CoreGraphics
import Foundation

/// The CatWM config (TypeScript) that makes CatWM behave the SkyRose way, generated from SkyRose's
/// own config so Settings › Windows keeps working. CatWM re-runs the whole text on every apply and
/// changes only what differs.
public enum CatWMConfigText {
    /// `area` is SkyRose's usable area and `visible` the display's visible frame (both top-left
    /// points); the difference becomes CatWM's padding.
    public static func make(_ config: Config, area: CGRect?, visible: CGRect?) -> String {
        let wm = config.wm
        // Like SkyRose's own layout (LayoutParams): the border sits inside the gap, so each tile
        // gives up the border width on top of gapsIn / gapsOut.
        let border = wm.gameMode ? 0 : wm.borderSize
        let outer = wm.gameMode ? 0 : wm.gapsOut + border
        let bar = padding(area: area, visible: visible, fallback: 0)
        let pad = (left: bar.left + outer, right: bar.right + outer, top: bar.top + outer, bottom: bar.bottom + outer)
        let move = AnimationTable.from(config: config.animations, reduceMotion: config.animations.reduceMotion)[.windowsMove]
        let animate = !wm.gameMode && config.animations.windows != .off && move.enabled && move.durationMs > 0
        let gap = wm.gameMode ? 0 : wm.gapsIn * 2 + border * 2
        var lines = [
            "import { catwm } from \"./catwm\"",
            "catwm.features.windows.tiling = true",
            "catwm.features.windows.tabGroups = true",
            "catwm.features.input.mouse = true",
            "catwm.workspaces.parked = true",
            "catwm.layouts = \(layouts(wm.catwm.layouts))",
            "catwm.mouse.swapsWindows = \(wm.catwm.dragToSwap)",
            "catwm.mouse.resizesWindows = \(wm.catwm.dragToResize)",
            "catwm.floating.smallWindows = \(wm.catwm.floatSmallWindows)",
            "catwm.floating.apps = \(list(wm.catwm.floatingApps))",
            "catwm.gaps.enabled = \(gap > 0)",
            "catwm.gaps.size = \(number(min(100, gap)))",
            "catwm.gaps.smart = false",
            "catwm.gaps.single = \(number(wm.gameMode ? 0 : min(200, max(0, wm.gapsOutSingle - wm.gapsOut))))",
            "catwm.padding.left = \(number(pad.left))",
            "catwm.padding.right = \(number(pad.right))",
            "catwm.padding.top = \(number(pad.top))",
            "catwm.padding.bottom = \(number(pad.bottom))",
            "catwm.noPaddingOnBuiltinDisplay = false",
            "catwm.focus.mouseFollowsFocus = \(wm.cursorFollowsFocus)",
            "catwm.focus.followsMouse = \(wm.focusFollowsMouse)",
            "catwm.focus.followsMouseInModeOnly = false",
            "catwm.motion.enabled = \(animate)",
            "catwm.lab.resizeAnimation = \"\(config.animations.windows == .snapshot ? "snapshot" : "live")\"",
        ]
        if animate {
            let speed = wm.catwm.motionSpeed > 0 ? min(1, max(0.05, wm.catwm.motionSpeed)) : min(5, move.durationMs / 1000)
            lines.append("catwm.motion.duration = \(number(speed))")
            let style = wm.catwm.motionStyle
            if style != "skyrose", CatWMSettings.motionStyles.contains(style) {
                lines.append("catwm.motion.curve = \"\(style)\"")
            } else {
                switch move.curve {
                case .bezier(let c):
                    lines.append("catwm.motion.curve = \"cubic-bezier(\([c.x1, c.y1, c.x2, c.y2].map(number).joined(separator: ", ")))\"")
                case .spring:
                    lines.append("catwm.motion.curve = \"spring\"")
                }
            }
            lines.append("catwm.motion.bounce = \(number(min(1, max(0, wm.catwm.motionBounce))))")
        }
        if !wm.catwm.extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(wm.catwm.extra) }
        return lines.joined(separator: "\n") + "\n"
    }

    static func layouts(_ names: [String]) -> String {
        let known = names.filter(CatWMSettings.knownLayouts.contains)
        return list(known.isEmpty ? ["dwindle"] : known)
    }

    static func list(_ items: [String]) -> String {
        "[" + items.map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            .joined(separator: ", ") + "]"
    }

    static func padding(area: CGRect?, visible: CGRect?, fallback: Double) -> (left: Double, right: Double, top: Double, bottom: Double) {
        guard let area, let visible, !area.isEmpty, !visible.isEmpty else { return (fallback, fallback, fallback, fallback) }
        func clamp(_ v: Double) -> Double { min(500, max(0, v.rounded())) }
        return (clamp(area.minX - visible.minX), clamp(visible.maxX - area.maxX),
                clamp(area.minY - visible.minY), clamp(visible.maxY - area.maxY))
    }

    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.4g", v)
    }
}
