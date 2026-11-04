import Foundation
import CaelestiaCore

/// The JSON type an IPC argument is expected to carry.
public enum IPCArgumentType: String, Codable, Sendable, CaseIterable {
    case string, int, double, bool, object, any

    /// Converts a value typed on the command line into the JSON form this type expects.
    /// Returns `nil` when the text cannot be converted.
    public func parse(_ text: String) -> JSONValue? {
        switch self {
        case .string, .any: return .string(text)
        case .int: return Int(text).map { .number(Double($0)) }
        case .double: return Double(text).map(JSONValue.number)
        case .bool: return JSONValue.string(text).lenientBoolValue.map(JSONValue.bool)
        case .object: return try? JSONValue.parse(text)
        }
    }
}

/// One named argument of an IPC command.
public struct IPCArgument: Hashable, Sendable, Codable {
    public var name: String
    public var type: IPCArgumentType
    public var required: Bool
    public var help: String

    public init(_ name: String, _ type: IPCArgumentType = .string, required: Bool = true, help: String = "") {
        self.name = name
        self.type = type
        self.required = required
        self.help = help
    }

    /// Shorthand for an optional argument.
    public static func optional(_ name: String, _ type: IPCArgumentType = .string, help: String = "") -> IPCArgument {
        IPCArgument(name, type, required: false, help: help)
    }
}

/// Broad grouping of commands, used by `caelestia help` and the schema document.
public enum IPCCommandGroup: String, Codable, Sendable, CaseIterable {
    case system, workspace, window, query, config, wm, shell, capture, misc, shellTarget
}

/// Human-readable description of one command: what it does, its arguments and its result.
public struct IPCCommandSpec: Hashable, Sendable {
    public var group: IPCCommandGroup
    public var summary: String
    public var arguments: [IPCArgument]
    /// Prose description of the `result` shape ("null", "bool", "array of WindowQueryEntry", ...).
    public var returns: String

    public init(_ group: IPCCommandGroup, _ summary: String, arguments: [IPCArgument] = [], returns: String = "null") {
        self.group = group
        self.summary = summary
        self.arguments = arguments
        self.returns = returns
    }

    /// Argument names in declaration order; the CLI maps positional values onto these.
    public var argumentNames: [String] { arguments.map(\.name) }
    public var requiredArguments: [IPCArgument] { arguments.filter(\.required) }
}

/// A Linux-shell IPC target (`caelestia shell <target> <fn>` on Arch). The Mac shell implements
/// every target and function in `Tests/fixtures/ref/ipc-commands.txt` under the same names.
public enum ShellTarget: String, CaseIterable, Sendable, Codable {
    case toaster, brightness, wallpaper, nexus, lock, notifs, picker, gameMode, drawers, idleInhibitor, mpris, audio, hypr

    /// The functions of this target in the order the Linux shell lists them.
    public var functions: [ShellFunction] {
        switch self {
        case .toaster:
            return [
                ShellFunction("error", ["title", "message", "icon"], returns: "void"),
                ShellFunction("warn", ["title", "message", "icon"], returns: "void"),
                ShellFunction("info", ["title", "message", "icon"], returns: "void"),
                ShellFunction("success", ["title", "message", "icon"], returns: "void"),
            ]
        case .brightness:
            return [
                ShellFunction("set", ["value"], returns: "string"),
                ShellFunction("get", [], returns: "real"),
                ShellFunction("getFor", ["query"], returns: "real"),
                ShellFunction("setFor", ["query", "value"], returns: "string"),
            ]
        case .wallpaper:
            return [
                ShellFunction("set", ["path"], returns: "void"),
                ShellFunction("get", [], returns: "string"),
                ShellFunction("list", [], returns: "string"),
            ]
        case .nexus:
            return [ShellFunction("open", [], returns: "void")]
        case .lock:
            return [
                ShellFunction("isLocked", [], returns: "bool"),
                ShellFunction("lock", [], returns: "void"),
                ShellFunction("unlock", [], returns: "void"),
            ]
        case .notifs:
            return [
                ShellFunction("toggleDnd", [], returns: "void"),
                ShellFunction("isDndEnabled", [], returns: "bool"),
                ShellFunction("clear", [], returns: "void"),
                ShellFunction("disableDnd", [], returns: "void"),
                ShellFunction("enableDnd", [], returns: "void"),
            ]
        case .picker:
            return [
                ShellFunction("openFreezeClip", [], returns: "void"),
                ShellFunction("openClip", [], returns: "void"),
                ShellFunction("open", [], returns: "void"),
                ShellFunction("openFreeze", [], returns: "void"),
            ]
        case .gameMode:
            return [
                ShellFunction("toggle", [], returns: "void"),
                ShellFunction("enable", [], returns: "void"),
                ShellFunction("isEnabled", [], returns: "bool"),
                ShellFunction("disable", [], returns: "void"),
            ]
        case .drawers:
            return [
                ShellFunction("toggle", ["drawer"], returns: "void"),
                ShellFunction("isOpen", ["drawer"], returns: "string"),
                ShellFunction("list", [], returns: "string"),
            ]
        case .idleInhibitor:
            return [
                ShellFunction("toggle", [], returns: "void"),
                ShellFunction("enable", [], returns: "void"),
                ShellFunction("isEnabled", [], returns: "bool"),
                ShellFunction("disable", [], returns: "void"),
            ]
        case .mpris:
            return [
                ShellFunction("next", [], returns: "void"),
                ShellFunction("stop", [], returns: "void"),
                ShellFunction("getActive", ["prop"], returns: "string"),
                ShellFunction("play", [], returns: "void"),
                ShellFunction("pause", [], returns: "void"),
                ShellFunction("playPause", [], returns: "void"),
                ShellFunction("previous", [], returns: "void"),
                ShellFunction("list", [], returns: "string"),
            ]
        case .audio:
            return [ShellFunction("cycleOutput", [], returns: "void")]
        case .hypr:
            return [
                ShellFunction("listSpecialWorkspaces", [], returns: "string"),
                ShellFunction("cycleSpecialWorkspace", ["direction"], returns: "void"),
                ShellFunction("refreshDevices", [], returns: "void"),
            ]
        }
    }

    /// Looks a function up by name (case-sensitive, as on Linux).
    public func function(named name: String) -> ShellFunction? {
        functions.first { $0.name == name }
    }

    /// Case-insensitive target lookup so `gamemode` and `gameMode` both work on the command line.
    public init?(cliName: String) {
        guard let t = ShellTarget.allCases.first(where: { $0.rawValue.lowercased() == cliName.lowercased() }) else { return nil }
        self = t
    }

    /// Every `target.function` pair as it appears in `ipc-commands.txt`, flattened.
    public static var allFunctions: [(target: ShellTarget, function: ShellFunction)] {
        allCases.flatMap { t in t.functions.map { (t, $0) } }
    }
}

/// One function of a shell target, with the Linux signature.
public struct ShellFunction: Hashable, Sendable {
    public var name: String
    /// Parameter names in call order; every parameter is a string on Linux.
    public var parameters: [String]
    /// Linux return type: `void`, `string`, `real` or `bool`.
    public var returns: String

    public init(_ name: String, _ parameters: [String], returns: String) {
        self.name = name
        self.parameters = parameters
        self.returns = returns
    }

    /// `fn(param: string, ...): ret`, as printed by the Linux `caelestia shell` help.
    public var signature: String {
        "\(name)(\(parameters.map { "\($0): string" }.joined(separator: ", "))): \(returns)"
    }

    /// The IPC spec derived from the Linux signature.
    public var spec: IPCCommandSpec {
        IPCCommandSpec(.shellTarget, "Shell IPC \(signature)", arguments: parameters.map { IPCArgument($0, .string) }, returns: returns == "void" ? "null" : (returns == "real" ? "number" : returns))
    }
}

/// Every command the WM understands over IPC. Raw values are the wire names.
///
/// Names mirror the Linux tools: `ws.*`/`window.*`/`query.*` replace `hyprctl dispatch` and
/// `hyprctl -j`, and `shell.<target>.<fn>` is the Caelestia shell IPC 1:1.
public enum IPCCommand: String, CaseIterable, Codable, Sendable, Hashable {
    // MARK: System
    case hello

    // MARK: Workspaces
    case wsFocus = "ws.focus"
    case wsMove = "ws.move"
    case wsToggleSpecial = "ws.toggleSpecial"

    // MARK: Windows
    case windowFocus = "window.focus"
    case windowMove = "window.move"
    case windowFloat = "window.float"
    case windowFullscreen = "window.fullscreen"
    case windowMaximize = "window.maximize"
    case windowPin = "window.pin"
    case windowClose = "window.close"
    case windowCenter = "window.center"

    /// Generic dispatcher: any `ActionKind` raw value with its arguments.
    case action

    // MARK: Queries (hyprctl -j)
    case queryWindows = "query.windows"
    case queryWorkspaces = "query.workspaces"
    case queryMonitors = "query.monitors"
    case queryBinds = "query.binds"
    case queryState = "query.state"
    case queryOverlays = "query.overlays"
    case debugOverlay = "debug.overlay"

    // MARK: Config
    case configReload = "config.reload"
    case rulesReload = "rules.reload"
    case keysList = "keys.list"

    // MARK: WM lifecycle / safety
    case wmPanic = "wm.panic"
    case wmRestoreAll = "wm.restoreAll"
    case wmQuit = "wm.quit"
    case permissionsStatus = "permissions.status"
    case doctor

    // MARK: Shell conveniences (`caelestia shell <panel>`)
    case shellLauncher = "shell.launcher"
    case shellDashboard = "shell.dashboard"
    case shellSidebar = "shell.sidebar"
    case shellSession = "shell.session"
    case shellShowAll = "shell.showall"
    case shellClearNotifs = "shell.clear-notifs"
    case shellKill = "shell.kill"
    case shellRestart = "shell.restart"

    // MARK: Capture and utilities
    case screenshot
    case record
    case clipboard
    case emoji
    case schemeSet = "scheme.set"
    case wallpaperRandom = "wallpaper.random"
    case notify
    case frameCalibrate = "frame.calibrate"

    // MARK: Shell targets (ipc-commands.txt, 1:1)
    case shellToasterError = "shell.toaster.error"
    case shellToasterWarn = "shell.toaster.warn"
    case shellToasterInfo = "shell.toaster.info"
    case shellToasterSuccess = "shell.toaster.success"
    case shellBrightnessSet = "shell.brightness.set"
    case shellBrightnessGet = "shell.brightness.get"
    case shellBrightnessGetFor = "shell.brightness.getFor"
    case shellBrightnessSetFor = "shell.brightness.setFor"
    case shellWallpaperSet = "shell.wallpaper.set"
    case shellWallpaperGet = "shell.wallpaper.get"
    case shellWallpaperList = "shell.wallpaper.list"
    case shellNexusOpen = "shell.nexus.open"
    case shellLockIsLocked = "shell.lock.isLocked"
    case shellLockLock = "shell.lock.lock"
    case shellLockUnlock = "shell.lock.unlock"
    case shellNotifsToggleDnd = "shell.notifs.toggleDnd"
    case shellNotifsIsDndEnabled = "shell.notifs.isDndEnabled"
    case shellNotifsClear = "shell.notifs.clear"
    case shellNotifsDisableDnd = "shell.notifs.disableDnd"
    case shellNotifsEnableDnd = "shell.notifs.enableDnd"
    case shellPickerOpenFreezeClip = "shell.picker.openFreezeClip"
    case shellPickerOpenClip = "shell.picker.openClip"
    case shellPickerOpen = "shell.picker.open"
    case shellPickerOpenFreeze = "shell.picker.openFreeze"
    case shellGameModeToggle = "shell.gameMode.toggle"
    case shellGameModeEnable = "shell.gameMode.enable"
    case shellGameModeIsEnabled = "shell.gameMode.isEnabled"
    case shellGameModeDisable = "shell.gameMode.disable"
    case shellDrawersToggle = "shell.drawers.toggle"
    case shellDrawersIsOpen = "shell.drawers.isOpen"
    case shellDrawersList = "shell.drawers.list"
    case shellIdleInhibitorToggle = "shell.idleInhibitor.toggle"
    case shellIdleInhibitorEnable = "shell.idleInhibitor.enable"
    case shellIdleInhibitorIsEnabled = "shell.idleInhibitor.isEnabled"
    case shellIdleInhibitorDisable = "shell.idleInhibitor.disable"
    case shellMprisNext = "shell.mpris.next"
    case shellMprisStop = "shell.mpris.stop"
    case shellMprisGetActive = "shell.mpris.getActive"
    case shellMprisPlay = "shell.mpris.play"
    case shellMprisPause = "shell.mpris.pause"
    case shellMprisPlayPause = "shell.mpris.playPause"
    case shellMprisPrevious = "shell.mpris.previous"
    case shellMprisList = "shell.mpris.list"
    case shellAudioCycleOutput = "shell.audio.cycleOutput"
    case shellHyprListSpecialWorkspaces = "shell.hypr.listSpecialWorkspaces"
    case shellHyprCycleSpecialWorkspace = "shell.hypr.cycleSpecialWorkspace"
    case shellHyprRefreshDevices = "shell.hypr.refreshDevices"

    /// The `(target, function)` pair for `shell.<target>.<fn>` commands, `nil` otherwise.
    public var shellFunction: (target: ShellTarget, function: ShellFunction)? {
        let parts = rawValue.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "shell", let target = ShellTarget(rawValue: parts[1]),
            let fn = target.function(named: parts[2])
        else { return nil }
        return (target, fn)
    }

    /// Resolves `shell.<target>.<fn>` from a target and function name.
    public static func shell(_ target: ShellTarget, _ function: String) -> IPCCommand? {
        IPCCommand(rawValue: "shell.\(target.rawValue).\(function)")
    }

    /// Commands grouped for help output, in catalog order.
    public static func commands(in group: IPCCommandGroup) -> [IPCCommand] {
        allCases.filter { $0.spec.group == group }
    }

    /// The documented schema of this command.
    public var spec: IPCCommandSpec {
        if let sf = shellFunction { return sf.function.spec }
        let direction = IPCArgument("direction", .string, help: "left | right | up | down")
        switch self {
        case .hello:
            return IPCCommandSpec(.system, "Handshake; answered by the server itself.", returns: "{version, protocolVersion, pid}")

        case .wsFocus:
            return IPCCommandSpec(.workspace, "Focus workspace N (1-based, across groups).", arguments: [IPCArgument("index", .int, help: "workspace number")])
        case .wsMove:
            return IPCCommandSpec(.workspace, "Move the focused window to workspace N and follow it (or stay with silent).", arguments: [IPCArgument("index", .int, help: "workspace number"), .optional("silent", .bool, help: "do not follow (movetoworkspacesilent)")])
        case .wsToggleSpecial:
            return IPCCommandSpec(.workspace, "Toggle a special workspace (scratchpad).", arguments: [.optional("name", .string, help: "special workspace name, default \"special\"")])

        case .windowFocus:
            return IPCCommandSpec(.window, "Move focus in a direction (movefocus).", arguments: [direction])
        case .windowMove:
            return IPCCommandSpec(.window, "Swap/move the focused window in a direction (movewindow).", arguments: [direction])
        case .windowFloat:
            return IPCCommandSpec(.window, "Toggle floating for the focused window.")
        case .windowFullscreen:
            return IPCCommandSpec(.window, "Toggle fullscreen (fullscreen 0) for the focused window.")
        case .windowMaximize:
            return IPCCommandSpec(.window, "Toggle maximize (fullscreen 1) for the focused window.")
        case .windowPin:
            return IPCCommandSpec(.window, "Toggle pin (visible on every workspace) for the focused floating window.")
        case .windowClose:
            return IPCCommandSpec(.window, "Close the focused window (killactive).")
        case .windowCenter:
            return IPCCommandSpec(.window, "Center the focused floating window.")

        case .action:
            return IPCCommandSpec(.wm, "Run any keymap action by name.", arguments: [IPCArgument("action", .string, help: "an ActionKind raw value, e.g. workspace.next"), .optional("args", .object, help: "action arguments")], returns: "null")

        case .queryWindows:
            return IPCCommandSpec(.query, "List managed windows (hyprctl clients).", returns: "array of WindowQueryEntry")
        case .queryWorkspaces:
            return IPCCommandSpec(.query, "List workspaces that exist (hyprctl workspaces).", returns: "array of WorkspaceQueryEntry")
        case .queryMonitors:
            return IPCCommandSpec(.query, "List displays (hyprctl monitors).", returns: "array of MonitorQueryEntry")
        case .queryBinds:
            return IPCCommandSpec(.query, "List active binds (hyprctl binds).", returns: "array of BindQueryEntry")
        case .queryOverlays:
            return IPCCommandSpec(.query, "Border overlay windows: target window, overlay window number, frame, alpha (Riko R2).", returns: "array of OverlayQueryEntry")
        case .debugOverlay:
            return IPCCommandSpec(.wm, "Show or hide the debug overlay (usable areas, target frames, counters).",
                                  arguments: [.optional("on", .bool, help: "true/false; toggles when omitted")], returns: "{on: bool}")
        case .queryState:
            return IPCCommandSpec(.query, "WM state summary: mode, focused window/workspace, counters.", returns: "StateQueryEntry")

        case .configReload:
            return IPCCommandSpec(.config, "Re-read config.toml and keymap.toml and apply them live.", returns: "{warnings: [string]}")
        case .rulesReload:
            return IPCCommandSpec(.config, "Re-read rules.toml and re-evaluate every window.", returns: "{warnings: [string]}")
        case .keysList:
            return IPCCommandSpec(.config, "Binds as the WM currently has them loaded.", returns: "array of BindQueryEntry")

        case .wmPanic:
            return IPCCommandSpec(.wm, "Panic: restore every window to a visible frame and stop managing.")
        case .wmRestoreAll:
            return IPCCommandSpec(.wm, "Bring every parked/off-screen window back on screen without quitting.")
        case .wmQuit:
            return IPCCommandSpec(.wm, "Restore windows and quit the WM.")
        case .permissionsStatus:
            return IPCCommandSpec(.wm, "TCC permission status as the WM sees it.", returns: "{accessibility, inputMonitoring, screenRecording, automation: bool|string}")
        case .doctor:
            return IPCCommandSpec(.wm, "WM-side diagnostics (mode, permissions, displays, counters).", returns: "object")

        case .shellLauncher: return IPCCommandSpec(.shell, "Toggle the launcher.")
        case .shellDashboard: return IPCCommandSpec(.shell, "Toggle the dashboard.")
        case .shellSidebar: return IPCCommandSpec(.shell, "Toggle the sidebar.")
        case .shellSession: return IPCCommandSpec(.shell, "Toggle the session menu.")
        case .shellShowAll: return IPCCommandSpec(.shell, "Show all panels.")
        case .shellClearNotifs: return IPCCommandSpec(.shell, "Clear all notifications.")
        case .shellKill: return IPCCommandSpec(.shell, "Hide the shell UI (bar and panels) until restart.")
        case .shellRestart: return IPCCommandSpec(.shell, "Restart the shell UI.")

        case .screenshot:
            return IPCCommandSpec(.capture, "Take a screenshot.", arguments: [.optional("mode", .string, help: "region (default) | freeze | full")], returns: "{path}")
        case .record:
            return IPCCommandSpec(.capture, "Start/stop the screen recorder.", arguments: [.optional("sound", .bool, help: "capture system audio"), .optional("region", .bool, help: "pick a region")], returns: "{recording: bool, path?}")
        case .clipboard:
            return IPCCommandSpec(.misc, "Open clipboard history (or delete mode).", arguments: [.optional("delete", .bool, help: "open in delete mode")])
        case .emoji:
            return IPCCommandSpec(.misc, "Open the emoji picker.")
        case .schemeSet:
            return IPCCommandSpec(.misc, "Switch the colour scheme.", arguments: [IPCArgument("name", .string, help: "scheme name, e.g. caelestia-dynamic")])
        case .wallpaperRandom:
            return IPCCommandSpec(.misc, "Pick a random wallpaper from the configured folder.", returns: "{path}")
        case .frameCalibrate:
            return IPCCommandSpec(.shell, "Tune the screen frame's outer corner radius by eye (arrow keys, Return saves per display, Esc cancels).",
                                  arguments: [.optional("display", .string, help: "display id or name (default: the one under the pointer)")],
                                  returns: "{display, radius}")
        case .notify:
            return IPCCommandSpec(.misc, "Post a notification to the sidebar.", arguments: [IPCArgument("title", .string), .optional("body", .string), .optional("app", .string, help: "app name shown as the sender"), .optional("icon", .string, help: "SF Symbol or Material icon name")], returns: "{id}")

        case .shellToasterError, .shellToasterWarn, .shellToasterInfo, .shellToasterSuccess,
            .shellBrightnessSet, .shellBrightnessGet, .shellBrightnessGetFor, .shellBrightnessSetFor,
            .shellWallpaperSet, .shellWallpaperGet, .shellWallpaperList, .shellNexusOpen,
            .shellLockIsLocked, .shellLockLock, .shellLockUnlock,
            .shellNotifsToggleDnd, .shellNotifsIsDndEnabled, .shellNotifsClear, .shellNotifsDisableDnd, .shellNotifsEnableDnd,
            .shellPickerOpenFreezeClip, .shellPickerOpenClip, .shellPickerOpen, .shellPickerOpenFreeze,
            .shellGameModeToggle, .shellGameModeEnable, .shellGameModeIsEnabled, .shellGameModeDisable,
            .shellDrawersToggle, .shellDrawersIsOpen, .shellDrawersList,
            .shellIdleInhibitorToggle, .shellIdleInhibitorEnable, .shellIdleInhibitorIsEnabled, .shellIdleInhibitorDisable,
            .shellMprisNext, .shellMprisStop, .shellMprisGetActive, .shellMprisPlay, .shellMprisPause, .shellMprisPlayPause, .shellMprisPrevious, .shellMprisList,
            .shellAudioCycleOutput,
            .shellHyprListSpecialWorkspaces, .shellHyprCycleSpecialWorkspace, .shellHyprRefreshDevices:
            // Unreachable: every shell.<target>.<fn> case is resolved through `shellFunction` above.
            // Kept exhaustive so adding a case without a table entry is a compile-time error.
            return IPCCommandSpec(.shellTarget, "Shell IPC \(rawValue)")
        }
    }

    /// The keymap action a simple WM command corresponds to, when there is a 1:1 mapping. The
    /// WM can route these through its normal action dispatcher.
    public var equivalentAction: ActionKind? {
        switch self {
        case .wsFocus: return .workspaceFocus
        case .wsToggleSpecial: return .specialToggle
        case .windowFocus: return .windowFocus
        case .windowMove: return .windowSwap
        case .windowFloat: return .windowToggleFloat
        case .windowFullscreen: return .windowFullscreen
        case .windowMaximize: return .windowMaximize
        case .windowPin: return .windowPin
        case .windowClose: return .windowClose
        case .windowCenter: return .windowCenter
        case .shellLauncher: return .launcherToggle
        case .shellDashboard: return .dashboardToggle
        case .shellSidebar: return .sidebarToggle
        case .shellSession: return .sessionToggle
        case .shellShowAll: return .panelsShowAll
        case .shellClearNotifs, .shellNotifsClear: return .notifsClear
        case .shellKill: return .shellKill
        case .shellRestart: return .shellRestart
        case .shellLockLock: return .lock
        case .emoji: return .emojiOpen
        case .wmPanic: return .wmPanic
        case .shellPickerOpen: return .pickerColor
        case .shellMprisPlayPause: return .mediaPlayPause
        case .shellMprisNext: return .mediaNext
        case .shellMprisPrevious: return .mediaPrev
        case .shellMprisStop: return .mediaStop
        default: return nil
        }
    }
}
