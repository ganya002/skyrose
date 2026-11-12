import CaelestiaCore
import CatWMKit
import CoreGraphics

/// SkyRose bind -> the CatWM commands that do the same (Hyprland names on both sides).
public enum CatWMCommands {
    public typealias Call = (name: String, args: [String: JSON])

    /// nil: not a window-manager action (the shell takes it). An empty list: a WM action CatWM
    /// can't do yet. `area` sizes percent resizes; `current` is the shown workspace.
    public static func calls(for action: Action, area: CGRect?, perGroup: Int, current: String?) -> [Call]? {
        func ws(_ name: String, _ workspace: String) -> [Call] { [(name, ["workspace": .string(workspace)])] }
        let per = max(1, perGroup)
        switch action.kind {
        case .workspaceFocus:
            return action.index.map { ws("workspace", String($0)) } ?? []
        case .workspaceMove:
            return action.index.map { ws("movetoworkspace", String($0)) } ?? []
        case .workspaceMoveSilent:
            return action.index.map { ws("movetoworkspacesilent", String($0)) } ?? []
        case .workspaceFocusGroup:
            return action.group.map { ws("workspace", String(($0 - 1) * per + 1)) } ?? []
        case .workspaceMoveGroup:
            return action.group.map { ws("movetoworkspace", String(($0 - 1) * per + 1)) } ?? []
        case .workspaceNext: return ws("workspace", "+1")
        case .workspacePrev: return ws("workspace", "-1")
        case .workspaceNextGroup: return ws("workspace", "+\(per)")
        case .workspacePrevGroup: return ws("workspace", "-\(per)")
        case .workspaceMoveToNext: return ws("movetoworkspace", "+1")
        case .workspaceMoveToPrev: return ws("movetoworkspace", "-1")
        case .workspaceMoveToSpecial:
            return ws("movetoworkspacesilent", "special:" + (action.name ?? "special"))
        case .workspaceMoveOutOfSpecial:
            return current.map { ws("movetoworkspacesilent", $0) } ?? []
        case .specialToggle:
            return [("togglespecialworkspace", ["name": .string(action.name ?? "special")])]
        case .windowFocus:
            return action.direction.map { [("movefocus", ["direction": .string($0.rawValue)])] } ?? []
        case .windowCycleNext: return [("cyclenext", [:])]
        case .windowCyclePrev: return [("cyclenext", ["step": .string("prev")])]
        case .windowSwap:
            return action.direction.map { [("swapwindow", ["direction": .string($0.rawValue)])] } ?? []
        case .windowResize:
            guard let axis = action.axis, let delta = action.delta else { return [] }
            let base = axis == .width ? area?.width ?? 1440 : area?.height ?? 900
            let points = (base * delta / 100).rounded()
            let size = axis == .width ? "\(Int(points)) 0" : "0 \(Int(points))"
            return [("resizeactive", ["size": .string(size)])]
        case .windowToggleFloat: return [("togglefloating", [:])]
        case .windowFullscreen, .windowMaximize: return [("fullscreen", [:])]
        case .windowPin: return [("setfloating", [:]), ("pin", [:])]
        case .windowCenter: return [("centerwindow", [:])]
        case .windowPseudo: return [("pseudo", [:])]
        case .layoutToggleSplit: return [("layoutmsg", ["message": .string("togglesplit")])]
        case .layoutSwapSplit: return [("layoutmsg", ["message": .string("swapsplit")])]
        case .windowNormalize:
            guard let area else { return [("setfloating", [:]), ("centerwindow", [:])] }
            let size = "exact \(Int((area.width * 0.55).rounded(.down))) \(Int((area.height * 0.7).rounded(.down)))"
            return [("setfloating", [:]), ("resizeactive", ["size": .string(size)]), ("centerwindow", [:])]
        case .windowPip:
            guard let area else { return [("setfloating", [:]), ("pin", [:])] }
            let width = (area.width * 0.25).rounded(), height = (width * 9 / 16).rounded()
            let x = Int(area.width - width - 20), y = Int(area.height - height - 20)
            return [("setfloating", [:]), ("resizeactive", ["size": .string("exact \(Int(width)) \(Int(height))")]),
                    ("moveactive", ["position": .string("exact \(x) \(y)")]), ("pin", [:])]
        case .windowClose: return [("killactive", [:])]
        case .groupMoveOut: return [("moveoutofgroup", [:])]
        case .groupNext: return [("changegroupactive", ["tab": .string("next")])]
        case .groupPrev: return [("changegroupactive", ["tab": .string("prev")])]
        case .groupToggle: return [("togglegroup", [:])]
        case .groupLock: return [("lockactivegroup", [:])]
        case .windowDrag, .windowResizeDrag: return []
        default: return nil
        }
    }
}
