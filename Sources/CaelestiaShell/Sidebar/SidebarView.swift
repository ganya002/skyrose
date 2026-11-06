import AppKit
import CaelestiaCore
import SwiftUI

@MainActor
public final class SidebarModel: ObservableObject {
    @Published public var shown = false
    @Published public var expanded: Set<String> = []
    @Published public var brightnessAvailable = true
    @Published public var width: Double = ShellSizing.sidebarDesignWidth
    public var onDismiss: (UUID) -> Void = { _ in }
    public var onClear: () -> Void = {}
    public var onToggle: (String) -> Void = { _ in }
    public var onVolume: (Double) -> Void = { _ in }
    public var onBrightness: (Double) -> Void = { _ in }
    public var onKeepAwake: (Bool) -> Void = { _ in }
    /// Keep awake for a preset time (nil = until turned off).
    public var onKeepAwakeFor: (TimeInterval?) -> Void = { _ in }
    /// Clamshell on/off (the lid-closed `disablesleep`).
    public var onClamshell: (Bool) -> Void = { _ in }
    public var onMute: () -> Void = {}
    public var onWallpaper: () -> Void = {}
    public init() {}
}

struct SidebarView: View {
    @ObservedObject var model: SidebarModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme
    let fillet: Double

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                FrostedShape(shape: DrawerShape(edge: .right, radius: theme.frameRounding, fillet: fillet), theme: theme)
                    .liquidBody(edge: .right, shown: model.shown, depth: model.width, theme: theme, neck: false)
                VStack(spacing: 10) {
                    NotificationsSection(model: model, state: state)
                    UtilitiesSection(model: model, state: state)
                }
                .padding(.horizontal, 12)
                .padding(.top, fillet + 6)
                .padding(.bottom, fillet + 6)
                .padding(.leading, 4)
                .liquidContent(edge: .right, shown: model.shown, depth: model.width, theme: theme)
            }
            .frame(width: model.width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

private struct NotificationsSection: View {
    @ObservedObject var model: SidebarModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        let groups = NotificationGrouper.group(state.notifications)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NotificationGrouper.title(count: state.notifications.count))
                    .font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
                if state.doNotDisturb {
                    Label("Do not disturb", systemImage: "bell.slash.fill").labelStyle(.titleAndIcon)
                        .font(theme.sans(11, weight: .medium)).foregroundStyle(theme[.tertiary])
                }
                Spacer()
            }
            .padding(.leading, 6)
            ZStack(alignment: .bottomTrailing) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        if groups.isEmpty {
                            VStack(spacing: 8) {
                                MaterialIcon("bell.slash", size: 28, weight: .light)
                                Text("Notifications from SkyRose and `skyrose notify` appear here")
                                    .font(theme.sans(12)).multilineTextAlignment(.center)
                            }
                            .foregroundStyle(theme[.onSurfaceVariant].opacity(0.7)).padding(.top, 60).padding(.horizontal, 24)
                        }
                        ForEach(groups) { g in GroupCard(group: g, model: model) }
                    }
                    .padding(.bottom, 52)
                }
                if !groups.isEmpty {
                    Button(action: model.onClear) {
                        HStack(spacing: 6) { MaterialIcon("delete", size: 12, weight: .semibold); Text("Clear all") }
                            .font(theme.sans(12, weight: .semibold)).foregroundStyle(theme[.onPrimaryContainer])
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Capsule().fill(theme[.primaryContainer]))
                    }
                    .buttonStyle(.plain).padding(8).accessibilityIdentifier("sidebar.clearAll")
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct GroupCard: View {
    var group: NotificationGroup
    @ObservedObject var model: SidebarModel
    @Environment(\.shellTheme) var theme

    var body: some View {
        let open = model.expanded.contains(group.appName)
        let shown = open ? group.items : Array(group.items.prefix(1))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MaterialIcon(group.icon.isEmpty ? "info" : group.icon, size: 12)
                    .foregroundStyle(theme[.onSecondaryContainer]).frame(width: 22, height: 22)
                    .background(Circle().fill(theme[.secondaryContainer]))
                Text(group.appName).font(theme.sans(12, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant])
                Spacer()
                Text(NotificationGrouper.relativeTime(group.latest)).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant])
                if group.items.count > 1 {
                    Button {
                        withAnimation(theme.small) { if open { model.expanded.remove(group.appName) } else { model.expanded.insert(group.appName) } }
                    } label: {
                        Text("\(group.items.count)").font(theme.sans(11, weight: .bold)).foregroundStyle(theme[.onPrimaryContainer])
                            .frame(minWidth: 20, minHeight: 20).background(Capsule().fill(theme[.primaryContainer]))
                    }.buttonStyle(.plain)
                }
            }
            ForEach(shown) { n in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.summary).font(theme.sans(13, weight: .semibold)).foregroundStyle(theme[.onSurface]).lineLimit(2)
                        if !n.body.isEmpty { Text(n.body).font(theme.sans(12)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(open ? 6 : 2) }
                    }
                    Spacer(minLength: 4)
                    Button { model.onDismiss(n.id) } label: {
                        MaterialIcon("xmark", size: 9, weight: .bold).foregroundStyle(theme[.onSurfaceVariant])
                            .frame(width: 20, height: 20)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shellCard(radius: 20)
        .accessibilityIdentifier("sidebar.group")
    }
}

struct UtilitiesSection: View {
    @ObservedObject var model: SidebarModel
    @ObservedObject var state: ShellState
    @Environment(\.shellTheme) var theme

    var body: some View {
        VStack(spacing: 8) {
            keepAwake
            sliders
            toggles
        }
    }

    private var keepAwake: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                MaterialIcon("cup.and.saucer.fill", size: 16)
                    .foregroundStyle(theme[.onSurface]).frame(width: 40, height: 40)
                    .background(Circle().fill(theme[.onSurface].opacity(0.08)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep awake").font(theme.sans(14, weight: .medium)).foregroundStyle(theme[.onSurface])
                    // Ticks so a timed keep-awake counts down.
                    TimelineView(.periodic(from: .now, by: 20)) { ctx in
                        Text(KeepAwakeTimer.status(enabled: state.keepAwake, until: state.keepAwakeUntil, now: ctx.date))
                            .font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).monospacedDigit()
                    }
                }
                Spacer()
                // Only real flips: re-sending the current value would turn a timed keep-awake into an unlimited one.
                Toggle("", isOn: Binding(get: { state.keepAwake }, set: { if $0 != state.keepAwake { model.onKeepAwake($0) } })).toggleStyle(.switch).labelsHidden()
                    .tint(theme[.primary]).accessibilityIdentifier("sidebar.keepAwake")
            }
            HStack(spacing: 6) {
                ForEach(Array(KeepAwakeTimer.presets.enumerated()), id: \.offset) { _, d in
                    let chosen = KeepAwakeTimer.isChosen(d, enabled: state.keepAwake, duration: state.keepAwakeDuration)
                    Button { model.onKeepAwakeFor(d) } label: {
                        Text(KeepAwakeTimer.label(d)).font(theme.sans(11, weight: .medium))
                            .foregroundStyle(chosen ? theme[.onPrimary] : theme[.onSurface])
                            .frame(maxWidth: .infinity).frame(height: 24)
                            .background(Capsule().fill(chosen ? theme[.primary] : theme[.onSurface].opacity(0.08)))
                    }
                    .buttonStyle(.plain).help(d == nil ? "Keep awake until turned off" : "Keep awake for \(KeepAwakeTimer.label(d))")
                }
            }
            .accessibilityIdentifier("sidebar.keepAwake.timers")
            if state.clamshell.hasLid {
                // What closing the lid does now, and the Clamshell chip (SleepDisabled while on).
                HStack(spacing: 6) {
                    MaterialIcon("laptopcomputer", size: 13).foregroundStyle(theme[.onSurfaceVariant])
                    Text(Clamshell.summary(state.clamshell, lid: state.lidSleep)).font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant])
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    let on = state.lidSleep.clamshellOn
                    Button { model.onClamshell(!on) } label: {
                        Text("Clamshell").font(theme.sans(11, weight: .medium))
                            .foregroundStyle(on ? theme[.onPrimary] : theme[.onSurface])
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(on ? theme[.primary] : theme[.onSurface].opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar.clamshell.toggle")
                }
                .padding(.leading, 2)
                .help(state.lidSleep.helper == .missing
                      ? "Clamshell needs its helper: run `skyrose clamshell helper` and paste the command it prints into a terminal (once)."
                      : "Clamshell keeps the Mac running with the lid closed, on battery and with only the built-in display (pmset disablesleep). A closed lid runs warmer and drains the battery faster.")
                .accessibilityIdentifier("sidebar.clamshell")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).shellCard(radius: 20)
    }

    private var sliders: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HSlider(value: state.status.muted ? 0 : state.status.volume,
                        icon: state.status.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", onSet: model.onVolume)
                    .accessibilityIdentifier("sidebar.volume")
                Text("\(Int(((state.status.muted ? 0 : state.status.volume) * 100).rounded()))%")
                    .font(theme.sans(11, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant]).monospacedDigit().frame(width: 34, alignment: .trailing)
            }
            if model.brightnessAvailable {
                HStack(spacing: 8) {
                    HSlider(value: state.status.brightness, icon: "brightness_high", onSet: model.onBrightness).accessibilityIdentifier("sidebar.brightness")
                    Text("\(Int((state.status.brightness * 100).rounded()))%")
                        .font(theme.sans(11, weight: .medium)).foregroundStyle(theme[.onSurfaceVariant]).monospacedDigit().frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(12).shellCard(radius: 20)
    }

    private var toggles: some View {
        let items = QuickToggles.make(status: state.status, dnd: state.doNotDisturb, darkMode: state.systemDarkMode)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick toggles").font(theme.sans(13, weight: .medium)).foregroundStyle(theme[.onSurface])
                Spacer()
                Button(action: model.onWallpaper) {
                    MaterialIcon("photo.on.rectangle", size: 12).foregroundStyle(theme[.onSurfaceVariant])
                }.buttonStyle(.plain).help("Wallpaper picker").accessibilityIdentifier("sidebar.wallpaper")
            }
            HStack(spacing: 8) {
                ForEach(items) { t in
                    Button { model.onToggle(t.id) } label: {
                        MaterialIcon(t.icon, size: 15, weight: .medium)
                            .foregroundStyle(t.active ? theme[.onPrimary] : theme[.onSurface])
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: t.active ? 14 : 22, style: .continuous)
                                .fill(t.active ? theme[.primary] : theme[.onSurface].opacity(0.08)))
                    }
                    .buttonStyle(.plain).help(t.label).accessibilityIdentifier("sidebar.toggle.\(t.id)")
                    .animation(theme.small, value: t.active)
                }
            }
        }
        .padding(12).shellCard(radius: 20)
    }
}
