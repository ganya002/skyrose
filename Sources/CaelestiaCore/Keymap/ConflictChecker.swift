import Foundation

// MARK: - Report types

public enum ConflictSeverity: String, Codable, Sendable, Comparable {
    case error, warn, info

    private var rank: Int {
        switch self {
        case .error: return 0
        case .warn: return 1
        case .info: return 2
        }
    }

    public static func < (a: ConflictSeverity, b: ConflictSeverity) -> Bool { a.rank < b.rank }
}

/// One finding of the conflict checker (section 3.3).
public struct ConflictItem: Codable, Sendable, Hashable {
    public var severity: ConflictSeverity
    /// The bind the finding is about, if any.
    public var bindID: String?
    /// The chord as written in the keymap ("SUPER + Space").
    public var chord: String
    /// `duplicate` | `system` | `app` | `optionChar` | `missingKey`.
    public var category: String
    public var message: String
    /// A suggested fix, when there is one.
    public var fix: String?

    public init(severity: ConflictSeverity, bindID: String?, chord: String, category: String, message: String, fix: String?) {
        self.severity = severity
        self.bindID = bindID
        self.chord = chord
        self.category = category
        self.message = message
        self.fix = fix
    }

    public static let duplicateCategory = "duplicate"
    public static let systemCategory = "system"
    public static let appCategory = "app"
    public static let optionCharCategory = "optionChar"
    public static let missingKeyCategory = "missingKey"
}

/// The outcome of ``ConflictChecker/check()``.
public struct ConflictReport: Codable, Sendable {
    public var items: [ConflictItem]
    public var errorCount: Int
    public var warnCount: Int
    public var infoCount: Int

    public init(items: [ConflictItem]) {
        self.items = items
        errorCount = items.filter { $0.severity == .error }.count
        warnCount = items.filter { $0.severity == .warn }.count
        infoCount = items.filter { $0.severity == .info }.count
    }

    /// `true` when nothing of severity `error` was found.
    public var isClean: Bool { errorCount == 0 }

    /// A fixed-width text table for the CLI, followed by a summary line.
    public func formattedTable() -> String {
        guard !items.isEmpty else { return "No conflicts found." }
        let header = ["SEVERITY", "CATEGORY", "CHORD", "BIND", "MESSAGE", "FIX"]
        let rows = items.map { item in
            [item.severity.rawValue.uppercased(), item.category, item.chord, item.bindID ?? "-", item.message, item.fix ?? "-"]
        }
        var widths = header.map(\.count)
        for row in rows {
            for (i, cell) in row.enumerated() { widths[i] = max(widths[i], cell.count) }
        }
        func line(_ cells: [String]) -> String {
            cells.enumerated().map { i, cell in
                i == cells.count - 1 ? cell : cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }
        var out = [line(header), line(widths.map { String(repeating: "-", count: $0) })]
        out += rows.map(line)
        out.append("")
        out.append("\(errorCount) error\(errorCount == 1 ? "" : "s"), \(warnCount) warning\(warnCount == 1 ? "" : "s"), \(infoCount) info")
        return out.joined(separator: "\n")
    }
}

// MARK: - macOS symbolic hotkeys

/// A macOS keyboard shortcut from `com.apple.symbolichotkeys` (or one that cannot be changed).
public struct SystemHotkey: Sendable, Hashable {
    /// `AppleSymbolicHotKeys` id; `nil` for the fixed ones macOS does not expose.
    public var id: Int?
    public var name: String
    /// Virtual key code, or `nil` when the shortcut has no key assigned.
    public var keyCode: UInt16?
    /// Modifier flags in `NX_*MASK` form (shift 0x20000, control 0x40000, option 0x80000,
    /// command 0x100000, fn 0x800000) — the same values as `PhysicalModifier.familyFlag`.
    public var modifierFlags: UInt64
    public var enabled: Bool
    /// `true` for ⌘Tab, ⌘⇧Q, ⌃⌘Q, ⌥⌘Esc: not configurable in System Settings.
    public var isFixed: Bool

    public init(id: Int?, name: String, keyCode: UInt16?, modifierFlags: UInt64, enabled: Bool, isFixed: Bool = false) {
        self.id = id
        self.name = name
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.enabled = enabled
        self.isFixed = isFixed
    }

    public static let shiftFlag: UInt64 = 0x0002_0000
    public static let controlFlag: UInt64 = 0x0004_0000
    public static let optionFlag: UInt64 = 0x0008_0000
    public static let commandFlag: UInt64 = 0x0010_0000
    public static let fnFlag: UInt64 = 0x0080_0000
    public static let allFlags: UInt64 = shiftFlag | controlFlag | optionFlag | commandFlag | fnFlag

    /// "⌃⌥Space"-style rendering of the physical chord.
    public var chordSymbols: String {
        var s = ""
        if modifierFlags & Self.fnFlag != 0 { s += "fn " }
        if modifierFlags & Self.controlFlag != 0 { s += "⌃" }
        if modifierFlags & Self.optionFlag != 0 { s += "⌥" }
        if modifierFlags & Self.shiftFlag != 0 { s += "⇧" }
        if modifierFlags & Self.commandFlag != 0 { s += "⌘" }
        return s + (keyCode.map { ChordParser.keyLabel(.code($0)) } ?? "(no key)")
    }

    /// Default path of the user's symbolic hotkeys plist.
    public static var defaultPlistURL: URL {
        Paths.home.appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")
    }

    /// macOS defaults: what applies when an id is absent from the plist.
    public static let defaults: [SystemHotkey] = {
        let c = controlFlag, o = optionFlag, s = shiftFlag, m = commandFlag, f = fnFlag
        var list: [SystemHotkey] = [
            SystemHotkey(id: 7, name: "Move focus to the menu bar", keyCode: 0x78, modifierFlags: c | f, enabled: true),
            SystemHotkey(id: 8, name: "Move focus to the Dock", keyCode: 0x63, modifierFlags: c | f, enabled: true),
            SystemHotkey(id: 9, name: "Move focus to active or next window", keyCode: 0x76, modifierFlags: c | f, enabled: true),
            SystemHotkey(id: 10, name: "Move focus to the window toolbar", keyCode: 0x60, modifierFlags: c | f, enabled: true),
            SystemHotkey(id: 11, name: "Move focus to the floating window", keyCode: 0x61, modifierFlags: c | f, enabled: true),
            SystemHotkey(id: 12, name: "Turn keyboard access on or off", keyCode: 0x7A, modifierFlags: c | f, enabled: true),
            SystemHotkey(id: 13, name: "Change the way Tab moves focus", keyCode: 0x62, modifierFlags: c | f, enabled: true),
            SystemHotkey(id: 15, name: "Turn zoom on or off", keyCode: 0x1C, modifierFlags: o | m, enabled: false),
            SystemHotkey(id: 17, name: "Zoom in", keyCode: 0x18, modifierFlags: o | m, enabled: false),
            SystemHotkey(id: 19, name: "Zoom out", keyCode: 0x1B, modifierFlags: o | m, enabled: false),
            SystemHotkey(id: 21, name: "Invert colors", keyCode: 0x1C, modifierFlags: c | o | m, enabled: false),
            SystemHotkey(id: 23, name: "Turn image smoothing on or off", keyCode: 0x2A, modifierFlags: o | m, enabled: false),
            SystemHotkey(id: 25, name: "Increase contrast", keyCode: 0x2F, modifierFlags: c | o | m, enabled: false),
            SystemHotkey(id: 26, name: "Decrease contrast", keyCode: 0x2B, modifierFlags: c | o | m, enabled: false),
            SystemHotkey(id: 27, name: "Move focus to next window", keyCode: 0x32, modifierFlags: m, enabled: true),
            SystemHotkey(id: 28, name: "Save picture of screen as a file", keyCode: 0x14, modifierFlags: s | m, enabled: true),
            SystemHotkey(id: 29, name: "Copy picture of screen to the clipboard", keyCode: 0x14, modifierFlags: c | s | m, enabled: true),
            SystemHotkey(id: 30, name: "Save picture of selected area as a file", keyCode: 0x15, modifierFlags: s | m, enabled: true),
            SystemHotkey(id: 31, name: "Copy picture of selected area to the clipboard", keyCode: 0x15, modifierFlags: c | s | m, enabled: true),
            SystemHotkey(id: 32, name: "Mission Control", keyCode: 0x7E, modifierFlags: c, enabled: true),
            SystemHotkey(id: 33, name: "Application windows", keyCode: 0x7D, modifierFlags: c, enabled: true),
            SystemHotkey(id: 34, name: "Mission Control (Shift variant)", keyCode: 0x7E, modifierFlags: c | s, enabled: true),
            SystemHotkey(id: 35, name: "Application windows (Shift variant)", keyCode: 0x7D, modifierFlags: c | s, enabled: true),
            SystemHotkey(id: 36, name: "Show Desktop", keyCode: 0x67, modifierFlags: f, enabled: true),
            SystemHotkey(id: 37, name: "Show Desktop (Shift variant)", keyCode: 0x67, modifierFlags: s | f, enabled: true),
            SystemHotkey(id: 52, name: "Turn Dock hiding on/off", keyCode: 0x02, modifierFlags: o | m, enabled: true),
            SystemHotkey(id: 57, name: "Move focus to status menus", keyCode: 0x64, modifierFlags: c | f, enabled: true),
            SystemHotkey(id: 59, name: "Turn VoiceOver on or off", keyCode: 0x60, modifierFlags: m | f, enabled: true),
            SystemHotkey(id: 60, name: "Select the previous input source", keyCode: 0x31, modifierFlags: c, enabled: true),
            SystemHotkey(id: 61, name: "Select next source in Input menu", keyCode: 0x31, modifierFlags: c | o, enabled: true),
            SystemHotkey(id: 64, name: "Show Spotlight search", keyCode: 0x31, modifierFlags: m, enabled: true),
            SystemHotkey(id: 65, name: "Show Finder search window", keyCode: 0x31, modifierFlags: o | m, enabled: true),
            SystemHotkey(id: 79, name: "Move left a space", keyCode: 0x7B, modifierFlags: c, enabled: true),
            SystemHotkey(id: 80, name: "Move right a space", keyCode: 0x7C, modifierFlags: c, enabled: true),
            SystemHotkey(id: 81, name: "Move left a space (Shift variant)", keyCode: 0x7B, modifierFlags: c | s, enabled: true),
            SystemHotkey(id: 82, name: "Move right a space (Shift variant)", keyCode: 0x7C, modifierFlags: c | s, enabled: true),
            SystemHotkey(id: 98, name: "Show Help menu", keyCode: 0x2C, modifierFlags: s | m, enabled: true),
            SystemHotkey(id: 160, name: "Show Launchpad", keyCode: nil, modifierFlags: 0, enabled: true),
            SystemHotkey(id: 163, name: "Show Notification Center", keyCode: nil, modifierFlags: 0, enabled: true),
            SystemHotkey(id: 164, name: "Turn Do Not Disturb on/off", keyCode: nil, modifierFlags: 0, enabled: true),
            SystemHotkey(id: 175, name: "Application windows", keyCode: nil, modifierFlags: 0, enabled: true),
            SystemHotkey(id: 184, name: "Screenshot and recording options", keyCode: 0x17, modifierFlags: s | m, enabled: true),
            SystemHotkey(id: 222, name: "Show Desktop", keyCode: nil, modifierFlags: 0, enabled: true),
        ]
        let digitCodes: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        for (n, code) in digitCodes.enumerated() {
            list.append(SystemHotkey(id: 118 + n, name: "Switch to Desktop \(n + 1)", keyCode: code, modifierFlags: c, enabled: false))
        }
        return list
    }()

    /// Shortcuts macOS does not let the user change.
    public static let fixed: [SystemHotkey] = [
        SystemHotkey(id: nil, name: "App switcher", keyCode: 0x30, modifierFlags: commandFlag, enabled: true, isFixed: true),
        SystemHotkey(id: nil, name: "App switcher (reverse)", keyCode: 0x30, modifierFlags: commandFlag | shiftFlag, enabled: true, isFixed: true),
        SystemHotkey(id: nil, name: "Log out", keyCode: 0x0C, modifierFlags: commandFlag | shiftFlag, enabled: true, isFixed: true),
        SystemHotkey(id: nil, name: "Lock screen", keyCode: 0x0C, modifierFlags: controlFlag | commandFlag, enabled: true, isFixed: true),
        SystemHotkey(id: nil, name: "Force Quit", keyCode: 0x35, modifierFlags: optionFlag | commandFlag, enabled: true, isFixed: true),
    ]

    /// The effective shortcuts: ``defaults`` overlaid with the user's plist, plus ``fixed``.
    /// A missing or unreadable plist yields the defaults.
    public static func effective(plist url: URL?) -> [SystemHotkey] {
        var byID: [Int: SystemHotkey] = [:]
        for h in defaults { byID[h.id!] = h }
        for (id, entry) in read(plist: url ?? defaultPlistURL) {
            var hotkey = byID[id] ?? SystemHotkey(id: id, name: "macOS shortcut \(id)", keyCode: nil, modifierFlags: 0, enabled: true)
            hotkey.enabled = entry.enabled
            if let keyCode = entry.keyCode {
                hotkey.keyCode = keyCode
                hotkey.modifierFlags = entry.modifierFlags
            }
            byID[id] = hotkey
        }
        return byID.values.sorted { $0.id! < $1.id! } + fixed
    }

    struct PlistEntry {
        var enabled: Bool
        var keyCode: UInt16?
        var modifierFlags: UInt64
    }

    /// Parses `AppleSymbolicHotKeys` from the plist: `id → { enabled, value.parameters [char, key, flags] }`.
    static func read(plist url: URL) -> [Int: PlistEntry] {
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let hotkeys = root["AppleSymbolicHotKeys"] as? [String: Any]
        else { return [:] }
        var result: [Int: PlistEntry] = [:]
        for (key, value) in hotkeys {
            guard let id = Int(key), let dict = value as? [String: Any] else { continue }
            let enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
            var entry = PlistEntry(enabled: enabled, keyCode: nil, modifierFlags: 0)
            if let inner = dict["value"] as? [String: Any], let params = inner["parameters"] as? [NSNumber], params.count >= 3 {
                let code = params[1].intValue
                if code >= 0, code < 0xFFFF {
                    entry.keyCode = UInt16(code)
                    entry.modifierFlags = UInt64(truncatingIfNeeded: params[2].int64Value) & allFlags
                }
            }
            result[id] = entry
        }
        return result
    }
}

// MARK: - Checker

/// Runs the five checks of section 3.3 over a keymap.
public struct ConflictChecker {
    public var keymap: Keymap
    public var layout: any KeyboardLayoutCharacters
    public var systemHotkeysPlist: URL?
    public var isLaptop: Bool

    /// - Parameters:
    ///   - keymap: the keymap to check.
    ///   - layout: supplies Option characters for check 4 (the Platform module passes the real layout).
    ///   - systemHotkeysPlist: `com.apple.symbolichotkeys.plist`; `nil` reads the user's own.
    ///   - isLaptop: run check 5 (keys a MacBook keyboard lacks).
    public init(
        keymap: Keymap, layout: any KeyboardLayoutCharacters = USQwertyCharacters(), systemHotkeysPlist: URL? = nil,
        isLaptop: Bool = true
    ) {
        self.keymap = keymap
        self.layout = layout
        self.systemHotkeysPlist = systemHotkeysPlist
        self.isLaptop = isLaptop
    }

    public func check() -> ConflictReport {
        var items: [ConflictItem] = []
        items += duplicateItems()
        items += systemItems(hotkeys: SystemHotkey.effective(plist: systemHotkeysPlist))
        items += appShortcutItems()
        items += optionCharacterItems()
        if isLaptop { items += missingKeyItems() }
        items.sort { a, b in
            if a.severity != b.severity { return a.severity < b.severity }
            if a.category != b.category { return a.category < b.category }
            return a.chord < b.chord
        }
        return ConflictReport(items: items)
    }

    // MARK: Helpers

    private struct BoundChord {
        var bind: Bind
        var chord: KeyChord
        var text: String
    }

    private var enabledChords: [BoundChord] {
        var result: [BoundChord] = []
        for bind in keymap.binds where bind.enabled {
            for (i, chord) in bind.chords.enumerated() {
                result.append(BoundChord(bind: bind, chord: chord, text: i < bind.keys.count ? bind.keys[i] : ChordParser.keymapNotation(chord)))
            }
        }
        return result
    }

    /// NX-style flags of the physical modifiers a logical chord resolves to.
    private func physicalFlags(_ chord: KeyChord) -> UInt64 {
        chord.modifiers.reduce(0) { $0 | keymap.modifiers[$1].familyFlag }
    }

    private func macNotation(_ chord: KeyChord) -> String {
        ChordParser.format(chord, modifierMap: keymap.modifiers, layout: layout)
    }

    // MARK: 1. Duplicates

    private func duplicateItems() -> [ConflictItem] {
        var items: [ConflictItem] = []
        var firstText: [KeyChord: String] = [:]
        for bound in enabledChords where firstText[bound.chord] == nil { firstText[bound.chord] = bound.text }
        for (chord, binds) in keymap.bindsByChord where binds.count > 1 {
            let names = binds.map { "\($0.id) (\($0.action))" }
            let sameAction = Set(binds.map(\.action)).count == 1
            items.append(ConflictItem(
                severity: sameAction ? .warn : .error,
                bindID: binds.last?.id,
                chord: firstText[chord] ?? ChordParser.keymapNotation(chord),
                category: ConflictItem.duplicateCategory,
                message: sameAction
                    ? "\(macNotation(chord)) is bound \(binds.count) times to the same action by \(binds.map(\.id).joined(separator: ", "))"
                    : "\(macNotation(chord)) is bound to \(binds.count) different actions: \(names.joined(separator: ", "))",
                fix: sameAction ? "Remove the redundant bind." : "Remove or disable (enabled = false) all but one of them."
            ))
        }
        return items
    }

    // MARK: 2. macOS system shortcuts

    private func systemItems(hotkeys: [SystemHotkey]) -> [ConflictItem] {
        var items: [ConflictItem] = []
        let active = hotkeys.filter { $0.enabled && $0.keyCode != nil }
        for bound in enabledChords {
            guard case .code(let code) = bound.chord.key else { continue }
            let flags = physicalFlags(bound.chord)
            for hotkey in active where hotkey.keyCode == code && hotkey.modifierFlags == flags {
                let fix: String
                if hotkey.isFixed {
                    fix = "This macOS shortcut cannot be turned off: move the bind to another chord or pick another modifier preset."
                } else if let id = hotkey.id {
                    fix = "Turn off \"\(hotkey.name)\" in System Settings › Keyboard › Keyboard Shortcuts, or let Caelestia disable it (symbolichotkeys id \(id)) after backing up the plist."
                } else {
                    fix = "Move the bind to another chord."
                }
                items.append(ConflictItem(
                    severity: .error,
                    bindID: bound.bind.id,
                    chord: bound.text,
                    category: ConflictItem.systemCategory,
                    message: "\(bound.text) is \(hotkey.chordSymbols), the macOS shortcut \"\(hotkey.name)\"\(hotkey.isFixed ? " (fixed)" : hotkey.id.map { " (id \($0), enabled)" } ?? "")",
                    fix: fix
                ))
            }
        }
        return items
    }

    // MARK: 3. Common app shortcuts

    private static let appShortcuts: [UInt16: String] = [
        0x0C: "Quit", 0x0D: "Close window", 0x11: "New tab", 0x08: "Copy", 0x09: "Paste", 0x07: "Cut",
        0x06: "Undo", 0x01: "Save", 0x03: "Find", 0x2B: "Settings…", 0x2F: "Cancel",
    ]

    private func appShortcutItems() -> [ConflictItem] {
        let map = keymap.modifiers
        let cmdLogical = LogicalModifier.allCases.filter { map[$0].familyFlag == SystemHotkey.commandFlag }
        guard !cmdLogical.isEmpty else { return [] }
        var items: [ConflictItem] = []
        for bound in enabledChords {
            guard case .code(let code) = bound.chord.key, let meaning = Self.appShortcuts[code] else { continue }
            guard physicalFlags(bound.chord) == SystemHotkey.commandFlag else { continue }
            items.append(ConflictItem(
                severity: .warn,
                bindID: bound.bind.id,
                chord: bound.text,
                category: ConflictItem.appCategory,
                message: "\(bound.text) is \(macNotation(bound.chord)), which is \"\(meaning)\" in most apps; the window manager swallows it everywhere for \(bound.bind.action)",
                fix: "Move the bind to another key, or use a preset where \(cmdLogical.map(\.rawValue).joined(separator: "/")) is not a Command key."
            ))
        }
        return items
    }

    // MARK: 4. Option characters

    private func optionCharacterItems() -> [ConflictItem] {
        let map = keymap.modifiers
        let optionLogical = LogicalModifier.allCases.filter { map[$0].familyFlag == SystemHotkey.optionFlag }
        guard let logical = optionLogical.first else { return [] }
        let physical = map[logical]
        let otherSide: String? = physical == .lopt ? "Right" : physical == .ropt ? "Left" : nil
        var items: [ConflictItem] = []
        for bound in enabledChords {
            guard case .code(let code) = bound.chord.key else { continue }
            let flags = physicalFlags(bound.chord)
            let shift = flags == SystemHotkey.optionFlag | SystemHotkey.shiftFlag
            guard flags == SystemHotkey.optionFlag || shift else { continue }
            guard let ch = layout.optionCharacter(forKeyCode: code, shift: shift), !ch.isEmpty else { continue }
            let still = otherSide.map { "; typing it with the \($0.uppercased()) Option key still works" } ?? "; it cannot be typed while the window manager runs"
            items.append(ConflictItem(
                severity: otherSide == nil ? .warn : .info,
                bindID: bound.bind.id,
                chord: bound.text,
                category: ConflictItem.optionCharCategory,
                message: "\(macNotation(bound.chord)) hides \"\(ch)\" on the \(layout.layoutName) layout\(still)",
                fix: otherSide.map { "Type \"\(ch)\" with \($0) Option, or move the bind." } ?? "Map \(logical.rawValue) to a side-specific key (lopt/ropt) so the other Option keeps typing \"\(ch)\"."
            ))
        }
        return items
    }

    // MARK: 5. Keys a MacBook lacks

    private static let fnAlternatives: [String: String] = [
        "Delete": "fn ⌫", "PageUp": "fn ↑", "PageDown": "fn ↓", "Home": "fn ←", "End": "fn →",
    ]

    private func missingKeyItems() -> [ConflictItem] {
        var items: [ConflictItem] = []
        for bound in enabledChords {
            let missingName: String
            var fnAlternative: String?
            switch bound.chord.key {
            case .code(let code):
                guard let name = KeyTable.name(for: code), KeyTable.missingOnMacBook.contains(name) else { continue }
                missingName = name
                fnAlternative = Self.fnAlternatives[name]
            case .media(.micMute): missingName = "a microphone-mute key"
            case .media(.stop): missingName = "a Stop media key"
            default: continue
            }
            let alternatives = bound.bind.chords.enumerated()
                .filter { $0.element != bound.chord && !usesMissingKey($0.element) }
                .map { $0.offset < bound.bind.keys.count ? bound.bind.keys[$0.offset] : ChordParser.keymapNotation($0.element) }
            let modifiers = ChordParser.modifierSymbols(bound.chord.modifiers, modifierMap: keymap.modifiers).map { $0 + " " }.joined()
            var message = "\(bound.text) uses \(missingName), which the MacBook keyboard lacks"
            var fix: String?
            var severity = ConflictSeverity.info
            if let fnAlternative {
                message += "; press \(modifiers)\(fnAlternative) instead"
            } else if !alternatives.isEmpty {
                message += "; use \(alternatives.joined(separator: " or ")) instead"
            } else if bound.bind.action.kind == .osdLockKey {
                message += "; the OSD only appears on an external keyboard that has it"
            } else {
                severity = .warn
                fix = "Add a chord a MacBook can type to bind \"\(bound.bind.id)\"."
            }
            items.append(ConflictItem(
                severity: severity,
                bindID: bound.bind.id,
                chord: bound.text,
                category: ConflictItem.missingKeyCategory,
                message: message,
                fix: fix
            ))
        }
        return items
    }

    private func usesMissingKey(_ chord: KeyChord) -> Bool {
        switch chord.key {
        case .code(let code): return KeyTable.name(for: code).map { KeyTable.missingOnMacBook.contains($0) } ?? false
        case .media(.micMute), .media(.stop): return true
        default: return false
        }
    }
}
