import Foundation

// MARK: - Keyboard layout characters

/// Supplies the characters a keyboard layout produces for physical key codes, so the cheat sheet can
/// show "+" and "-" for the Norwegian layout where the key table only knows `Minus` and `Equal`, and
/// so the conflict checker can name the character an Option chord hides.
///
/// The Platform module implements this with `UCKeyTranslate` on the current input source; Core ships
/// ``USQwertyCharacters`` as a layout-independent default.
public protocol KeyboardLayoutCharacters: Sendable {
    /// Human-readable layout name shown in messages ("U.S.", "Norwegian").
    var layoutName: String { get }

    /// The character typed for `code` with no modifier (or with Shift), or `nil` for keys that do not
    /// produce a character (arrows, function keys, …).
    func character(forKeyCode code: UInt16, shift: Bool) -> String?

    /// The character typed for `code` with Option (and optionally Shift) held, or `nil` when the layout
    /// produces nothing for that combination. Dead keys return the accent they insert.
    func optionCharacter(forKeyCode code: UInt16, shift: Bool) -> String?
}

extension KeyboardLayoutCharacters {
    /// The character typed for `code` with Option alone (section 3.3 item 4).
    public func optionCharacter(forKeyCode code: UInt16) -> String? {
        optionCharacter(forKeyCode: code, shift: false)
    }
}

/// The U.S. ANSI layout, used when no platform layout is available (tests, docs generation).
public struct USQwertyCharacters: KeyboardLayoutCharacters {
    public init() {}

    public var layoutName: String { "U.S." }

    public func character(forKeyCode code: UInt16, shift: Bool) -> String? {
        shift ? Self.shifted[code] : Self.base[code]
    }

    public func optionCharacter(forKeyCode code: UInt16, shift: Bool) -> String? {
        shift ? Self.optionShifted[code] : Self.option[code]
    }

    private static let base: [UInt16: String] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x", 0x08: "c",
        0x09: "v", 0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t", 0x12: "1",
        0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-",
        0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "o", 0x20: "u", 0x21: "[", 0x22: "i", 0x23: "p", 0x25: "l",
        0x26: "j", 0x27: "'", 0x28: "k", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m",
        0x2F: ".", 0x32: "`", 0x0A: "§", 0x31: " ",
        0x52: "0", 0x53: "1", 0x54: "2", 0x55: "3", 0x56: "4", 0x57: "5", 0x58: "6", 0x59: "7", 0x5B: "8",
        0x5C: "9", 0x41: ".", 0x43: "*", 0x45: "+", 0x4B: "/", 0x4E: "-", 0x51: "=",
    ]

    private static let shifted: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C",
        0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "!",
        0x13: "@", 0x14: "#", 0x15: "$", 0x16: "^", 0x17: "%", 0x18: "+", 0x19: "(", 0x1A: "&", 0x1B: "_",
        0x1C: "*", 0x1D: ")", 0x1E: "}", 0x1F: "O", 0x20: "U", 0x21: "{", 0x22: "I", 0x23: "P", 0x25: "L",
        0x26: "J", 0x27: "\"", 0x28: "K", 0x29: ":", 0x2A: "|", 0x2B: "<", 0x2C: "?", 0x2D: "N", 0x2E: "M",
        0x2F: ">", 0x32: "~", 0x0A: "±", 0x31: " ",
    ]

    private static let option: [UInt16: String] = [
        0x00: "å", 0x01: "ß", 0x02: "∂", 0x03: "ƒ", 0x04: "˙", 0x05: "©", 0x06: "Ω", 0x07: "≈", 0x08: "ç",
        0x09: "√", 0x0B: "∫", 0x0C: "œ", 0x0D: "∑", 0x0E: "´", 0x0F: "®", 0x10: "¥", 0x11: "†", 0x12: "¡",
        0x13: "™", 0x14: "£", 0x15: "¢", 0x16: "§", 0x17: "∞", 0x18: "≠", 0x19: "ª", 0x1A: "¶", 0x1B: "–",
        0x1C: "•", 0x1D: "º", 0x1E: "‘", 0x1F: "ø", 0x20: "¨", 0x21: "“", 0x22: "ˆ", 0x23: "π", 0x25: "¬",
        0x26: "∆", 0x27: "æ", 0x28: "˚", 0x29: "…", 0x2A: "«", 0x2B: "≤", 0x2C: "÷", 0x2D: "˜", 0x2E: "µ",
        0x2F: "≥", 0x32: "`", 0x0A: "§",
    ]

    private static let optionShifted: [UInt16: String] = [
        0x00: "Å", 0x01: "Í", 0x02: "Î", 0x03: "Ï", 0x04: "Ó", 0x05: "˝", 0x06: "¸", 0x07: "˛", 0x08: "Ç",
        0x09: "◊", 0x0B: "ı", 0x0C: "Œ", 0x0D: "„", 0x0E: "´", 0x0F: "‰", 0x10: "Á", 0x11: "ˇ", 0x12: "⁄",
        0x13: "€", 0x14: "‹", 0x15: "›", 0x16: "ﬂ", 0x17: "ﬁ", 0x18: "±", 0x19: "·", 0x1A: "‡", 0x1B: "—",
        0x1C: "°", 0x1D: "‚", 0x1E: "’", 0x1F: "Ø", 0x20: "¨", 0x21: "”", 0x22: "ˆ", 0x23: "∏", 0x25: "Ò",
        0x26: "Ô", 0x27: "Æ", 0x28: "", 0x29: "Ú", 0x2A: "»", 0x2B: "¯", 0x2C: "¿", 0x2D: "˜", 0x2E: "Â",
        0x2F: "˘", 0x32: "`", 0x0A: "±",
    ]
}

// MARK: - Chord parsing

/// A chord string could not be parsed.
public struct ChordParseError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The chord text as written.
    public var text: String
    /// What is wrong with it.
    public var reason: String

    public init(text: String, reason: String) {
        self.text = text
        self.reason = reason
    }

    public var description: String { "invalid chord \"\(text)\": \(reason)" }
}

extension KeyChord {
    /// The canonical chord for a modifier tapped on its own (Hyprland "SUPER + SUPER_L" with the
    /// release flag). Taps carry the modifier in the key token and have an empty modifier set.
    public static func tap(_ modifier: LogicalModifier) -> KeyChord {
        KeyChord(modifiers: [], key: .modifierTap(modifier))
    }

    /// `true` for modifier-only chords (see ``tap(_:)``).
    public var isModifierTap: Bool {
        if case .modifierTap = key { return true }
        return false
    }
}

/// Parses and formats chord strings.
///
/// Grammar: tokens separated by `+`, surrounding whitespace ignored, everything case-insensitive.
/// Modifiers are the Linux names `SUPER`, `ALT`, `CTRL` (or `CONTROL`), `SHIFT`; at most one of each.
/// The last token is the key:
/// - a key name from ``KeyTable`` (`Left`, `Page_Up`, `Equal`, `F13`, …) or a raw code `0x1B`,
/// - `mouse:272` / `mouse:left|right|middle`, `mouse_up` / `mouse_down` (scroll),
/// - a media key (`VolumeUp`, `Play`, …) or its XF86 name (`XF86AudioRaiseVolume`, …),
/// - nothing at all (`"SUPER"`) or `SUPER_L` / `SUPER_TAP`: a modifier tap.
///
/// Taps parse to `KeyChord(modifiers: [], key: .modifierTap(m))`; see ``KeyChord/tap(_:)``.
public enum ChordParser {
    /// Parses one chord ("SUPER + SHIFT + Left").
    public static func parse(_ text: String) throws -> KeyChord {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChordParseError(text: text, reason: "empty chord") }

        let tokens = trimmed.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if tokens.contains(where: \.isEmpty) {
            throw ChordParseError(text: text, reason: "empty token; write keys as \"SUPER + Equal\", not \"SUPER + +\"")
        }

        var modifiers = Set<LogicalModifier>()
        var index = 0
        while index < tokens.count, let m = modifier(named: tokens[index]) {
            guard !modifiers.contains(m) else {
                throw ChordParseError(text: text, reason: "modifier \(m.rawValue) is listed twice")
            }
            modifiers.insert(m)
            index += 1
        }

        let rest = Array(tokens[index...])
        if rest.isEmpty {
            // Modifier-only chord: the tap.
            guard modifiers.count == 1, let m = modifiers.first else {
                throw ChordParseError(
                    text: text,
                    reason: "a modifier-only chord (a tap) must name exactly one modifier, e.g. \"SUPER\""
                )
            }
            return .tap(m)
        }
        guard rest.count == 1 else {
            throw ChordParseError(
                text: text,
                reason: "unknown modifier \"\(rest[0])\" (use SUPER, ALT, CTRL, SHIFT) or extra key \"\(rest[1])\""
            )
        }
        let keyText = rest[0]

        if let tapped = tapModifier(named: keyText) {
            guard modifiers.isSubset(of: [tapped]) else {
                throw ChordParseError(
                    text: text,
                    reason: "\(keyText) is the \(tapped.rawValue) tap and cannot be combined with other modifiers"
                )
            }
            return .tap(tapped)
        }
        let key = try keyToken(keyText, chord: text)
        return KeyChord(modifiers: modifiers, key: key)
    }

    /// Parses several chords separated by `separator` (the `linux` field uses " | ").
    public static func parseList(_ text: String, separator: Character = "|") throws -> [KeyChord] {
        try text.split(separator: separator).map { try parse(String($0)) }
    }

    // MARK: Formatting

    /// Mac notation for the cheat sheet: physical modifier symbols in Apple's order (fn ⇪ ⌃ ⌥ ⇧ ⌘)
    /// followed by the key as the layout prints it, e.g. "⌥L ⇧ ←", "⌃ ⌥L Space", "⌥L tap".
    public static func format(
        _ chord: KeyChord, modifierMap: ModifierMap, layout: any KeyboardLayoutCharacters = USQwertyCharacters()
    ) -> String {
        if case .modifierTap(let m) = chord.key {
            return "\(modifierMap[m].symbol) tap"
        }
        return (modifierSymbols(chord.modifiers, modifierMap: modifierMap) + [keyLabel(chord.key, layout: layout)])
            .joined(separator: " ")
    }

    /// Physical symbols for a set of logical modifiers in Apple's order (fn ⇪ ⌃ ⌥ ⇧ ⌘), e.g. ["⌃", "⌥L"].
    public static func modifierSymbols(_ modifiers: Set<LogicalModifier>, modifierMap: ModifierMap) -> [String] {
        modifiers.map { modifierMap[$0] }
            .sorted { familyOrder($0) < familyOrder($1) }
            .map(\.symbol)
    }

    /// The label for a key token in Mac notation ("←", "Space", "Q", "Left Click", "Volume Up").
    public static func keyLabel(_ key: KeyToken, layout: any KeyboardLayoutCharacters = USQwertyCharacters()) -> String {
        switch key {
        case .code(let code):
            if let symbol = macKeySymbols[code] { return symbol }
            if let ch = layout.character(forKeyCode: code, shift: false), !ch.isEmpty, ch != " " {
                return ch.count == 1 && ch.first!.isLetter ? ch.uppercased() : ch
            }
            if let name = KeyTable.name(for: code) {
                return name.hasPrefix("Keypad") ? "KP " + String(name.dropFirst("Keypad".count)) : name
            }
            return "0x" + String(code, radix: 16).uppercased()
        case .modifierTap(let m): return "\(m.rawValue) tap"
        case .mouseButton(let b):
            switch b {
            case 272: return "Left Click"
            case 273: return "Right Click"
            case 274: return "Middle Click"
            default: return "Mouse \(b)"
            }
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        case .media(let m):
            switch m {
            case .volumeUp: return "Volume Up"
            case .volumeDown: return "Volume Down"
            case .mute: return "Mute"
            case .brightnessUp: return "Brightness Up"
            case .brightnessDown: return "Brightness Down"
            case .play: return "Play"
            case .pause: return "Pause"
            case .next: return "Next"
            case .previous: return "Previous"
            case .stop: return "Stop"
            case .micMute: return "Mic Mute"
            }
        }
    }

    /// Hyprland notation ("SUPER + SUPER_L", "CTRL + SUPER + Page_Up", "XF86AudioRaiseVolume").
    public static func linuxNotation(_ chord: KeyChord) -> String {
        let mods = chord.modifiers.sorted().map(\.rawValue)
        switch chord.key {
        case .modifierTap(let m): return "\(m.rawValue) + \(m.rawValue)_L"
        case .media(let m): return (mods + [xf86Names[m] ?? m.rawValue]).joined(separator: " + ")
        case .code(let code):
            let name = linuxKeyNames[code] ?? KeyTable.name(for: code) ?? "0x" + String(code, radix: 16)
            return (mods + [name]).joined(separator: " + ")
        default: return (mods + [chord.key.description]).joined(separator: " + ")
        }
    }

    /// Keymap notation: the canonical spelling accepted by ``parse(_:)`` ("SUPER + SHIFT + Left",
    /// "SUPER" for the tap, "VolumeUp"). `parse(keymapNotation(c)) == c` for every chord.
    public static func keymapNotation(_ chord: KeyChord) -> String {
        if case .modifierTap(let m) = chord.key { return m.rawValue }
        return chord.description
    }

    // MARK: - Tables

    private static func modifier(named token: String) -> LogicalModifier? {
        switch token.uppercased() {
        case "SUPER": return .superKey
        case "ALT": return .altKey
        case "CTRL", "CONTROL": return .ctrlKey
        case "SHIFT": return .shiftKey
        default: return nil
        }
    }

    private static func tapModifier(named token: String) -> LogicalModifier? {
        let upper = token.uppercased()
        if upper == "SUPER_L" || upper == "SUPER_R" { return .superKey }
        for m in LogicalModifier.allCases where upper == "\(m.rawValue)_TAP" { return m }
        return nil
    }

    private static func keyToken(_ token: String, chord: String) throws -> KeyToken {
        let lower = token.lowercased()
        if lower.hasPrefix("mouse:") {
            let button = String(lower.dropFirst("mouse:".count))
            switch button {
            case "left": return .mouseButton(272)
            case "right": return .mouseButton(273)
            case "middle": return .mouseButton(274)
            default:
                guard let n = Int(button) else {
                    throw ChordParseError(text: chord, reason: "mouse button \"\(token)\" must be mouse:272 (left), mouse:273 (right), mouse:274 (middle) or mouse:<number>")
                }
                return .mouseButton(n)
            }
        }
        switch lower {
        case "mouse_up", "scrollup", "scroll_up": return .scrollUp
        case "mouse_down", "scrolldown", "scroll_down": return .scrollDown
        default: break
        }
        if let code = KeyTable.code(for: token) { return .code(code) }
        if let media = mediaKeys[lower] { return .media(media) }
        if lower.hasPrefix("0x"), let code = UInt16(lower.dropFirst(2), radix: 16) { return .code(code) }

        var reason = "unknown key \"\(token)\""
        if let hint = suggestion(for: lower) { reason += " (did you mean \"\(hint)\"?)" }
        throw ChordParseError(text: chord, reason: reason)
    }

    private static let mediaKeys: [String: MediaKey] = {
        var m: [String: MediaKey] = [:]
        for k in MediaKey.allCases { m[k.rawValue.lowercased()] = k }
        for (k, name) in xf86Names { m[name.lowercased()] = k }
        m["prev"] = .previous
        m["playpause"] = .play
        return m
    }()

    private static let xf86Names: [MediaKey: String] = [
        .volumeUp: "XF86AudioRaiseVolume", .volumeDown: "XF86AudioLowerVolume", .mute: "XF86AudioMute",
        .micMute: "XF86AudioMicMute", .brightnessUp: "XF86MonBrightnessUp", .brightnessDown: "XF86MonBrightnessDown",
        .play: "XF86AudioPlay", .pause: "XF86AudioPause", .next: "XF86AudioNext", .previous: "XF86AudioPrev",
        .stop: "XF86AudioStop",
    ]

    private static let linuxKeyNames: [UInt16: String] = [
        0x74: "Page_Up", 0x79: "Page_Down", 0x39: "Caps_Lock", 0x47: "Num_Lock", 0x33: "BackSpace",
    ]

    private static let macKeySymbols: [UInt16: String] = [
        0x7B: "←", 0x7C: "→", 0x7E: "↑", 0x7D: "↓", 0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫",
        0x75: "⌦", 0x35: "⎋", 0x74: "⇞", 0x79: "⇟", 0x73: "↖", 0x77: "↘", 0x39: "⇪", 0x47: "⌧",
        0x4C: "⌤", 0x72: "Help", 0x3F: "fn", 0x37: "⌘L", 0x36: "⌘R", 0x38: "⇧L", 0x3C: "⇧R",
        0x3A: "⌥L", 0x3D: "⌥R", 0x3B: "⌃L", 0x3E: "⌃R",
    ]

    private static func familyOrder(_ p: PhysicalModifier) -> Int {
        switch p {
        case .fn: return 0
        case .capslock: return 1
        case .lctrl, .rctrl, .ctrl: return 2
        case .lopt, .ropt, .opt: return 3
        case .lshift, .rshift, .shift: return 4
        case .lcmd, .rcmd, .cmd: return 5
        }
    }

    private static func suggestion(for lower: String) -> String? {
        var best: (name: String, distance: Int)?
        let candidates = KeyTable.namesByCode.values.map { $0 } + MediaKey.allCases.map(\.rawValue)
            + xf86Names.values.map { $0 } + ["mouse_up", "mouse_down", "mouse:272", "mouse:273"]
        for name in candidates {
            let d = editDistance(lower, name.lowercased())
            if d <= 2, best == nil || d < best!.distance { best = (name, d) }
        }
        return best?.name
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
