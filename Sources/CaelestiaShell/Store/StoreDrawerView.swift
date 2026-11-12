import CaelestiaCore
import SwiftUI

/// The SkyStore drawer: grows out of the bottom band like the launcher (same blob, motion and
/// colours), with Featured / Categories / Installed / Updates, search, and a detail page per addon.
struct StoreDrawerView: View {
    @ObservedObject var model: StoreModel
    let fillet: Double
    private var size: CGSize { model.size }
    @Environment(\.shellTheme) var theme
    @FocusState private var focused: Bool
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                DrawerBackground(edge: .bottom, fillet: fillet, radius: theme.frameRounding, shown: model.shown, depth: size.height)
                VStack(spacing: LauncherModel.gap) {
                    header
                    page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    search
                }
                .padding(LauncherModel.padding)
                .frame(width: size.width, height: size.height)
                .liquidContent(edge: .bottom, shown: model.shown, depth: size.height, theme: theme)
            }
            .frame(width: size.width + 2 * fillet, height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: model.shown) { _, shown in if shown { focused = true } }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            MaterialIcon("storefront", size: 18, weight: .medium).foregroundStyle(theme[.primary])
            Text("SkyStore").font(theme.sans(18, weight: .semibold)).foregroundStyle(theme[.onSurface])
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(StoreModel.Tab.allCases, id: \.self) { t in tabPill(t) }
            }
            .padding(4)
            .background(Capsule().fill(theme[.secondaryContainer].opacity(0.35)))
            RoundIconButton(symbol: "refresh", size: 32, tonal: true) { model.refresh() }
                .opacity(model.loading ? 0.5 : 1)
        }
        .frame(height: 40)
    }

    private func tabPill(_ t: StoreModel.Tab) -> some View {
        let on = model.tab == t && model.selected == nil && model.query.isEmpty
        let badge = t == .updates ? model.updates.count : 0
        return Button {
            withAnimation(theme.spatial) {
                model.query = ""
                model.back()
                model.tab = t
            }
        } label: {
            HStack(spacing: 5) {
                MaterialIcon(t.icon, size: 13, weight: .medium)
                Text(t.title).font(theme.sans(13, weight: on ? .semibold : .medium))
                if badge > 0 {
                    Text("\(badge)").font(theme.sans(10.5, weight: .bold)).foregroundStyle(theme[.onPrimary])
                        .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17).background(Capsule().fill(theme[.primary]))
                }
            }
            .foregroundStyle(on ? theme[.onSecondaryContainer] : theme[.onSurfaceVariant])
            .padding(.horizontal, 12).frame(height: 30)
            .background { if on { Capsule().fill(theme[.secondaryContainer]).matchedGeometryEffect(id: "tab", in: ns) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("store.tab.\(t.rawValue)")
    }

    @ViewBuilder private var page: some View {
        Group {
            if let id = model.selected, let e = model.entry(id) {
                StoreDetailView(model: model, entry: e)
                    .transition(.opacity.combined(with: .offset(x: theme.slide(18))))
            } else if !model.query.isEmpty {
                grid(model.visible, empty: "Nothing matches “\(model.query)”")
            } else {
                switch model.tab {
                case .featured: indexGated { grid(model.visible, empty: "The index is empty.") }
                case .categories: indexGated { categories }
                case .installed: installedList
                case .updates: indexGated { updatesList }
                }
            }
        }
        .animation(theme.spatial, value: model.selected)
        .animation(theme.spatial, value: model.tab)
    }

    /// The index state instead of an empty grid: loading, not set up, offline, bad signature.
    @ViewBuilder private func indexGated<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if model.index != nil {
            content()
        } else if model.loading {
            placeholder("downloading", "Loading the SkyStore index…", nil)
        } else {
            placeholder("cloud_off", "SkyStore is not available", model.indexError)
        }
    }

    private func placeholder(_ icon: String, _ title: String, _ detail: String?) -> some View {
        VStack(spacing: 8) {
            MaterialIcon(icon, size: 30, weight: .light)
            Text(title).font(theme.sans(15, weight: .medium))
            if let detail { Text(detail).font(theme.sans(12)).multilineTextAlignment(.center).frame(maxWidth: 460) }
        }
        .foregroundStyle(theme[.onSurfaceVariant])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func grid(_ entries: [StoreEntry], empty: String) -> some View {
        if entries.isEmpty {
            placeholder("search_off", empty, nil)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(entries) { e in StoreCard(model: model, entry: e) }
                }
            }
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.shelves, id: \.self) { s in
                        let on = s == (model.category ?? model.shelves.first)
                        Button { withAnimation(theme.small) { model.category = s } } label: {
                            Text(s).font(theme.sans(12.5, weight: .medium))
                                .foregroundStyle(on ? theme[.onSecondaryContainer] : theme[.onSurfaceVariant])
                                .padding(.horizontal, 12).frame(height: 28)
                                .background(Capsule().fill(theme[.secondaryContainer].opacity(on ? 1 : 0.35)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            grid(model.visible, empty: "No addons in this category yet.")
        }
    }

    @ViewBuilder private var installedList: some View {
        if model.installed.isEmpty {
            placeholder("inventory_2", "No addons installed", "Install one from Featured or Categories. Addons stay on this Mac; `skyrose wm panic` switches them all off.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(model.installed) { a in InstalledRow(model: model, addon: a) }
                }
            }
        }
    }

    @ViewBuilder private var updatesList: some View {
        let ups = model.updates
        if ups.isEmpty {
            placeholder("check_circle", "Everything is up to date", nil)
        } else {
            VStack(spacing: 8) {
                HStack {
                    Text("\(ups.count) update\(ups.count == 1 ? "" : "s")").font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
                    Spacer()
                    StorePill(title: "Update all", icon: "update", filled: true) { model.updateAll() }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(ups, id: \.entry.id) { u in
                            HStack(spacing: 12) {
                                StoreIcon(entry: u.entry, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(u.entry.name).font(theme.sans(14, weight: .medium)).foregroundStyle(theme[.onSurface])
                                    Text("\(u.installed.version) → \(u.version.version)" + (u.version.notes.map { " · \($0)" } ?? ""))
                                        .font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                StoreActionButton(model: model, entry: u.entry)
                            }
                            .padding(10).shellCard(radius: 18, tint: 0.45)
                            .contentShape(Rectangle()).onTapGesture { model.open(u.entry.id) }
                        }
                    }
                }
            }
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            MaterialIcon("magnifyingglass", size: 15, weight: .medium).foregroundStyle(theme[.onSurfaceVariant])
            TextField("", text: $model.query, prompt: Text("Search SkyStore").foregroundColor(theme[.onSurfaceVariant]))
                .textFieldStyle(.plain)
                .font(theme.sans(16))
                .foregroundStyle(theme[.onSurface])
                .focused($focused)
                .accessibilityIdentifier("store.search")
                .onChange(of: model.query) { _, q in if !q.isEmpty, model.selected != nil { model.back() } }
        }
        .padding(.horizontal, 20)
        .frame(height: LauncherModel.searchHeight)
        .background(Capsule().fill(theme[.secondaryContainer].opacity(0.7)))
    }
}

/// An addon's icon from the index (HTTPS only), or its kind's Material icon.
struct StoreIcon: View {
    var entry: StoreEntry?
    var kind: AddonKind = .scheme
    var size: Double
    @Environment(\.shellTheme) var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            shape.fill(theme[.primaryContainer])
            if let url = entry?.icon, url.scheme == "https" {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { glyph }
            } else {
                glyph
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }

    private var glyph: some View {
        MaterialIcon((entry?.kind ?? kind).icon, size: size * 0.42, weight: .medium).foregroundStyle(theme[.onPrimaryContainer])
    }
}

struct StoreCard: View {
    @ObservedObject var model: StoreModel
    var entry: StoreEntry
    @Environment(\.shellTheme) var theme
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StoreIcon(entry: entry, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).font(theme.sans(14.5, weight: .semibold)).foregroundStyle(theme[.onSurface]).lineLimit(1)
                    Text(entry.author).font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(entry.summary).font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            HStack {
                Text(entry.shelf).font(theme.sans(11, weight: .medium)).foregroundStyle(theme[.onTertiaryContainer])
                    .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(theme[.tertiaryContainer].opacity(0.8)))
                Spacer(minLength: 0)
                StoreActionButton(model: model, entry: entry, compact: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme[.secondaryContainer].opacity(hover ? 0.6 : 0.4)))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { model.open(entry.id) }
        .onHover { h in withAnimation(theme.small) { hover = h } }
    }
}

struct StorePill: View {
    var title: String
    var icon: String?
    var filled = false
    var danger = false
    var action: () -> Void
    @Environment(\.shellTheme) var theme

    var body: some View {
        let bg: Color = danger ? theme[.error] : filled ? theme[.primary] : theme[.secondaryContainer]
        let fg: Color = danger ? theme[.onError] : filled ? theme[.onPrimary] : theme[.onSecondaryContainer]
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { MaterialIcon(icon, size: 12.5, weight: .semibold) }
                Text(title).font(theme.sans(12.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(bg))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Install / Update / Installed / Revoked, with the progress bar while busy and the second-press
/// state when new permissions need allowing.
struct StoreActionButton: View {
    @ObservedObject var model: StoreModel
    var entry: StoreEntry
    var compact = false
    @Environment(\.shellTheme) var theme

    var body: some View {
        Group {
            if let p = model.busy[entry.id] {
                let width: Double = p.setupFraction == nil || compact ? 96 : 220
                VStack(alignment: .trailing, spacing: 3) {
                    Text(p.label).font(theme.sans(11, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: width, alignment: .trailing)
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme[.secondaryContainer])
                        Capsule().fill(theme[.primary]).frame(width: max(8, width * p.fraction))
                    }
                    .frame(width: width, height: 6)
                    .animation(theme.spatial, value: p.fraction)
                    if let d = p.detail, !compact {
                        Text(d).font(theme.mono(10)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
            } else {
                switch model.action(for: entry) {
                case .install, .update:
                    let update = { if case .update = model.action(for: entry) { return true } else { return false } }()
                    if model.confirming == entry.id, let diff = model.permissionDiff(for: entry) {
                        StorePill(title: "Allow \(diff.added.count) new permission\(diff.added.count == 1 ? "" : "s")", icon: "shield", danger: true) {
                            model.install(entry)
                        }
                    } else {
                        StorePill(title: update ? "Update" : "Install", icon: update ? "update" : "download", filled: true) { model.install(entry) }
                    }
                case .installed: label("Installed", "check")
                case .setup: StorePill(title: "Set up", icon: "build", filled: true) { model.runSetup(entry.id) }
                case .revoked: label("Revoked", "block")
                case .needsNewerSkyRose: label("Needs a newer SkyRose", "upgrade")
                case .notSupported: label("Code addon: later SkyRose", "code")
                }
            }
        }
        .animation(theme.small, value: model.confirming)
    }

    private func label(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 4) {
            MaterialIcon(icon, size: 12, weight: .medium)
            if !compact || text.count < 12 { Text(text).font(theme.sans(12, weight: .medium)) }
        }
        .foregroundStyle(theme[.onSurfaceVariant])
        .frame(height: 28)
    }
}

struct InstalledRow: View {
    @ObservedObject var model: StoreModel
    var addon: InstalledAddon
    @Environment(\.shellTheme) var theme

    var body: some View {
        let entry = model.entry(addon.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                StoreIcon(entry: entry, kind: addon.kind, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(addon.name).font(theme.sans(14, weight: .medium)).foregroundStyle(theme[.onSurface])
                    Text("\(addon.version) · \(addon.kind.title) · \(addon.status)").font(theme.sans(12))
                        .foregroundStyle(addon.isRevoked ? theme[.error] : theme[.onSurfaceVariant]).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let entry, case .update = model.action(for: entry) { StoreActionButton(model: model, entry: entry, compact: true) }
                if !addon.isRevoked {
                    StorePill(title: addon.enabled ? "Turn off" : "Turn on", icon: addon.enabled ? "toggle_on" : "toggle_off") {
                        model.setEnabled(addon.id, !addon.enabled)
                    }
                }
                StorePill(title: model.confirming == addon.id ? "Remove?" : "Uninstall", icon: "delete", danger: model.confirming == addon.id) {
                    model.uninstall(addon.id)
                }
            }
            if let err = model.errors[addon.id] { Text(err).font(theme.sans(11.5)).foregroundStyle(theme[.error]).lineLimit(2) }
        }
        .padding(10)
        .shellCard(radius: 18, tint: 0.45)
        .contentShape(Rectangle())
        .onTapGesture { if entry != nil { model.open(addon.id) } }
        .animation(theme.small, value: model.confirming)
    }
}

struct StoreDetailView: View {
    @ObservedObject var model: StoreModel
    var entry: StoreEntry
    @Environment(\.shellTheme) var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    RoundIconButton(symbol: "chevron_left", size: 32, tonal: true) { model.back() }
                    StoreIcon(entry: entry, size: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(theme.sans(22, weight: .semibold)).foregroundStyle(theme[.onSurface])
                        Text("by \(entry.author)").font(theme.sans(13)).foregroundStyle(theme[.onSurfaceVariant])
                        Text([entry.shelf, entry.history.first.map { "v\($0.version)" }, entry.licence].compactMap { $0 }.joined(separator: " · "))
                            .font(theme.sans(12)).foregroundStyle(theme[.outline])
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        StoreActionButton(model: model, entry: entry)
                        if let a = model.installed(entry.id) {
                            StorePill(title: model.confirming == a.id ? "Remove?" : "Uninstall", icon: "delete", danger: model.confirming == a.id) {
                                model.uninstall(a.id)
                            }
                        }
                    }
                }
                if let err = model.errors[entry.id] {
                    Text(err).font(theme.sans(12)).foregroundStyle(theme[.error])
                }
                if let why = entry.revoked ?? model.installed(entry.id).flatMap({ a -> String? in if case .revoked(let w) = a.disabled { return w } else { return nil } }) {
                    Label { Text("Revoked by the SkyStore maintainers: \(why). It is switched off and cannot be turned back on.") } icon: { MaterialIcon("block", size: 14) }
                        .font(theme.sans(12.5)).foregroundStyle(theme[.onErrorContainer])
                        .padding(10).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme[.errorContainer]))
                }
                if let shots = entry.screenshots?.filter({ $0.scheme == "https" }), !shots.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shots, id: \.self) { url in
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
                                    MaterialIcon("image", size: 24, weight: .light).foregroundStyle(theme[.onSurfaceVariant])
                                }
                                .frame(width: 300, height: 188)
                                .background(theme[.secondaryContainer].opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }
                Text(entry.description ?? entry.summary).font(theme.sans(13)).foregroundStyle(theme[.onSurface])
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 10) {
                    permissions.frame(maxWidth: .infinity, alignment: .topLeading)
                    history.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.bottom, 6)
        }
    }

    private var permissions: some View {
        let v = entry.latest(for: model.addons.skyRoseVersion) ?? entry.history.first
        let added = Set(model.permissionDiff(for: entry)?.added ?? [])
        let list = v?.parsedPermissions ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text("Permissions").font(theme.sans(13.5, weight: .semibold)).foregroundStyle(theme[.onSurface])
            if list.isEmpty {
                Label { Text(entry.kind.isDataOnly ? "None. Data only: SkyRose reads its files and never runs them." : "None.") } icon: { MaterialIcon("verified_user", size: 13) }
                    .font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant])
            }
            ForEach(list, id: \.self) { p in
                Label { Text(p.summary + (added.contains(p) && model.installed(entry.id) != nil ? " (new)" : "")) } icon: { MaterialIcon(p.icon, size: 13) }
                    .font(theme.sans(12, weight: added.contains(p) ? .semibold : .regular))
                    .foregroundStyle(added.contains(p) ? theme[.error] : theme[.onSurfaceVariant])
            }
            if entry.kind == .app {
                Label { Text("An app: built on this Mac from the reviewed source in the bundle, then run as its own app, never inside SkyRose. Panic, off and uninstall stop it.") } icon: { MaterialIcon("apps", size: 13) }
                    .font(theme.sans(11.5)).foregroundStyle(theme[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
            }
            Text("Verified on install: index signature and SHA-256.").font(theme.sans(11)).foregroundStyle(theme[.outline])
        }
        .padding(12).shellCard(radius: 18, tint: 0.4)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Version history").font(theme.sans(13.5, weight: .semibold)).foregroundStyle(theme[.onSurface])
            ForEach(entry.history) { v in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(v.version).font(theme.sans(12.5, weight: .semibold)).foregroundStyle(theme[.onSurface])
                        Text(v.released).font(theme.sans(11.5)).foregroundStyle(theme[.outline])
                        if model.installed(entry.id)?.version == v.version {
                            Text("installed").font(theme.sans(10.5, weight: .medium)).foregroundStyle(theme[.primary])
                        }
                        if v.revoked != nil { Text("revoked").font(theme.sans(10.5, weight: .medium)).foregroundStyle(theme[.error]) }
                    }
                    if let n = v.notes { Text(n).font(theme.sans(11.5)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(3) }
                }
            }
        }
        .padding(12).shellCard(radius: 18, tint: 0.4)
    }
}
