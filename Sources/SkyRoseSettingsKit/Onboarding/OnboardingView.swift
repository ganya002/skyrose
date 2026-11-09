import AppKit
import CaelestiaCore
import CaelestiaPlatform
import SwiftUI

/// The first-run tour (also re-runnable from Settings › General, and opened by the WM with just
/// the permission step when a grant goes away later).
public struct OnboardingView: View {
    @ObservedObject var store: SettingsStore
    let request: OnboardingRequest
    var onFinish: () -> Void
    @State private var index = 0
    @State private var forward = true

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
        .environment(\.look, look)
        .animation(look.motion.page, value: index)
        .frame(width: 780, height: 640)
        .onChange(of: permissionsReady) { _, ready in
            // A lost grant came back: nothing left to do here.
            guard isRepair, ready else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if permissionsReady { finish() } }
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
        case .tweaks: TweaksStep()
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
        if step == .tweaks { return "Continue" }
        if step == .kitty || step == .fonts || step == .corners { return "Skip" }
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

/// The recommended macOS tweaks: what changes is shown first, nothing is written before a click,
/// every change is recorded in the restore manifest and can be undone here.
@MainActor
final class TweaksModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        var tweak: SystemTweak
        var isOn: Bool
        var changedBySkyRose: Bool
        var id: SystemTweak.ID { tweak.id }
    }

    @Published var rows: [Row] = []
    @Published var error: String?
    let tweaks: SystemTweaks

    init(tweaks: SystemTweaks = SystemTweaks()) {
        self.tweaks = tweaks
        reload()
    }

    func reload() {
        rows = SystemTweak.all.map { Row(tweak: $0, isOn: tweaks.isOn($0), changedBySkyRose: tweaks.isChangedBySkyRose($0)) }
    }

    func apply(_ t: SystemTweak) {
        do { try tweaks.apply(t); error = nil } catch { self.error = "\(t.title): \(error)" }
        reload()
    }

    func undo(_ t: SystemTweak) {
        do { try tweaks.undo(t); error = nil } catch { self.error = "\(t.title): \(error)" }
        reload()
    }
}

/// Recommended on the onboarding step. Nothing is written until Apply.
struct DockRemovalCard: View {
    @Environment(\.look) var look
    @State private var hidden = false
    @State private var error: String?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "dock.rectangle").font(.system(size: 20)).foregroundStyle(look[.primary])
                    .frame(width: 44, height: 44).background(Circle().fill(look[.primaryContainer].opacity(0.6)))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Remove the Dock").font(look.font(15, .semibold)).foregroundStyle(look[.onSurface])
                    Text("Recommended. The Dock never slides out. It keeps running, so Mission Control and Spaces stay. Undo puts your old Dock back.")
                        .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if hidden {
                        PillButton(title: "Undo", icon: "arrow.uturn.backward", kind: .outline) { toggle(false) }
                    } else {
                        PillButton(title: "Apply", kind: .filled) { toggle(true) }
                            .accessibilityIdentifier("tweak.apply.dockRemoval")
                    }
                }
            }
            if let error { Text(error).font(look.font(12)).foregroundStyle(look[.error]) }
        }
        .onAppear { hidden = DockRemoval().isHidden() }
    }

    func toggle(_ on: Bool) {
        let removal = DockRemoval()
        do {
            if on { try removal.hide() } else { try removal.show() }
            hidden = removal.isHidden()
            error = nil
        } catch { self.error = "\(error)" }
    }
}

struct TweaksStep: View {
    @StateObject private var model = TweaksModel()
    @Environment(\.look) var look

    var body: some View {
        VStack(spacing: 16) {
            StepHeader(title: "Recommended macOS tweaks",
                       subtitle: "So the SkyRose bar and frame have the screen edges to themselves. Nothing changes until you click Apply, and Undo puts back what you had.")
            ForEach(model.rows) { row in
                Card {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: row.id == .dockAutoHide ? "dock.rectangle" : "menubar.rectangle")
                            .font(.system(size: 20)).foregroundStyle(look[.primary])
                            .frame(width: 44, height: 44).background(Circle().fill(look[.primaryContainer].opacity(0.6)))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.tweak.title).font(look.font(15, .semibold)).foregroundStyle(look[.onSurface])
                            Text(row.tweak.change).font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                valuePill(row.isOn ? "Hides automatically" : "Always shown", active: false)
                                if !row.isOn {
                                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(look[.onSurfaceVariant])
                                    valuePill("Hides automatically", active: true)
                                }
                            }
                            Text("\(row.tweak.domain) \(row.tweak.key)").font(look.mono(10.5)).foregroundStyle(look[.onSurfaceVariant].opacity(0.8))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            if row.isOn {
                                Label(row.changedBySkyRose ? "Applied" : "Already on", systemImage: "checkmark.circle.fill")
                                    .font(look.font(12.5, .semibold)).foregroundStyle(look[.success])
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                PillButton(title: "Apply", kind: .filled) { withAnimation(look.motion.pop) { model.apply(row.tweak) } }
                                    .accessibilityIdentifier("tweak.apply.\(row.id.rawValue)")
                            }
                            if row.changedBySkyRose {
                                PillButton(title: "Undo", icon: "arrow.uturn.backward", kind: .outline) { withAnimation(look.motion.pop) { model.undo(row.tweak) } }
                                    .accessibilityIdentifier("tweak.undo.\(row.id.rawValue)")
                            }
                        }
                    }
                }
            }
            DockRemovalCard()
            if let e = model.error {
                Text(e).font(look.font(12)).foregroundStyle(look[.error])
            }
            Text("Changes are recorded so the uninstaller can put them back.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
        }
        .animation(look.motion.pop, value: model.rows)
        .onAppear { model.reload() }
    }

    func valuePill(_ text: String, active: Bool) -> some View {
        Text(text).font(look.font(11.5, .medium))
            .foregroundStyle(active ? look[.onPrimaryContainer] : look[.onSurfaceVariant])
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(active ? look[.primaryContainer] : look[.surfaceContainerHighest]))
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
