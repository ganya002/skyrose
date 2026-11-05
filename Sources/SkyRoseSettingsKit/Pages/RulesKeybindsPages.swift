import AppKit
import CaelestiaCore
import SwiftUI

// MARK: - Window rules

struct RulesPage: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look
    @State private var filter = ""

    var rows: [AppRuleRow] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let base = store.appRules.filter { $0.source.lowercased() != "builtin" || $0.running || $0.rule != "auto" }
        let shown = q.isEmpty ? base : base.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
        return shown.sorted { a, b in
            if a.running != b.running { return a.running }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Window rules", subtitle: "Tile an app's windows, float them, or let SkyRose decide (Auto). Applies to open windows at once.")
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(look[.onSurfaceVariant])
                    TextField("Search apps", text: $filter).textFieldStyle(.plain).font(look.font(13.5)).foregroundStyle(look[.onSurface])
                    Spacer()
                    if let app = store.lastOtherApp, !store.appRules.contains(where: { $0.bundleID == app.bundleID && $0.rule != "auto" }) {
                        PillButton(title: "Add \(app.name)", icon: "plus", kind: .tonal) {
                            withAnimation(look.motion.page) { store.setAppRule("float", for: app.bundleID, name: app.name) }
                        }
                        .accessibilityIdentifier("rules.addFocused")
                        .help("The app you used last before Settings: \(app.bundleID)")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(look[.surfaceContainerHighest].opacity(0.8)))
                if rows.isEmpty {
                    Text(store.wmRunning ? "No apps match." : "Start SkyRose to see your open apps; rules you set are listed here.")
                        .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).padding(.vertical, 6)
                }
                LazyVStack(spacing: 6) {
                    ForEach(rows) { row in
                        RuleRow(row: row) { mode in withAnimation(look.motion.quick) { store.setAppRule(mode, for: row.bundleID) } }
                            .transition(.opacity.combined(with: .offset(y: look.motion.slide(-6))))
                    }
                }
            }
        }
        .onAppear { store.loadAppRules() }
        .animation(look.motion.page, value: rows.map(\.bundleID))
    }
}

struct RuleRow: View {
    var row: AppRuleRow
    var onSet: (String) -> Void
    @Environment(\.look) var look

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(bundleID: row.bundleID).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.name).font(look.font(13.5, .medium)).foregroundStyle(look[.onSurface]).lineLimit(1)
                    if row.running {
                        Circle().fill(look[.success]).frame(width: 6, height: 6).help("Running")
                    }
                }
                Text(subtitle).font(look.font(11.5)).foregroundStyle(look[.onSurfaceVariant]).lineLimit(1)
            }
            Spacer()
            PillSegmented(options: [("tile", "Tile", "square.split.2x1"), ("float", "Float", "macwindow"), ("auto", "Auto", nil)],
                          selection: Binding(get: { row.rule }, set: { onSet($0) }))
                .accessibilityIdentifier("rule.\(row.bundleID)")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: SettingsLook.rowRadius, style: .continuous).fill(look[.surfaceContainerHigh].opacity(0.55)))
    }

    var subtitle: String {
        var parts = [row.bundleID]
        if row.rule == "auto", row.source.lowercased() == "builtin" { parts.append("floats by default") }
        if row.windows > 0 { parts.append("\(row.windows) window\(row.windows == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

struct AppIcon: View {
    var bundleID: String
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: "app.dashed").resizable().scaledToFit().padding(4).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Keybinds

/// Turns a key press into keymap notation ("SUPER + SHIFT + Left") through the modifier map:
/// each logical modifier counts as held when its physical key is (side-specific when mapped so).
public enum ChordRecorder {
    public static func notation(keyCode: UInt16, flags: UInt64, map: ModifierMap) -> String? {
        guard let key = KeyTable.name(for: keyCode) else { return nil }
        var mods: [LogicalModifier] = []
        for m in LogicalModifier.allCases.sorted() {
            let p = map[m]
            guard p.familyFlag != 0, flags & p.familyFlag != 0 else { continue }
            if p.isSideSpecific, flags & p.familySideFlags != 0, flags & p.sideFlag == 0 { continue }
            mods.append(m)
        }
        return (mods.map(\.rawValue) + [key]).joined(separator: " + ")
    }

    /// Modifier key codes (a press of only these is not a chord yet).
    public static let modifierKeyCodes: Set<UInt16> = [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]
}

/// The keymap as the Settings app shows it: binds grouped by category, conflicts per bind.
@MainActor
final class KeymapModel: ObservableObject {
    @Published var keymap: Keymap?
    @Published var conflicts: [String: [ConflictItem]] = [:]
    @Published var error: String?
    let editor: KeymapFileEditor

    init(editor: KeymapFileEditor = KeymapFileEditor()) {
        self.editor = editor
        reload()
    }

    func reload() {
        do {
            let km = try KeymapParser.parse(toml: editor.currentText())
            apply(km)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    func apply(_ km: Keymap) {
        keymap = km
        Task.detached(priority: .utility) {
            let report = ConflictChecker(keymap: km).check()
            await MainActor.run {
                var m: [String: [ConflictItem]] = [:]
                for item in report.items where item.severity != .info { if let id = item.bindID { m[id, default: []].append(item) } }
                self.conflicts = m
            }
        }
    }

    func edit(_ store: SettingsStore, _ body: () throws -> Keymap) {
        do {
            apply(try body())
            error = nil
            store.runReload()
        } catch {
            store.message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}

struct KeybindsPage: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var model = KeymapModel()
    @Environment(\.look) var look
    @State private var filter = ""
    @State private var recording: String?
    @State private var onlyConflicts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Keybinds", subtitle: "Click a shortcut to record a new one. Saved to keymap.toml and applied at once.")
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(look[.onSurfaceVariant])
                    TextField("Search binds", text: $filter).textFieldStyle(.plain).font(look.font(13.5)).foregroundStyle(look[.onSurface])
                    Spacer()
                    let n = model.conflicts.count
                    PillSegmented(options: [(false, "All", nil), (true, n == 0 ? "Conflicts" : "Conflicts (\(n))", "exclamationmark.triangle")],
                                  selection: $onlyConflicts)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(look[.surfaceContainerHighest].opacity(0.8)))
                if let e = model.error {
                    Text(e).font(look.mono(11.5)).foregroundStyle(look[.error])
                }
            }
            if let km = model.keymap {
                ForEach(BindCategory.allCases, id: \.self) { cat in
                    let binds = visible(km, cat)
                    if !binds.isEmpty {
                        Card {
                            SectionLabel(text: cat.rawValue)
                            ForEach(binds) { b in
                                BindRow(bind: b, modifiers: km.modifiers, conflicts: model.conflicts[b.id] ?? [],
                                        recording: recording == b.id,
                                        onRecord: { startRecording(b.id) },
                                        onRecorded: { keys in finish(b.id, keys) },
                                        onCancel: { recording = nil },
                                        onToggle: { on in model.edit(store) { try model.editor.setEnabled(on, forBind: b.id) } },
                                        onReset: { model.edit(store) { try model.editor.resetBind(b.id) } })
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: recording) { _, r in if r == nil { store.pauseHotkeys(0) } }
        .onDisappear { if recording != nil { store.pauseHotkeys(0) } }
    }

    func visible(_ km: Keymap, _ cat: BindCategory) -> [Bind] {
        let q = filter.lowercased()
        return km.binds.filter { b in
            b.action.kind.category == cat
                && (!onlyConflicts || model.conflicts[b.id] != nil)
                && (q.isEmpty || b.description.lowercased().contains(q) || b.id.lowercased().contains(q) || b.keys.joined().lowercased().contains(q))
        }
    }

    func startRecording(_ id: String) {
        // The WM would act on the chord before we see it: pause its hotkeys while recording.
        store.pauseHotkeys(10)
        withAnimation(look.motion.quick) { recording = id }
    }

    func finish(_ id: String, _ keys: String) {
        recording = nil
        model.edit(store) { try model.editor.setKeys([keys], forBind: id) }
    }
}

struct BindRow: View {
    var bind: Bind
    var modifiers: ModifierMap
    var conflicts: [ConflictItem]
    var recording: Bool
    var onRecord: () -> Void
    var onRecorded: (String) -> Void
    var onCancel: () -> Void
    var onToggle: (Bool) -> Void
    var onReset: () -> Void
    @Environment(\.look) var look
    @State private var hover = false

    var isPanic: Bool { bind.id == KeymapParser.panicBindID }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bind.description.isEmpty ? bind.id : bind.description.prefix(1).uppercased() + bind.description.dropFirst())
                        .font(look.font(13.5, .medium)).foregroundStyle(look[.onSurface].opacity(bind.enabled ? 1 : 0.5))
                    Text(bind.id).font(look.mono(10.5)).foregroundStyle(look[.onSurfaceVariant])
                }
                Spacer()
                if hover, !isPanic {
                    Button(action: onReset) { Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(look[.onSurfaceVariant]).help("Back to the default")
                        .transition(.opacity)
                }
                chordButton
                PillToggle(isOn: Binding(get: { bind.enabled }, set: { onToggle($0) }), enabled: !isPanic, accessibilityLabel: "Enable \(bind.id)")
                    .scaleEffect(0.85)
            }
            ForEach(conflicts, id: \.self) { c in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: c.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(c.severity == .error ? look[.error] : look[.tertiary])
                    Text(c.message + (c.fix.map { " — \($0)" } ?? "")).font(look.font(11.5)).foregroundStyle(look[.onSurfaceVariant])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: SettingsLook.rowRadius, style: .continuous)
            .fill(recording ? look[.primaryContainer].opacity(0.5) : hover ? look[.surfaceContainerHigh].opacity(0.6) : .clear))
        .onHover { h in withAnimation(look.motion.quick) { hover = h } }
        .accessibilityIdentifier("bind.\(bind.id)")
    }

    @ViewBuilder var chordButton: some View {
        if recording {
            HStack(spacing: 6) {
                Image(systemName: "record.circle").foregroundStyle(look[.error]).symbolEffect(.pulse)
                Text("Press a shortcut…").font(look.font(12.5, .medium)).foregroundStyle(look[.onPrimaryContainer])
                Text("esc").font(look.font(10.5)).foregroundStyle(look[.onSurfaceVariant])
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().strokeBorder(look[.primary], lineWidth: 1.5))
            .background(KeyCatcher(modifiers: modifiers, onChord: onRecorded, onCancel: onCancel))
        } else {
            Button(action: onRecord) {
                HStack(spacing: 6) {
                    if bind.chords.isEmpty {
                        Text("Not set").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                    }
                    ForEach(Array(bind.chords.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Text("or").font(look.font(11)).foregroundStyle(look[.onSurfaceVariant]) }
                        KeyCaps(text: ChordParser.format(c, modifierMap: modifiers))
                    }
                }
                .opacity(bind.enabled ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(isPanic)
            .help(isPanic ? "The panic shortcut is fixed so you can always get out." : "Click to record a new shortcut")
        }
    }
}

/// Captures the next key press while recording (a local monitor; the WM's hotkeys are paused).
struct KeyCatcher: NSViewRepresentable {
    var modifiers: ModifierMap
    var onChord: (String) -> Void
    var onCancel: () -> Void

    final class Coordinator {
        var monitor: Any?
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let map = modifiers
        let onChord = onChord
        let onCancel = onCancel
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { e in
            if e.keyCode == 0x35, e.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                onCancel()
                return nil
            }
            guard !ChordRecorder.modifierKeyCodes.contains(e.keyCode),
                let text = ChordRecorder.notation(keyCode: e.keyCode, flags: UInt64(e.modifierFlags.rawValue), map: map)
            else { return nil }
            onChord(text)
            return nil
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
