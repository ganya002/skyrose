import Foundation

/// Modifier presets of section 3.1 and the `hidutil` remap preset B needs.
///
/// The Platform module applies ``capsLockToF18Command`` at login (hidutil mappings reset on reboot)
/// and ``capsLockRestoreCommand`` when the preset is switched off or on uninstall. Both run as the
/// user; no root is needed.
public enum ModifierPresets {
    /// HID usage page 0x07 (keyboard) shifted into the high word, as `hidutil` expects.
    public static let hidKeyboardUsagePage: UInt64 = 0x7_0000_0000
    /// HID usage of Caps Lock (0x39) on the keyboard page.
    public static let capsLockUsage: UInt64 = hidKeyboardUsagePage | 0x39
    /// HID usage of F18 (0x6D) on the keyboard page; the WM treats F18 as the Super modifier.
    public static let f18Usage: UInt64 = hidKeyboardUsagePage | 0x6D

    /// The `UserKeyMapping` JSON for preset B: Caps Lock → F18.
    public static let capsLockToF18Mapping = """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}
        """

    /// The `UserKeyMapping` JSON that removes every user mapping (stock behaviour).
    public static let capsLockRestoreMapping = """
        {"UserKeyMapping":[]}
        """

    /// `hidutil` arguments that apply preset B (`hidutil property --set '<json>'`).
    public static let capsLockToF18Command: [String] = ["hidutil", "property", "--set", capsLockToF18Mapping]

    /// `hidutil` arguments that undo preset B.
    public static let capsLockRestoreCommand: [String] = ["hidutil", "property", "--set", capsLockRestoreMapping]

    /// `hidutil` arguments that print the current mapping (`hidutil property --get UserKeyMapping`).
    public static let readMappingCommand: [String] = ["hidutil", "property", "--get", "UserKeyMapping"]

    /// `true` when the text printed by ``readMappingCommand`` already contains the Caps Lock → F18 map.
    public static func mappingIsApplied(hidutilOutput: String) -> Bool {
        let compact = String(hidutilOutput.lowercased().filter { !$0.isWhitespace })
        let src = "hidkeyboardmodifiermappingsrc=\(capsLockUsage)"
        let dst = "hidkeyboardmodifiermappingdst=\(f18Usage)"
        return compact.contains(src) && compact.contains(dst)
    }

    /// What the Settings app shows for a preset.
    public struct Description: Sendable, Equatable {
        public var preset: ModifierMap.Preset
        /// Short title ("Option is Super").
        public var title: String
        /// The physical key for Linux SUPER, as a symbol ("⌥L").
        public var superKey: String
        /// The physical key for Linux ALT.
        public var altKey: String
        /// One-paragraph explanation.
        public var summary: String
        /// Caveats worth a line in the UI.
        public var notes: [String]
        /// Whether choosing this preset runs `hidutil`.
        public var requiresHidutil: Bool

        public init(
            preset: ModifierMap.Preset, title: String, superKey: String, altKey: String, summary: String,
            notes: [String], requiresHidutil: Bool
        ) {
            self.preset = preset
            self.title = title
            self.superKey = superKey
            self.altKey = altKey
            self.summary = summary
            self.notes = notes
            self.requiresHidutil = requiresHidutil
        }
    }

    /// Descriptions for every preset, in UI order (A, B, C, D).
    public static let descriptions: [Description] = ModifierMap.Preset.allCases.map(description(for:))

    /// The description of one preset.
    public static func description(for preset: ModifierMap.Preset) -> Description {
        switch preset {
        case .optionIsSuper:
            return Description(
                preset: preset, title: "Option is Super", superKey: PhysicalModifier.lopt.symbol, altKey: PhysicalModifier.lcmd.symbol,
                summary: "Left Option acts as the Linux Super key and Left Command as Alt. The right-hand keys keep their "
                    + "normal meaning, so Option characters (æ ø å @ £ $ { } [ ] | \\ …) still type with Right Option "
                    + "and Right Command stays a normal ⌘.",
                notes: [
                    "A tap of Left Option alone opens the launcher.",
                    "Left Command shortcuts such as ⌘L+Tab are not taken over by default (see \"Take over ⌘Tab\").",
                ],
                requiresHidutil: false
            )
        case .capsLockIsHyper:
            return Description(
                preset: preset, title: "Caps Lock is Hyper", superKey: PhysicalModifier.capslock.symbol, altKey: PhysicalModifier.lopt.symbol,
                summary: "Caps Lock becomes the Super key through a user-level hidutil remap (Caps Lock → F18, which the "
                    + "window manager treats as a modifier). Left Option is Alt. Both Option keys type characters as usual.",
                notes: [
                    "Reversible and needs no root; the mapping is re-applied at login because hidutil resets on reboot.",
                    "Caps Lock itself is no longer available; use Shift for capitals.",
                    "A tap of Caps Lock alone opens the launcher.",
                ],
                requiresHidutil: true
            )
        case .commandIsSuper:
            return Description(
                preset: preset, title: "Command is Super", superKey: PhysicalModifier.lcmd.symbol, altKey: PhysicalModifier.lopt.symbol,
                summary: "Left Command is Super and Left Option is Alt, like other Mac window managers. Right Command "
                    + "stays a normal ⌘ for app shortcuts.",
                notes: [
                    "Binds on ⌘L+Q/W/T/C/V/X/Z/S/F/,/. shadow those app shortcuts while the window manager runs; the "
                        + "conflict checker lists every one of them.",
                    "⌘L+Space clashes with Spotlight and ⌘L+Tab with the app switcher unless those are changed.",
                ],
                requiresHidutil: false
            )
        case .custom:
            return Description(
                preset: preset, title: "Custom", superKey: "—", altKey: "—",
                summary: "Pick any physical key for each Linux modifier in keymap.toml ([modifiers]).",
                notes: [
                    "Available keys: " + PhysicalModifier.allCases.map { "\($0.rawValue) (\($0.symbol))" }.joined(separator: ", ") + ".",
                    "Side-specific keys (lopt, lcmd, …) leave the other side free for typing.",
                ],
                requiresHidutil: false
            )
        }
    }
}

extension ModifierMap.Preset {
    /// Short UI title ("Option is Super").
    public var title: String { ModifierPresets.description(for: self).title }

    /// One-paragraph explanation for the UI.
    public var summary: String { ModifierPresets.description(for: self).summary }

    /// Whether choosing this preset needs the Caps Lock → F18 hidutil mapping.
    public var requiresHidutil: Bool { self == .capsLockIsHyper }
}
