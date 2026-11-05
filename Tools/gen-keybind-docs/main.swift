import CaelestiaCore
import Foundation

// gen-keybind-docs [output path]
//
// Renders docs/KEYBINDS.md from the bundled keymap.default.toml so the mapping doc can never drift
// from the binds the window manager actually uses (spec 3.2).

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help") {
    print("usage: gen-keybind-docs [output path]   (default: <repo>/docs/KEYBINDS.md)")
    exit(0)
}

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let output = arguments.first.map { URL(fileURLWithPath: $0) } ?? repoRoot.appendingPathComponent("docs/KEYBINDS.md")

let keymap: Keymap
let extras: KeymapExtras
do {
    (keymap, extras) = try KeymapParser.parseWithExtras(toml: try KeymapLoader.defaultKeymapText())
} catch {
    FileHandle.standardError.write(Data("gen-keybind-docs: cannot load the default keymap: \(error)\n".utf8))
    exit(1)
}

func escapeCell(_ text: String) -> String {
    text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
}

func code(_ text: String) -> String {
    text.isEmpty ? "" : "`" + text.replacingOccurrences(of: "`", with: "'") + "`"
}

func macChords(_ bind: Bind) -> String {
    bind.chords.map { ChordParser.format($0, modifierMap: keymap.modifiers) }.map(code).joined(separator: " / ")
}

func linuxChords(_ bind: Bind) -> String {
    guard let linux = bind.linux else { return "—" }
    return linux.split(separator: "|").map { code($0.trimmingCharacters(in: .whitespaces)) }.joined(separator: " / ")
}

func keymapChords(_ bind: Bind) -> String {
    bind.keys.map(code).joined(separator: " / ")
}

func actionText(_ bind: Bind) -> String {
    code(bind.action.description)
}

func flagsText(_ bind: Bind) -> String {
    bind.flags.map(\.rawValue).sorted().joined(separator: ", ")
}

var lines: [String] = []
lines.append("# Keybinds")
lines.append("")
lines.append("Generated from `Sources/CaelestiaCore/Resources/keymap.default.toml` by `gen-keybind-docs`; do not edit by hand.")
lines.append("Every bind of the Hyprland setup (`Tests/fixtures/binds.json`, \(keymap.binds.compactMap(\.linux).flatMap { $0.split(separator: "|") }.count) entries) is listed with its Mac equivalent.")
lines.append("")
lines.append("## Notation")
lines.append("")
lines.append("- **Linux**: the original Hyprland chord. `SUPER_L` alone is a Super tap; `mouse_up` / `mouse_down` are scroll steps; `mouse:272` / `mouse:273` are left / right drag.")
lines.append("- **Mac**: the physical chord under the shipped modifier preset (**\(keymap.modifiers.preset.title)**: SUPER = \(keymap.modifiers.superKey.symbol), ALT = \(keymap.modifiers.altKey.symbol), CTRL = \(keymap.modifiers.ctrlKey.symbol), SHIFT = \(keymap.modifiers.shiftKey.symbol)). Only the LEFT Option / Command keys are window-manager modifiers; the right ones keep typing characters and ⌘ shortcuts. Keys are bound by position: `-` / `=` are the two keys right of `0` (`+` and `´` on the Norwegian layout) and `\\` is the key next to Return.")
lines.append("- **Keymap**: how the chord is written in `keymap.toml` (Linux modifier names, Mac key names). Edit `~/.config/skyrose/keymap.toml` to change a bind; the window manager reloads it within 200 ms.")
lines.append("- **Flags**: `release` fires on key-up, `repeat` auto-repeats while held, `locked` also works on the lock screen (media / volume / brightness), `mouse` is a drag bind.")
lines.append("- `window.resize` deltas are **percent of the window's current size**, not pixels.")
lines.append("")

for category in BindCategory.allCases {
    let binds = keymap.binds.filter { $0.action.kind.category == category }
    guard !binds.isEmpty else { continue }
    lines.append("## \(category.rawValue)")
    lines.append("")
    lines.append("| Linux chord | Mac chord | Action | Flags | Description | Keymap chord | Bind id |")
    lines.append("|---|---|---|---|---|---|---|")
    for bind in binds {
        var description = escapeCell(bind.description)
        if !bind.enabled { description = "_(disabled)_ " + description }
        lines.append("| \(escapeCell(linuxChords(bind))) | \(escapeCell(macChords(bind))) | \(escapeCell(actionText(bind))) | \(flagsText(bind)) | \(description) | \(escapeCell(keymapChords(bind))) | \(code(bind.id)) |")
    }
    lines.append("")
}

lines.append("## Modifier presets")
lines.append("")
lines.append("Pick one in Settings; each preset is just a different `[modifiers]` table in `keymap.toml`. The binds above stay the same, only the physical keys change.")
lines.append("")
lines.append("| Preset | SUPER | ALT | Summary |")
lines.append("|---|---|---|---|")
for description in ModifierPresets.descriptions {
    let letter = ["A", "B", "C", "D"][min(ModifierMap.Preset.allCases.firstIndex(of: description.preset) ?? 3, 3)]
    let marker = description.preset == keymap.modifiers.preset ? " (default)" : ""
    lines.append("| \(letter). \(description.title)\(marker) | \(description.superKey) | \(description.altKey) | \(escapeCell(description.summary)) |")
}
lines.append("")
for description in ModifierPresets.descriptions where !description.notes.isEmpty {
    lines.append("**\(description.title)**")
    lines.append("")
    for note in description.notes { lines.append("- \(note)") }
    lines.append("")
}
lines.append("Preset B remaps Caps Lock to F18 with a user-level `hidutil` mapping (reversible, no root, re-applied at login):")
lines.append("")
lines.append("```")
lines.append(ModifierPresets.capsLockToF18Command.map { $0.contains(" ") || $0.contains("{") ? "'" + $0 + "'" : $0 }.joined(separator: " "))
lines.append("```")
lines.append("")
lines.append("Undo it with `hidutil property --set '\(ModifierPresets.capsLockRestoreMapping)'`.")
lines.append("")

lines.append("## Trackpad gestures")
lines.append("")
let gestures = extras.gestures ?? .default
lines.append("Gestures are **\(gestures.enabled ? "on" : "off")** by default (`[gestures]` in `keymap.toml`): macOS uses 3- and 4-finger swipes for Spaces and Mission Control, so turn those off in System Settings › Trackpad first.")
lines.append("")
lines.append("| Gesture | Action |")
lines.append("|---|---|")
lines.append("| \(gestures.workspaceSwipeFingers)-finger swipe left / right | previous / next workspace |")
lines.append("| \(gestures.specialFingers)-finger swipe up | open the special workspace |")
lines.append("| \(gestures.specialFingers)-finger swipe down | toggle the special workspace closed |")
lines.append("| \(gestures.sleepFingers)-finger swipe down | sleep |")
lines.append("")

lines.append("## Safety")
lines.append("")
lines.append("`\(KeymapParser.panicChordText)` (physically ⌃⌥⌘⇧Esc) is the panic chord: it stops tiling and brings every window back on screen. It cannot be removed; the parser restores it if the keymap lacks it.")
lines.append("")

let markdown = lines.joined(separator: "\n")
do {
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try markdown.write(to: output, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("gen-keybind-docs: cannot write \(output.path): \(error)\n".utf8))
    exit(1)
}
print("gen-keybind-docs: wrote \(output.path) (\(keymap.binds.count) binds)")
