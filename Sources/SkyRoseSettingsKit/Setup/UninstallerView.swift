import AppKit
import CaelestiaCore
import CaelestiaShell
import SwiftUI

/// Where the uninstaller engine and the CLI are, seen from SkyRose Settings.
public enum SetupLocator {
    /// `uninstall.sh` inside SkyRose.app (next to this Settings app, then ~/Applications,
    /// /Applications), then a repository checkout above the executable (`swift run`, dist/).
    public static func uninstallScript(bundle: URL = Bundle.main.bundleURL, executable: URL? = Bundle.main.executableURL,
                                       dryRun: Bool = false, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        // Previews only: a stand-in engine (screenshots of the stages mid-run, tests).
        if dryRun, let demo = environment["SKYROSE_SETUP_DEMO_ENGINE"], FileManager.default.isReadableFile(atPath: demo) {
            return URL(fileURLWithPath: demo)
        }
        return firstReadable(appCandidates(bundle: bundle).map { $0.appendingPathComponent("Contents/Resources/scripts/uninstall.sh") }
            + repoCandidates(executable).map { $0.appendingPathComponent("scripts/uninstall.sh") })
    }

    /// The `skyrose` CLI the engine should use (passed as SKYROSE_CLI).
    public static func cli(bundle: URL = Bundle.main.bundleURL) -> URL? {
        appCandidates(bundle: bundle).map { $0.appendingPathComponent("Contents/MacOS/skyrose") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func appCandidates(bundle: URL) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [bundle.deletingLastPathComponent().appendingPathComponent("SkyRose.app"),
                home.appendingPathComponent("Applications/SkyRose.app"),
                URL(fileURLWithPath: "/Applications/SkyRose.app")]
    }

    static func repoCandidates(_ executable: URL?) -> [URL] {
        var out: [URL] = []
        var dir = executable?.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<7 {
            guard let d = dir else { break }
            if FileManager.default.fileExists(atPath: d.appendingPathComponent("Package.swift").path) { out.append(d) }
            dir = d.deletingLastPathComponent()
        }
        return out
    }

    static func firstReadable(_ urls: [URL]) -> URL? {
        urls.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }
}

/// The SkyRose-styled uninstaller: confirm → restore settings → remove profile bits → trash
/// apps → report. It runs `uninstall.sh --progress` (the same engine as `skyrose uninstall`)
/// and draws only what the script reports.
public struct UninstallerView: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var runner = ScriptRunner()
    let dryRun: Bool
    let script: URL?
    var onClose: () -> Void
    @State private var removeConfig = false
    @State private var removeFonts = false
    @State private var removeCert = false
    @State private var restores: [RestoreManifest.Item] = []
    @State private var hasFonts = false
    @State private var hasConfig = false
    @State private var sipShown = false

    static let steps = SetupFlow.uninstall

    public init(store: SettingsStore, dryRun: Bool, script: URL?? = nil, onClose: @escaping () -> Void) {
        self.store = store
        self.dryRun = dryRun
        self.script = script ?? SetupLocator.uninstallScript(dryRun: dryRun)
        self.onClose = onClose
    }

    var active: Int { SetupFlow.activeIndex(Self.steps, progress: runner.progress, started: runner.started) }
    var failed: Bool { runner.stoppedEarly }
    var finished: Bool { runner.progress.finished || runner.stoppedEarly }

    public var body: some View {
        let look = store.look
        SetupChrome(title: "Uninstall", steps: Self.steps, active: active,
                    stateOf: { SetupFlow.state(of: $0, active: active, failed: failed, finished: finished) },
                    fraction: runner.progress.fraction, status: status,
                    badge: dryRun ? "Preview: nothing is changed" : nil,
                    onClose: runner.isRunning ? nil : onClose) {
            stage
        } footer: {
            footer(look)
        }
        .environment(\.look, look)
        .onAppear(perform: load)
        .onChange(of: runner.progress.sipReminder) { _, need in
            // A preview only shows the card in the report. A real run puts the guarded reminder up
            // and does not let the engine trash anything until it is dismissed.
            guard need, !sipShown else { return }
            sipShown = true
            guard !dryRun else { return }
            SIPReminderPresenter.show(look: look) { runner.acknowledgeSIP() }
        }
    }

    var status: String {
        if !runner.started { return script == nil ? "The uninstaller script is missing" : "Ready when you are" }
        if runner.stoppedEarly { return "Stopped" }
        if runner.progress.finished { return dryRun ? "Preview finished" : "SkyRose is uninstalled" }
        return runner.progress.current?.label ?? "Starting"
    }

    @ViewBuilder var stage: some View {
        switch Self.steps[active].id {
        case "confirm": confirm
        case "report": report
        default: running
        }
    }

    // MARK: Confirm

    var confirm: some View {
        let look = store.look
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: dryRun ? "Preview the uninstall" : "Uninstall SkyRose",
                           subtitle: "Your windows come back, every macOS setting SkyRose changed goes back to what you had, and the apps go to the Trash. Nothing needs your password.")
                if let error = scriptError {
                    SetupErrorCard(title: "The uninstaller is missing", message: error, detail: "")
                }
                Card {
                    SectionLabel(text: "Settings put back")
                    if restores.isEmpty {
                        Text("None recorded: SkyRose did not change any macOS setting.").font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
                    } else {
                        ForEach(restores.prefix(8)) { r in
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(look[.primary])
                                Text(r.title).font(look.font(13)).foregroundStyle(look[.onSurface])
                            }
                        }
                        if restores.count > 8 {
                            Text("and \(restores.count - 8) more").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                        }
                    }
                }
                Card {
                    SectionLabel(text: "Also remove")
                    SettingRow(title: "My SkyRose config", detail: hasConfig ? "~/.config/skyrose goes to the Trash. Keep it to start again where you left off." : "There is no ~/.config/skyrose.", icon: "doc.text") {
                        PillToggle(isOn: $removeConfig, enabled: hasConfig, accessibilityLabel: "Remove config")
                    }
                    SettingRow(title: "Fonts SkyRose installed", detail: hasFonts ? "Only the files SkyRose copied into ~/Library/Fonts." : "SkyRose did not install any fonts.", icon: "textformat") {
                        PillToggle(isOn: $removeFonts, enabled: hasFonts, accessibilityLabel: "Remove fonts")
                    }
                    SettingRow(title: "The local signing certificate", detail: "Kept by default: the next build would need a new one, and macOS would ask for every permission again.", icon: "checkmark.seal") {
                        PillToggle(isOn: $removeCert, accessibilityLabel: "Remove certificate")
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    var scriptError: String? {
        script == nil ? "uninstall.sh was not found inside SkyRose.app. Rebuild SkyRose or run scripts/uninstall.sh from the repository." : nil
    }

    // MARK: Running

    var running: some View {
        let look = store.look
        let stages = runner.progress.stages.filter { s in Self.steps[active].engineStages.contains(s.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: Self.steps[active].title, subtitle: runner.progress.current?.label ?? "")
                ForEach(stages, id: \.index) { s in
                    Card(padding: 14) {
                        Text(s.label).font(look.font(13.5, .semibold)).foregroundStyle(look[.onSurface])
                        ForEach(Array(s.items.enumerated()), id: \.offset) { _, item in
                            SetupItemRow(item: item).transition(.opacity.combined(with: .offset(y: look.theme.slide(8))))
                        }
                    }
                }
            }
            .animation(look.theme.spatial, value: runner.progress.items.count)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    // MARK: Report

    var report: some View {
        let look = store.look
        let p = runner.progress
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: runner.stoppedEarly ? "The uninstall stopped" : dryRun ? "This is what would happen" : "SkyRose is gone",
                           subtitle: runner.stoppedEarly ? "Nothing after the last step ran. You can try again or run scripts/uninstall.sh in Terminal."
                               : dryRun ? "Nothing was changed. Run it for real from Settings › Backup & uninstall."
                               : "Everything below went to the Trash or back to how it was. Empty the Trash when you are sure.")
                if runner.stoppedEarly {
                    SetupErrorCard(title: "Uninstaller exited early", message: exitText,
                                   detail: (runner.errorOutput + p.output.suffix(6).joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if p.sipReminder {
                    Card(padding: 14) {
                        SettingRow(title: "Turn SIP back on", detail: "You used SIP-off mode. Only you can turn System Integrity Protection back on, from Recovery.", icon: "lock.shield") {
                            PillButton(title: "Show steps", kind: .tonal) { SIPReminderPresenter.show(look: look) }
                        }
                    }
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
        if case .ended(let code) = runner.phase { return "uninstall.sh ended with code \(code) before it finished." }
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

    // MARK: Footer

    func footer(_ look: SettingsLook) -> some View {
        HStack {
            if !runner.started {
                PillButton(title: "Cancel", kind: .outline, action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                PillButton(title: dryRun ? "Preview" : "Uninstall SkyRose", icon: dryRun ? "eye" : "trash", kind: dryRun ? .filled : .danger, action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(script == nil)
                    .opacity(script == nil ? 0.4 : 1)
                    .accessibilityIdentifier("uninstall.start")
            } else if runner.isRunning {
                Text("Please keep this window open.").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                Spacer()
            } else {
                if runner.stoppedEarly {
                    PillButton(title: "Try again", icon: "arrow.clockwise", kind: .outline, action: start)
                }
                Spacer()
                PillButton(title: "Close", icon: "checkmark", kind: .filled, action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("uninstall.close")
            }
        }
    }

    // MARK: Actions

    func load() {
        restores = (try? RestoreManifest().pendingRestores()) ?? []
        hasFonts = FileManager.default.fileExists(atPath: Paths.appSupport.appendingPathComponent("Fonts/installed.json").path)
        hasConfig = FileManager.default.fileExists(atPath: Paths.configDir.path)
    }

    func start() {
        guard let script else { return }
        store.flush()
        var args: [String] = []
        if dryRun { args.append("--dry-run") }
        if removeConfig { args.append("--remove-config") }
        if removeFonts { args.append("--remove-fonts") }
        if removeCert { args.append("--remove-cert") }
        var env = ProcessInfo.processInfo.environment
        if let cli = SetupLocator.cli() { env["SKYROSE_CLI"] = cli.path }
        runner.start(script: script, arguments: args, environment: env)
    }
}
