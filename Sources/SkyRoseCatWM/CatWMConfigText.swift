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
        let pad = padding(area: area, visible: visible, fallback: wm.gapsOut)
        let move = AnimationTable.from(config: config.animations, reduceMotion: config.animations.reduceMotion)[.windowsMove]
        let animate = !wm.gameMode && config.animations.windows != .off && move.enabled && move.durationMs > 0
        let gap = wm.gameMode ? 0 : wm.gapsIn * 2
        var lines = [
            "import { catwm } from \"./catwm\"",
            "catwm.features.windows.tiling = true",
            "catwm.features.input.mouse = true",
            "catwm.workspaces.parked = true",
            "catwm.layouts = [\"dwindle\", \"floating\"]",
            "catwm.gaps.enabled = \(gap > 0)",
            "catwm.gaps.size = \(number(min(100, gap)))",
            "catwm.gaps.smart = false",
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
            lines.append("catwm.motion.duration = \(number(min(5, move.durationMs / 1000)))")
            switch move.curve {
            case .bezier(let c):
                lines.append("catwm.motion.curve = \"cubic-bezier(\([c.x1, c.y1, c.x2, c.y2].map(number).joined(separator: ", ")))\"")
            case .spring:
                lines.append("catwm.motion.curve = \"spring\"")
            }
        }
        return lines.joined(separator: "\n") + "\n"
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
