import Foundation

/// Every action a bind, IPC command or CLI verb can trigger. Names mirror Hyprland dispatchers and
/// Caelestia IPC targets. The WM switches over this enum; nothing else hard-codes chords.
public enum ActionKind: String, Codable, Sendable, CaseIterable {
    // Shell
    case launcherToggle = "launcher.toggle"
    case sessionToggle = "session.toggle"
    case sidebarToggle = "sidebar.toggle"
    case dashboardToggle = "dashboard.toggle"
    case panelsShowAll = "panels.showAll"
    case notifsClear = "notifs.clear"
    case lock = "lock"
    case shellRestoreLock = "shell.restoreLock"
    case shellKill = "shell.kill"
    case shellRestart = "shell.restart"

    // Workspaces
    case workspaceFocus = "workspace.focus"  // index
    case workspaceMove = "workspace.move"  // index (move window and follow)
    case workspaceMoveSilent = "workspace.moveSilent"  // index
    case workspaceFocusGroup = "workspace.focusGroup"  // group
    case workspaceMoveGroup = "workspace.moveGroup"  // group
    case workspaceNext = "workspace.next"
    case workspacePrev = "workspace.prev"
    case workspaceNextGroup = "workspace.nextGroup"
    case workspacePrevGroup = "workspace.prevGroup"
    case workspaceMoveToNext = "workspace.moveToNext"
    case workspaceMoveToPrev = "workspace.moveToPrev"
    case workspaceMoveToSpecial = "workspace.moveToSpecial"  // name (default "special")
    case workspaceMoveOutOfSpecial = "workspace.moveOutOfSpecial"
    case specialToggle = "special.toggle"  // name

    // Windows and groups
    case windowCycleNext = "window.cycleNext"
    case windowCyclePrev = "window.cyclePrev"
    case groupNext = "group.next"
    case groupPrev = "group.prev"
    case groupToggle = "group.toggle"
    case groupMoveOut = "group.moveOut"
    case groupLock = "group.lock"
    case windowFocus = "window.focus"  // direction
    case windowSwap = "window.swap"  // direction
    case windowResize = "window.resize"  // axis: width|height, delta
    case windowDrag = "window.drag"  // mouse flag
    case windowResizeDrag = "window.resizeDrag"  // mouse flag
    case windowCenter = "window.center"
    case windowPseudo = "window.pseudo"
    case layoutToggleSplit = "layout.toggleSplit"
    case layoutSwapSplit = "layout.swapSplit"
    case windowNormalize = "window.normalize"
    case windowPip = "window.pip"
    case windowPin = "window.pin"
    case windowFullscreen = "window.fullscreen"
    case windowMaximize = "window.maximize"
    case windowToggleFloat = "window.toggleFloat"
    case windowClose = "window.close"

    // Apps
    case appTerminal = "app.terminal"
    case appBrowser = "app.browser"
    case appEditor = "app.editor"
    case appFiles = "app.files"
    case appAudioSettings = "app.audioSettings"
    case exec = "exec"  // cmd

    // Capture
    case captureRegion = "capture.region"
    case captureFull = "capture.full"
    case captureFreeze = "capture.freeze"
    case recordScreen = "record.screen"
    case recordSound = "record.sound"
    case recordRegion = "record.region"
    case pickerColor = "picker.color"

    // Media / volume / brightness
    case brightnessUp = "brightness.up"
    case brightnessDown = "brightness.down"
    case mediaPlayPause = "media.playPause"
    case mediaNext = "media.next"
    case mediaPrev = "media.prev"
    case mediaStop = "media.stop"
    case audioToggleMute = "audio.toggleMute"
    case audioToggleMicMute = "audio.toggleMicMute"
    case audioVolumeUp = "audio.volumeUp"
    case audioVolumeDown = "audio.volumeDown"
    case osdLockKey = "osd.lockKey"  // key: caps|num

    // Session / utilities
    case systemSleep = "system.sleep"
    case clipboardOpen = "clipboard.open"
    case clipboardDelete = "clipboard.delete"
    case clipboardTypeLatest = "clipboard.typeLatest"
    case emojiOpen = "emoji.open"
    case notifyTest = "notify.test"

    // Safety (fixed chord ⌃⌥⌘⇧Esc, not configurable away)
    case wmPanic = "wm.panic"

    /// Actions that are meaningful on the lock screen (Hyprland `locked` flag) where macOS allows it.
    public var allowedWhileLocked: Bool {
        switch self {
        case .brightnessUp, .brightnessDown, .mediaPlayPause, .mediaNext, .mediaPrev, .mediaStop,
            .audioToggleMute, .audioToggleMicMute, .audioVolumeUp, .audioVolumeDown, .osdLockKey:
            return true
        default:
            return false
        }
    }

    /// Argument names each action accepts (validated by the keymap parser).
    public var argumentNames: [String] {
        switch self {
        case .workspaceFocus, .workspaceMove, .workspaceMoveSilent: return ["index"]
        case .workspaceFocusGroup, .workspaceMoveGroup: return ["group"]
        case .workspaceMoveToSpecial, .specialToggle: return ["name"]
        case .windowFocus, .windowSwap: return ["direction"]
        case .windowResize: return ["axis", "delta"]
        case .exec: return ["cmd"]
        case .osdLockKey: return ["key"]
        default: return []
        }
    }

    public var requiredArgumentNames: [String] {
        switch self {
        case .workspaceMoveToSpecial, .specialToggle: return []
        default: return argumentNames
        }
    }
}

/// A scalar bind argument (TOML inline table values).
public enum ArgValue: Hashable, Sendable, Codable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public var description: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        case .bool: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s): return Double(s)
        case .bool: return nil
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

/// A fully specified action: kind + arguments.
public struct Action: Hashable, Sendable, Codable, CustomStringConvertible {
    public var kind: ActionKind
    public var args: [String: ArgValue]

    public init(_ kind: ActionKind, args: [String: ArgValue] = [:]) {
        self.kind = kind
        self.args = args
    }

    public init(_ kind: ActionKind, index: Int) { self.init(kind, args: ["index": .int(index)]) }
    public init(_ kind: ActionKind, group: Int) { self.init(kind, args: ["group": .int(group)]) }
    public init(_ kind: ActionKind, direction: Direction) { self.init(kind, args: ["direction": .string(direction.rawValue)]) }
    public init(_ kind: ActionKind, name: String) { self.init(kind, args: ["name": .string(name)]) }

    public var index: Int? { args["index"]?.intValue }
    public var group: Int? { args["group"]?.intValue }
    public var name: String? { args["name"]?.stringValue }
    public var direction: Direction? { args["direction"]?.stringValue.flatMap(Direction.init(rawValue:)) }
    public var axis: ResizeAxis? { args["axis"]?.stringValue.flatMap(ResizeAxis.init(rawValue:)) }
    public var delta: Double? { args["delta"]?.doubleValue }
    public var cmd: String? { args["cmd"]?.stringValue }
    public var key: String? { args["key"]?.stringValue }

    public var description: String {
        if args.isEmpty { return kind.rawValue }
        let a = args.keys.sorted().map { "\($0)=\(args[$0]!)" }.joined(separator: ", ")
        return "\(kind.rawValue)(\(a))"
    }
}

public enum ResizeAxis: String, Codable, Sendable {
    case width, height
}

/// Hyprland bind flags.
public enum BindFlag: String, Codable, Sendable, CaseIterable, Hashable {
    /// Fire on key release.
    case release
    /// Auto-repeat while held (repeat delay / rate from InputConfig).
    case `repeat`
    /// Also works while the screen is locked (media/volume/brightness only).
    case locked
    /// Mouse drag bind (⌥L+drag).
    case mouse
}

/// One `[[bind]]` entry from keymap.toml.
public struct Bind: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    /// Chords as written ("SUPER + 1", "SUPER + mouse:272", "SUPER" for the tap).
    public var keys: [String]
    public var action: Action
    public var flags: Set<BindFlag>
    /// The original Hyprland bind text, for the mapping doc and the coverage test.
    public var linux: String?
    public var description: String
    public var enabled: Bool
    /// Parsed chords (filled by the parser; one per `keys` entry, in order).
    public var chords: [KeyChord]

    public init(
        id: String, keys: [String], action: Action, flags: Set<BindFlag> = [], linux: String? = nil,
        description: String = "", enabled: Bool = true, chords: [KeyChord] = []
    ) {
        self.id = id
        self.keys = keys
        self.action = action
        self.flags = flags
        self.linux = linux
        self.description = description
        self.enabled = enabled
        self.chords = chords
    }
}

/// The parsed keymap: modifier map + binds.
public struct Keymap: Equatable, Sendable, Codable {
    public var modifiers: ModifierMap
    public var binds: [Bind]

    public init(modifiers: ModifierMap, binds: [Bind]) {
        self.modifiers = modifiers
        self.binds = binds
    }

    /// Binds indexed by chord (a chord can map to several binds only when one of them is disabled;
    /// the conflict checker reports duplicates among enabled binds).
    public var bindsByChord: [KeyChord: [Bind]] {
        var m: [KeyChord: [Bind]] = [:]
        for b in binds where b.enabled {
            for c in b.chords { m[c, default: []].append(b) }
        }
        return m
    }

    public func bind(id: String) -> Bind? { binds.first { $0.id == id } }
}
