import Foundation
import TOMLKit

// MARK: - Errors

/// A keymap file problem, precise enough for the OSD, the CLI and Settings to point at the line.
public struct KeymapError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public enum Kind: String, Sendable, Equatable, Codable {
        /// TOML syntax error.
        case syntax
        /// The file could not be read.
        case io
        /// A required key is missing or has the wrong TOML type.
        case structure
        /// A key the format does not define.
        case unknownKey
        /// A value outside the allowed set (modifier name, enabled flag, …).
        case invalidValue
        case unknownAction
        case invalidArguments
        case invalidFlag
        case invalidChord
        case duplicateID
    }

    public var kind: Kind
    /// 1-based line in the keymap file, when known.
    public var line: Int?
    /// The `id` of the offending `[[bind]]`, when known.
    public var bindID: String?
    public var reason: String

    public init(kind: Kind, reason: String, line: Int? = nil, bindID: String? = nil) {
        self.kind = kind
        self.reason = reason
        self.line = line
        self.bindID = bindID
    }

    public var description: String {
        var location: [String] = []
        if let line { location.append("line \(line)") }
        if let bindID { location.append("bind \"\(bindID)\"") }
        let prefix = location.isEmpty ? "keymap" : "keymap " + location.joined(separator: ", ")
        return "\(prefix): \(reason)"
    }

    public var errorDescription: String? { description }
}

// MARK: - Extras (gestures)

/// The `[gestures]` table of keymap.toml (section 3.5). Gestures are opt-in because macOS already
/// uses 3/4-finger swipes for Spaces and Mission Control.
public struct GestureConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Horizontal swipe = previous/next workspace (Hyprland `workspaceSwipeFingers`).
    public var workspaceSwipeFingers: Int
    /// Swipe up = open the special workspace, swipe down = toggle it closed (`gestureFingers`).
    public var specialFingers: Int
    /// Swipe down = sleep (`gestureFingersMore`).
    public var sleepFingers: Int

    public init(enabled: Bool = false, workspaceSwipeFingers: Int = 4, specialFingers: Int = 3, sleepFingers: Int = 4) {
        self.enabled = enabled
        self.workspaceSwipeFingers = workspaceSwipeFingers
        self.specialFingers = specialFingers
        self.sleepFingers = sleepFingers
    }

    /// Gabby's values from variables.lua.
    public static let `default` = GestureConfig()
}

/// Everything in keymap.toml that is not a bind or the modifier map.
public struct KeymapExtras: Codable, Equatable, Sendable {
    /// `[gestures]`, or `nil` when the file has no such table.
    public var gestures: GestureConfig?

    public init(gestures: GestureConfig? = nil) {
        self.gestures = gestures
    }
}

// MARK: - Bind categories (docs, cheat sheet)

/// The groups of section 3.4, used by docs/KEYBINDS.md and the cheat-sheet overlay.
public enum BindCategory: String, CaseIterable, Sendable, Codable {
    case shell = "Shell"
    case workspaces = "Workspaces"
    case windowCycling = "Window cycling and groups"
    case windows = "Focus / move / resize"
    case special = "Special workspaces"
    case apps = "Apps"
    case capture = "Capture"
    case media = "Media / volume / brightness"
    case session = "Session / utilities"
    case safety = "Safety"
}

extension ActionKind {
    /// The section-3.4 group this action belongs to.
    public var category: BindCategory {
        switch self {
        case .launcherToggle, .sessionToggle, .sidebarToggle, .dashboardToggle, .panelsShowAll, .notifsClear,
            .lock, .shellRestoreLock, .shellKill, .shellRestart:
            return .shell
        case .workspaceFocus, .workspaceMove, .workspaceMoveSilent, .workspaceFocusGroup, .workspaceMoveGroup,
            .workspaceNext, .workspacePrev, .workspaceNextGroup, .workspacePrevGroup, .workspaceMoveToNext,
            .workspaceMoveToPrev, .workspaceMoveToSpecial, .workspaceMoveOutOfSpecial:
            return .workspaces
        case .windowCycleNext, .windowCyclePrev, .groupNext, .groupPrev, .groupToggle, .groupMoveOut, .groupLock:
            return .windowCycling
        case .windowFocus, .windowSwap, .windowResize, .windowDrag, .windowResizeDrag, .windowCenter,
            .windowNormalize, .windowPip, .windowPin, .windowFullscreen, .windowMaximize, .windowToggleFloat,
            .windowClose:
            return .windows
        case .specialToggle:
            return .special
        case .appTerminal, .appBrowser, .appEditor, .appFiles, .appAudioSettings, .exec:
            return .apps
        case .captureRegion, .captureFull, .captureFreeze, .recordScreen, .recordSound, .recordRegion, .pickerColor:
            return .capture
        case .brightnessUp, .brightnessDown, .mediaPlayPause, .mediaNext, .mediaPrev, .mediaStop, .audioToggleMute,
            .audioToggleMicMute, .audioVolumeUp, .audioVolumeDown, .osdLockKey:
            return .media
        case .systemSleep, .clipboardOpen, .clipboardDelete, .clipboardTypeLatest, .emojiOpen, .notifyTest:
            return .session
        case .wmPanic:
            return .safety
        }
    }
}

// MARK: - Parser

/// Reads and writes keymap.toml (section 3.2).
///
/// ```toml
/// [modifiers]
/// super = "lopt"
/// alt   = "lcmd"
/// ctrl  = "ctrl"
/// shift = "shift"
///
/// [[bind]]
/// id          = "ws.focus.1"
/// keys        = ["SUPER + 1"]
/// action      = "workspace.focus"
/// args        = { index = 1 }
/// flags       = []            # any of: release, repeat, locked, mouse
/// linux       = "SUPER + 1"   # original Hyprland bind, for the mapping doc
/// description = "focus workspace 1"
/// enabled     = true
/// ```
///
/// Every file is guaranteed to contain the fixed panic bind (``panicBind``): a keymap without it, or
/// with it altered or disabled, gets it restored and a warning.
public enum KeymapParser {
    /// The panic chord of section 10.10: ⌃⌥⌘⇧Esc. In logical terms (all four modifiers) it is the
    /// same physical chord under presets A and C; the Platform panic detector also matches the
    /// physical keys directly, so it keeps working under every preset.
    public static let panicChordText = "CTRL + SUPER + ALT + SHIFT + Escape"
    public static let panicBindID = "wm.panic"
    public static let panicBind = Bind(
        id: panicBindID, keys: [panicChordText], action: Action(.wmPanic), flags: [],
        linux: nil, description: "fixed; cannot be removed", enabled: true,
        chords: [KeyChord(modifiers: [.superKey, .altKey, .ctrlKey, .shiftKey], key: .code(0x35))]
    )

    private static let allowedTopLevelKeys: Set<String> = ["modifiers", "bind", "gestures"]
    private static let allowedBindKeys: Set<String> = ["id", "keys", "action", "args", "flags", "linux", "description", "enabled"]
    private static let allowedModifierKeys: Set<String> = ["super", "alt", "ctrl", "shift"]
    private static let allowedGestureKeys: Set<String> = ["enabled", "workspaceSwipeFingers", "specialFingers", "sleepFingers"]

    /// Parses a keymap. Warnings (panic bind restored, mouse chord without the `mouse` flag, …) are
    /// logged to the config log; use ``parse(toml:warnings:)`` to collect them.
    public static func parse(toml: String) throws -> Keymap {
        var warnings: [String] = []
        let keymap = try parse(toml: toml, warnings: &warnings)
        for w in warnings { Log.config.warning("keymap: \(w, privacy: .public)") }
        return keymap
    }

    /// Parses a keymap, appending non-fatal findings to `warnings`.
    public static func parse(toml: String, warnings: inout [String]) throws -> Keymap {
        let (keymap, _) = try parseWithExtras(toml: toml, warnings: &warnings)
        return keymap
    }

    /// Parses a keymap together with its `[gestures]` table.
    public static func parseWithExtras(toml: String) throws -> (Keymap, KeymapExtras) {
        var warnings: [String] = []
        let result = try parseWithExtras(toml: toml, warnings: &warnings)
        for w in warnings { Log.config.warning("keymap: \(w, privacy: .public)") }
        return result
    }

    /// Parses a keymap together with its `[gestures]` table, appending non-fatal findings to `warnings`.
    public static func parseWithExtras(toml: String, warnings: inout [String]) throws -> (Keymap, KeymapExtras) {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: toml)
        } catch let error as TOMLParseError {
            throw KeymapError(kind: .syntax, reason: error.description, line: error.source.begin.line)
        }
        let lines = SourceLines(toml)

        for key in root.keys where !allowedTopLevelKeys.contains(key) {
            throw KeymapError(
                kind: .unknownKey, reason: "unknown top-level key \"\(key)\"; the keymap has [modifiers], [[bind]] and [gestures]",
                line: lines.line(ofKey: key)
            )
        }

        let modifiers = try parseModifiers(root["modifiers"], lines: lines)
        let extras = KeymapExtras(gestures: try parseGestures(root["gestures"], lines: lines))

        var binds: [Bind] = []
        var seenIDs: [String: Int] = [:]
        if let bindValue = root["bind"] {
            guard let array = bindValue.array else {
                throw KeymapError(
                    kind: .structure, reason: "\"bind\" must be an array of tables; write each bind as a [[bind]] section",
                    line: lines.line(ofKey: "bind")
                )
            }
            let headerLines = lines.bindHeaderLines.count == array.count ? lines.bindHeaderLines : []
            for (index, element) in array.enumerated() {
                let line = headerLines.isEmpty ? nil : headerLines[index]
                guard let table = element.table else {
                    throw KeymapError(kind: .structure, reason: "bind #\(index + 1) is not a table", line: line)
                }
                let bind = try parseBind(table, line: line, warnings: &warnings)
                if let previous = seenIDs[bind.id] {
                    throw KeymapError(
                        kind: .duplicateID, reason: "duplicate bind id \"\(bind.id)\" (first defined at bind #\(previous + 1)); ids must be unique",
                        line: line, bindID: bind.id
                    )
                }
                seenIDs[bind.id] = index
                binds.append(bind)
            }
        }

        binds = ensurePanicBind(in: binds, warnings: &warnings)
        return (Keymap(modifiers: modifiers, binds: binds), extras)
    }

    // MARK: Serialization

    /// Writes a keymap in the canonical format (round-trips through ``parse(toml:)``).
    public static func serialize(_ keymap: Keymap) -> String {
        serialize(keymap, extras: KeymapExtras())
    }

    /// Writes a keymap and its extras in the canonical format.
    public static func serialize(_ keymap: Keymap, extras: KeymapExtras) -> String {
        var out = """
        # Caelestia for Mac keymap. Chords use Linux modifier names (SUPER, ALT, CTRL, SHIFT); the
        # [modifiers] table maps them to physical Mac keys. Flags: release, repeat, locked, mouse.

        [modifiers]
        super = \(tomlString(keymap.modifiers.superKey.rawValue))
        alt   = \(tomlString(keymap.modifiers.altKey.rawValue))
        ctrl  = \(tomlString(keymap.modifiers.ctrlKey.rawValue))
        shift = \(tomlString(keymap.modifiers.shiftKey.rawValue))

        """
        if let g = extras.gestures {
            out += """

            [gestures]
            enabled               = \(g.enabled)
            workspaceSwipeFingers = \(g.workspaceSwipeFingers)
            specialFingers        = \(g.specialFingers)
            sleepFingers          = \(g.sleepFingers)

            """
        }
        for bind in keymap.binds {
            out += "\n[[bind]]\n"
            out += "id          = \(tomlString(bind.id))\n"
            out += "keys        = [\(bind.keys.map(tomlString).joined(separator: ", "))]\n"
            out += "action      = \(tomlString(bind.action.kind.rawValue))\n"
            if !bind.action.args.isEmpty {
                let args = bind.action.args.keys.sorted().map { "\($0) = \(tomlValue(bind.action.args[$0]!))" }
                out += "args        = { \(args.joined(separator: ", ")) }\n"
            }
            let flags = bind.flags.map(\.rawValue).sorted().map(tomlString)
            out += "flags       = [\(flags.joined(separator: ", "))]\n"
            if let linux = bind.linux { out += "linux       = \(tomlString(linux))\n" }
            if !bind.description.isEmpty { out += "description = \(tomlString(bind.description))\n" }
            if !bind.enabled { out += "enabled     = false\n" }
        }
        return out
    }

    // MARK: - Sections

    private static func parseModifiers(_ value: TOMLValueConvertible?, lines: SourceLines) throws -> ModifierMap {
        guard let value else { return .optionIsSuper }
        let line = lines.line(ofKey: "modifiers")
        guard let table = value.table else {
            throw KeymapError(kind: .structure, reason: "[modifiers] must be a table with super, alt, ctrl and shift", line: line)
        }
        for key in table.keys where !allowedModifierKeys.contains(key) {
            throw KeymapError(
                kind: .unknownKey, reason: "unknown key \"\(key)\" in [modifiers]; allowed: super, alt, ctrl, shift",
                line: lines.line(ofKey: key, after: line)
            )
        }
        func physical(_ key: String, default fallback: PhysicalModifier) throws -> PhysicalModifier {
            guard let raw = table[key] else { return fallback }
            guard let text = raw.string else {
                throw KeymapError(kind: .invalidValue, reason: "[modifiers] \(key) must be a string", line: lines.line(ofKey: key, after: line))
            }
            guard let p = PhysicalModifier(rawValue: text.lowercased()) else {
                let allowed = PhysicalModifier.allCases.map(\.rawValue).joined(separator: ", ")
                throw KeymapError(
                    kind: .invalidValue, reason: "[modifiers] \(key) = \"\(text)\" is not a physical modifier; allowed: \(allowed)",
                    line: lines.line(ofKey: key, after: line)
                )
            }
            return p
        }
        return ModifierMap(
            superKey: try physical("super", default: .lopt), altKey: try physical("alt", default: .lcmd),
            ctrlKey: try physical("ctrl", default: .ctrl), shiftKey: try physical("shift", default: .shift)
        )
    }

    private static func parseGestures(_ value: TOMLValueConvertible?, lines: SourceLines) throws -> GestureConfig? {
        guard let value else { return nil }
        let line = lines.line(ofKey: "gestures")
        guard let table = value.table else {
            throw KeymapError(kind: .structure, reason: "[gestures] must be a table", line: line)
        }
        for key in table.keys where !allowedGestureKeys.contains(key) {
            throw KeymapError(
                kind: .unknownKey,
                reason: "unknown key \"\(key)\" in [gestures]; allowed: enabled, workspaceSwipeFingers, specialFingers, sleepFingers",
                line: lines.line(ofKey: key, after: line)
            )
        }
        var config = GestureConfig.default
        if let v = table["enabled"] {
            guard let b = v.bool else {
                throw KeymapError(kind: .invalidValue, reason: "[gestures] enabled must be true or false", line: lines.line(ofKey: "enabled", after: line))
            }
            config.enabled = b
        }
        func fingers(_ key: String, _ current: Int) throws -> Int {
            guard let v = table[key] else { return current }
            guard let n = v.int, (2...5).contains(n) else {
                throw KeymapError(kind: .invalidValue, reason: "[gestures] \(key) must be a finger count between 2 and 5", line: lines.line(ofKey: key, after: line))
            }
            return n
        }
        config.workspaceSwipeFingers = try fingers("workspaceSwipeFingers", config.workspaceSwipeFingers)
        config.specialFingers = try fingers("specialFingers", config.specialFingers)
        config.sleepFingers = try fingers("sleepFingers", config.sleepFingers)
        return config
    }

    private static func parseBind(_ table: TOMLTable, line: Int?, warnings: inout [String]) throws -> Bind {
        let idText = table["id"]?.string
        for key in table.keys where !allowedBindKeys.contains(key) {
            throw KeymapError(
                kind: .unknownKey,
                reason: "unknown key \"\(key)\" in [[bind]]; allowed: id, keys, action, args, flags, linux, description, enabled",
                line: line, bindID: idText
            )
        }
        guard let id = idText, !id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw KeymapError(kind: .structure, reason: "[[bind]] needs a non-empty string id, e.g. id = \"ws.focus.1\"", line: line)
        }

        guard let keysValue = table["keys"] else {
            throw KeymapError(kind: .structure, reason: "missing keys; write keys = [\"SUPER + 1\"]", line: line, bindID: id)
        }
        guard let keysArray = keysValue.array else {
            throw KeymapError(kind: .structure, reason: "keys must be an array of chord strings, e.g. keys = [\"SUPER + 1\"]", line: line, bindID: id)
        }
        var keys: [String] = []
        var chords: [KeyChord] = []
        for element in keysArray {
            guard let text = element.string else {
                throw KeymapError(kind: .structure, reason: "every entry of keys must be a chord string", line: line, bindID: id)
            }
            do {
                chords.append(try ChordParser.parse(text))
            } catch let error as ChordParseError {
                throw KeymapError(kind: .invalidChord, reason: error.description, line: line, bindID: id)
            }
            keys.append(text)
        }
        guard !keys.isEmpty else {
            throw KeymapError(kind: .structure, reason: "keys is empty; a bind needs at least one chord (or set enabled = false)", line: line, bindID: id)
        }

        guard let actionValue = table["action"] else {
            throw KeymapError(kind: .structure, reason: "missing action, e.g. action = \"workspace.focus\"", line: line, bindID: id)
        }
        guard let actionText = actionValue.string else {
            throw KeymapError(kind: .structure, reason: "action must be a string", line: line, bindID: id)
        }
        guard let kind = ActionKind(rawValue: actionText) else {
            var reason = "unknown action \"\(actionText)\""
            let similar = ActionKind.allCases.map(\.rawValue).filter { candidate in
                candidate.lowercased() == actionText.lowercased()
                    || candidate.split(separator: ".").first.map { actionText.lowercased().hasPrefix($0.lowercased() + ".") } == true
            }
            if !similar.isEmpty { reason += "; similar actions: " + similar.prefix(6).joined(separator: ", ") }
            throw KeymapError(kind: .unknownAction, reason: reason, line: line, bindID: id)
        }

        let args = try parseArgs(table["args"], kind: kind, line: line, bindID: id)

        var flags = Set<BindFlag>()
        if let flagsValue = table["flags"] {
            guard let flagsArray = flagsValue.array else {
                throw KeymapError(kind: .structure, reason: "flags must be an array, e.g. flags = [\"repeat\"]", line: line, bindID: id)
            }
            for element in flagsArray {
                guard let text = element.string, let flag = BindFlag(rawValue: text.lowercased()) else {
                    let allowed = BindFlag.allCases.map(\.rawValue).joined(separator: ", ")
                    throw KeymapError(kind: .invalidFlag, reason: "unknown flag \(element.debugDescription); allowed: \(allowed)", line: line, bindID: id)
                }
                flags.insert(flag)
            }
        }

        var linux: String?
        if let linuxValue = table["linux"] {
            guard let text = linuxValue.string else {
                throw KeymapError(kind: .structure, reason: "linux must be a string (several chords separated by \" | \")", line: line, bindID: id)
            }
            do {
                _ = try ChordParser.parseList(text)
            } catch let error as ChordParseError {
                throw KeymapError(kind: .invalidChord, reason: "linux: \(error.description)", line: line, bindID: id)
            }
            linux = text
        }

        var description = ""
        if let value = table["description"] {
            guard let text = value.string else {
                throw KeymapError(kind: .structure, reason: "description must be a string", line: line, bindID: id)
            }
            description = text
        }

        var enabled = true
        if let value = table["enabled"] {
            guard let b = value.bool else {
                throw KeymapError(kind: .invalidValue, reason: "enabled must be true or false", line: line, bindID: id)
            }
            enabled = b
        }

        let hasMouseButton = chords.contains { if case .mouseButton = $0.key { return true } else { return false } }
        if hasMouseButton && !flags.contains(.mouse) {
            warnings.append("bind \"\(id)\" uses a mouse button chord without the mouse flag; it will fire on click, not drag")
        }

        return Bind(id: id, keys: keys, action: Action(kind, args: args), flags: flags, linux: linux,
                    description: description, enabled: enabled, chords: chords)
    }

    private static func parseArgs(_ value: TOMLValueConvertible?, kind: ActionKind, line: Int?, bindID: String) throws -> [String: ArgValue] {
        var args: [String: ArgValue] = [:]
        if let value {
            guard let table = value.table else {
                throw KeymapError(kind: .invalidArguments, reason: "args must be an inline table, e.g. args = { index = 1 }", line: line, bindID: bindID)
            }
            for key in table.keys {
                guard kind.argumentNames.contains(key) else {
                    let allowed = kind.argumentNames.isEmpty ? "it takes no arguments" : "allowed: " + kind.argumentNames.joined(separator: ", ")
                    throw KeymapError(kind: .invalidArguments, reason: "\(kind.rawValue) has no argument \"\(key)\"; \(allowed)", line: line, bindID: bindID)
                }
                let raw = table[key]!
                let arg: ArgValue
                switch raw.type {
                case .string: arg = .string(raw.string!)
                case .int: arg = .int(raw.int!)
                case .double: arg = .double(raw.double!)
                case .bool: arg = .bool(raw.bool!)
                default:
                    throw KeymapError(kind: .invalidArguments, reason: "argument \"\(key)\" must be a string, number or boolean", line: line, bindID: bindID)
                }
                try validate(arg: arg, named: key, for: kind, line: line, bindID: bindID)
                args[key] = arg
            }
        }
        let missing = kind.requiredArgumentNames.filter { args[$0] == nil }
        if !missing.isEmpty {
            throw KeymapError(
                kind: .invalidArguments,
                reason: "\(kind.rawValue) requires \(missing.map { "\"\($0)\"" }.joined(separator: ", ")); e.g. args = { \(exampleArgs(kind)) }",
                line: line, bindID: bindID
            )
        }
        return args
    }

    private static func validate(arg: ArgValue, named name: String, for kind: ActionKind, line: Int?, bindID: String) throws {
        func fail(_ reason: String) -> KeymapError {
            KeymapError(kind: .invalidArguments, reason: "\(kind.rawValue) argument \(name) = \(arg): \(reason)", line: line, bindID: bindID)
        }
        switch name {
        case "index":
            guard case .int(let i) = arg, i >= 1 else { throw fail("must be a workspace number ≥ 1") }
        case "group":
            guard case .int(let g) = arg, g >= 1 else { throw fail("must be a workspace group number ≥ 1") }
        case "direction":
            guard let s = arg.stringValue, Direction(rawValue: s.lowercased()) != nil else {
                throw fail("must be one of left, right, up, down")
            }
        case "axis":
            guard let s = arg.stringValue, ResizeAxis(rawValue: s.lowercased()) != nil else { throw fail("must be width or height") }
        case "delta":
            guard arg.doubleValue != nil, arg.boolValue == nil, arg.stringValue == nil else { throw fail("must be a number (percent of the current window size)") }
        case "key":
            guard let s = arg.stringValue, ["caps", "num"].contains(s.lowercased()) else { throw fail("must be caps or num") }
        case "name", "cmd":
            guard let s = arg.stringValue, !s.isEmpty else { throw fail("must be a non-empty string") }
        default:
            break
        }
    }

    private static func exampleArgs(_ kind: ActionKind) -> String {
        switch kind {
        case .workspaceFocus, .workspaceMove, .workspaceMoveSilent: return "index = 1"
        case .workspaceFocusGroup, .workspaceMoveGroup: return "group = 1"
        case .windowFocus, .windowSwap: return "direction = \"left\""
        case .windowResize: return "axis = \"width\", delta = -10"
        case .exec: return "cmd = \"open -a Finder\""
        case .osdLockKey: return "key = \"caps\""
        case .workspaceMoveToSpecial, .specialToggle: return "name = \"special\""
        default: return ""
        }
    }

    private static func ensurePanicBind(in binds: [Bind], warnings: inout [String]) -> [Bind] {
        var result = binds
        let fixed = panicBind
        if let index = result.firstIndex(where: { $0.id == panicBindID }) {
            let existing = result[index]
            var problems: [String] = []
            if existing.action.kind != .wmPanic { problems.append("action \"\(existing.action.kind.rawValue)\"") }
            if existing.chords != fixed.chords { problems.append("keys \(existing.keys)") }
            if !existing.enabled { problems.append("enabled = false") }
            if !existing.flags.isEmpty { problems.append("flags \(existing.flags.map(\.rawValue).sorted())") }
            if !problems.isEmpty {
                warnings.append("bind \"\(panicBindID)\" is fixed and cannot be changed (\(problems.joined(separator: ", "))); restored to \(panicChordText)")
                result[index] = fixed
            }
        } else {
            warnings.append("keymap has no \"\(panicBindID)\" bind; the fixed panic chord \(panicChordText) was added (it cannot be removed)")
            result.append(fixed)
        }
        return result
    }

    // MARK: - TOML writing helpers

    static func tomlString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    static func tomlValue(_ v: ArgValue) -> String {
        switch v {
        case .string(let s): return tomlString(s)
        case .int(let i): return String(i)
        case .double(let d):
            if d.isNaN { return "nan" }
            if d.isInfinite { return d < 0 ? "-inf" : "inf" }
            let text = String(d)
            return text.contains(".") || text.contains("e") ? text : text + ".0"
        case .bool(let b): return b ? "true" : "false"
        }
    }
}

/// Maps TOML structure back to source lines: TOMLKit does not expose node positions, so the parser
/// locates `[[bind]]` headers and `key =` lines itself.
struct SourceLines {
    private let lines: [Substring]
    let bindHeaderLines: [Int]

    init(_ text: String) {
        let split = text.split(separator: "\n", omittingEmptySubsequences: false)
        lines = split
        var headers: [Int] = []
        for (i, line) in split.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[[") {
                let inner = t.dropFirst(2).prefix { $0 != "]" }.trimmingCharacters(in: .whitespaces)
                if inner == "bind" { headers.append(i + 1) }
            }
        }
        bindHeaderLines = headers
    }

    /// First line (1-based) at or after `after` that defines `key` (`key =` or `[key]`).
    func line(ofKey key: String, after: Int? = nil) -> Int? {
        let start = max(0, (after ?? 1) - 1)
        guard start < lines.count else { return nil }
        for i in start..<lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") {
                let inner = t.drop { $0 == "[" }.prefix { $0 != "]" }.trimmingCharacters(in: .whitespaces)
                if inner == key { return i + 1 }
                continue
            }
            if t.hasPrefix(key) {
                let rest = t.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("=") { return i + 1 }
            }
        }
        return nil
    }
}

// MARK: - Loader

/// Loads keymaps from the bundled default and from the user's file.
public struct KeymapLoader: Sendable {
    /// Resource name of the shipped default (`Sources/CaelestiaCore/Resources/keymap.default.toml`).
    public static let defaultResourceName = "keymap.default"

    /// Location of the bundled default keymap, if the resource bundle is intact.
    public static var defaultKeymapURL: URL? {
        let bundle = Bundle.module
        if let url = bundle.url(forResource: defaultResourceName, withExtension: "toml", subdirectory: "Resources") {
            return url
        }
        if let url = bundle.url(forResource: defaultResourceName, withExtension: "toml") {
            return url
        }
        if let base = bundle.resourceURL {
            let candidate = base.appendingPathComponent("Resources/\(defaultResourceName).toml")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The text of the bundled default keymap.
    public static func defaultKeymapText() throws -> String {
        guard let url = defaultKeymapURL else {
            throw KeymapError(kind: .io, reason: "bundled \(defaultResourceName).toml not found in \(Bundle.module.bundlePath)")
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw KeymapError(kind: .io, reason: "cannot read \(url.path): \(error.localizedDescription)")
        }
    }

    /// The bundled default keymap. The resource is verified by the test suite; should the bundle
    /// nevertheless be damaged this logs a fault and returns a map with only the panic bind so the
    /// WM stays controllable.
    public static func loadDefault() -> Keymap {
        do {
            return try loadDefaultOrThrow()
        } catch {
            Log.config.fault("default keymap unavailable: \(String(describing: error), privacy: .public)")
            return Keymap(modifiers: .optionIsSuper, binds: [KeymapParser.panicBind])
        }
    }

    /// The bundled default keymap, or the reason it cannot be loaded.
    public static func loadDefaultOrThrow() throws -> Keymap {
        try KeymapParser.parse(toml: try defaultKeymapText())
    }

    /// Parses the keymap at `url`.
    public static func load(from url: URL) throws -> Keymap {
        var warnings: [String] = []
        return try load(from: url, warnings: &warnings)
    }

    /// Parses the keymap at `url`, appending parser warnings to `warnings`.
    public static func load(from url: URL, warnings: inout [String]) throws -> Keymap {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw KeymapError(kind: .io, reason: "cannot read \(url.path): \(error.localizedDescription)")
        }
        return try KeymapParser.parse(toml: text, warnings: &warnings)
    }

    /// The user's `~/.config/caelestia-mac/keymap.toml` when present and valid, otherwise the bundled
    /// default. Problems with the user file are returned as warnings, never thrown.
    public static func loadUserOrDefault() -> (Keymap, [String]) {
        loadUserOrDefault(userFile: Paths.keymapFile)
    }

    /// ``loadUserOrDefault()`` with an explicit user file (for tests).
    public static func loadUserOrDefault(userFile: URL) -> (Keymap, [String]) {
        var warnings: [String] = []
        if FileManager.default.fileExists(atPath: userFile.path) {
            do {
                let keymap = try load(from: userFile, warnings: &warnings)
                return (keymap, warnings)
            } catch {
                warnings.append("\(userFile.path): \(error); using the default keymap")
            }
        }
        return (loadDefault(), warnings)
    }
}

// MARK: - Watcher

/// Watches the user keymap and reloads it on change (section 3.2 hot reload).
///
/// Events on the file and on its directory (editors save atomically by renaming a temp file over the
/// original) are debounced, then the file is parsed: a good parse is delivered to `onChange` within
/// ~200 ms, a bad one to `onError` while the last good keymap stays in force.
public final class KeymapWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable (_ keymap: Keymap, _ warnings: [String]) -> Void
    public typealias ErrorHandler = @Sendable (_ error: KeymapError) -> Void

    /// The watched file.
    public let url: URL
    /// Quiet period after the last file-system event before reloading.
    public let debounce: TimeInterval

    private let queue: DispatchQueue
    private let onChange: ChangeHandler
    private let onError: ErrorHandler
    private let fallback: Keymap?
    private let lock = NSLock()

    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var watchedDirectory: URL?
    private var pending: DispatchWorkItem?
    private var lastContents: Data?
    private var _lastGood: Keymap?
    private var running = false
    private var missingReported = false

    /// - Parameters:
    ///   - url: the keymap file (defaults to `Paths.keymapFile`).
    ///   - debounce: quiet period in seconds (default 0.1).
    ///   - fallback: delivered when the file is missing (deleting the user keymap = back to defaults).
    ///   - onChange: called on the watcher queue after every successful (re)load.
    ///   - onError: called when the file exists but cannot be read or parsed; the last good map is kept.
    public init(
        url: URL = Paths.keymapFile, debounce: TimeInterval = 0.1, fallback: Keymap? = nil,
        onChange: @escaping ChangeHandler, onError: @escaping ErrorHandler
    ) {
        self.url = url.standardizedFileURL
        self.debounce = debounce
        self.fallback = fallback
        self.onChange = onChange
        self.onError = onError
        self.queue = DispatchQueue(label: "com.caelestia.mac.keymap-watcher", qos: .userInitiated)
    }

    deinit {
        fileSource?.cancel()
        directorySource?.cancel()
    }

    /// The last keymap that parsed successfully (or the fallback), if any.
    public var lastGood: Keymap? {
        lock.lock()
        defer { lock.unlock() }
        return _lastGood
    }

    /// Starts watching. With `deliverInitial` the current file is loaded right away.
    public func start(deliverInitial: Bool = true) {
        queue.async { [self] in
            guard !running else { return }
            running = true
            arm()
            if deliverInitial { reload() }
        }
    }

    /// Stops watching; pending reloads are dropped.
    public func stop() {
        queue.async { [self] in
            running = false
            pending?.cancel()
            pending = nil
            fileSource?.cancel()
            fileSource = nil
            directorySource?.cancel()
            directorySource = nil
            watchedDirectory = nil
        }
    }

    /// Reloads immediately (bypassing the debounce), e.g. after Settings wrote the file itself.
    public func reloadNow() {
        queue.async { [self] in
            pending?.cancel()
            pending = nil
            reload()
        }
    }

    // MARK: Internals (all on `queue`)

    private func arm() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(url.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke, .link], queue: queue
            )
            source.setEventHandler { [weak self] in self?.scheduleReload() }
            source.setCancelHandler { close(fd) }
            source.resume()
            fileSource = source
        }

        let directory = nearestExistingDirectory(for: url)
        if directorySource == nil || watchedDirectory != directory {
            directorySource?.cancel()
            directorySource = nil
            watchedDirectory = nil
            let dfd = open(directory.path, O_EVTONLY)
            if dfd >= 0 {
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: dfd, eventMask: [.write, .delete, .rename, .link], queue: queue
                )
                source.setEventHandler { [weak self] in self?.scheduleReload() }
                source.setCancelHandler { close(dfd) }
                source.resume()
                directorySource = source
                watchedDirectory = directory
            }
        }
    }

    private func nearestExistingDirectory(for file: URL) -> URL {
        var dir = file.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        while dir.path.count > 1 {
            if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "/")
    }

    private func scheduleReload() {
        guard running else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.reload()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func reload() {
        guard running else { return }
        arm()
        guard FileManager.default.fileExists(atPath: url.path) else {
            guard !missingReported else { return }
            missingReported = true
            lastContents = nil
            if let fallback {
                setLastGood(fallback)
                onChange(fallback, ["\(url.path) is missing; using the default keymap"])
            } else {
                onError(KeymapError(kind: .io, reason: "\(url.path) does not exist"))
            }
            return
        }
        missingReported = false
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            onError(KeymapError(kind: .io, reason: "cannot read \(url.path): \(error.localizedDescription)"))
            return
        }
        if data == lastContents { return }
        guard let text = String(data: data, encoding: .utf8) else {
            onError(KeymapError(kind: .io, reason: "\(url.path) is not UTF-8"))
            return
        }
        var warnings: [String] = []
        do {
            let keymap = try KeymapParser.parse(toml: text, warnings: &warnings)
            lastContents = data
            setLastGood(keymap)
            onChange(keymap, warnings)
        } catch let error as KeymapError {
            onError(error)
        } catch {
            onError(KeymapError(kind: .structure, reason: String(describing: error)))
        }
    }

    private func setLastGood(_ keymap: Keymap) {
        lock.lock()
        _lastGood = keymap
        lock.unlock()
    }
}
