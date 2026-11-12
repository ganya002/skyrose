import CaelestiaCore
import SwiftUI

/// The Settings pages, in sidebar order.
public enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case general, appearance, windows, catwm, rules, keybinds, shell, store, terminal, sipOff, permissions, backup, about
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .windows: return "Windows"
        case .catwm: return "CatWM"
        case .rules: return "Window rules"
        case .keybinds: return "Keybinds"
        case .shell: return "Bar and Shell"
        case .store: return "SkyStore"
        case .terminal: return "Terminal"
        case .sipOff: return "SIP-off mode"
        case .permissions: return "Permissions"
        case .backup: return "Backup & uninstall"
        case .about: return "About"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintpalette"
        case .windows: return "macwindow.on.rectangle"
        case .catwm: return "pawprint.fill"
        case .rules: return "rectangle.3.group"
        case .keybinds: return "keyboard"
        case .shell: return "sidebar.left"
        case .store: return "bag"
        case .terminal: return "terminal"
        case .sipOff: return "bolt.shield"
        case .permissions: return "lock.shield"
        case .backup: return "arrow.uturn.backward.circle"
        case .about: return "info.circle"
        }
    }

    /// Pages that only matter with the shell (dimmed in WM-only mode, still reachable).
    public var needsShell: Bool { self == .shell }
}

/// The whole Settings window: sidebar, page, message banner.
public struct SettingsRoot: View {
    @ObservedObject var store: SettingsStore
    @State var page: SettingsPage
    /// The page to go back to from the CatWM panel.
    @State private var previous: SettingsPage = .general
    var onClose: () -> Void
    var onRunOnboarding: () -> Void
    var onUninstall: (Bool) -> Void
    @Namespace private var ns

    public init(store: SettingsStore, page: SettingsPage = .general, onClose: @escaping () -> Void, onRunOnboarding: @escaping () -> Void,
                onUninstall: @escaping (_ dryRun: Bool) -> Void = { _ in }) {
        self.store = store
        self.onUninstall = onUninstall
        _page = State(initialValue: page)
        self.onClose = onClose
        self.onRunOnboarding = onRunOnboarding
    }

    public var body: some View {
        let look = store.look
        ZStack {
            if page == .catwm {
                catwmPanel(look)
            } else {
                settings(look)
            }
        }
        .overlay(alignment: .bottom) { banner(look) }
        .background(PanelBackground())
        .environment(\.look, look)
        .frame(minWidth: 860, minHeight: 600)
    }

    /// The CatWM panel: its background is the sidebar row's, grown to the whole window
    /// (`matchedGeometryEffect`), and the page fades in on top once it has room.
    private func catwmPanel(_ look: SettingsLook) -> some View {
        ScrollView {
            CatWMPage(store: store, onBack: { withAnimation(look.motion.morph) { page = previous } })
                .padding(.horizontal, 40).padding(.top, 34).padding(.bottom, 30)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: look.motion.reduceMotion ? 1 : 0.96)).animation(look.motion.morph.delay(look.motion.reduceMotion ? 0 : 0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.1))))
        .background {
            RoundedRectangle(cornerRadius: SettingsLook.insetPanelRadius, style: .circular)
                .fill(look[.primaryContainer].opacity(0.35))
                .matchedGeometryEffect(id: "catwm.morph", in: ns)
                .padding(SettingsLook.panelInset)
        }
        .accessibilityIdentifier("catwm.panel")
    }

    private func settings(_ look: SettingsLook) -> some View {
        HStack(spacing: 0) {
            sidebar(look)
            ScrollView {
                pageView
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: look.motion.slide(14))),
                        removal: .opacity))
                    .padding(.horizontal, 30).padding(.top, 34).padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .transition(.opacity.combined(with: .scale(scale: look.motion.reduceMotion ? 1 : 1.03)))
    }

    private func sidebar(_ look: SettingsLook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                WindowButtons(onClose: onClose)
                Spacer()
            }
            .padding(.bottom, 14)
            HStack(spacing: 10) {
                BrandIcon(which: store.config.general.mode == .wm ? .wm : .main, size: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.config.general.mode == .wm ? "SkyRose WM" : "SkyRose").font(look.font(17, .semibold)).foregroundStyle(look[.onSurface])
                    Text("Settings").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                }
            }
            .padding(.bottom, 16)
            .animation(look.motion.quick, value: store.config.general.mode)
            ForEach(SettingsPage.allCases) { p in
                let selected = p == page
                Button {
                    if p == .catwm {
                        previous = page
                        withAnimation(look.motion.morph) { page = p }
                    } else {
                        withAnimation(look.motion.page) { page = p }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.icon).font(.system(size: 13, weight: .medium)).frame(width: 18)
                        Text(p.title).font(look.font(13.5, selected ? .semibold : .regular))
                        Spacer()
                        if p == .permissions, let missing = missingCount, missing > 0 {
                            Text("\(missing)").font(look.font(11, .bold)).foregroundStyle(look[.onError])
                                .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(look[.error]))
                        }
                    }
                    .foregroundStyle(selected ? look[.onSecondaryContainer] : look[.onSurfaceVariant])
                    .opacity(p.needsShell && store.config.shellOff ? 0.5 : 1)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule().fill(look[.secondaryContainer]).matchedGeometryEffect(id: "pill", in: ns)
                        } else if p == .catwm {
                            Capsule().fill(look[.primaryContainer].opacity(0.35)).matchedGeometryEffect(id: "catwm.morph", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("page.\(p.rawValue)")
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(store.wmRunning ? (store.wmBusy ? look[.tertiary] : look[.success]) : look[.outline]).frame(width: 7, height: 7)
                Text(store.statusLine).font(look.font(11.5)).foregroundStyle(look[.onSurfaceVariant])
            }
            .padding(.leading, 6)
        }
        .padding(.horizontal, 14 - SettingsLook.panelInset).padding(.vertical, 16 - SettingsLook.panelInset)
        .frame(width: 228 - 2 * SettingsLook.panelInset)
        .frame(maxHeight: .infinity, alignment: .top)
        // An inset panel with concentric corners: it never meets the window edge, so there is
        // no seam and its corners follow the window's.
        .background(
            RoundedRectangle(cornerRadius: SettingsLook.insetPanelRadius, style: .circular)
                .fill(look[.surfaceContainerLow].opacity(0.6))
        )
        .padding(SettingsLook.panelInset)
    }

    private var missingCount: Int? {
        guard let p = store.permissions else { return nil }
        return SkyRosePermission.allCases.filter { !p.isGranted($0) }.count
    }

    @ViewBuilder private var pageView: some View {
        switch page {
        case .general: GeneralPage(store: store, onRunOnboarding: onRunOnboarding)
        case .appearance: AppearancePage(store: store)
        case .windows: WindowsPage(store: store)
        case .catwm: CatWMPage(store: store, onBack: { page = previous })
        case .rules: RulesPage(store: store)
        case .keybinds: KeybindsPage(store: store)
        case .shell: ShellPage(store: store)
        case .store: StorePage(store: store)
        case .terminal: TerminalPage(store: store)
        case .sipOff: SIPOffPage(store: store)
        case .permissions: PermissionsPage(store: store, only: [])
        case .backup: BackupUninstallPage(store: store, onUninstall: onUninstall)
        case .about: AboutPage(store: store)
        }
    }

    @ViewBuilder private func banner(_ look: SettingsLook) -> some View {
        if let m = store.message {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(look[.error])
                Text(m).font(look.font(12.5)).foregroundStyle(look[.onSurface]).lineLimit(3)
                Spacer()
                Button { withAnimation(look.motion.quick) { store.message = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(look[.onSurfaceVariant])
                }.buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: SettingsLook.rowRadius, style: .continuous).fill(look[.surfaceContainerHighest]))
            .padding(18)
            .frame(maxWidth: 560)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: m) {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                withAnimation(look.motion.quick) { if store.message == m { store.message = nil } }
            }
        }
    }
}

/// Close / minimise dots in the shell palette (the window is borderless).
struct WindowButtons: View {
    @Environment(\.look) var look
    var onClose: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Circle().fill(look[.error].opacity(hover ? 1 : 0.85)).frame(width: 13, height: 13)
                    .overlay(Image(systemName: "xmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(look[.onError]).opacity(hover ? 1 : 0))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("w", modifiers: .command)
            .accessibilityLabel("Close")
            Button { NSApp.keyWindow?.miniaturize(nil) } label: {
                Circle().fill(look[.tertiary].opacity(hover ? 1 : 0.7)).frame(width: 13, height: 13)
                    .overlay(Image(systemName: "minus").font(.system(size: 7, weight: .heavy)).foregroundStyle(look[.surface]).opacity(hover ? 1 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimise")
        }
        .onHover { h in withAnimation(look.motion.quick) { hover = h } }
    }
}
