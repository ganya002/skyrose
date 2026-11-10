import CaelestiaCore
import SwiftUI

/// The SkyRose-styled installer. It runs `install-release.sh --progress` and draws only what the
/// script reports: the bar moves when a stage actually finishes, not on a timer.
public struct InstallerView: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var runner = ScriptRunner()
    let dryRun: Bool
    let payload: String?
    let script: URL?
    var onClose: () -> Void
    @State private var commandLine = false
    @State private var openWhenDone = true
    @State private var showAdvanced = false

    static let steps = SetupFlow.install

    public init(store: SettingsStore, dryRun: Bool, payload: String? = nil, script: URL?? = nil, onClose: @escaping () -> Void) {
        self.store = store
        self.dryRun = dryRun
        self.payload = payload
        self.script = script ?? SetupLocator.installScript(payload: payload)
        self.onClose = onClose
    }

    var active: Int { SetupFlow.activeIndex(Self.steps, progress: runner.progress, started: runner.started) }
    var failed: Bool { runner.stoppedEarly }
    var finished: Bool { runner.progress.finished || runner.stoppedEarly }

    public var body: some View {
        let look = store.look
        SetupChrome(title: "Install", steps: Self.steps, active: active,
                    stateOf: { SetupFlow.state(of: $0, active: active, failed: failed, finished: finished) },
                    fraction: runner.progress.fraction, status: status,
                    badge: dryRun ? "Preview: nothing is changed" : nil,
                    onClose: runner.isRunning ? nil : onClose) {
            stage
        } footer: {
            footer(look)
        }
        .environment(\.look, look)
    }

    var status: String {
        if !runner.started { return script == nil ? "The installer script is missing" : "Ready when you are" }
        if runner.stoppedEarly { return "Stopped" }
        if runner.progress.finished { return dryRun ? "Preview finished" : "SkyRose is installed" }
        return runner.progress.current?.label ?? "Starting"
    }

    @ViewBuilder var stage: some View {
        if !runner.started { welcome }
        else if runner.progress.finished || runner.stoppedEarly { report }
        else { running }
    }

    var welcome: some View {
        let look = store.look
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: dryRun ? "Preview the install" : "Install SkyRose",
                           subtitle: "Copies SkyRose into your Applications folder. No password. This build is signed on the build machine, not with an Apple Developer ID, and it is not notarized.")
                if script == nil {
                    SetupErrorCard(title: "The installer is missing", message: "install-release.sh was not found next to SkyRose.", detail: "")
                }
                DisclosureGroup(isExpanded: $showAdvanced) {
                    Card {
                        SettingRow(title: "Command line", detail: "Optional symlink at ~/.local/bin/skyrose. Off unless you turn it on.", icon: "terminal") {
                            PillToggle(isOn: $commandLine, accessibilityLabel: "Install the command line")
                        }
                        SettingRow(title: "Open SkyRose when finished", detail: "On. First launch asks for the three permissions.", icon: "arrow.up.forward.app") {
                            PillToggle(isOn: $openWhenDone, accessibilityLabel: "Open SkyRose")
                        }
                    }
                } label: {
                    Text("Advanced").font(look.font(14, .semibold)).foregroundStyle(look[.onSurface])
                }
                .accessibilityIdentifier("install.advanced")
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    var running: some View {
        let look = store.look
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: Self.steps[active].title, subtitle: runner.progress.current?.label ?? "")
                ForEach(runner.progress.stages, id: \.index) { s in
                    Card(padding: 14) {
                        Text(s.label).font(look.font(13.5, .semibold)).foregroundStyle(look[.onSurface])
                        ForEach(Array(s.items.enumerated()), id: \.offset) { _, item in
                            SetupItemRow(item: item)
                        }
                    }
                }
            }
            .animation(look.theme.spatial, value: runner.progress.items.count)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    var report: some View {
        let look = store.look
        let p = runner.progress
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: runner.stoppedEarly ? "The install stopped" : dryRun ? "This is what would happen" : "SkyRose is installed",
                           subtitle: runner.stoppedEarly ? "Nothing after the last step ran."
                               : "Open SkyRose if it is not already open. Onboarding asks for the permissions it needs.")
                if runner.stoppedEarly {
                    SetupErrorCard(title: "The install stopped", message: "SkyRose did not finish installing. Nothing after the last successful step was changed.", detail: p.output.suffix(6).joined(separator: "\n"), fixTitle: "Fix it", fix: start)
                }
                group("Needs you", p.items(.left) + p.items(.fail))
                group(dryRun ? "Would do" : "Done", p.items(.done))
                group("Not needed", p.items(.skip))
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    var exitText: String {
        if case .ended(let code) = runner.phase { return "install-release.sh ended with code \(code) before it finished." }
        return ""
    }

    @ViewBuilder func group(_ title: String, _ items: [SetupItem]) -> some View {
        if !items.isEmpty {
            Card(padding: 14) {
                SectionLabel(text: title)
                ForEach(items) { SetupItemRow(item: $0) }
            }
        }
    }

    func footer(_ look: SettingsLook) -> some View {
        HStack {
            if !runner.started {
                PillButton(title: "Cancel", kind: .outline, action: onClose)
                Spacer()
                PillButton(title: dryRun ? "Preview" : "Install SkyRose", icon: dryRun ? "eye" : "arrow.down.circle", kind: .filled, action: start)
                    .disabled(script == nil)
                    .accessibilityIdentifier("install.start")
            } else if runner.isRunning {
                Text("Please keep this window open.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                Spacer()
            } else {
                Spacer()
                PillButton(title: "Close", icon: "checkmark", kind: .filled, action: onClose)
                    .accessibilityIdentifier("install.close")
            }
        }
    }

    func start() {
        guard let script else { return }
        var args = ["--yes"]
        if dryRun { args.append("--dry-run") }
        if commandLine { args.append("--cli") } else { args.append("--no-cli") }
        if !openWhenDone { args.append("--no-open") }
        if let payload, !payload.isEmpty { args += ["--payload", payload] }
        runner.start(script: script, arguments: args)
    }
}
