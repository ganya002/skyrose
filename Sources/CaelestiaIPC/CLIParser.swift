import Foundation
import CaelestiaCore

/// Commands the `skyrose` binary handles in-process (no WM needed).
public enum CLILocalCommand: Equatable, Sendable {
    /// `keys check`: conflict checker on the user keymap.
    case keysCheck
    /// `keys list`: table of every bind in the user keymap.
    case keysList
    /// `doctor`: environment, permissions, versions, conflicts.
    case doctor
    /// `uninstall`: run scripts/uninstall.sh or print the manual steps.
    case uninstall
    /// `shell -d`: launch the WM app and wait for its socket.
    case shellStart
    /// `shell help [target]`: print the Linux shell IPC targets and signatures.
    case shellTargets(String?)
    /// `migrate`: move a pre-rename Caelestia for Mac install to the SkyRose locations.
    case migrate
    /// `settings` / `onboarding`: open SkyRose Settings (at the onboarding).
    case openSettings(onboarding: Bool)
    /// `cursor list | status | set <cape> | reset`: the session cursor theme (works without the WM).
    case cursor(CursorVerb)
    /// `kitty status | install | uninstall`: the SkyRose kitty profile (works without the WM).
    case kitty(KittyVerb)
    /// `fonts status | download | install | uninstall`: the Arch font pack.
    case fonts(FontsVerb)
    /// `sa status | load-command | reset`: the SIP-off scripting addition in the Dock.
    case sa(SAVerb)
}

public enum SAVerb: String, Equatable, Sendable {
    case status
    case loadCommand = "load-command"
    case reset
}

public enum FontsVerb: String, Equatable, Sendable {
    case status, download, install, uninstall
}

public enum KittyVerb: String, Equatable, Sendable {
    case status, install, uninstall
}

public enum CursorVerb: Equatable, Sendable {
    case list, status, reset
    case set(String)
}

/// What a parsed command line asks the CLI to do.
public struct CLIInvocation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Send the request to the WM and print its result.
        case ipc(IPCRequest)
        /// Handle inside the CLI process.
        case local(CLILocalCommand)
        /// Print usage (for a topic, or everything).
        case help(topic: String?)
        /// Print versions.
        case version
    }

    public var kind: Kind
    /// `--json`: print raw JSON instead of tables.
    public var json: Bool = false
    /// `--socket PATH`: talk to a different socket (tests, several users).
    public var socketPath: String?
    /// `--timeout SECONDS`: per-request timeout.
    public var timeout: TimeInterval?
    /// `--yes`: skip confirmations (uninstall).
    public var yes: Bool = false

    public init(kind: Kind, json: Bool = false, socketPath: String? = nil, timeout: TimeInterval? = nil, yes: Bool = false) {
        self.kind = kind
        self.json = json
        self.socketPath = socketPath
        self.timeout = timeout
        self.yes = yes
    }

    /// The IPC request when `kind` is `.ipc`.
    public var request: IPCRequest? {
        if case .ipc(let r) = kind { return r }
        return nil
    }
}

/// Command-line mistakes; the CLI prints `errorDescription` plus the relevant usage and exits 3.
public enum CLIUsageError: Error, Equatable, Sendable, LocalizedError {
    case unknownCommand(String)
    case unknownVerb(group: String, verb: String, expected: [String])
    case missingArgument(command: String, name: String)
    case invalidArgument(command: String, name: String, value: String, expected: String)
    case unexpectedArgument(command: String, value: String)
    case unknownOption(String)
    case optionNeedsValue(String)

    public var errorDescription: String? {
        switch self {
        case .unknownCommand(let c):
            return "Unknown command '\(c)'."
        case .unknownVerb(let g, let v, let expected):
            return "Unknown '\(g)' subcommand '\(v)'. Expected one of: \(expected.joined(separator: ", "))."
        case .missingArgument(let c, let n):
            return "'\(c)' needs <\(n)>."
        case .invalidArgument(let c, let n, let v, let e):
            return "'\(c)': invalid \(n) '\(v)' (expected \(e))."
        case .unexpectedArgument(let c, let v):
            return "'\(c)': unexpected argument '\(v)'."
        case .unknownOption(let o):
            return "Unknown option '\(o)'."
        case .optionNeedsValue(let o):
            return "Option '\(o)' needs a value."
        }
    }

    /// The help topic that best explains the mistake.
    public var topic: String? {
        switch self {
        case .unknownCommand, .unknownOption, .optionNeedsValue: return nil
        case .unknownVerb(let g, _, _): return g
        case .missingArgument(let c, _), .invalidArgument(let c, _, _, _), .unexpectedArgument(let c, _):
            return c.split(separator: " ").first.map(String.init)
        }
    }
}

/// Parses `skyrose <group> <verb> [args] [options]` (spec 4.8) into a `CLIInvocation`.
/// No third-party argument parser: the grammar is small and fixed.
public enum CLIParser {
    public static let programName = "skyrose"

    /// Options that take a value.
    static let valueOptions: Set<String> = ["--socket", "--timeout", "--app", "--icon"]
    /// Boolean options (long and short).
    static let flagOptions: Set<String> = ["--json", "--silent", "--yes", "-y", "-s", "-r", "-d", "--help", "-h", "--version", "-v", "--sound", "--region", "--delete"]

    struct Tokens {
        var positionals: [String] = []
        var flags: Set<String> = []
        var options: [String: String] = [:]

        func has(_ names: String...) -> Bool { names.contains { flags.contains($0) } }
    }

    // MARK: - Entry point

    public static func parse(_ argv: [String]) throws -> CLIInvocation {
        let tokens = try tokenize(argv)
        var inv = CLIInvocation(kind: .help(topic: nil))
        inv.json = tokens.has("--json")
        inv.yes = tokens.has("--yes", "-y")
        inv.socketPath = tokens.options["--socket"]
        if let t = tokens.options["--timeout"] {
            guard let seconds = TimeInterval(t), seconds > 0 else {
                throw CLIUsageError.invalidArgument(command: "--timeout", name: "seconds", value: t, expected: "a positive number")
            }
            inv.timeout = seconds
        }

        if tokens.has("--version", "-v") {
            inv.kind = .version
            return inv
        }
        var args = tokens.positionals
        guard !args.isEmpty else {
            inv.kind = .help(topic: nil)
            return inv
        }
        let group = args.removeFirst()
        if tokens.has("--help", "-h") || group == "help" {
            let topic = group == "help" ? args.first : group
            inv.kind = .help(topic: topic)
            return inv
        }

        switch group {
        case "ws", "workspace":
            inv.kind = try parseWorkspace(args, tokens)
        case "window", "win":
            inv.kind = try parseWindow(args, tokens)
        case "shell":
            inv.kind = try parseShell(args, tokens)
        case "screenshot":
            inv.kind = try parseScreenshot(args, tokens)
        case "record":
            try rejectExtra("record", args)
            inv.kind = .ipc(IPCRequest(.record, args: [
                "sound": .bool(tokens.has("-s", "--sound")),
                "region": .bool(tokens.has("-r", "--region")),
            ]))
        case "clipboard":
            try rejectExtra("clipboard", args)
            inv.kind = .ipc(IPCRequest(.clipboard, args: ["delete": .bool(tokens.has("-d", "--delete"))]))
        case "emoji":
            try rejectExtra("emoji", args)
            inv.kind = .ipc(IPCRequest(.emoji))
        case "picker":
            try rejectExtra("picker", args)
            inv.kind = .ipc(IPCRequest(.shellPickerOpen))
        case "scheme":
            inv.kind = try parseScheme(args)
        case "wallpaper":
            inv.kind = try parseWallpaper(args)
        case "frame":
            guard let verb = args.first else { throw CLIUsageError.missingArgument(command: "frame", name: "calibrate") }
            guard verb == "calibrate" else { throw CLIUsageError.unknownVerb(group: "frame", verb: verb, expected: ["calibrate"]) }
            // The display may be a name with spaces ("Built-in Retina Display").
            let display = args.dropFirst().joined(separator: " ")
            inv.kind = .ipc(display.isEmpty ? IPCRequest(.frameCalibrate) : IPCRequest(.frameCalibrate, args: ["display": .string(display)]))
        case "keys":
            inv.kind = try parseKeys(args)
        case "rules":
            try expectVerb("rules", args, ["reload", "apps", "set", "focused"])
            switch args[0] {
            case "apps":
                try rejectExtra("rules apps", Array(args.dropFirst()))
                inv.kind = .ipc(IPCRequest(.rulesApps))
            case "focused":
                try rejectExtra("rules focused", Array(args.dropFirst()))
                inv.kind = .ipc(IPCRequest(.rulesFocused))
            case "set":
                guard args.count >= 2 else { throw CLIUsageError.missingArgument(command: "rules set", name: "bundle-id") }
                guard args.count >= 3 else { throw CLIUsageError.missingArgument(command: "rules set", name: "tile|float|auto") }
                let mode = args[2].lowercased()
                guard AppLayoutMode(rawValue: mode) != nil else {
                    throw CLIUsageError.unknownVerb(group: "rules set \(args[1])", verb: args[2], expected: AppLayoutMode.allCases.map(\.rawValue))
                }
                try rejectExtra("rules set", Array(args.dropFirst(3)))
                inv.kind = .ipc(IPCRequest(.rulesSet, args: ["bundleID": .string(args[1]), "mode": .string(mode)]))
            default:
                try rejectExtra("rules reload", Array(args.dropFirst()))
                inv.kind = .ipc(IPCRequest(.rulesReload))
            }
        case "config":
            try expectVerb("config", args, ["reload", "get", "set", "reset"])
            switch args[0] {
            case "get":
                try rejectExtra("config get", Array(args.dropFirst(2)))
                inv.kind = .ipc(args.count >= 2 ? IPCRequest(.configGet, args: ["path": .string(args[1])]) : IPCRequest(.configGet))
            case "set":
                guard args.count >= 2 else { throw CLIUsageError.missingArgument(command: "config set", name: "table.key") }
                guard args.count >= 3 else { throw CLIUsageError.missingArgument(command: "config set \(args[1])", name: "value") }
                // The value may contain spaces (a command line for apps.terminal).
                let value = args.dropFirst(2).joined(separator: " ")
                inv.kind = .ipc(IPCRequest(.configSet, args: ["path": .string(args[1]), "value": CLIParser.configValue(value)]))
            case "reset":
                guard args.count >= 2 else { throw CLIUsageError.missingArgument(command: "config reset", name: "table.key") }
                try rejectExtra("config reset", Array(args.dropFirst(2)))
                inv.kind = .ipc(IPCRequest(.configReset, args: ["path": .string(args[1])]))
            default:
                try rejectExtra("config reload", Array(args.dropFirst()))
                inv.kind = .ipc(IPCRequest(.configReload))
            }
        case "query", "q":
            inv.kind = try parseQuery(args)
        case "notify":
            inv.kind = try parseNotify(args, tokens)
        case "action", "dispatch":
            inv.kind = try parseAction(args)
        case "wm":
            inv.kind = try parseWM(args)
        case "debug":
            inv.kind = try parseDebug(args)
        case "permissions":
            try expectVerb("permissions", args, ["status", "request"])
            if args[0] == "request" {
                let kinds = ["accessibility", "inputMonitoring", "screenRecording"]
                guard args.count >= 2 else { throw CLIUsageError.missingArgument(command: "permissions request", name: kinds.joined(separator: "|")) }
                guard kinds.contains(args[1]) else { throw CLIUsageError.unknownVerb(group: "permissions request", verb: args[1], expected: kinds) }
                try rejectExtra("permissions request", Array(args.dropFirst(2)))
                inv.kind = .ipc(IPCRequest(.permissionsRequest, args: ["kind": .string(args[1])]))
            } else {
                try rejectExtra("permissions status", Array(args.dropFirst()))
                inv.kind = .ipc(IPCRequest(.permissionsStatus))
            }
        case "migrate":
            try rejectExtra("migrate", args)
            inv.kind = .local(.migrate)
        case "settings":
            try rejectExtra("settings", args)
            inv.kind = .local(.openSettings(onboarding: false))
        case "onboarding":
            try rejectExtra("onboarding", args)
            inv.kind = .local(.openSettings(onboarding: true))
        case "doctor":
            try rejectExtra("doctor", args)
            inv.kind = .local(.doctor)
        case "uninstall":
            try rejectExtra("uninstall", args)
            inv.kind = .local(.uninstall)
        case "cursor":
            let verb = args.first ?? "status"
            switch verb {
            case "list", "status", "reset":
                try rejectExtra("cursor \(verb)", Array(args.dropFirst()))
                inv.kind = .local(.cursor(verb == "list" ? .list : verb == "status" ? .status : .reset))
            case "set":
                guard args.count >= 2 else { throw CLIUsageError.missingArgument(command: "cursor set", name: "cape identifier | default") }
                try rejectExtra("cursor set", Array(args.dropFirst(2)))
                inv.kind = .local(.cursor(.set(args[1])))
            default:
                throw CLIUsageError.unknownVerb(group: "cursor", verb: verb, expected: ["list", "status", "set", "reset"])
            }
        case "fonts":
            let verb = args.first ?? "status"
            guard let v = FontsVerb(rawValue: verb) else {
                throw CLIUsageError.unknownVerb(group: "fonts", verb: verb, expected: ["status", "download", "install", "uninstall"])
            }
            try rejectExtra("fonts \(verb)", Array(args.dropFirst()))
            inv.kind = .local(.fonts(v))
        case "kitty":
            let verb = args.first ?? "status"
            guard let v = KittyVerb(rawValue: verb) else {
                throw CLIUsageError.unknownVerb(group: "kitty", verb: verb, expected: ["status", "install", "uninstall"])
            }
            try rejectExtra("kitty \(verb)", Array(args.dropFirst()))
            inv.kind = .local(.kitty(v))
        case "sa":
            let verb = args.first ?? "status"
            guard let v = SAVerb(rawValue: verb) else {
                throw CLIUsageError.unknownVerb(group: "sa", verb: verb, expected: ["status", "load-command", "reset"])
            }
            try rejectExtra("sa \(verb)", Array(args.dropFirst()))
            inv.kind = .local(.sa(v))
        case "version":
            try rejectExtra("version", args)
            inv.kind = .version
        default:
            throw CLIUsageError.unknownCommand(group)
        }
        return inv
    }

    // MARK: - Tokenizer

    static func tokenize(_ argv: [String]) throws -> Tokens {
        var t = Tokens()
        var i = 0
        var literal = false
        while i < argv.count {
            let a = argv[i]
            i += 1
            if literal || !a.hasPrefix("-") || a == "-" || a.hasPrefix("-") && Int(a) != nil && !flagOptions.contains(a) {
                t.positionals.append(a)
                continue
            }
            if a == "--" {
                literal = true
                continue
            }
            if a.hasPrefix("--") {
                if let eq = a.firstIndex(of: "=") {
                    let name = String(a[..<eq])
                    guard valueOptions.contains(name) else { throw CLIUsageError.unknownOption(name) }
                    t.options[name] = String(a[a.index(after: eq)...])
                } else if valueOptions.contains(a) {
                    guard i < argv.count else { throw CLIUsageError.optionNeedsValue(a) }
                    t.options[a] = argv[i]
                    i += 1
                } else if flagOptions.contains(a) {
                    t.flags.insert(a)
                } else {
                    throw CLIUsageError.unknownOption(a)
                }
                continue
            }
            // Short flags, possibly combined (-sr).
            for ch in a.dropFirst() {
                let flag = "-\(ch)"
                guard flagOptions.contains(flag) else { throw CLIUsageError.unknownOption(flag) }
                t.flags.insert(flag)
            }
        }
        return t
    }

    // MARK: - Groups

    static func parseWorkspace(_ args: [String], _ tokens: Tokens) throws -> CLIInvocation.Kind {
        let verbs = ["focus", "move", "toggle-special"]
        guard let verb = args.first else { throw CLIUsageError.missingArgument(command: "ws", name: "focus|move|toggle-special") }
        let rest = Array(args.dropFirst())
        switch verb {
        case "focus":
            guard let target = rest.first else { throw CLIUsageError.missingArgument(command: "ws focus", name: "workspace") }
            try rejectExtra("ws focus", Array(rest.dropFirst()))
            switch target {
            case "next", "+1": return .ipc(IPCRequest(.action, args: ["action": .string(ActionKind.workspaceNext.rawValue)]))
            case "prev", "previous", "-1": return .ipc(IPCRequest(.action, args: ["action": .string(ActionKind.workspacePrev.rawValue)]))
            default:
                let index = try int("ws focus", "workspace", target)
                return .ipc(IPCRequest(.wsFocus, args: ["index": .number(Double(index))]))
            }
        case "move":
            guard let target = rest.first else { throw CLIUsageError.missingArgument(command: "ws move", name: "workspace") }
            try rejectExtra("ws move", Array(rest.dropFirst()))
            let index = try int("ws move", "workspace", target)
            return .ipc(IPCRequest(.wsMove, args: ["index": .number(Double(index)), "silent": .bool(tokens.has("--silent"))]))
        case "toggle-special", "special":
            try rejectExtra("ws toggle-special", Array(rest.dropFirst()))
            var a: [String: JSONValue] = [:]
            if let name = rest.first { a["name"] = .string(name) }
            return .ipc(IPCRequest(.wsToggleSpecial, args: a))
        default:
            throw CLIUsageError.unknownVerb(group: "ws", verb: verb, expected: verbs)
        }
    }

    static func parseWindow(_ args: [String], _ tokens: Tokens) throws -> CLIInvocation.Kind {
        let simple: [String: IPCCommand] = [
            "float": .windowFloat, "fullscreen": .windowFullscreen, "maximize": .windowMaximize,
            "pin": .windowPin, "close": .windowClose, "center": .windowCenter,
            "pseudo": .windowPseudo, "togglesplit": .windowToggleSplit, "swapsplit": .windowSwapSplit,
        ]
        let verbs = ["focus", "move"] + simple.keys.sorted()
        guard let verb = args.first else { throw CLIUsageError.missingArgument(command: "window", name: verbs.joined(separator: "|")) }
        let rest = Array(args.dropFirst())
        switch verb {
        case "focus", "move":
            let command = verb == "focus" ? IPCCommand.windowFocus : .windowMove
            guard let dir = rest.first else { throw CLIUsageError.missingArgument(command: "window \(verb)", name: "left|right|up|down") }
            try rejectExtra("window \(verb)", Array(rest.dropFirst()))
            let direction = try self.direction("window \(verb)", dir)
            return .ipc(IPCRequest(command, args: ["direction": .string(direction.rawValue)]))
        default:
            guard let command = simple[verb] else { throw CLIUsageError.unknownVerb(group: "window", verb: verb, expected: verbs) }
            try rejectExtra("window \(verb)", rest)
            return .ipc(IPCRequest(command))
        }
    }

    static func parseShell(_ args: [String], _ tokens: Tokens) throws -> CLIInvocation.Kind {
        if tokens.has("-d") {
            try rejectExtra("shell -d", args)
            return .local(.shellStart)
        }
        let panels: [String: IPCCommand] = [
            "launcher": .shellLauncher, "dashboard": .shellDashboard, "sidebar": .shellSidebar, "session": .shellSession,
            "showall": .shellShowAll, "clear-notifs": .shellClearNotifs, "kill": .shellKill, "restart": .shellRestart,
        ]
        guard let verb = args.first else {
            throw CLIUsageError.missingArgument(command: "shell", name: "-d|launcher|dashboard|sidebar|session|lock|showall|clear-notifs|kill|restart|<target> <fn>")
        }
        let rest = Array(args.dropFirst())
        if verb == "help" || verb == "list" {
            try rejectExtra("shell help", Array(rest.dropFirst()))
            return .local(.shellTargets(rest.first))
        }
        if verb == "lock", rest.isEmpty {
            return .ipc(IPCRequest(.shellLockLock))
        }
        if let command = panels[verb] {
            try rejectExtra("shell \(verb)", rest)
            return .ipc(IPCRequest(command))
        }
        guard let target = ShellTarget(cliName: verb) else {
            let expected = ["-d"] + panels.keys.sorted() + ["lock"] + ShellTarget.allCases.map(\.rawValue)
            throw CLIUsageError.unknownVerb(group: "shell", verb: verb, expected: expected)
        }
        guard let fnName = rest.first else {
            throw CLIUsageError.missingArgument(command: "shell \(target.rawValue)", name: target.functions.map(\.name).joined(separator: "|"))
        }
        guard let fn = target.function(named: fnName) ?? target.functions.first(where: { $0.name.lowercased() == fnName.lowercased() }) else {
            throw CLIUsageError.unknownVerb(group: "shell \(target.rawValue)", verb: fnName, expected: target.functions.map(\.name))
        }
        let values = Array(rest.dropFirst())
        let commandName = "shell \(target.rawValue) \(fn.name)"
        if values.count < fn.parameters.count {
            throw CLIUsageError.missingArgument(command: commandName, name: fn.parameters[values.count])
        }
        if values.count > fn.parameters.count {
            throw CLIUsageError.unexpectedArgument(command: commandName, value: values[fn.parameters.count])
        }
        guard let command = IPCCommand.shell(target, fn.name) else {
            throw CLIUsageError.unknownVerb(group: "shell \(target.rawValue)", verb: fn.name, expected: target.functions.map(\.name))
        }
        var a: [String: JSONValue] = [:]
        for (name, value) in zip(fn.parameters, values) {
            a[name] = .string(name == "path" ? absolutePath(value) : value)
        }
        return .ipc(IPCRequest(command, args: a))
    }

    static func parseScreenshot(_ args: [String], _ tokens: Tokens) throws -> CLIInvocation.Kind {
        let modes = ["region", "freeze", "window", "full"]
        let mode = args.first ?? "region"
        try rejectExtra("screenshot", Array(args.dropFirst()))
        guard modes.contains(mode) else {
            throw CLIUsageError.invalidArgument(command: "screenshot", name: "mode", value: mode, expected: modes.joined(separator: "|"))
        }
        return .ipc(IPCRequest(.screenshot, args: ["mode": .string(mode)]))
    }

    static func parseScheme(_ args: [String]) throws -> CLIInvocation.Kind {
        try expectVerb("scheme", args, ["set"])
        guard args.count >= 2 else { throw CLIUsageError.missingArgument(command: "scheme set", name: "name") }
        try rejectExtra("scheme set", Array(args.dropFirst(2)))
        return .ipc(IPCRequest(.schemeSet, args: ["name": .string(args[1])]))
    }

    static func parseWallpaper(_ args: [String]) throws -> CLIInvocation.Kind {
        let verbs = ["set", "random", "get", "list"]
        guard let verb = args.first else { throw CLIUsageError.missingArgument(command: "wallpaper", name: verbs.joined(separator: "|")) }
        switch verb {
        case "set":
            guard args.count >= 2 else { throw CLIUsageError.missingArgument(command: "wallpaper set", name: "file") }
            try rejectExtra("wallpaper set", Array(args.dropFirst(2)))
            return .ipc(IPCRequest(.shellWallpaperSet, args: ["path": .string(absolutePath(args[1]))]))
        case "random":
            try rejectExtra("wallpaper random", Array(args.dropFirst()))
            return .ipc(IPCRequest(.wallpaperRandom))
        case "get":
            try rejectExtra("wallpaper get", Array(args.dropFirst()))
            return .ipc(IPCRequest(.shellWallpaperGet))
        case "list":
            try rejectExtra("wallpaper list", Array(args.dropFirst()))
            return .ipc(IPCRequest(.shellWallpaperList))
        default:
            throw CLIUsageError.unknownVerb(group: "wallpaper", verb: verb, expected: verbs)
        }
    }

    static func parseKeys(_ args: [String]) throws -> CLIInvocation.Kind {
        let verbs = ["check", "list"]
        guard let verb = args.first else { throw CLIUsageError.missingArgument(command: "keys", name: "check|list") }
        try rejectExtra("keys \(verb)", Array(args.dropFirst()))
        switch verb {
        case "check": return .local(.keysCheck)
        case "list": return .local(.keysList)
        default: throw CLIUsageError.unknownVerb(group: "keys", verb: verb, expected: verbs)
        }
    }

    static func parseQuery(_ args: [String]) throws -> CLIInvocation.Kind {
        let kinds: [String: IPCCommand] = [
            "windows": .queryWindows, "clients": .queryWindows, "workspaces": .queryWorkspaces,
            "monitors": .queryMonitors, "binds": .queryBinds, "state": .queryState, "overlays": .queryOverlays,
        ]
        guard let what = args.first else { throw CLIUsageError.missingArgument(command: "query", name: "windows|workspaces|monitors|binds|state|overlays") }
        guard let command = kinds[what] else {
            throw CLIUsageError.unknownVerb(group: "query", verb: what, expected: ["windows", "workspaces", "monitors", "binds", "state", "overlays"])
        }
        try rejectExtra("query \(what)", Array(args.dropFirst()))
        return .ipc(IPCRequest(command))
    }

    static func parseNotify(_ args: [String], _ tokens: Tokens) throws -> CLIInvocation.Kind {
        guard let title = args.first else { throw CLIUsageError.missingArgument(command: "notify", name: "title") }
        try rejectExtra("notify", Array(args.dropFirst(2)))
        var a: [String: JSONValue] = ["title": .string(title)]
        if args.count >= 2 { a["body"] = .string(args[1]) }
        if let app = tokens.options["--app"] { a["app"] = .string(app) }
        if let icon = tokens.options["--icon"] { a["icon"] = .string(icon) }
        return .ipc(IPCRequest(.notify, args: a))
    }

    static func parseAction(_ args: [String]) throws -> CLIInvocation.Kind {
        guard let name = args.first else { throw CLIUsageError.missingArgument(command: "action", name: "action") }
        guard let kind = ActionKind(rawValue: name) else {
            throw CLIUsageError.invalidArgument(command: "action", name: "action", value: name, expected: "an action name, e.g. workspace.next (see `skyrose help action`)")
        }
        var actionArgs: [String: JSONValue] = [:]
        for pair in args.dropFirst() {
            guard let eq = pair.firstIndex(of: "=") else {
                throw CLIUsageError.invalidArgument(command: "action", name: "argument", value: pair, expected: "key=value")
            }
            let key = String(pair[..<eq])
            let raw = String(pair[pair.index(after: eq)...])
            guard kind.argumentNames.contains(key) else {
                let accepted = kind.argumentNames.isEmpty ? "no arguments" : "one of \(kind.argumentNames.joined(separator: ", "))"
                throw CLIUsageError.invalidArgument(command: "action \(name)", name: "argument", value: key, expected: accepted)
            }
            actionArgs[key] = typedValue(raw)
        }
        for required in kind.requiredArgumentNames where actionArgs[required] == nil {
            throw CLIUsageError.missingArgument(command: "action \(name)", name: "\(required)=value")
        }
        var a: [String: JSONValue] = ["action": .string(name)]
        if !actionArgs.isEmpty { a["args"] = .object(actionArgs) }
        return .ipc(IPCRequest(.action, args: a))
    }

    static func parseWM(_ args: [String]) throws -> CLIInvocation.Kind {
        let verbs: [String: IPCCommand] = ["panic": .wmPanic, "restore-all": .wmRestoreAll, "quit": .wmQuit]
        guard let verb = args.first else { throw CLIUsageError.missingArgument(command: "wm", name: "panic|restore-all|quit") }
        guard let command = verbs[verb] else { throw CLIUsageError.unknownVerb(group: "wm", verb: verb, expected: verbs.keys.sorted()) }
        try rejectExtra("wm \(verb)", Array(args.dropFirst()))
        return .ipc(IPCRequest(command))
    }

    /// `debug overlay [on|off]`.
    static func parseDebug(_ args: [String]) throws -> CLIInvocation.Kind {
        try expectVerb("debug", args, ["overlay"])
        let rest = Array(args.dropFirst())
        guard let value = rest.first else { return .ipc(IPCRequest(.debugOverlay)) }
        try rejectExtra("debug overlay", Array(rest.dropFirst()))
        guard let on = IPCArgumentType.bool.parse(value) else {
            throw CLIUsageError.invalidArgument(command: "debug overlay", name: "on", value: value, expected: "on|off")
        }
        return .ipc(IPCRequest(.debugOverlay, args: ["on": on]))
    }

    // MARK: - Small helpers

    static func expectVerb(_ group: String, _ args: [String], _ verbs: [String]) throws {
        guard let verb = args.first else { throw CLIUsageError.missingArgument(command: group, name: verbs.joined(separator: "|")) }
        guard verbs.contains(verb) else { throw CLIUsageError.unknownVerb(group: group, verb: verb, expected: verbs) }
    }

    static func rejectExtra(_ command: String, _ extra: [String]) throws {
        if let first = extra.first { throw CLIUsageError.unexpectedArgument(command: command, value: first) }
    }

    static func int(_ command: String, _ name: String, _ text: String) throws -> Int {
        guard let v = Int(text) else {
            throw CLIUsageError.invalidArgument(command: command, name: name, value: text, expected: "an integer")
        }
        return v
    }

    static func direction(_ command: String, _ text: String) throws -> Direction {
        switch text.lowercased() {
        case "l", "left": return .left
        case "r", "right": return .right
        case "u", "up": return .up
        case "d", "down": return .down
        default:
            throw CLIUsageError.invalidArgument(command: command, name: "direction", value: text, expected: "left|right|up|down")
        }
    }

    /// `key=value` values: integers and booleans become typed JSON, everything else is a string.
    static func typedValue(_ raw: String) -> JSONValue {
        if let i = Int(raw) { return .number(Double(i)) }
        if let d = Double(raw), raw.contains(".") { return .number(d) }
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        return .string(raw)
    }

    /// Expands `~` and resolves relative paths against the current directory, so the WM (a
    /// different process with a different cwd) gets a usable path.
    public static func absolutePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL.path
    }

    // MARK: - Usage text

    /// A help section: a title and `(usage, summary)` rows.
    public struct HelpSection: Equatable, Sendable {
        public var title: String
        public var topics: [String]
        public var rows: [(usage: String, summary: String)]

        public static func == (a: HelpSection, b: HelpSection) -> Bool {
            a.title == b.title && a.topics == b.topics && a.rows.map(\.usage) == b.rows.map(\.usage)
        }
    }

    public static let helpSections: [HelpSection] = [
        HelpSection(title: "Workspaces", topics: ["ws", "workspace"], rows: [
            ("ws focus <n|next|prev>", "Focus workspace n (1-based, across groups)"),
            ("ws move <n> [--silent]", "Move the focused window to workspace n and follow (--silent: stay)"),
            ("ws toggle-special [name]", "Toggle a special workspace (default \"special\")"),
        ]),
        HelpSection(title: "Windows", topics: ["window", "win"], rows: [
            ("window focus <left|right|up|down>", "Move focus in a direction"),
            ("window move <left|right|up|down>", "Move/swap the focused window in a direction"),
            ("window float|fullscreen|maximize|pin|close|center", "Act on the focused window"),
            ("window pseudo|togglesplit|swapsplit", "Pseudotile, flip or swap the focused window's split (dwindle)"),
        ]),
        HelpSection(title: "Shell", topics: ["shell", "frame"], rows: [
            ("shell launcher|dashboard|sidebar|session|lock|showall|clear-notifs", "Toggle a panel"),
            ("shell -d", "Start the WM app if it is not running"),
            ("shell kill | shell restart", "Hide / restart the shell UI"),
            ("shell <target> <fn> [args...]", "Linux shell IPC, 1:1 (e.g. shell toaster info \"Title\" \"Msg\" icon)"),
            ("shell help [target]", "List the IPC targets and their signatures"),
            ("frame calibrate [display]", "Tune the frame's corner radii by eye (↑↓ ±0.5, ⇧ ±0.1, Tab top/bottom, ←→ display, Return saves, Esc cancels)"),
        ]),
        HelpSection(title: "Capture and utilities", topics: ["screenshot", "record", "clipboard", "emoji", "picker", "scheme", "wallpaper", "notify"], rows: [
            ("screenshot [region|freeze|window|full]", "Take a screenshot (default: region): saved to capture.folder + clipboard"),
            ("record [-s] [-r]", "Start/stop the screen recorder (-s: system sound, -r: region)"),
            ("clipboard [-d]", "Open clipboard history (-d: delete mode)"),
            ("emoji", "Open the emoji picker"),
            ("picker", "Open the colour picker"),
            ("scheme set <name>", "Switch colour scheme"),
            ("wallpaper set <file> | random | get | list", "Wallpaper control"),
            ("notify <title> [body] [--app NAME] [--icon ICON]", "Post a notification to the sidebar"),
        ]),
        HelpSection(title: "Keys and config", topics: ["keys", "rules", "config", "settings", "onboarding", "migrate"], rows: [
            ("keys check [--json]", "Conflict checker on the keymap (exit 1 on errors)"),
            ("keys list [--json]", "Table of every bind"),
            ("rules reload", "Re-read rules.toml"),
            ("rules apps [--json]", "Per-app window rules (tile / float / auto) and where they come from"),
            ("rules set <bundle-id> <tile|float|auto>", "Set an app's window rule (saved to config.toml [appRules])"),
            ("rules focused [--json]", "The rule of the focused window's app"),
            ("config reload", "Re-read config.toml and keymap.toml"),
            ("config get [table.key] [--json]", "Read the config (or one key) as written in config.toml"),
            ("config set <table.key> <value>", "Set one key, validated and applied live (e.g. config set wm.gapsIn 8)"),
            ("config reset <table.key>", "Remove one key from config.toml (back to its default)"),
            ("settings", "Open SkyRose Settings"),
            ("onboarding", "Run the first-run onboarding again"),
            ("migrate", "Move a pre-rename Caelestia for Mac install to the SkyRose folders (runs by itself on first launch)"),
        ]),
        HelpSection(title: "Queries (like hyprctl -j)", topics: ["query", "q"], rows: [
            ("query windows|workspaces|monitors|binds|state [--json]", "Inspect WM state (tables, or raw JSON with --json)"),
        ]),
        HelpSection(title: "WM and diagnostics", topics: ["action", "dispatch", "wm", "permissions", "doctor", "uninstall", "cursor", "kitty", "fonts", "sa", "version"], rows: [
            ("action <name> [key=value ...]", "Run any keymap action, e.g. action workspace.focus index=3"),
            ("wm panic | restore-all | quit", "Restore windows and stop managing / bring parked windows back / quit"),
            ("permissions status", "TCC permissions as the WM sees them"),
            ("permissions request <accessibility|inputMonitoring|screenRecording>", "Ask for one permission and open its System Settings pane"),
            ("doctor [--json]", "Environment, permissions, versions, SIP status, conflicts"),
            ("uninstall [--yes]", "Run scripts/uninstall.sh (or print the manual steps)"),
            ("cursor list | status | set <cape|default> | reset", "Session cursor theme (Mousecape capes); reset puts the macOS cursors back"),
            ("fonts status | download | install | uninstall", "Arch font pack: download (checksummed, SkyRose only) / install into ~/Library/Fonts for kitty and other apps"),
            ("sa status | load-command | reset", "SIP-off mode: is the scripting addition loaded, the sudo line that loads it, undo everything it changed"),
            ("kitty status | install | uninstall", "SkyRose kitty profile: Gabby's Arch settings + live scheme colours (one include line in kitty.conf)"),
            ("version", "CLI and WM versions"),
        ]),
    ]

    /// Usage text for a topic (a group name), or the full help when `topic` is nil/unknown.
    public static func usage(for topic: String? = nil) -> String {
        var out = ""
        if let topic, let section = helpSections.first(where: { $0.topics.contains(topic) }) {
            out += "\(section.title)\n"
            out += rows(section)
            if section.topics.contains("shell") {
                out += "\nShell IPC targets: " + ShellTarget.allCases.map(\.rawValue).joined(separator: ", ") + "\n"
            }
            if section.topics.contains("action") {
                out += "\nActions: " + ActionKind.allCases.map(\.rawValue).joined(separator: ", ") + "\n"
            }
            return out
        }
        out += "Usage: \(programName) <command> [args] [--json] [--socket PATH] [--timeout SECONDS]\n"
        out += "SkyRose command line (replaces hyprctl + the Linux caelestia CLI). `caelestia` still works as a deprecated alias for one release.\n"
        for section in helpSections {
            out += "\n\(section.title)\n"
            out += rows(section)
        }
        out += "\nExit codes: 0 ok, 1 command failed, 2 WM not running, 3 usage error.\n"
        return out
    }

    /// Usage column cap; longer usages get the summary on their own indented line.
    static let usageColumnWidth = 48

    private static func rows(_ section: HelpSection) -> String {
        let width = section.rows.map { $0.usage.count }.filter { $0 <= usageColumnWidth }.max() ?? 0
        return section.rows.map { row in
            if row.usage.count > width {
                return "  \(row.usage)\n      \(row.summary)\n"
            }
            return "  \(row.usage.padding(toLength: width, withPad: " ", startingAt: 0))  \(row.summary)\n"
        }.joined()
    }

    /// The Linux-style target listing (`skyrose shell help [target]`).
    public static func shellTargetsHelp(target name: String? = nil) -> String {
        let targets: [ShellTarget]
        if let name {
            guard let t = ShellTarget(cliName: name) else {
                return "Unknown target '\(name)'. Targets: \(ShellTarget.allCases.map(\.rawValue).joined(separator: ", "))\n"
            }
            targets = [t]
        } else {
            targets = ShellTarget.allCases
        }
        var out = ""
        for t in targets {
            out += "target \(t.rawValue)\n"
            for f in t.functions { out += "  function \(f.signature)\n" }
        }
        return out
    }
}

/// The pre-rename CLI name, kept as a deprecated alias for one release.
public enum CLIAlias {
    public static let deprecatedName = "caelestia"
    public static let deprecationNotice =
        "caelestia: this command is now called `skyrose`; `caelestia` keeps working until the next release."

    /// True when the program was started as `caelestia` (argv[0], any directory).
    public static func isDeprecatedName(_ argv0: String) -> Bool {
        (argv0 as NSString).lastPathComponent == deprecatedName
    }
}

extension CLIParser {
    /// A `config set` value from the command line: true/false, a number, a TOML array/table
    /// literal (`[...]` / `{...}`, sent as a string and parsed by the WM), else a string.
    public static func configValue(_ text: String) -> JSONValue {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t == "true" { return .bool(true) }
        if t == "false" { return .bool(false) }
        if let d = Double(t), !t.isEmpty { return .number(d) }
        if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") { return .string(String(t.dropFirst().dropLast())) }
        return .string(t)
    }
}
