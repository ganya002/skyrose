import AppKit
import CaelestiaCore
import CaelestiaPlatform
import CaelestiaShell
import SwiftUI

/// The first-run tour (also re-runnable from Settings › General, and opened by the WM with just
/// the permission step when a grant goes away later).
public struct OnboardingView: View {
    @ObservedObject var store: SettingsStore
    let request: OnboardingRequest
    var onFinish: () -> Void
    @State private var index = 0
    @State private var forward = true
    /// Screen Recording was missing when this tour opened, so a new grant needs a relaunch.
    @State private var wasMissingScreenRecording = false

    public init(store: SettingsStore, request: OnboardingRequest, startAt: OnboardingStep? = nil, onFinish: @escaping () -> Void) {
        self.store = store
        self.request = request
        self.onFinish = onFinish
        let steps = request.steps.isEmpty ? OnboardingStep.allCases : request.steps
        _index = State(initialValue: startAt.flatMap { steps.firstIndex(of: $0) } ?? 0)
    }

    var steps: [OnboardingStep] { request.steps.isEmpty ? OnboardingStep.allCases : request.steps }
    var step: OnboardingStep { steps[min(index, steps.count - 1)] }
    var isRepair: Bool { request.steps == [.permissions] }

    public var body: some View {
        let look = store.look
        VStack(spacing: 0) {
            HStack {
                WindowButtons(onClose: onFinish)
                Spacer()
                if steps.count > 1 { progress(look) }
                Spacer()
                Color.clear.frame(width: 34, height: 1)
            }
            .padding(.horizontal, 18).padding(.top, 16)
            ScrollView {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: look.motion.slide(forward ? 40 : -40))),
                        removal: .opacity.combined(with: .offset(x: look.motion.slide(forward ? -40 : 40)))))
                    .padding(.horizontal, 44).padding(.vertical, 26)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            footer(look)
        }
        .background(PanelBackground())
        .onAppear { wasMissingScreenRecording = store.permissions?.screenRecording == false }
        .environment(\.look, look)
        .animation(look.motion.page, value: index)
        .frame(width: 780, height: 640)
        .onChange(of: permissionsReady) { _, ready in
            // The cards turned green: move on. A repair has nowhere else to go, so it closes.
            guard ready, step == .permissions else { return }
            if store.permissions?.screenRecording == true, store.permissions?.isGranted(.screenRecording) == true,
               SkyRosePermission.screenRecording.needsRestartAfterGrant, wasMissingScreenRecording {
                store.restartSkyRose()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                guard permissionsReady, step == .permissions else { return }
                if isRepair { finish() } else { go(1) }
            }
        }
    }

    func progress(_ look: SettingsLook) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, _ in
                Capsule().fill(i <= index ? look[.primary] : look[.outlineVariant])
                    .frame(width: i == index ? 26 : 8, height: 8)
            }
        }
        .animation(look.motion.pop, value: index)
        .accessibilityLabel("Step \(index + 1) of \(steps.count)")
    }

    @ViewBuilder var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .mode: ModeStep(store: store)
        case .permissions: PermissionsStep(store: store, only: request.onlyPermissions, repair: isRepair)
        case .tweaks: RecommendedStep(store: store)
        case .extras: ExtrasStep()
        case .kitty: OptionalSetupStep(title: "kitty profile", subtitle: "Adds one include line to kitty.conf so colours follow SkyRose. Skip if you do not use kitty.", command: ["kitty", "install"])
        case .fonts: OptionalSetupStep(title: "Fonts for other apps", subtitle: "Copies the SkyRose fonts into ~/Library/Fonts. Skip to keep them inside SkyRose only.", command: ["fonts", "install"])
        case .corners: CornersStep(store: store)
        case .done: DoneStep(store: store)
        }
    }

    func footer(_ look: SettingsLook) -> some View {
        HStack {
            if index > 0 {
                PillButton(title: "Back", icon: "chevron.left", kind: .outline) { go(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            Spacer()
            if step == .permissions, !permissionsReady {
                Text("You can allow these later in Settings › Permissions.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
            }
            PillButton(title: nextTitle, icon: index == steps.count - 1 ? "checkmark" : "chevron.right", kind: .filled) {
                if index == steps.count - 1 { finish() } else { go(1) }
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboarding.next")
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
    }

    var nextTitle: String {
        if index == steps.count - 1 { return isRepair ? "Done" : "Start using SkyRose" }
        if step == .welcome { return "Get started" }
        if step == .permissions, !permissionsReady { return "Skip for now" }
        if step == .tweaks || step == .extras || step == .kitty || step == .fonts || step == .corners { return "Skip" }
        return "Next"
    }

    var permissionsReady: Bool {
        guard let p = store.permissions else { return false }
        let shown = request.onlyPermissions.isEmpty ? SkyRosePermission.allCases : request.onlyPermissions
        return shown.allSatisfy { p.isGranted($0) || !$0.isRequired(in: store.config.general.mode) }
    }

    func go(_ d: Int) {
        forward = d > 0
        withAnimation(store.look.motion.page) { index = max(0, min(steps.count - 1, index + d)) }
    }

    func finish() {
        if !isRepair {
            try? OnboardingState(completed: true, completedAt: Date()).save()
            // Opened by `skyrose onboarding` or from Finder without the WM: start it now.
            if !store.wmRunning { store.launchSkyRose() }
        }
        onFinish()
    }
}

// MARK: - Steps

struct StepHeader: View {
    var title: String
    var subtitle: String
    @Environment(\.look) var look
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(look.font(28, .semibold)).foregroundStyle(look[.onSurface]).multilineTextAlignment(.center)
            Text(subtitle).font(look.font(14)).foregroundStyle(look[.onSurfaceVariant]).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }
}

struct WelcomeStep: View {
    @Environment(\.look) var look
    @State private var appeared = false
    var body: some View {
        VStack(spacing: 22) {
            BrandIcon(which: .main, size: 150)
                .scaleEffect(appeared || look.motion.reduceMotion ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            StepHeader(title: "Welcome to SkyRose",
                       subtitle: "Windows that arrange themselves, shortcuts for everything, and a calm desktop around them. Setup takes about a minute.")
            HStack(spacing: 12) {
                feature("rectangle.split.3x1", "Tiling", "New windows find their place.")
                feature("keyboard", "Shortcuts", "⌥ + T, ⌥ + 1…9, and more.")
                feature("sparkles", "Shell", "Bar, launcher, dashboard. Optional.")
            }
        }
        .onAppear { withAnimation(look.motion.spring(0.3, bounce: 0.25)) { appeared = true } }
    }

    func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(look[.primary])
                .frame(width: 44, height: 44).background(Circle().fill(look[.primaryContainer].opacity(0.6)))
            Text(title).font(look.font(13.5, .semibold)).foregroundStyle(look[.onSurface])
            Text(text).font(look.font(12)).foregroundStyle(look[.onSurfaceVariant]).multilineTextAlignment(.center)
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: SettingsLook.cardRadius, style: .continuous).fill(look[.surfaceContainer].opacity(0.7)))
    }
}

struct ModeStep: View {
    @ObservedObject var store: SettingsStore
    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: "How much SkyRose?", subtitle: "You can switch any time in Settings › General, and turn single parts off there too.")
            ModePicker(mode: store.binding(\.general.mode, "general.mode") { .string($0.rawValue) })
        }
    }
}

struct PermissionsStep: View {
    @ObservedObject var store: SettingsStore
    var only: [SkyRosePermission]
    var repair: Bool
    @Environment(\.look) var look
    var body: some View {
        VStack(spacing: 16) {
            if repair {
                StepHeader(title: only.count == 1 ? "SkyRose lost a permission" : "SkyRose lost some permissions",
                           subtitle: "macOS took it back (an update or a reset can do that). Allow it again and this window closes by itself.")
            } else {
                StepHeader(title: "Three permissions",
                           subtitle: "macOS asks you to allow these yourself. Each card turns green the moment you do.")
            }
            if !store.wmRunning, !repair {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(look[.primary])
                    Text("SkyRose starts when you finish this tour.").font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
                }
            }
            PermissionList(store: store, only: only)
            HStack(spacing: 8) {
                Image(systemName: "hand.raised").foregroundStyle(look[.primary])
                Text("SkyRose never asks for anything it does not use: no contacts, files, camera, microphone or location.")
                    .font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
            }
        }
    }
}

/// One button for the Dock, the menu bar, Bibata, a starter wallpaper and automatic corners.
/// Nothing is written until that click. Each change is journaled, so Undo and the uninstaller can put it back.
struct RecommendedStep: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look
    @State private var lines: [String] = []
    @State private var failed = false

    var pieces: [(String, String)] {
        [
            (RecommendedSetup.dockTitle, "The Dock never slides out. Mission Control and Spaces stay."),
            (RecommendedSetup.menuBarTitle, "It slides away, and comes back when the pointer touches the top edge."),
            (RecommendedSetup.cursorTitle, "SkyRose's pointer. The spinning wait cursor stays macOS's."),
            (RecommendedSetup.wallpaperTitle, "A starter picture, only if SkyRose has not set one yet."),
            (RecommendedSetup.cornersTitle, "The built-in screen follows its notch. Other screens stay square."),
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(title: "Use the recommended setup",
                       subtitle: "One click. Skip leaves your Mac exactly as it is. You can run this tour again from Settings › General.")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pieces, id: \.0) { title, detail in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(look[.primary])
                                .frame(width: 22, height: 22).background(Circle().fill(look[.primaryContainer]))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(look.font(14, .semibold)).foregroundStyle(look[.onSurface])
                                Text(detail).font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            PillButton(title: "Use recommended", icon: "sparkles", kind: .filled, action: apply)
                .accessibilityIdentifier("tweak.useRecommended")
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.self) { Text($0).font(look.font(12.5)).foregroundStyle(failed ? look[.error] : look[.onSurfaceVariant]) }
                }
                if failed {
                    PillButton(title: "Fix it", icon: "arrow.clockwise", kind: .tonal, action: apply)
                }
            }
            Text("Changes are recorded, so the uninstaller can put them back.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
        }
    }

    func apply() {
        var notes: [String] = []
        var bad = false
        func note(_ decision: RecommendedDecision, _ name: String, write: () throws -> String) {
            switch decision {
            case .already: notes.append("\(name): already set.")
            case .skip(let why): notes.append("\(name): \(why)")
            case .apply:
                do { notes.append(try write()) } catch { bad = true; notes.append("\(name): \(error.localizedDescription)") }
            }
        }
        note(RecommendedSetup.dock(hidden: DockRemoval().isHidden()), RecommendedSetup.dockTitle) {
            try DockRemoval().hide()
            return "\(RecommendedSetup.dockTitle): hidden."
        }
        let tweaks = SystemTweaks()
        note(RecommendedSetup.menuBar(autoHides: tweaks.isOn(.menuBarAutoHide)), RecommendedSetup.menuBarTitle) {
            try tweaks.apply(.menuBarAutoHide)
            return "\(RecommendedSetup.menuBarTitle): hides automatically."
        }
        let cursor = store.config.appearance.cursor
        let cape = CursorCapeLibrary().url(for: RecommendedSetup.cursorName) != nil
        note(RecommendedSetup.cursor(configured: cursor, capeAvailable: cape), RecommendedSetup.cursorTitle) {
            store.set("appearance.cursor", .string(RecommendedSetup.cursorName)) { $0.appearance.cursor = RecommendedSetup.cursorName }
            return "\(RecommendedSetup.cursorTitle): SkyRose will use it."
        }
        let journal = BackupJournal(url: Paths.restoreManifest)
        let alreadyWallpaper = ((try? journal.entries()) ?? []).contains { $0.kind == .wallpaper }
        note(RecommendedSetup.wallpaper(alreadySet: alreadyWallpaper, bundled: StarterWallpapers.bundledFolder != nil), RecommendedSetup.wallpaperTitle) {
            guard let bundled = StarterWallpapers.bundledFolder else { return "\(RecommendedSetup.wallpaperTitle): nothing bundled." }
            let dest = Paths.home.appendingPathComponent("Pictures/Wallpapers/Static", isDirectory: true)
            let report = try StarterWallpapers.install(bundled: bundled, destination: dest, journal: journal, hasSkyRoseWallpaper: false)
            if let suggested = report.suggested {
                var service = WallpaperService()
                service.journal = journal
                if let failure = service.apply(suggested) { bad = true; return "\(RecommendedSetup.wallpaperTitle): \(failure)" }
                return "\(RecommendedSetup.wallpaperTitle): set."
            }
            return "\(RecommendedSetup.wallpaperTitle): pictures are in place."
        }
        note(RecommendedSetup.corners(displayCornerRadius: store.config.frame.displayCornerRadius), RecommendedSetup.cornersTitle) {
            store.set("frame.displayCornerRadius", .number(-1)) { $0.frame.displayCornerRadius = -1 }
            return "\(RecommendedSetup.cornersTitle): automatic."
        }
        lines = notes
        failed = bad
    }
}

/// kitty and fonts, both optional, on one step.
struct ExtrasStep: View {
    var body: some View {
        VStack(spacing: 22) {
            StepHeader(title: "kitty and fonts", subtitle: "Optional. Skip both if you do not want them. You can do either later from Settings › Terminal.")
            OptionalSetupStep(title: "kitty profile", subtitle: "Adds one include line to kitty.conf so colours follow SkyRose.", command: ["kitty", "install"])
            OptionalSetupStep(title: "Fonts for other apps", subtitle: "Copies the SkyRose fonts into ~/Library/Fonts.", command: ["fonts", "install"])
        }
    }
}

struct DoneStep: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look
    @State private var appeared = false

    /// The binds worth knowing on day one (shell ones only in full mode).
    static let cheatSheet: [(String, Bool)] = [
        ("app.terminal", false), ("ws.focus.1", false), ("ws.move.1", false), ("window.focus.left", false),
        ("window.toggleFloat", false), ("window.close", false), ("window.fullscreen", false),
        ("launcher.tap", true), ("sidebar.toggle", true), ("wm.panic", false),
    ]

    var rows: [(String, String)] {
        let km = (try? KeymapParser.parse(toml: KeymapFileEditor().currentText())) ?? KeymapLoader.loadDefault()
        return Self.cheatSheet.compactMap { id, shell in
            if shell, store.config.shellOff { return nil }
            guard let b = km.bind(id: id), b.enabled, let c = b.chords.first else { return nil }
            let what = id == KeymapParser.panicBindID ? "Panic: stop tiling and put every window back"
                : b.description.isEmpty ? id : b.description.prefix(1).uppercased() + b.description.dropFirst()
            return (ChordParser.format(c, modifierMap: km.modifiers), what)
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(look[.primaryContainer]).frame(width: 96, height: 96)
                Image(systemName: "checkmark").font(.system(size: 42, weight: .bold)).foregroundStyle(look[.onPrimaryContainer])
            }
            .scaleEffect(appeared || look.motion.reduceMotion ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            StepHeader(title: "You're all set", subtitle: "A few shortcuts to start with. All of them are in Settings › Keybinds.")
            Card {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ForEach(rows, id: \.0) { r in
                        HStack(spacing: 10) {
                            KeyCaps(text: r.0)
                            Text(r.1).font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .onAppear { withAnimation(look.motion.spring(0.3, bounce: 0.35)) { appeared = true } }
    }
}

/// Skippable. The built-in panel starts from the notched-Mac radius; external screens start square.
/// Calibrate opens the live overlay when SkyRose is already running. Skip leaves the defaults.
struct CornersStep: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look
    @State private var note = ""

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: "Screen corners",
                       subtitle: "A notched built-in screen starts at \(Int(FrameConfig.autoBuiltInRadius)) pt on the top corners, and square along the bottom. External screens start square. Match the real corner now, or skip and do it later in Settings › Appearance.")
            PillButton(title: "Calibrate on screen", icon: "viewfinder", kind: .tonal) {
                guard store.wmRunning else {
                    note = "SkyRose is not running yet. Skip this, then use Settings › Appearance › Corners, or skyrose corners calibrate."
                    return
                }
                store.calibrateFrame()
                note = "The overlay is on the display under the pointer. Drag the slider or use the arrow keys until the line hugs the corner. Return saves. Esc cancels."
            }
            if !note.isEmpty {
                Text(note).font(look.font(13)).foregroundStyle(look[.onSurfaceVariant]).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 520)
            }
        }
    }
}

/// An optional first-run step. Next says Skip. The button runs `skyrose` only when it is already installed.
struct OptionalSetupStep: View {
    var title: String
    var subtitle: String
    var command: [String]
    @Environment(\.look) var look
    @State private var note = ""

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: title, subtitle: subtitle)
            PillButton(title: "Set up", icon: "arrow.down.circle", kind: .tonal, action: run)
            if !note.isEmpty {
                Text(note).font(look.font(13)).foregroundStyle(look[.onSurfaceVariant]).multilineTextAlignment(.center)
            }
        }
    }

    func run() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Applications/SkyRose.app/Contents/MacOS/skyrose"),
            URL(fileURLWithPath: "/Applications/SkyRose.app/Contents/MacOS/skyrose"),
        ]
        guard let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            note = "SkyRose is not installed yet. You can run skyrose \(command.joined(separator: " ")) later."
            return
        }
        let p = Process()
        p.executableURL = cli
        p.arguments = command
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            note = p.terminationStatus == 0 ? "Done." : "That did not finish (status \(p.terminationStatus)). You can try again from Settings."
        } catch {
            note = error.localizedDescription
        }
    }
}
