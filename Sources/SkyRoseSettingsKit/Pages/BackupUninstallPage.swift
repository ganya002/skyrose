import AppKit
import CaelestiaCore
import SwiftUI

/// Settings › Backup & uninstall: what SkyRose changed (the restore manifest), copies of it and
/// of the config, and the way into the uninstaller (after a confirm in the page itself).
struct BackupUninstallPage: View {
    @ObservedObject var store: SettingsStore
    var onUninstall: (_ dryRun: Bool) -> Void
    @Environment(\.look) var look
    @State private var restores: [RestoreManifest.Item] = []
    @State private var manifestError: String?
    @State private var confirming = false
    @State private var saved: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Backup & uninstall",
                       subtitle: "Every macOS setting SkyRose changes is written down first, so it can be put back exactly.")
            Card {
                SectionLabel(text: "Changes SkyRose made to macOS")
                if let manifestError {
                    Text("The restore list cannot be read: \(manifestError)").font(look.font(12.5)).foregroundStyle(look[.error])
                } else if restores.isEmpty {
                    Text("None. SkyRose has not changed any macOS setting.").font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
                } else {
                    Text("Each one is undone by the uninstaller, back to the value you had.").font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
                    ForEach(restores) { r in
                        HStack {
                            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(look[.primary])
                            Text(r.title).font(look.font(13)).foregroundStyle(look[.onSurface])
                            Spacer()
                            Text(r.changedAt.formatted(date: .abbreviated, time: .omitted)).font(look.font(11.5)).foregroundStyle(look[.onSurfaceVariant])
                        }
                    }
                }
                Text(Paths.restoreManifest.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(look.mono(10.5)).foregroundStyle(look[.onSurfaceVariant]).textSelection(.enabled)
            }
            Card {
                SectionLabel(text: "Backups")
                SettingRow(title: "Save the restore list", detail: "A copy of restore-manifest.json, wherever you like.", icon: "doc.on.doc") {
                    PillButton(title: "Save…", kind: .outline) { saveManifest() }
                }
                SettingRow(title: "Save my config", detail: "~/.config/skyrose as a .zip (config, keymap, rules).", icon: "archivebox") {
                    PillButton(title: "Save…", kind: .outline) { saveConfig() }
                }
                if let saved {
                    Text(saved).font(look.font(12)).foregroundStyle(look[.onSurfaceVariant]).transition(.opacity)
                }
            }
            Card {
                SectionLabel(text: "Uninstall")
                SettingRow(title: "Uninstall SkyRose",
                           detail: "Brings every window back, restores the settings above, removes the login item and moves the apps to the Trash. No password needed. You choose whether your config and fonts go too.",
                           icon: "trash") {
                    HStack(spacing: 8) {
                        PillButton(title: "Preview", kind: .outline) { onUninstall(true) }
                            .help("Runs the uninstaller with --dry-run: nothing is changed.")
                            .accessibilityIdentifier("backup.preview")
                        PillButton(title: "Uninstall…", kind: .tonal) {
                            withAnimation(look.theme.spatial) { confirming = true }
                        }
                        .accessibilityIdentifier("backup.uninstall")
                    }
                }
                if confirming {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(look[.error])
                        Text("Open the uninstaller? Nothing happens until you press Uninstall SkyRose there.")
                            .font(look.font(12.5)).foregroundStyle(look[.onSurface]).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        PillButton(title: "Not now", kind: .outline) { withAnimation(look.theme.spatial) { confirming = false } }
                        PillButton(title: "Open uninstaller", kind: .danger) {
                            withAnimation(look.theme.spatial) { confirming = false }
                            onUninstall(false)
                        }
                        .accessibilityIdentifier("backup.confirm")
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: SettingsLook.rowRadius, style: .continuous).fill(look[.errorContainer].opacity(0.3)))
                    .transition(.opacity.combined(with: .offset(y: look.theme.slide(-8))))
                }
                Text("In Terminal: skyrose uninstall --dry-run, then skyrose uninstall.")
                    .font(look.mono(11)).foregroundStyle(look[.onSurfaceVariant]).textSelection(.enabled)
            }
            Card {
                SettingRow(title: "Preview the SIP reminder", detail: "The uninstaller shows this if SIP-off mode was ever used. It cannot be closed for 5 seconds.", icon: "lock.shield") {
                    PillButton(title: "Show", kind: .outline) { SIPReminderPresenter.show(look: look) }
                        .accessibilityIdentifier("about.sipPreview")
                }
            }
        }
        .onAppear(perform: load)
    }

    func load() {
        let m = RestoreManifest()
        manifestError = m.readError
        restores = (try? m.pendingRestores()) ?? []
    }

    func saveManifest() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "skyrose-restore-manifest.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            if FileManager.default.fileExists(atPath: Paths.restoreManifest.path) {
                try FileManager.default.copyItem(at: Paths.restoreManifest, to: url)
            } else {
                try Data(#"{"version":1,"entries":[]}"#.utf8).write(to: url)
            }
            withAnimation(look.theme.small) { saved = "Saved \(url.lastPathComponent)." }
        } catch {
            store.message = "Could not save the restore list: \(error.localizedDescription)"
        }
    }

    func saveConfig() {
        guard FileManager.default.fileExists(atPath: Paths.configDir.path) else {
            store.message = "There is no ~/.config/skyrose to save yet."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "skyrose-config.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", Paths.configDir.path, url.path]
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                withAnimation(look.theme.small) { saved = "Saved \(url.lastPathComponent)." }
            } else {
                store.message = "ditto could not write \(url.lastPathComponent)."
            }
        } catch {
            store.message = "Could not save the config: \(error.localizedDescription)"
        }
    }
}
