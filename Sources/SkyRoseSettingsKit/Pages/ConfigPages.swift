import AppKit
import CaelestiaCore
import CaelestiaShell
import SwiftUI
import CaelestiaPlatform

// MARK: - General

struct GeneralPage: View {
    @ObservedObject var store: SettingsStore
    var onRunOnboarding: () -> Void
    @Environment(\.look) var look

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "General", subtitle: "Choose how much of SkyRose runs. Every change applies at once, no restart.")
            Card {
                SectionLabel(text: "Mode")
                ModePicker(mode: store.binding(\.general.mode, "general.mode") { .string($0.rawValue) })
            }
            Card {
                SettingRow(title: "Run the welcome tour again", detail: "Mode, permissions and the recommended macOS tweaks, step by step.", icon: "sparkles") {
                    PillButton(title: "Open", icon: "play.fill", kind: .tonal, action: onRunOnboarding)
                }
                SettingRow(title: "Config folder", detail: "~/.config/skyrose — the files these settings are saved in.", icon: "folder") {
                    PillButton(title: "Show", kind: .outline) { NSWorkspace.shared.open(Paths.configDir) }
                }
            }
        }
    }
}

/// Full SkyRose / SkyRose WM only, as two big cards (used by Settings and the onboarding).
struct ModePicker: View {
    @Binding var mode: GeneralConfig.Mode
    @Environment(\.look) var look

    var body: some View {
        HStack(spacing: 14) {
            card(.full, icon: .main, title: "SkyRose", subtitle: "Tiling, keyboard shortcuts and borders, plus the bar, launcher, dashboard, screen frame and on-screen displays.")
            card(.wm, icon: .wm, title: "SkyRose WM only", subtitle: "Just tiling, keyboard shortcuts and borders. No bar, no shell, no frame. Your Mac otherwise looks as it does now.")
        }
    }

    func card(_ m: GeneralConfig.Mode, icon: BrandIcon.Which, title: String, subtitle: String) -> some View {
        let selected = mode == m
        return Button {
            withAnimation(look.motion.pop) { mode = m }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    BrandIcon(which: icon, size: 54)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20)).foregroundStyle(selected ? look[.primary] : look[.outline])
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(title).font(look.font(16, .semibold)).foregroundStyle(look[.onSurface])
                Text(subtitle).font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: SettingsLook.cardRadius, style: .continuous)
                .fill(selected ? look[.primaryContainer].opacity(0.55) : look[.surfaceContainerHigh].opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: SettingsLook.cardRadius, style: .continuous)
                .strokeBorder(selected ? look[.primary] : look[.outlineVariant], lineWidth: selected ? 2 : 1))
            .scaleEffect(selected && !look.motion.reduceMotion ? 1.0 : 0.985)
            .contentShape(RoundedRectangle(cornerRadius: SettingsLook.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mode.\(m.rawValue)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Appearance

struct AppearancePage: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look
    @State private var wallpapers: [URL] = []
    @State private var calibrationDisplays: [DisplayInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Appearance", subtitle: "Colours, wallpaper and the frame around your screen.")
            Card {
                SectionLabel(text: "Colours")
                SettingRow(title: "Colour source", detail: store.config.appearance.schemeMode == "dynamic"
                    ? "Taken from your wallpaper, and updated when it changes." : "A fixed palette you pick below.", icon: "circle.lefthalf.filled") {
                    PillSegmented(options: [("static", "Static", nil), ("dynamic", "From wallpaper", "photo")],
                                  selection: store.binding(\.appearance.schemeMode, "appearance.schemeMode") { .string($0) })
                }
                if store.config.appearance.schemeMode != "dynamic" {
                    HStack(spacing: 10) {
                        ForEach(SchemeLoader.builtInNames, id: \.self) { name in
                            SchemeSwatch(name: name, selected: SchemeLoader.canonicalName(store.config.appearance.theme) == name) {
                                store.set("appearance.theme", .string(name), update: { $0.appearance.theme = name })
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: look.motion.slide(-6))))
                }
            }
            .animation(look.motion.page, value: store.config.appearance.schemeMode)
            Card {
                SectionLabel(text: "Wallpaper")
                Text(store.config.appearance.wallpaperFolder).font(look.mono(11.5)).foregroundStyle(look[.onSurfaceVariant])
                if wallpapers.isEmpty {
                    Text("No pictures in this folder yet.").font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(wallpapers.prefix(16), id: \.self) { url in
                            WallpaperThumb(url: url) { store.setWallpaper(url) }
                        }
                    }
                }
                HStack {
                    PillButton(title: "Choose a picture…", icon: "photo.on.rectangle", kind: .tonal) { pickWallpaper() }
                    if !store.wmRunning {
                        Text("Start SkyRose to change the wallpaper.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                    }
                }
            }
            Card {
                SectionLabel(text: "Screen frame")
                SettingRow(title: "Frame band", detail: "A thin rounded frame around the screen, like Caelestia's border.", icon: "rectangle.dashed") {
                    PillToggle(isOn: store.bool(\.wm.screenFrame, "wm.screenFrame"), enabled: store.config.general.mode == .full, accessibilityLabel: "Frame band")
                }
                if store.config.wm.screenFrame {
                    SettingRow(title: "Band thickness") {
                        PillSlider(value: store.number(\.wm.screenFrameInset, "wm.screenFrameInset"), range: 2...30, step: 1,
                                   format: { "\(Int($0)) pt" }, onCommit: store.flush)
                    }
                }
                if store.config.general.mode == .wm {
                    Text("The frame is part of the shell, so it is off in WM-only mode.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                }
            }
            .animation(look.motion.page, value: store.config.wm.screenFrame)
            CursorCard(store: store)
            FontsCard(store: store)
            Card {
                SectionLabel(text: "Corner calibration")
                Text("Match the frame to the rounded corners of each display. Auto uses a good guess for MacBook screens.")
                    .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
                ForEach(calibrationDisplays) { d in
                    CornerRow(store: store, display: d)
                }
                HStack {
                    PillButton(title: "Calibrate on screen…", icon: "viewfinder", kind: .tonal) { store.calibrateFrame() }
                    Text("Shows a live preview on the display under the pointer.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                }
            }
        }
        .onAppear {
            wallpapers = WallpaperLibrary.scan(folder: WallpaperLibrary.folderURL(store.config.appearance.wallpaperFolder)).urls
            calibrationDisplays = DisplayInfo.all()
        }
    }

    private func pickWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.directoryURL = WallpaperLibrary.folderURL(store.config.appearance.wallpaperFolder)
        if panel.runModal() == .OK, let url = panel.url { store.setWallpaper(url) }
    }
}

struct SchemeSwatch: View {
    var name: String
    var selected: Bool
    var action: () -> Void
    @Environment(\.look) var look
    var body: some View {
        let s = SchemeLoader.builtIn(named: name)
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach([ColorRole.primary, .secondary, .tertiary, .surfaceContainer], id: \.self) { r in
                        Rectangle().fill(s.map { Color(rgba: $0[r]) } ?? .gray)
                    }
                }
                .frame(height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(SchemeLoader.builtInTitles[name] ?? name).font(look.font(11.5, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? look[.onSurface] : look[.onSurfaceVariant]).lineLimit(1)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? look[.primary] : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .animation(look.motion.quick, value: selected)
    }
}

struct WallpaperThumb: View {
    var url: URL
    var action: () -> Void
    @State private var image: NSImage?
    @State private var hover = false
    @Environment(\.look) var look
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(look[.surfaceContainerHighest])
                if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            }
            .frame(height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(hover ? look[.primary] : .clear, lineWidth: 2))
            .scaleEffect(hover && !look.motion.reduceMotion ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(look.motion.quick) { hover = h } }
        .task(id: url) { image = await Thumbnailer.thumbnail(url, maxPixel: 280) }
    }
}

enum Thumbnailer {
    static func thumbnail(_ url: URL, maxPixel: Int) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}

/// A display for corner calibration.
struct DisplayInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var builtIn: Bool

    static func all() -> [DisplayInfo] {
        NSScreen.screens.compactMap { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let did = CGDirectDisplayID(n.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(did)?.takeRetainedValue(),
                let text = CFUUIDCreateString(nil, uuid) as String?
            else { return nil }
            return DisplayInfo(id: text, name: s.localizedName, builtIn: CGDisplayIsBuiltin(did) != 0)
        }
    }
}

struct CornerRow: View {
    @ObservedObject var store: SettingsStore
    var display: DisplayInfo
    @Environment(\.look) var look

    var body: some View {
        let o = store.config.displays[display.id]
        let top = o?.displayCornerRadius ?? store.config.frame.displayCornerRadius
        let bottom = o?.displayBottomCornerRadius ?? store.config.frame.displayBottomCornerRadius
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: display.builtIn ? "laptopcomputer" : "display").foregroundStyle(look[.primary])
                Text(display.name).font(look.font(13.5, .medium)).foregroundStyle(look[.onSurface])
            }
            radius("Top corners", top, key: "displayCornerRadius") { $0.displayCornerRadius = $1 }
            radius("Bottom corners", bottom, key: "displayBottomCornerRadius") { $0.displayBottomCornerRadius = $1 }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SettingsLook.rowRadius, style: .continuous).fill(look[.surfaceContainerHigh].opacity(0.6)))
    }

    private func radius(_ title: String, _ value: Double, key: String, _ apply: @escaping (inout DisplayOverride, Double?) -> Void) -> some View {
        let path = "displays.\(display.id).\(key)"
        let auto = value < 0
        return SettingRow(title: title) {
            HStack(spacing: 10) {
                PillSegmented(options: [(true, "Auto", nil), (false, "Manual", nil)], selection: Binding(
                    get: { auto },
                    set: { isAuto in
                        if isAuto {
                            store.set(path, .number(-1), update: { c in var o = c.displays[display.id] ?? DisplayOverride(); apply(&o, -1); c.displays[display.id] = o })
                        } else {
                            let start = display.builtIn ? FrameConfig.autoBuiltInRadius : 0
                            store.set(path, .number(start), update: { c in var o = c.displays[display.id] ?? DisplayOverride(); apply(&o, start); c.displays[display.id] = o })
                        }
                    }))
                    .fixedSize()  // the slider beside it must not squeeze the labels into a column
                if !auto {
                    PillSlider(value: Binding(get: { value }, set: { v in
                        store.set(path, .number(v), update: { c in var o = c.displays[display.id] ?? DisplayOverride(); apply(&o, v); c.displays[display.id] = o }, coalesce: true)
                    }), range: 0...FrameConfig.maxRadius, step: 0.5, format: { String(format: "%.1f pt", $0) }, onCommit: store.flush)
                }
            }
        }
    }
}

// MARK: - Windows

struct WindowsPage: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Windows", subtitle: "Spacing, borders and how windows move.")
            Card {
                SectionLabel(text: "Gaps")
                SettingRow(title: "Between windows", detail: "Space on each side of a tiled window.", icon: "square.split.2x1") {
                    PillSlider(value: store.number(\.wm.gapsIn, "wm.gapsIn"), range: 0...30, format: { "\(Int($0)) pt" }, onCommit: store.flush)
                }
                SettingRow(title: "Around the edges", detail: "Space between the windows and the screen edge.", icon: "square.dashed") {
                    PillSlider(value: store.number(\.wm.gapsOut, "wm.gapsOut"), range: 0...60, format: { "\(Int($0)) pt" }, onCommit: store.flush)
                }
                SettingRow(title: "Single window", detail: "Edge space when only one window is open.", icon: "square") {
                    PillSlider(value: store.number(\.wm.gapsOutSingle, "wm.gapsOutSingle"), range: 0...80, format: { "\(Int($0)) pt" }, onCommit: store.flush)
                }
            }
            Card {
                SectionLabel(text: "Borders")
                SettingRow(title: "Window borders", detail: "A thin coloured outline around every window; the focused one is brighter.", icon: "square.on.square") {
                    PillToggle(isOn: store.bool(\.wm.bordersEnabled, "wm.bordersEnabled"), accessibilityLabel: "Window borders")
                }
                if store.config.wm.bordersEnabled {
                    SettingRow(title: "Width") {
                        PillSlider(value: store.number(\.wm.borderSize, "wm.borderSize"), range: 1...6, step: 0.5, format: { String(format: "%.1f pt", $0) }, onCommit: store.flush)
                    }
                    SettingRow(title: "Corner radius") {
                        PillSlider(value: store.number(\.wm.windowRounding, "wm.windowRounding"), range: 0...24, format: { "\(Int($0)) pt" }, onCommit: store.flush)
                    }
                }
            }
            .animation(look.motion.page, value: store.config.wm.bordersEnabled)
            CloseQuitsCard(store: store)
            Card {
                SectionLabel(text: "Motion")
                SettingRow(title: "Window animations", detail: "Windows glide into place (needs Screen Recording). Off: they move at once.", icon: "wand.and.rays") {
                    PillSegmented(options: [(AnimationsConfig.WindowMode.snapshot, "Glide", nil), (.off, "Off", nil)],
                                  selection: store.binding(\.animations.windows, "animations.windows") { .string($0.rawValue) })
                }
                SettingRow(title: "Animation speed", detail: "2× is twice as fast.", icon: "speedometer") {
                    PillSlider(value: store.number(\.animations.speed, "animations.speed"), range: 0.5...3, step: 0.1,
                               format: { String(format: "%.1f×", $0) }, onCommit: store.flush)
                }
                SettingRow(title: "Reduce Motion", detail: "Every SkyRose animation becomes a short fade, whatever macOS is set to.", icon: "figure.walk.motion") {
                    PillToggle(isOn: store.bool(\.animations.reduceMotion, "animations.reduceMotion"), accessibilityLabel: "Reduce Motion")
                }
                SettingRow(title: "Follow macOS Reduce Motion", detail: store.systemReduceMotion ? "macOS Reduce Motion is on." : "macOS Reduce Motion is off.", icon: "accessibility") {
                    PillToggle(isOn: store.bool(\.animations.respectReduceMotion, "animations.respectReduceMotion"), accessibilityLabel: "Follow macOS Reduce Motion")
                }
            }
        }
    }
}

/// Windows › Closing: the red button quits an app on its last window (opt-in) + exceptions.
struct CloseQuitsCard: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look

    var body: some View {
        let exceptions = store.config.wm.closeQuitsAppExceptions
        Card {
            SectionLabel(text: "Closing")
            SettingRow(title: "Red button quits the app",
                       detail: "Closing an app's last window with the red button quits it. A normal quit: apps still ask to save. With other windows open only that window closes; ⌘W, yellow and green work as usual.",
                       icon: "xmark.circle") {
                PillToggle(isOn: store.bool(\.wm.closeQuitsApp, "wm.closeQuitsApp"), accessibilityLabel: "Red button quits the app")
            }
            if store.config.wm.closeQuitsApp {
                SettingRow(title: "Never quit these", detail: "They keep running when their last window closes. Menu-bar apps are never quit.", icon: "hand.raised") {
                    if let app = store.lastOtherApp, !exceptions.contains(where: { $0.caseInsensitiveCompare(app.bundleID) == .orderedSame }) {
                        PillButton(title: "Add \(app.name)", icon: "plus", kind: .tonal) {
                            withAnimation(look.motion.page) { store.setCloseQuitExceptions(exceptions + [app.bundleID]) }
                        }
                        .accessibilityIdentifier("windows.closeQuits.addFocused")
                        .help("The app you used last before Settings: \(app.bundleID)")
                    }
                }
                if exceptions.isEmpty {
                    Text("No exceptions: every Dock app quits with its last window.").font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
                }
                ForEach(exceptions, id: \.self) { id in
                    HStack(spacing: 10) {
                        Image(nsImage: Self.icon(for: id)).resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.name(for: id)).font(look.font(13.5, .medium)).foregroundStyle(look[.onSurface])
                            Text(id).font(look.font(11)).foregroundStyle(look[.onSurfaceVariant])
                        }
                        Spacer()
                        Button {
                            withAnimation(look.motion.page) { store.setCloseQuitExceptions(exceptions.filter { $0 != id }) }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(look[.onSurfaceVariant])
                                .frame(width: 26, height: 26).background(Circle().fill(look[.onSurface].opacity(0.08)))
                        }
                        .buttonStyle(.plain).help("Remove \(Self.name(for: id))").accessibilityIdentifier("windows.closeQuits.remove.\(id)")
                    }
                    .padding(.leading, 34)
                }
            }
        }
        .animation(look.motion.page, value: store.config.wm.closeQuitsApp)
    }

    static func appURL(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func name(for id: String) -> String {
        guard let url = appURL(id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for id: String) -> NSImage {
        guard let url = appURL(id) else { return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Appearance › Cursor: a Mousecape cape (Bibata Modern Classic, from Gabby's Arch setup) for
/// this login session, applied by the WM. The wait cursor is never replaced.
struct CursorCard: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look
    @State private var capes: [(identifier: String, name: String, url: URL)] = []
    @State private var previews: [String: [NSImage]] = [:]
    @State private var resetNote: String?

    var body: some View {
        let current = store.config.appearance.cursor
        Card {
            SectionLabel(text: "Cursor")
            SettingRow(title: "Pointer theme",
                       detail: "For this login session only: nothing on disk changes, and quitting SkyRose or logging out brings the macOS cursors back. Same size and hotspots as on Arch (24 pt). The pointer switches the next time it changes shape.",
                       icon: "cursorarrow") {
                PillSegmented(options: [("", "macOS", nil)] + capes.map { ($0.identifier, $0.name, nil) },
                              selection: Binding(get: { current }, set: { choose($0) }))
            }
            if capes.isEmpty {
                Text("No cursor themes found. Put a Mousecape .cape file (e.g. Bibata Modern Classic) in ~/Library/Application Support/SkyRose/cursors.")
                    .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
            }
            if let images = previews[current], !images.isEmpty {
                HStack(spacing: 14) {
                    ForEach(images.indices, id: \.self) { i in
                        Image(nsImage: images[i]).frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look[.onSurface].opacity(0.06)))
                    }
                }
                .padding(.leading, 34)
            }
            HStack(spacing: 10) {
                PillButton(title: "Reset to macOS default", icon: "arrow.uturn.backward", kind: .tonal) { reset() }
                    .accessibilityIdentifier("appearance.cursor.reset")
                if let resetNote {
                    Text(resetNote).font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                } else if !current.isEmpty, !store.wmRunning {
                    Text("Applies when SkyRose is running.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                }
            }
            Label("The spinning wait cursor always stays macOS's: once it is changed macOS cannot put it back until you log out, so SkyRose never touches it.",
                  systemImage: "info.circle")
                .font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
        }
        .onAppear(perform: load)
    }

    private func choose(_ identifier: String) {
        resetNote = nil
        store.set("appearance.cursor", .string(identifier), update: { $0.appearance.cursor = identifier })
        if identifier.isEmpty, !store.wmRunning { reset() }
    }

    /// Clears the option (the WM restores) and, when the WM is not running, restores right here.
    private func reset() {
        store.set("appearance.cursor", .string(""), update: { $0.appearance.cursor = "" })
        guard !store.wmRunning else { resetNote = "macOS cursors restored."; return }
        let report = CursorThemeManager().reset()
        resetNote = report.ok ? "macOS cursors restored." : "Some cursors could not be restored; logging out restores them."
    }

    private func load() {
        let library = CursorCapeLibrary()
        capes = library.available()
        for cape in capes where previews[cape.identifier] == nil {
            guard let loaded = try? CursorCape.load(cape.url) else { continue }
            previews[cape.identifier] = Self.previewNames.compactMap { loaded.cursors[$0] }.compactMap { c in
                c.images.last.map { image in
                    // Animated cursors stack their frames vertically: show the first one.
                    let frameHeight = image.height / max(1, c.frameCount)
                    let first = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: frameHeight)) ?? image
                    return NSImage(cgImage: first, size: c.size)
                }
            }
        }
    }

    /// Arrow, I-beam, pointing hand, resize, crosshair.
    static let previewNames = ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.IBeam", "com.apple.cursor.13",
                               "com.apple.cursor.19", "com.apple.cursor.7"]
}

// MARK: - Bar and Shell

struct ShellPage: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look

    static let modules: [(WritableKeyPath<Config, Bool>, String, String, String, String)] = [
        (\.shell.launcher, "shell.launcher", "Launcher", "Search apps, maths and more. Tap ⌥ on its own.", "magnifyingglass"),
        (\.shell.dashboard, "shell.dashboard", "Dashboard", "Clock, calendar, media and system stats.", "square.grid.2x2"),
        (\.shell.sidebar, "shell.sidebar", "Sidebar", "Notifications and quick toggles.", "sidebar.right"),
        (\.shell.session, "shell.session", "Session menu", "Lock, log out, restart, shut down.", "power"),
        (\.shell.osd, "shell.osd", "Volume and brightness display", "Off: the media keys go back to macOS.", "speaker.wave.2"),
        (\.shell.notifications, "shell.notifications", "Notifications", "Toasts and the history.", "bell"),
        (\.shell.wallpaperPicker, "shell.wallpaperPicker", "Wallpaper picker", "Pick a wallpaper from the shell.", "photo"),
    ]

    static let barModules: [(WritableKeyPath<Config, Bool>, String, String, String)] = [
        (\.bar.showLogo, "bar.showLogo", "Logo (opens the launcher)", "apple.logo"),
        (\.bar.showWorkspaces, "bar.showWorkspaces", "Workspaces", "circle.grid.3x3"),
        (\.bar.showActiveWindow, "bar.showActiveWindow", "Active window", "macwindow"),
        (\.bar.showTray, "bar.showTray", "Menu bar button", "menubar.rectangle"),
        (\.bar.showClock, "bar.showClock", "Clock", "clock"),
        (\.bar.showStatusIcons, "bar.showStatusIcons", "Status icons", "wifi"),
        (\.bar.showPower, "bar.showPower", "Power button", "power"),
    ]

    var body: some View {
        let wmOnly = store.config.general.mode == .wm
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Bar and Shell", subtitle: "Every part of the shell can be switched off on its own.")
            if wmOnly {
                Card {
                    SettingRow(title: "WM-only mode is on", detail: "The bar and the shell are off. Switch to full SkyRose in General to use them.", icon: "info.circle") {
                        PillButton(title: "Use full SkyRose", kind: .tonal) {
                            store.set("general.mode", .string("full"), update: { $0.general.mode = .full })
                        }
                    }
                }
            }
            Group {
                Card {
                    SettingRow(title: "Shell", detail: "Off: no bar, panels or displays (tiling keeps working).", icon: "sparkles") {
                        PillToggle(isOn: store.bool(\.shell.enabled, "shell.enabled"), accessibilityLabel: "Shell")
                    }
                }
                Card {
                    SectionLabel(text: "Bar")
                    SettingRow(title: "Bar", detail: "The bar on the left edge.", icon: "sidebar.left") {
                        PillToggle(isOn: store.bool(\.bar.enabled, "bar.enabled"), enabled: store.config.shell.enabled, accessibilityLabel: "Bar")
                    }
                    SettingRow(title: "Always visible", detail: "Off: it slides in when the pointer touches the left edge.", icon: "pin") {
                        PillToggle(isOn: store.bool(\.bar.persistent, "bar.persistent"), enabled: store.config.shell.enabled && store.config.bar.enabled, accessibilityLabel: "Bar always visible")
                    }
                    ForEach(Array(Self.barModules.enumerated()), id: \.offset) { _, m in
                        SettingRow(title: m.2, icon: m.3) {
                            PillToggle(isOn: store.bool(m.0, m.1), enabled: store.config.shell.enabled && store.config.bar.enabled, accessibilityLabel: m.2)
                        }
                    }
                }
                Card {
                    SectionLabel(text: "Panels")
                    ForEach(Array(Self.modules.enumerated()), id: \.offset) { _, m in
                        SettingRow(title: m.2, detail: m.3, icon: m.4) {
                            PillToggle(isOn: store.bool(m.0, m.1), enabled: store.config.shell.enabled, accessibilityLabel: m.2)
                        }
                    }
                }
                WeatherSettingsCard(store: store, enabled: store.config.shell.enabled)
            }
            .opacity(wmOnly ? 0.45 : 1)
            .allowsHitTesting(!wmOnly)
        }
        .animation(look.motion.page, value: wmOnly)
    }
}

// MARK: - Terminal

struct TerminalPage: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var keymap = KeymapModel()
    @Environment(\.look) var look
    @State private var custom = ""
    @State private var recording = false
    @State private var kitty = KittySetup().status()
    @State private var kittyNote: String?
    @State private var fontStatus: [FontStore.FamilyStatus] = []

    static let bindID = "app.terminal"
    var choice: TerminalChoice { TerminalChoice(config: store.config.apps.terminal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Terminal", subtitle: "What \(shortcutText) opens.")
            Card {
                ForEach(TerminalChoice.presets) { preset in option(preset) }
                otherOption
            }
            shortcutCard
            kittyCard
            Card {
                SettingRow(title: "Try it", detail: store.wmRunning ? "Opens the terminal the way \(shortcutText) does." : "Start SkyRose to try it.", icon: "play.circle") {
                    PillButton(title: "Open terminal", icon: "terminal", kind: .tonal) { store.runAction("app.terminal") }
                        .disabled(!store.wmRunning).opacity(store.wmRunning ? 1 : 0.5)
                }
            }
        }
        .onAppear {
            if case .command(let c) = choice { custom = c } else if case .app(let id) = choice, choice.preset == nil { custom = id }
            kitty = KittySetup().status()
            fontStatus = FontStore.shared.status()
        }
        .onChange(of: recording) { _, r in if !r { store.pauseHotkeys(0) } }
        .onDisappear { if recording { store.pauseHotkeys(0) } }
    }

    // MARK: Shortcut

    var terminalBind: Bind? { keymap.keymap?.binds.first { $0.id == Self.bindID } }

    var shortcutText: String {
        guard let b = terminalBind, let km = keymap.keymap, b.enabled, let first = b.chords.first else { return "⌥ + T" }
        return ChordParser.format(first, modifierMap: km.modifiers)
    }

    @ViewBuilder var shortcutCard: some View {
        if let b = terminalBind, let km = keymap.keymap {
            Card {
                SectionLabel(text: "Shortcut")
                BindRow(bind: b, modifiers: km.modifiers, conflicts: keymap.conflicts[b.id] ?? [], recording: recording,
                        onRecord: { store.pauseHotkeys(10); withAnimation(look.motion.quick) { recording = true } },
                        onRecorded: { keys in recording = false; keymap.edit(store) { try keymap.editor.setKeys([keys], forBind: b.id) } },
                        onCancel: { recording = false },
                        onToggle: { on in keymap.edit(store) { try keymap.editor.setEnabled(on, forBind: b.id) } },
                        onReset: { keymap.edit(store) { try keymap.editor.resetBind(b.id) } })
                Text("Also under Keybinds › Apps. Saved to keymap.toml and applied at once.")
                    .font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
            }
        }
    }

    // MARK: kitty

    var kittyInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalChoice.kittyBundleID) != nil }

    var kittyCard: some View {
        Card {
            SectionLabel(text: "kitty setup")
            if !kittyInstalled {
                SettingRow(title: "kitty is not installed",
                           detail: "SkyRose does not install it for you. Get it from sw.kovidgoyal.net/kitty (or `brew install --cask kitty`); until then \(shortcutText) opens macOS Terminal.",
                           icon: "exclamationmark.circle") { EmptyView() }
            }
            SettingRow(title: kitty.included ? "SkyRose profile in use" : "Use the SkyRose profile",
                       detail: kitty.included
                           ? "kitty.conf includes skyrose.conf: Gabby's Arch settings (JetBrainsMono Nerd Font 13, glass 0.62, beam cursor with trail, powerline tabs) and colours that follow the scheme live."
                           : "Adds one `include skyrose.conf` line to the end of ~/.config/kitty/kitty.conf (a copy of it is kept for the uninstaller). Your own settings stay; ours win where both set a value.",
                       icon: "terminal") {
                if kitty.included {
                    PillButton(title: "Remove", kind: .outline) { runKitty { try KittySetup().uninstall() } }
                } else {
                    PillButton(title: "Set up", icon: "wand.and.stars", kind: .filled) {
                        runKitty { try KittySetup().install(scheme: store.scheme, options: store.config.apps.kittyOptions, journal: BackupJournal()) }
                    }
                    .disabled(kitty.foreignFile != nil).opacity(kitty.foreignFile == nil ? 1 : 0.5)
                }
            }
            SettingRow(title: "Font", detail: kittyFontDetail, icon: "textformat") {
                PillSegmented(options: FontPack.terminalFamilies.map { ($0.name, $0.name.replacingOccurrences(of: " Nerd Font", with: ""), nil) },
                              selection: Binding(get: { store.config.apps.kittyFont }, set: { setKittyFont($0) }))
            }
            if let f = kitty.foreignFile {
                Text("\(f) was not written by SkyRose; move it away to use the profile.").font(look.font(12)).foregroundStyle(look[.error])
            }
            if let kittyNote {
                Text(kittyNote).font(look.mono(11.5)).foregroundStyle(look[.onSurfaceVariant]).textSelection(.enabled)
            }
        }
    }

    var kittyFontDetail: String {
        let f = store.config.apps.kittyFont
        let visible = fontStatus.first { $0.name == f }?.availableSystemWide ?? true
        return visible ? "\(f), \(Int(store.config.apps.kittyFontSize)) pt (apps.kittyFont / kittyFontSize)."
            : "\(f) is not installed for other apps yet: Appearance › Fonts › Install for kitty."
    }

    func setKittyFont(_ family: String) {
        store.set("apps.kittyFont", .string(family), update: { $0.apps.kittyFont = family })
        guard kitty.included else { return }
        var options = store.config.apps.kittyOptions
        options.fontFamily = family
        runKitty {
            let notes = try KittySetup().install(scheme: store.scheme, options: options)
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: TerminalChoice.kittyBundleID) where app.processIdentifier > 0 {
                kill(app.processIdentifier, SIGUSR1)
            }
            return notes
        }
    }

    func runKitty(_ body: () throws -> [String]) {
        do {
            let notes = try body()
            kittyNote = notes.isEmpty ? "Nothing to change." : notes.joined(separator: "\n") + "\nOpen kitty windows pick it up on their next reload (⌃⌘, in kitty) or new window."
        } catch {
            kittyNote = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        kitty = KittySetup().status()
    }

    // MARK: Choices

    func isSelected(_ p: TerminalChoice.Preset) -> Bool { choice.preset == p }
    var otherSelected: Bool { choice.preset == nil }

    func select(_ value: String) {
        store.set("apps.terminal", .string(value), update: { $0.apps.terminal = value })
    }

    func option(_ p: TerminalChoice.Preset) -> some View {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundleID)
        let selected = isSelected(p)
        return Button { withAnimation(look.motion.quick) { select(p.choice.configValue) } } label: {
            HStack(spacing: 12) {
                if let installed {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: installed.path)).resizable().frame(width: 36, height: 36)
                } else {
                    Image(systemName: "terminal").frame(width: 36, height: 36).foregroundStyle(look[.outline])
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(look.font(14, .medium)).foregroundStyle(look[.onSurface].opacity(installed == nil ? 0.6 : 1))
                    Text(installed == nil ? "Not installed\(selected ? ": \(shortcutText) opens macOS Terminal instead" : "")" : p.detail)
                        .font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18)).foregroundStyle(selected ? look[.primary] : look[.outline])
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: SettingsLook.rowRadius, style: .continuous)
                .fill(selected ? look[.primaryContainer].opacity(0.45) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("terminal.\(p.name.lowercased())")
    }

    var otherOption: some View {
        let selected = otherSelected
        return VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(look.motion.quick) { if !custom.isEmpty { select(custom) } else { select("open -a Terminal") } } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "ellipsis.rectangle").font(.system(size: 20)).foregroundStyle(look[.primary]).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Other").font(look.font(14, .medium)).foregroundStyle(look[.onSurface])
                        Text("A bundle id (dev.warp.Warp-Stable) or a command (wezterm start).").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                    }
                    Spacer()
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18)).foregroundStyle(selected ? look[.primary] : look[.outline])
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: SettingsLook.rowRadius, style: .continuous)
                    .fill(selected ? look[.primaryContainer].opacity(0.45) : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if selected {
                HStack {
                    TextField("open -a Terminal", text: $custom)
                        .textFieldStyle(.plain).font(look.mono(13)).foregroundStyle(look[.onSurface])
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(look[.surfaceContainerHighest]))
                        .onSubmit { if !custom.isEmpty { select(custom) } }
                    PillButton(title: "Save", kind: .filled) { if !custom.isEmpty { select(custom) } }
                }
                .padding(.leading, 58)
                .transition(.opacity)
            }
        }
        .animation(look.motion.page, value: selected)
    }
}
