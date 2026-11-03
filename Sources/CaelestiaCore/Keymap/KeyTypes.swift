import Foundation

// MARK: - Modifiers

/// The four Linux-side modifiers a bind is written with ("SUPER + SHIFT + Left").
public enum LogicalModifier: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case superKey = "SUPER"
    case altKey = "ALT"
    case ctrlKey = "CTRL"
    case shiftKey = "SHIFT"

    public static func < (a: LogicalModifier, b: LogicalModifier) -> Bool { a.order < b.order }
    private var order: Int {
        switch self {
        case .superKey: return 0
        case .ctrlKey: return 1
        case .altKey: return 2
        case .shiftKey: return 3
        }
    }

    /// Hyprland modmask bit (binds.json `modmask`).
    public var hyprlandMask: Int {
        switch self {
        case .shiftKey: return 1
        case .ctrlKey: return 4
        case .altKey: return 8
        case .superKey: return 64
        }
    }

    public static func fromHyprlandMask(_ mask: Int) -> Set<LogicalModifier> {
        var s = Set<LogicalModifier>()
        for m in allCases where mask & m.hyprlandMask != 0 { s.insert(m) }
        return s
    }
}

/// A physical macOS modifier key (or side-agnostic group) a logical modifier maps to.
public enum PhysicalModifier: String, Codable, Sendable, CaseIterable, Hashable {
    case lopt, ropt, opt
    case lcmd, rcmd, cmd
    case lctrl, rctrl, ctrl
    case lshift, rshift, shift
    /// Caps Lock remapped to F18 with hidutil (preset B). The WM treats F18 as a modifier.
    case capslock
    case fn

    /// Human-readable symbol for cheat sheets.
    public var symbol: String {
        switch self {
        case .lopt: return "⌥L"
        case .ropt: return "⌥R"
        case .opt: return "⌥"
        case .lcmd: return "⌘L"
        case .rcmd: return "⌘R"
        case .cmd: return "⌘"
        case .lctrl: return "⌃L"
        case .rctrl: return "⌃R"
        case .ctrl: return "⌃"
        case .lshift: return "⇧L"
        case .rshift: return "⇧R"
        case .shift: return "⇧"
        case .capslock: return "⇪"
        case .fn: return "fn"
        }
    }

    /// CGEventFlags bit for the modifier family (device-independent).
    public var familyFlag: UInt64 {
        switch self {
        case .lopt, .ropt, .opt: return 0x0008_0000  // maskAlternate
        case .lcmd, .rcmd, .cmd: return 0x0010_0000  // maskCommand
        case .lctrl, .rctrl, .ctrl: return 0x0004_0000  // maskControl
        case .lshift, .rshift, .shift: return 0x0002_0000  // maskShift
        case .capslock: return 0  // F18 is a key, not a flag; handled as a synthetic modifier
        case .fn: return 0x0080_0000  // maskSecondaryFn
        }
    }

    /// Device-dependent side bit (NX_DEVICE*KEYMASK) when the mapping is side-specific, else 0.
    /// NX_DEVICELCTLKEYMASK 0x01, NX_DEVICELSHIFTKEYMASK 0x02, NX_DEVICERSHIFTKEYMASK 0x04,
    /// NX_DEVICELCMDKEYMASK 0x08, NX_DEVICERCMDKEYMASK 0x10, NX_DEVICELALTKEYMASK 0x20,
    /// NX_DEVICERALTKEYMASK 0x40, NX_DEVICERCTLKEYMASK 0x2000.
    public var sideFlag: UInt64 {
        switch self {
        case .lctrl: return 0x01
        case .lshift: return 0x02
        case .rshift: return 0x04
        case .lcmd: return 0x08
        case .rcmd: return 0x10
        case .lopt: return 0x20
        case .ropt: return 0x40
        case .rctrl: return 0x2000
        default: return 0
        }
    }

    /// Both side bits of the family, used to tell "the other side is held" apart.
    public var familySideFlags: UInt64 {
        switch self {
        case .lopt, .ropt, .opt: return 0x20 | 0x40
        case .lcmd, .rcmd, .cmd: return 0x08 | 0x10
        case .lctrl, .rctrl, .ctrl: return 0x01 | 0x2000
        case .lshift, .rshift, .shift: return 0x02 | 0x04
        case .capslock, .fn: return 0
        }
    }

    public var isSideSpecific: Bool { sideFlag != 0 }

    /// Virtual key codes of the physical key(s) (used for tap detection and the F18 modifier).
    public var keyCodes: [UInt16] {
        switch self {
        case .lopt: return [0x3A]
        case .ropt: return [0x3D]
        case .opt: return [0x3A, 0x3D]
        case .lcmd: return [0x37]
        case .rcmd: return [0x36]
        case .cmd: return [0x37, 0x36]
        case .lctrl: return [0x3B]
        case .rctrl: return [0x3E]
        case .ctrl: return [0x3B, 0x3E]
        case .lshift: return [0x38]
        case .rshift: return [0x3C]
        case .shift: return [0x38, 0x3C]
        case .capslock: return [0x4F]  // F18 after hidutil remap
        case .fn: return [0x3F]
        }
    }
}

/// Logical → physical modifier map ([modifiers] table in keymap.toml).
public struct ModifierMap: Codable, Equatable, Sendable {
    public var superKey: PhysicalModifier
    public var altKey: PhysicalModifier
    public var ctrlKey: PhysicalModifier
    public var shiftKey: PhysicalModifier

    public init(superKey: PhysicalModifier, altKey: PhysicalModifier, ctrlKey: PhysicalModifier, shiftKey: PhysicalModifier) {
        self.superKey = superKey
        self.altKey = altKey
        self.ctrlKey = ctrlKey
        self.shiftKey = shiftKey
    }

    public subscript(_ m: LogicalModifier) -> PhysicalModifier {
        switch m {
        case .superKey: return superKey
        case .altKey: return altKey
        case .ctrlKey: return ctrlKey
        case .shiftKey: return shiftKey
        }
    }

    /// Preset A "Option is Super" (default).
    public static let optionIsSuper = ModifierMap(superKey: .lopt, altKey: .lcmd, ctrlKey: .ctrl, shiftKey: .shift)
    /// Preset B "Caps Lock is Hyper".
    public static let capsLockIsHyper = ModifierMap(superKey: .capslock, altKey: .lopt, ctrlKey: .ctrl, shiftKey: .shift)
    /// Preset C "Command is Super".
    public static let commandIsSuper = ModifierMap(superKey: .lcmd, altKey: .lopt, ctrlKey: .ctrl, shiftKey: .shift)

    public enum Preset: String, Codable, Sendable, CaseIterable {
        case optionIsSuper = "option-is-super"
        case capsLockIsHyper = "capslock-is-hyper"
        case commandIsSuper = "command-is-super"
        case custom

        public var map: ModifierMap? {
            switch self {
            case .optionIsSuper: return .optionIsSuper
            case .capsLockIsHyper: return .capsLockIsHyper
            case .commandIsSuper: return .commandIsSuper
            case .custom: return nil
            }
        }
    }

    public var preset: Preset {
        if self == .optionIsSuper { return .optionIsSuper }
        if self == .capsLockIsHyper { return .capsLockIsHyper }
        if self == .commandIsSuper { return .commandIsSuper }
        return .custom
    }
}

// MARK: - Keys

/// The non-modifier part of a chord.
public enum KeyToken: Hashable, Sendable, Codable, CustomStringConvertible {
    /// A physical key by macOS virtual key code (kVK_*). Binds are by position, not character.
    case code(UInt16)
    /// Modifier-only chord (Hyprland "SUPER + SUPER_L" release binds: the Super tap).
    case modifierTap(LogicalModifier)
    /// Mouse buttons: 272 = left, 273 = right, 274 = middle (Hyprland mouse:NNN).
    case mouseButton(Int)
    case scrollUp
    case scrollDown
    /// Keys that arrive as NSSystemDefined events on macOS (NX_KEYTYPE_*), not key codes.
    case media(MediaKey)

    public var description: String {
        switch self {
        case .code(let c): return KeyTable.name(for: c) ?? "0x\(String(c, radix: 16))"
        case .modifierTap(let m): return "\(m.rawValue)_TAP"
        case .mouseButton(let b): return "mouse:\(b)"
        case .scrollUp: return "mouse_up"
        case .scrollDown: return "mouse_down"
        case .media(let m): return m.rawValue
        }
    }
}

public enum MediaKey: String, Codable, Sendable, CaseIterable, Hashable {
    case volumeUp = "VolumeUp"
    case volumeDown = "VolumeDown"
    case mute = "Mute"
    case brightnessUp = "BrightnessUp"
    case brightnessDown = "BrightnessDown"
    case play = "Play"
    case pause = "Pause"
    case next = "Next"
    case previous = "Previous"
    case stop = "Stop"
    case micMute = "MicMute"

    /// NX_KEYTYPE_* constants from IOKit/hidsystem/ev_keymap.h.
    public var nxKeyType: Int {
        switch self {
        case .brightnessUp: return 2
        case .brightnessDown: return 3
        case .mute: return 7
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .play, .pause: return 16
        case .next: return 17
        case .previous: return 18
        case .stop: return 19  // NX_KEYTYPE_FAST=19 is used for "next" by some keyboards; stop has no NX constant, keep 19 for parity
        case .micMute: return -1  // no NX constant on Mac
        }
    }
}

/// A resolved chord: logical modifiers + key token.
public struct KeyChord: Hashable, Sendable, Codable, CustomStringConvertible {
    public var modifiers: Set<LogicalModifier>
    public var key: KeyToken

    public init(modifiers: Set<LogicalModifier>, key: KeyToken) {
        self.modifiers = modifiers
        self.key = key
    }

    public var description: String {
        let mods = modifiers.sorted().map(\.rawValue)
        return (mods + [key.description]).joined(separator: " + ")
    }
}

/// Virtual key code table (kVK_* from Carbon HIToolbox/Events.h). Names are case-insensitive and
/// accept both Hyprland spellings (Page_Up, Caps_Lock) and Mac spellings (PageUp, CapsLock).
public enum KeyTable {
    public static let codesByName: [String: UInt16] = {
        var m: [String: UInt16] = [:]
        func add(_ names: [String], _ code: UInt16) { for n in names { m[n.lowercased()] = code } }
        add(["A"], 0x00); add(["S"], 0x01); add(["D"], 0x02); add(["F"], 0x03); add(["H"], 0x04)
        add(["G"], 0x05); add(["Z"], 0x06); add(["X"], 0x07); add(["C"], 0x08); add(["V"], 0x09)
        add(["B"], 0x0B); add(["Q"], 0x0C); add(["W"], 0x0D); add(["E"], 0x0E); add(["R"], 0x0F)
        add(["Y"], 0x10); add(["T"], 0x11)
        add(["1"], 0x12); add(["2"], 0x13); add(["3"], 0x14); add(["4"], 0x15); add(["6"], 0x16)
        add(["5"], 0x17); add(["Equal", "="], 0x18); add(["9"], 0x19); add(["7"], 0x1A)
        add(["Minus", "-"], 0x1B); add(["8"], 0x1C); add(["0"], 0x1D)
        add(["RightBracket", "BracketRight", "]"], 0x1E); add(["O"], 0x1F); add(["U"], 0x20)
        add(["LeftBracket", "BracketLeft", "["], 0x21); add(["I"], 0x22); add(["P"], 0x23)
        add(["L"], 0x25); add(["J"], 0x26); add(["Quote", "Apostrophe", "'"], 0x27); add(["K"], 0x28)
        add(["Semicolon", ";"], 0x29); add(["Backslash", "\\"], 0x2A); add(["Comma", ","], 0x2B)
        add(["Slash", "/"], 0x2C); add(["N"], 0x2D); add(["M"], 0x2E); add(["Period", "."], 0x2F)
        add(["Grave", "`"], 0x32); add(["Section", "ISO_Section", "§"], 0x0A)
        add(["Return", "Enter"], 0x24); add(["Tab", "TAB"], 0x30); add(["Space"], 0x31)
        add(["Backspace", "BackSpace"], 0x33); add(["Escape", "Esc"], 0x35)
        add(["Delete", "ForwardDelete"], 0x75)
        add(["Left", "LeftArrow"], 0x7B); add(["Right", "RightArrow"], 0x7C)
        add(["Down", "DownArrow"], 0x7D); add(["Up", "UpArrow"], 0x7E)
        add(["Home"], 0x73); add(["End"], 0x77); add(["PageUp", "Page_Up", "Prior"], 0x74)
        add(["PageDown", "Page_Down", "Next_Page"], 0x79); add(["Help", "Insert"], 0x72)
        add(["CapsLock", "Caps_Lock"], 0x39); add(["Fn", "Function"], 0x3F)
        add(["F1"], 0x7A); add(["F2"], 0x78); add(["F3"], 0x63); add(["F4"], 0x76); add(["F5"], 0x60)
        add(["F6"], 0x61); add(["F7"], 0x62); add(["F8"], 0x64); add(["F9"], 0x65); add(["F10"], 0x6D)
        add(["F11"], 0x67); add(["F12"], 0x6F); add(["F13", "Print", "PrintScreen"], 0x69); add(["F14"], 0x6B)
        add(["F15"], 0x71); add(["F16"], 0x6A); add(["F17"], 0x40); add(["F18"], 0x4F); add(["F19"], 0x50)
        add(["F20"], 0x5A)
        add(["Keypad0", "KP_0"], 0x52); add(["Keypad1", "KP_1"], 0x53); add(["Keypad2", "KP_2"], 0x54)
        add(["Keypad3", "KP_3"], 0x55); add(["Keypad4", "KP_4"], 0x56); add(["Keypad5", "KP_5"], 0x57)
        add(["Keypad6", "KP_6"], 0x58); add(["Keypad7", "KP_7"], 0x59); add(["Keypad8", "KP_8"], 0x5B)
        add(["Keypad9", "KP_9"], 0x5C); add(["KeypadDecimal", "KP_Decimal"], 0x41)
        add(["KeypadMultiply", "KP_Multiply"], 0x43); add(["KeypadPlus", "KP_Add"], 0x45)
        add(["KeypadClear", "Num_Lock", "NumLock"], 0x47); add(["KeypadDivide", "KP_Divide"], 0x4B)
        add(["KeypadEnter", "KP_Enter"], 0x4C); add(["KeypadMinus", "KP_Subtract"], 0x4E)
        add(["KeypadEquals", "KP_Equal"], 0x51)
        // Modifier keys as plain keys (used by tap detection).
        add(["Command_L", "LeftCommand"], 0x37); add(["Command_R", "RightCommand"], 0x36)
        add(["Shift_L", "LeftShift"], 0x38); add(["Shift_R", "RightShift"], 0x3C)
        add(["Option_L", "Alt_L", "LeftOption"], 0x3A); add(["Option_R", "Alt_R", "RightOption"], 0x3D)
        add(["Control_L", "LeftControl"], 0x3B); add(["Control_R", "RightControl"], 0x3E)
        return m
    }()

    /// Canonical display names (first spelling wins).
    public static let namesByCode: [UInt16: String] = {
        var m: [UInt16: String] = [:]
        let canonical: [(String, UInt16)] = [
            ("A", 0x00), ("S", 0x01), ("D", 0x02), ("F", 0x03), ("H", 0x04), ("G", 0x05), ("Z", 0x06), ("X", 0x07),
            ("C", 0x08), ("V", 0x09), ("B", 0x0B), ("Q", 0x0C), ("W", 0x0D), ("E", 0x0E), ("R", 0x0F), ("Y", 0x10),
            ("T", 0x11), ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15), ("6", 0x16), ("5", 0x17),
            ("Equal", 0x18), ("9", 0x19), ("7", 0x1A), ("Minus", 0x1B), ("8", 0x1C), ("0", 0x1D),
            ("RightBracket", 0x1E), ("O", 0x1F), ("U", 0x20), ("LeftBracket", 0x21), ("I", 0x22), ("P", 0x23),
            ("L", 0x25), ("J", 0x26), ("Quote", 0x27), ("K", 0x28), ("Semicolon", 0x29), ("Backslash", 0x2A),
            ("Comma", 0x2B), ("Slash", 0x2C), ("N", 0x2D), ("M", 0x2E), ("Period", 0x2F), ("Grave", 0x32),
            ("Section", 0x0A), ("Return", 0x24), ("Tab", 0x30), ("Space", 0x31), ("Backspace", 0x33),
            ("Escape", 0x35), ("Delete", 0x75), ("Left", 0x7B), ("Right", 0x7C), ("Down", 0x7D), ("Up", 0x7E),
            ("Home", 0x73), ("End", 0x77), ("PageUp", 0x74), ("PageDown", 0x79), ("Help", 0x72),
            ("CapsLock", 0x39), ("Fn", 0x3F), ("F1", 0x7A), ("F2", 0x78), ("F3", 0x63), ("F4", 0x76),
            ("F5", 0x60), ("F6", 0x61), ("F7", 0x62), ("F8", 0x64), ("F9", 0x65), ("F10", 0x6D), ("F11", 0x67),
            ("F12", 0x6F), ("F13", 0x69), ("F14", 0x6B), ("F15", 0x71), ("F16", 0x6A), ("F17", 0x40),
            ("F18", 0x4F), ("F19", 0x50), ("F20", 0x5A), ("Keypad0", 0x52), ("Keypad1", 0x53), ("Keypad2", 0x54),
            ("Keypad3", 0x55), ("Keypad4", 0x56), ("Keypad5", 0x57), ("Keypad6", 0x58), ("Keypad7", 0x59),
            ("Keypad8", 0x5B), ("Keypad9", 0x5C), ("KeypadDecimal", 0x41), ("KeypadMultiply", 0x43),
            ("KeypadPlus", 0x45), ("KeypadClear", 0x47), ("KeypadDivide", 0x4B), ("KeypadEnter", 0x4C),
            ("KeypadMinus", 0x4E), ("KeypadEquals", 0x51), ("Command_L", 0x37), ("Command_R", 0x36),
            ("Shift_L", 0x38), ("Shift_R", 0x3C), ("Option_L", 0x3A), ("Option_R", 0x3D), ("Control_L", 0x3B),
            ("Control_R", 0x3E),
        ]
        for (n, c) in canonical { m[c] = n }
        return m
    }()

    public static func code(for name: String) -> UInt16? { codesByName[name.lowercased()] }
    public static func name(for code: UInt16) -> String? { namesByCode[code] }

    /// Keys a MacBook keyboard physically lacks (section 3.3 item 5).
    public static let missingOnMacBook: Set<String> = ["F13", "Help", "PageUp", "PageDown", "Home", "End", "KeypadClear", "Delete"]
}
