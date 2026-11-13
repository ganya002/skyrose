import Foundation

/// A SkyRose feature that is compiled in and switched by SkyStore (a `feature` addon,
/// docs/SKYSTORE.md). Installing one writes only a state record, so no code is downloaded.
/// Uninstalling it or switching it off turns the feature off. Every builtin starts installed, so
/// an update to a SkyRose that has the switch changes nothing.
public struct BuiltinFeature: Equatable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var permissions: [String]

    public static let clamshell = BuiltinFeature(
        id: "skyrose.clamshell", name: "Clamshell",
        summary: "Keep the Mac running with the lid closed, also on battery: the sidebar's Clamshell chip, skyrose clamshell and keep-awake when closed.",
        permissions: [])
    public static let colorPicker = BuiltinFeature(
        id: "skyrose.colorpicker", name: "Colour picker",
        summary: "Pick a colour anywhere on screen (Super+Shift+C or skyrose picker) and copy its hex value.",
        permissions: ["clipboard"])
    public static let all = [clamshell, colorPicker]

    public static func named(_ id: String) -> BuiltinFeature? { all.first { $0.id == id } }

    /// How the Store lists it. The version is this SkyRose's own; its `url` is never fetched.
    public func entry(skyRoseVersion: String = CaelestiaVersion.string) -> StoreEntry {
        StoreEntry(id: id, name: name, author: "SkyRose", summary: summary, kind: .feature, category: "Built in",
                   licence: "GPL-3.0", versions: [StoreVersion(version: skyRoseVersion, minSkyRose: skyRoseVersion,
                                                               url: URL(string: "https://github.com/ganya002/skyrose")!, sha256: "",
                                                               size: 0, permissions: permissions, released: "")])
    }

    func record(version: String) -> InstalledAddon {
        InstalledAddon(id: id, name: name, author: "SkyRose", kind: .feature, version: version, permissions: permissions.sorted(),
                       sha256: "", installedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
                       disabled: nil, setup: nil)
    }
}
