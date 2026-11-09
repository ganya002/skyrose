import AppKit
import CaelestiaCore
import SwiftUI

// MARK: - Permissions

struct PermissionsPage: View {
    @ObservedObject var store: SettingsStore
    var only: [SkyRosePermission]
    @Environment(\.look) var look

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Permissions", subtitle: "SkyRose asks only for what it uses. Each one turns green here as soon as you allow it.")
            if !store.wmRunning {
                Card {
                    SettingRow(title: "SkyRose is not running", detail: "The status below is still live. Start SkyRose to use tiling and shortcuts.", icon: "info.circle") {
                        PillButton(title: "Start SkyRose", icon: "play.fill", kind: .filled) { store.launchSkyRose() }
                    }
                }
            }
            PermissionList(store: store, only: only)
            Card {
                SectionLabel(text: "Never asked for")
                Text("Contacts, Calendars, Photos, Files and Folders, Full Disk Access, Camera, Microphone, Location, Bluetooth, Automation of other apps. SkyRose does not use them, so it never asks.")
                    .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The permission cards (Settings page and onboarding step).
struct PermissionList: View {
    @ObservedObject var store: SettingsStore
    var only: [SkyRosePermission]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(only.isEmpty ? SkyRosePermission.allCases : only, id: \.self) { p in
                PermissionCard(store: store, permission: p)
            }
        }
    }
}

struct PermissionCard: View {
    @ObservedObject var store: SettingsStore
    var permission: SkyRosePermission
    @Environment(\.look) var look
    /// Missing when this card appeared (or later): a grant then may need a restart.
    @State private var wasMissing = false
    @State private var showSteps = false

    var granted: Bool? { store.permissions?.isGranted(permission) }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                StatusDot(state: granted)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(permission.title).font(look.font(15, .semibold)).foregroundStyle(look[.onSurface])
                        Text(permission.isRequired(in: store.config.general.mode) ? "Needed" : "Recommended")
                            .font(look.font(10.5, .semibold)).foregroundStyle(look[.onSecondaryContainer])
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(look[.secondaryContainer]))
                    }
                    Text(permission.why).font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                    if granted == false {
                        Text("Without it: \(permission.withoutIt)").font(look.font(12)).foregroundStyle(look[.error].opacity(0.9))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if granted == true {
                        Text("Allowed").font(look.font(13, .semibold)).foregroundStyle(look[.success])
                            .transition(.scale.combined(with: .opacity))
                        if wasMissing, permission.needsRestartAfterGrant {
                            PillButton(title: "Restart SkyRose", icon: "arrow.clockwise", kind: .tonal) { store.restartSkyRose() }
                                .help("macOS applies this permission when SkyRose starts again.")
                        }
                    } else {
                        PillButton(title: "Open System Settings", icon: "arrow.up.forward.app", kind: .filled) {
                            store.requestPermission(permission)
                            withAnimation(look.motion.page) { showSteps = true }
                        }
                        .accessibilityIdentifier("permission.open.\(permission.rawValue)")
                    }
                }
            }
            if granted != true, showSteps || granted == false {
                PermissionSteps(permission: permission)
                    .transition(.opacity.combined(with: .offset(y: look.motion.slide(-8))))
            }
        }
        .animation(look.motion.pop, value: granted)
        .onAppear { if granted == false { wasMissing = true } }
        .onChange(of: granted) { _, g in if g == false { wasMissing = true } }
        .accessibilityIdentifier("permission.\(permission.rawValue)")
    }
}

/// Three small pictures of what to do in System Settings.
struct PermissionSteps: View {
    var permission: SkyRosePermission
    @Environment(\.look) var look

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            step(1, "Privacy & Security", "System Settings opens on the right list.") {
                miniList(["Accessibility", "Input Monitoring", "Screen & System Audio Recording"], highlight: permission.paneName)
            }
            step(2, "Find SkyRose", "Not in the list? Click + and pick SkyRose in Applications.") {
                miniApps
            }
            step(3, "Turn it on", "This card turns green by itself. No need to come back and click.") {
                HStack(spacing: 8) {
                    BrandIcon(which: .main, size: 22)
                    Text("SkyRose").font(look.font(11.5, .medium)).foregroundStyle(look[.onSurface])
                    Spacer()
                    Capsule().fill(look[.primary]).frame(width: 30, height: 18)
                        .overlay(alignment: .trailing) { Circle().fill(look[.onPrimary]).frame(width: 14).padding(2) }
                }
                .padding(8)
            }
        }
    }

    func step<V: View>(_ n: Int, _ title: String, _ text: String, @ViewBuilder picture: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            picture()
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(look[.surfaceContainerHighest].opacity(0.8)))
            HStack(spacing: 6) {
                Text("\(n)").font(look.font(10.5, .bold)).foregroundStyle(look[.onPrimary])
                    .frame(width: 17, height: 17).background(Circle().fill(look[.primary]))
                Text(title).font(look.font(12, .semibold)).foregroundStyle(look[.onSurface])
            }
            Text(text).font(look.font(11)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func miniList(_ items: [String], highlight: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items, id: \.self) { i in
                Text(i).font(look.font(10.5, i == highlight ? .semibold : .regular)).lineLimit(1)
                    .foregroundStyle(i == highlight ? look[.onPrimary] : look[.onSurfaceVariant])
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(i == highlight ? look[.primary] : .clear))
            }
        }
        .padding(8)
    }

    var miniApps: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(look[.outlineVariant]).frame(width: 14, height: 14)
                Capsule().fill(look[.outlineVariant]).frame(width: 50, height: 6)
            }
            HStack(spacing: 6) {
                BrandIcon(which: .main, size: 14)
                Text("SkyRose").font(look.font(10.5, .semibold)).foregroundStyle(look[.onSurface])
            }
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Image(systemName: "minus").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(look[.onSurfaceVariant])
        }
        .padding(8)
    }
}

// MARK: - About

struct AboutPage: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look

    static let credits: [(String, String, String)] = [
        ("Caelestia", "The shell this is modelled on: bar, panels, colours and motion. GPL-3.0.", "https://github.com/caelestia-dots/shell"),
        ("Hyprland", "The tiling layout, the keybinds and the feel. BSD-3-Clause.", "https://hyprland.org"),
        ("Material Color Utilities", "Colours from the wallpaper. Apache-2.0.", "https://github.com/material-foundation/material-color-utilities"),
        ("AeroSpace and yabai", "Ideas for window management on macOS.", "https://github.com/nikitabobko/AeroSpace"),
        ("Rubik and Material Symbols", "Fonts and icons. OFL / Apache-2.0.", "https://fonts.google.com/specimen/Rubik"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                HStack(spacing: 18) {
                    BrandIcon(which: .main, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SkyRose").font(look.font(28, .semibold)).foregroundStyle(look[.onSurface])
                        Text("Version \(CaelestiaVersion.string)").font(look.mono(12.5)).foregroundStyle(look[.onSurfaceVariant])
                        Text("A tiling window manager and desktop shell for macOS, after Hyprland and Caelestia.")
                            .font(look.font(13)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    BrandIcon(which: .wm, size: 52).opacity(0.85).help("SkyRose WM")
                }
            }
            Card {
                SectionLabel(text: "Credits")
                ForEach(Self.credits, id: \.0) { c in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.0).font(look.font(13.5, .semibold)).foregroundStyle(look[.onSurface])
                            Text(c.1).font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                        }
                        Spacer()
                        Button { if let u = URL(string: c.2) { NSWorkspace.shared.open(u) } } label: {
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(look[.primary])
                        }.buttonStyle(.plain)
                    }
                }
            }
            Card {
                SettingRow(title: "Backup & uninstall", detail: "The settings SkyRose changed, a copy of your config, and the uninstaller are in Settings › Backup & uninstall.", icon: "arrow.uturn.backward.circle") { EmptyView() }
            }
        }
    }
}
