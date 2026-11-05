import AppKit
import CaelestiaCore
import CaelestiaPlatform
import SwiftUI

/// Settings › SIP-off mode: status, the sudo line that loads the scripting addition, the opt-in
/// switch (locked until the showcase was read to the end) and the per-feature switches.
struct SIPOffPage: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.look) var look
    @AppStorage(SIPOffShowcase.seenKey) private var showcaseSeen = false
    @State private var readiness = SIPOffReadiness()
    @State private var loaded: SAProtocol.Hello?
    @State private var copied = false
    private let poll = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var loadCommand: String? {
        let settingsApp = Bundle.main.bundleURL
        let sibling = settingsApp.deletingLastPathComponent().appendingPathComponent("SkyRose.app")
        let app = FileManager.default.fileExists(atPath: sibling.path) ? sibling
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.skyrose.mac")
        return SAClient.bundledLoader(appBundle: app).map { SAProtocol.loadCommand(loader: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "SIP-off mode",
                       subtitle: "Extras that only work with System Integrity Protection partly off, the way yabai does it. Off by default, and SkyRose works fully without it.")
            Card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.shield").font(.system(size: 22, weight: .semibold)).foregroundStyle(look[.error])
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This lowers your Mac's security").font(look.font(15, .semibold)).foregroundStyle(look[.onSurface])
                        Text("With SIP partly off, code can be injected into Apple's own apps. SkyRose uses that to load a small helper into the Dock. Check your school's rules first, and read what changes before you switch it on.")
                            .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                        PillButton(title: "What changes with SIP off?", icon: "sparkles.rectangle.stack", kind: .tonal) {
                            SIPOffShowcase.present(look: look)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            Card {
                SectionLabel(text: "Status")
                statusRow("System Integrity Protection", ok: readiness.filesystemOff && readiness.debuggingOff,
                          detail: readiness.filesystemOff && readiness.debuggingOff ? "Filesystem and Debugging protections are off" : "Fully on: SIP-off mode cannot load (that is fine)")
                if readiness.appleSilicon {
                    statusRow("Boot argument", ok: readiness.bootArg, detail: readiness.bootArg ? "-arm64e_preview_abi is set" : "-arm64e_preview_abi is not set")
                }
                statusRow("Scripting addition", ok: loaded != nil,
                          detail: loaded.map { "Loaded in the Dock: " + $0.capabilities.names.joined(separator: ", ") } ?? "Not loaded")
                if loaded == nil, readiness.ready, let cmd = loadCommand {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Load it once per boot: paste this into Terminal. It asks for your password and only loads SkyRose's helper into your Dock.")
                            .font(look.font(12)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(cmd).font(look.mono(11.5)).foregroundStyle(look[.onSurface]).textSelection(.enabled)
                                .lineLimit(2).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look[.surfaceContainerHighest]))
                            PillButton(title: copied ? "Copied" : "Copy", icon: copied ? "checkmark" : "doc.on.doc", kind: .outline) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd, forType: .string)
                                copied = true
                            }
                        }
                    }
                }
            }
            Card {
                SectionLabel(text: "Use it")
                SettingRow(title: "SIP-off mode", detail: showcaseSeen
                           ? "When the helper is loaded, SkyRose uses it; when it is not (or a macOS update broke it), SkyRose quietly keeps its normal behaviour."
                           : "Open “What changes with SIP off?” and read it to the end first.", icon: "bolt.shield") {
                    PillToggle(isOn: Binding(get: { store.config.sipOff.enabled }, set: { on in
                        if on, !showcaseSeen { SIPOffShowcase.present(look: look); return }
                        store.set("sipOff.enabled", .bool(on), update: { $0.sipOff.enabled = on })
                    }), enabled: showcaseSeen || store.config.sipOff.enabled, accessibilityLabel: "SIP-off mode")
                }
                if store.config.sipOff.enabled {
                    feature("Real window animations", "Windows pop in, close and move with live content (no snapshots).", "rectangle.stack", \.sipOff.animations, "sipOff.animations")
                    feature("Window opacity", "Other apps' windows at \(Int((store.config.wm.windowOpacity * 100).rounded())) % like Arch (fullscreen stays opaque).", "circle.lefthalf.filled", \.sipOff.opacity, "sipOff.opacity")
                    feature("Window shadows", "Off removes the macOS shadow from other apps' windows.", "shadow", \.sipOff.shadows, "sipOff.shadows")
                    feature("Instant workspaces", "Switch workspaces at once, without the slide.", "bolt", \.sipOff.instantWorkspaces, "sipOff.instantWorkspaces")
                    feature("Pinned windows on top", "A pinned window really stays above the others.", "pin", \.sipOff.pinOnTop, "sipOff.pinOnTop")
                }
            }
            .animation(look.motion.page, value: store.config.sipOff.enabled)
            Card {
                SectionLabel(text: "Turning SIP back on")
                Text("1. Shut down, hold the power button until “Loading startup options”, choose Options › Continue.\n2. Utilities › Terminal: csrutil enable, then restart.\n3. In Terminal: sudo nvram -d boot-args, then restart.\nSkyRose switches back to its normal behaviour by itself; `skyrose wm panic` undoes every window change at once.")
                    .font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(poll) { _ in refresh() }
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let r = SIPOffReadiness.current()
            let client = SAClient()
            let h = client.connect()
            client.close()
            DispatchQueue.main.async {
                readiness = r
                loaded = h
            }
        }
    }

    private func statusRow(_ title: String, ok: Bool, detail: String) -> some View {
        SettingRow(title: title, detail: detail, icon: ok ? "checkmark.circle" : "circle.dashed") {
            Text(ok ? "Ready" : "—").font(look.font(12, .semibold)).foregroundStyle(ok ? look[.primary] : look[.onSurfaceVariant])
        }
    }

    private func feature(_ title: String, _ detail: String, _ icon: String, _ key: WritableKeyPath<Config, Bool>, _ path: String) -> some View {
        SettingRow(title: title, detail: detail, icon: icon) {
            PillToggle(isOn: store.bool(key, path), accessibilityLabel: title)
        }
    }
}
