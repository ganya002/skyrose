import CaelestiaCore
import SwiftUI

/// The Settings pages, in sidebar order.
public enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case general, appearance, windows, rules, keybinds, shell, terminal, permissions, about
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .windows: return "Windows"
        case .rules: return "Window rules"
        case .keybinds: return "Keybinds"
        case .shell: return "Bar and Shell"
        case .terminal: return "Terminal"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintpalette"
        case .windows: return "macwindow.on.rectangle"
        case .rules: return "rectangle.3.group"
        case .keybinds: return "keyboard"
        case .shell: return "sidebar.left"
        case .terminal: return "terminal"
        case .permissions: return "lock.shield"
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
    var onClose: () -> Void
    var onRunOnboarding: () -> Void
    @Namespace private var ns

    public init(store: SettingsStore, page: SettingsPage = .general, onClose: @escaping () -> Void, onRunOnboarding: @escaping () -> Void) {
        self.store = store
        _page = State(initialValue: page)
        self.onClose = onClose
        self.onRunOnboarding = onRunOnboarding
    }

    public var body: some View {
        let look = store.look
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
        .overlay(alignment: .bottom) { banner(look) }
        .background(PanelBackground())
        .environment(\.look, look)
        .animation(look.motion.page, value: page)
        .frame(minWidth: 860, minHeight: 600)
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
                    withAnimation(look.motion.page) { page = p }
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
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("page.\(p.rawValue)")
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(store.wmRunning ? look[.success] : look[.outline]).frame(width: 7, height: 7)
                Text(store.wmRunning ? "SkyRose is running" : "SkyRose is not running").font(look.font(11.5)).foregroundStyle(look[.onSurfaceVariant])
            }
            .padding(.leading, 6)
        }
        .padding(.horizontal, 14).padding(.vertical, 16)
        .frame(width: 228)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(look[.surfaceContainerLow].opacity(0.6))
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
        case .rules: RulesPage(store: store)
        case .keybinds: KeybindsPage(store: store)
        case .shell: ShellPage(store: store)
        case .terminal: TerminalPage(store: store)
        case .permissions: PermissionsPage(store: store, only: [])
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
