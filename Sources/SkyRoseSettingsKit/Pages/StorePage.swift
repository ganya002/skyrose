import CaelestiaCore
import SwiftUI

/// Settings › SkyStore: open the Store, what is installed, and creator mode (off by default).
struct StorePage: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look
    @State private var installed: [InstalledAddon] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "SkyStore", subtitle: "Themes, wallpapers and more, checked before they install.")
            Card {
                SectionLabel(text: "Store")
                SettingRow(title: "Open SkyStore", detail: store.wmRunning ? "Opens in the shell, from the bottom of the screen. Also: skyrose store, or >store in the launcher."
                    : "SkyRose is not running.", icon: "bag") {
                    PillButton(title: "Open", icon: "arrow.up.forward", kind: .tonal) { store.openStore() }
                        .disabled(!store.wmRunning)
                }
                SettingRow(title: "Installed", detail: installed.isEmpty ? "No addons yet."
                    : installed.map { "\($0.name) \($0.version) (\($0.status))" }.joined(separator: ", "), icon: "shippingbox") { EmptyView() }
                Text("Every index is signed and every bundle is checked against its SHA-256. A revoked addon is switched off for you, and skyrose wm panic switches every addon off.")
                    .font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
            }
            Card {
                SectionLabel(text: "Creator mode")
                SettingRow(title: "Creator mode", detail: "Make and submit your own addons from the command line.", icon: "hammer") {
                    PillToggle(isOn: store.bool(\.store.creatorMode, "store.creatorMode"), accessibilityLabel: "Creator mode")
                }
                if store.config.store.creatorMode {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(["skyrose store new dev.you.my-theme [--kind scheme|wallpaper|widget]", "skyrose store validate", "skyrose store pack",
                                 "skyrose store submit --repo you/my-addons"], id: \.self) { c in
                            Text(c).font(look.mono(11.5)).foregroundStyle(look[.onSurface]).textSelection(.enabled)
                        }
                        Text("Submit uploads the bundle with your own gh login and opens a pre-filled pull request in your browser. SkyRose never stores a token. A person reviews every submission before it appears.")
                            .font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                        Text("For a local test index, creator mode also accepts a file:// store.indexURL and your own store.trustedKeys in config.toml.")
                            .font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                    }
                    .transition(.opacity.combined(with: .offset(y: look.motion.slide(-6))))
                }
            }
            .animation(look.motion.page, value: store.config.store.creatorMode)
        }
        .onAppear { let a = AddonStore(); a.seedBuiltinFeatures(); installed = a.installed() }
    }
}
