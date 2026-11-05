import AppKit
import CaelestiaCore
import CaelestiaPlatform
import CaelestiaShell
import SwiftUI

/// Settings › Appearance › Fonts: the Arch font pack (``FontPack``). Download keeps the files in
/// SkyRose's own folder and registers them for SkyRose only (bar, shell, Settings); "Install for
/// kitty" copies them into ~/Library/Fonts so other apps see them too. Both are explicit.
@MainActor
final class FontsModel: ObservableObject {
    @Published var status: [FontStore.FamilyStatus] = []
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var message: String?
    let store = FontStore.shared

    func refresh() { status = store.status() }

    var allDownloaded: Bool { !status.isEmpty && status.allSatisfy(\.downloaded) }
    var anyInstalledBySkyRose: Bool { status.contains(where: \.installedBySkyRose) }

    func download(settings: SettingsStore) {
        guard !busy else { return }
        busy = true
        message = nil
        let fontStore = store
        Task {
            do {
                let fetched = try await fontStore.download { done, total in
                    Task { @MainActor in self.progress = total == 0 ? 1 : Double(done) / Double(total) }
                }
                if !fontStore.registerForProcess().isEmpty { ShellTheme.fontsChanged() }
                message = fetched.isEmpty ? "Already downloaded." : "Downloaded \(fetched.count) files; the bar and shell use them now."
                settings.objectWillChange.send()
                settings.runReload()
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            busy = false
            refresh()
        }
    }

    func run(_ body: () throws -> [String]) {
        do {
            let notes = try body()
            message = notes.isEmpty ? "Nothing to change." : notes.joined(separator: "\n")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        refresh()
    }
}

struct FontsCard: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var model = FontsModel()
    @Environment(\.look) var look

    var body: some View {
        Card {
            SectionLabel(text: "Fonts")
            Text("The fonts of the Arch desktop. Downloaded from their upstream projects (checked against pinned checksums) into SkyRose's folder and used by SkyRose only, unless you install them for other apps.")
                .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant])
            ForEach(FontPack.families) { family in
                let s = model.status.first { $0.name == family.name }
                SettingRow(title: family.name, detail: detail(family, s), icon: icon(family.role)) {
                    Image(systemName: s?.downloaded == true ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(s?.downloaded == true ? look[.primary] : look[.outline])
                }
            }
            HStack(spacing: 10) {
                if model.busy {
                    ProgressView(value: model.progress).frame(width: 160)
                } else if !model.allDownloaded {
                    PillButton(title: "Download (\(megabytes(FontPack.totalBytes)) MB)", icon: "arrow.down", kind: .filled) { model.download(settings: store) }
                }
                if model.allDownloaded {
                    PillButton(title: "Install for kitty and other apps", icon: "square.and.arrow.down", kind: .tonal) {
                        model.run { try model.store.installForUser(journal: BackupJournal()) }
                        ShellTheme.fontsChanged()
                    }
                }
                if model.anyInstalledBySkyRose {
                    PillButton(title: "Remove from other apps", kind: .outline) { model.run { try model.store.uninstallUser() } }
                }
                Spacer()
            }
            if let m = model.message {
                Text(m).font(look.mono(11.5)).foregroundStyle(look[.onSurfaceVariant]).textSelection(.enabled)
            }
        }
        .onAppear { model.refresh() }
    }

    func detail(_ f: FontPack.Family, _ s: FontStore.FamilyStatus?) -> String {
        let use: String
        switch f.role {
        case .sans: use = f.name == "Rubik" ? "Bar and shell text" : "Text fallback"
        case .mono: use = "Shell numbers and code"
        case .terminal: use = "kitty (Terminal › kitty setup)"
        case .icons: use = "Caelestia's icon font (the shell still draws SF Symbols)"
        }
        var where_ = s?.availableSystemWide == true ? "installed for every app" : (s?.downloaded == true ? "SkyRose only" : "not downloaded")
        if s?.installedBySkyRose == true { where_ = "installed by SkyRose for every app" }
        return "\(use) · \(f.licence) · \(megabytes(f.bytes)) MB · \(where_)"
    }

    func icon(_ r: FontPack.Role) -> String {
        switch r {
        case .sans: return "textformat"
        case .mono: return "chevron.left.forwardslash.chevron.right"
        case .terminal: return "terminal"
        case .icons: return "square.grid.2x2"
        }
    }

    func megabytes(_ b: Int) -> String { String(format: b >= 10_000_000 ? "%.0f" : "%.1f", Double(b) / 1_000_000) }
}
