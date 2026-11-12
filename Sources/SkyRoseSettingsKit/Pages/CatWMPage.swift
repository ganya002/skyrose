import CaelestiaCore
import SwiftUI

/// Settings › CatWM: the window engine and the `[wm.catwm]` switches. SettingsRoot shows it as a
/// full-window panel that grows out of its sidebar row (see `SettingsRoot.body`).
struct CatWMPage: View {
    @ObservedObject var store: SettingsStore
    var onBack: () -> Void
    @Environment(\.look) var look
    /// The engine when the panel opened: a change only takes effect after a restart.
    @State private var startEngine: WMEngine?
    @State private var extra = ""

    private var catwm: CatWMSettings { store.config.wm.catwm }
    private var onCatWM: Bool { store.config.wm.engine == .catwm }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            engineCard
            Group {
                layoutsCard
                mouseCard
                floatingCard
                advancedCard
            }
            .disabled(!onCatWM)
            .opacity(onCatWM ? 1 : 0.5)
            Text("Gaps, focus and window motion come from Settings › Windows. Window management powered by CatWM by Per William Krogstad-Østensen (@noxaur), used with permission.")
                .font(look.font(11.5)).foregroundStyle(look[.onSurfaceVariant])
        }
        .animation(look.motion.page, value: store.config.wm.engine)
        .onAppear {
            if startEngine == nil { startEngine = store.config.wm.engine }
            extra = catwm.extra
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(look[.onPrimaryContainer])
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(look[.primaryContainer]))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Back to Settings")
            .accessibilityIdentifier("catwm.back")
            Image(systemName: "pawprint.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(look[.primary])
            VStack(alignment: .leading, spacing: 2) {
                Text("CatWM").font(look.font(26, .semibold)).foregroundStyle(look[.onSurface])
                Text("The tiling engine behind SkyRose.").font(look.font(13)).foregroundStyle(look[.onSurfaceVariant])
            }
        }
    }

    private var engineCard: some View {
        Card {
            SectionLabel(text: "Engine")
            SettingRow(title: "Window manager", detail: onCatWM
                       ? "CatWM tiles, moves and animates your windows."
                       : "SkyRose's own tiler. Work in progress, not recommended.", icon: "square.grid.2x2") {
                PillSegmented(options: [(WMEngine.catwm, "CatWM (default)", nil), (.skyrose, "SkyRose WM (WIP)", nil)],
                              selection: store.binding(\.wm.engine, "wm.engine") { .string($0.rawValue) })
            }
            if let startEngine, startEngine != store.config.wm.engine {
                SettingRow(title: "Restart to switch", detail: "Your windows stay open. They are re-tiled on workspace 1.", icon: "arrow.clockwise") {
                    PillButton(title: "Restart SkyRose", icon: "arrow.clockwise", kind: .filled) {
                        self.startEngine = store.config.wm.engine
                        store.restartSkyRose()
                    }
                    .accessibilityIdentifier("catwm.restart")
                }
                .transition(.opacity.combined(with: .offset(y: look.motion.slide(-6))))
            }
        }
    }

    private var layoutsCard: some View {
        Card {
            SectionLabel(text: "Layouts")
            Text("The layouts the cycle-layout bind steps through. The first one is where every workspace starts.")
                .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
            FlowChips(items: CatWMSettings.knownLayouts) { name in
                let index = catwm.layouts.firstIndex(of: name)
                Button {
                    var list = catwm.layouts
                    if let index { if list.count > 1 { list.remove(at: index) } } else { list.append(name) }
                    withAnimation(look.motion.quick) { store.setList(\.wm.catwm.layouts, "wm.catwm.layouts", list) }
                } label: {
                    HStack(spacing: 5) {
                        if index == 0 { Image(systemName: "star.fill").font(.system(size: 9, weight: .bold)) }
                        Text(name).font(look.font(12.5, .medium))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .foregroundStyle(index != nil ? look[.onPrimary] : look[.onSurfaceVariant])
                    .background(Capsule().fill(index != nil ? look[.primary] : look[.surfaceContainerHighest]))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(index != nil ? [.isButton, .isSelected] : .isButton)
            }
            SettingRow(title: "Start with", icon: "star") {
                Menu(catwm.layouts.first ?? "dwindle") {
                    ForEach(catwm.layouts, id: \.self) { name in
                        Button(name) {
                            store.setList(\.wm.catwm.layouts, "wm.catwm.layouts", [name] + catwm.layouts.filter { $0 != name })
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("catwm.startLayout")
            }
        }
    }

    private var mouseCard: some View {
        Card {
            SectionLabel(text: "Mouse")
            SettingRow(title: "Drag to swap", detail: "Drop a tiled window onto another to swap them.", icon: "arrow.left.arrow.right") {
                PillToggle(isOn: store.bool(\.wm.catwm.dragToSwap, "wm.catwm.dragToSwap"), accessibilityLabel: "Drag to swap")
            }
            SettingRow(title: "Drag to resize", detail: "Drag the edge between tiled windows to resize both.", icon: "arrow.left.and.right") {
                PillToggle(isOn: store.bool(\.wm.catwm.dragToResize, "wm.catwm.dragToResize"), accessibilityLabel: "Drag to resize")
            }
        }
    }

    private var floatingCard: some View {
        Card {
            SectionLabel(text: "Floating")
            SettingRow(title: "Float small windows", detail: "Dialogs, panels and other small windows float instead of tiling.", icon: "macwindow.on.rectangle") {
                PillToggle(isOn: store.bool(\.wm.catwm.floatSmallWindows, "wm.catwm.floatSmallWindows"), accessibilityLabel: "Float small windows")
            }
            SettingRow(title: "Always float", detail: "Every window of these apps floats. Wildcards like com.adobe.* work.", icon: "pin") {
                if let app = store.lastOtherApp, !catwm.floatingApps.contains(app.bundleID) {
                    PillButton(title: "Add \(app.name)", icon: "plus", kind: .tonal) {
                        withAnimation(look.motion.page) { store.setList(\.wm.catwm.floatingApps, "wm.catwm.floatingApps", catwm.floatingApps + [app.bundleID]) }
                    }
                    .help("The app you used last before Settings: \(app.bundleID)")
                    .accessibilityIdentifier("catwm.floating.add")
                }
            }
            if catwm.floatingApps.isEmpty {
                Text("No apps: windows float only by size or by your window rules.").font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
            } else {
                FlowChips(items: catwm.floatingApps) { id in
                    HStack(spacing: 6) {
                        Text(id).font(look.mono(12)).foregroundStyle(look[.onSecondaryContainer])
                        Button {
                            withAnimation(look.motion.page) { store.setList(\.wm.catwm.floatingApps, "wm.catwm.floatingApps", catwm.floatingApps.filter { $0 != id }) }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(look[.onSecondaryContainer])
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(id)")
                    }
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Capsule().fill(look[.secondaryContainer]))
                }
            }
        }
    }

    private var advancedCard: some View {
        Card {
            SectionLabel(text: "Advanced")
            Text("Extra CatWM config lines (TypeScript), added after SkyRose's own. For options this page doesn't show, e.g. catwm.resizeStep = 10.")
                .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
            TextEditor(text: $extra)
                .font(look.mono(12.5)).foregroundStyle(look[.onSurface])
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 90)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(look[.surfaceContainerHighest]))
                .accessibilityIdentifier("catwm.extra")
            if extra != catwm.extra {
                HStack {
                    Spacer()
                    PillButton(title: "Revert", kind: .outline) { extra = catwm.extra }
                    PillButton(title: "Save", kind: .filled) {
                        let text = extra
                        store.set("wm.catwm.extra", .string(text), update: { $0.wm.catwm.extra = text })
                    }
                    .accessibilityIdentifier("catwm.extra.save")
                }
                .transition(.opacity)
            }
        }
        .animation(look.motion.quick, value: extra != catwm.extra)
    }
}

/// Chips that wrap onto the next line.
struct FlowChips<Item: Hashable, Chip: View>: View {
    var items: [Item]
    @ViewBuilder var chip: (Item) -> Chip
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { chip($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var width = 0.0; var y = 0.0; var height = 0.0 }

    private func arrange(width: Double, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
