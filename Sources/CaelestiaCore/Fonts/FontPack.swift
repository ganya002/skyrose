import CryptoKit
import Foundation

/// The fonts Gabby's Arch desktop uses (Tests/fixtures/ref/fonts.txt, Caelestia's defaults), fetched
/// from pinned upstream sources and checked against SHA-256 sums recorded on 2026-11-05.
///
/// | Family | Used for | Licence | Source |
/// |---|---|---|---|
/// | Rubik | shell sans (Caelestia `font.family.sans`) | SIL OFL 1.1 | google/fonts @ 8b0a1d0 |
/// | Inter | sans fallback | SIL OFL 1.1 | google/fonts @ 0b58fb3 |
/// | CaskaydiaCove Nerd Font | shell mono (Caelestia `font.family.mono`) | SIL OFL 1.1 (Cascadia Code, renamed: Reserved Font Name) | ryanoasis/nerd-fonts v3.4.0 |
/// | JetBrainsMono Nerd Font | kitty (Gabby's kitty.conf) | SIL OFL 1.1 | ryanoasis/nerd-fonts v3.4.0 |
/// | Material Symbols Rounded | Caelestia's icon font | Apache 2.0 | google/material-design-icons @ 10ecc14 |
///
/// All five allow redistribution; each family's licence text is fetched and kept next to it.
public enum FontPack {
    public struct Asset: Equatable, Sendable {
        public let fileName: String
        public let url: String
        public let sha256: String
        public let bytes: Int
    }

    public enum Role: String, Sendable { case sans, mono, terminal, icons }

    public struct Family: Equatable, Sendable, Identifiable {
        public let name: String
        public let role: Role
        public let licence: String
        public let files: [Asset]
        public let licenceFile: Asset
        public var id: String { name }
        public var bytes: Int { files.reduce(0) { $0 + $1.bytes } }
    }

    static let nerdFonts = "https://github.com/ryanoasis/nerd-fonts/raw/v3.4.0/patched-fonts"
    static let googleFonts = "https://github.com/google/fonts/raw"
    static let materialIcons = "https://github.com/google/material-design-icons/raw/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7"

    public static let families: [Family] = [
        Family(name: "Rubik", role: .sans, licence: "SIL OFL 1.1", files: [
            Asset(fileName: "Rubik[wght].ttf", url: "\(googleFonts)/8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/rubik/Rubik%5Bwght%5D.ttf",
                  sha256: "1b3a7437ba2af80e465e773ed60c5036d1ba6ace492d89046dbcf18fb31e4e88", bytes: 359_804),
        ], licenceFile: Asset(fileName: "Rubik-OFL.txt", url: "\(googleFonts)/8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/rubik/OFL.txt",
                              sha256: "472cbe7c25441df63e9c7864b43eb3c0f4b3df950c66a76224e6cfe1eae843fb", bytes: 0)),
        Family(name: "Inter", role: .sans, licence: "SIL OFL 1.1", files: [
            Asset(fileName: "Inter[opsz,wght].ttf", url: "\(googleFonts)/0b58fb370093f9a9f4ff785d94405710b79de67c/ofl/inter/Inter%5Bopsz,wght%5D.ttf",
                  sha256: "29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031", bytes: 876_576),
        ], licenceFile: Asset(fileName: "Inter-OFL.txt", url: "\(googleFonts)/0b58fb370093f9a9f4ff785d94405710b79de67c/ofl/inter/OFL.txt",
                              sha256: "5b9321a4298cfeb6b34354164a1c3afc3db114569984c502b9b35d988fd58c57", bytes: 0)),
        Family(name: "CaskaydiaCove Nerd Font", role: .mono, licence: "SIL OFL 1.1", files: [
            Asset(fileName: "CaskaydiaCoveNerdFont-Regular.ttf", url: "\(nerdFonts)/CascadiaCode/CaskaydiaCoveNerdFont-Regular.ttf",
                  sha256: "701d7ec08f58f07251c1758361c5d1ab57ba0a867dd378cbb0fa52e1d2beccad", bytes: 2_892_532),
            Asset(fileName: "CaskaydiaCoveNerdFont-Bold.ttf", url: "\(nerdFonts)/CascadiaCode/CaskaydiaCoveNerdFont-Bold.ttf",
                  sha256: "d38b2e9461f52c70ef9f18c5c79f869d8b084432416ea6e850855c5222fbdc38", bytes: 2_894_232),
        ], licenceFile: Asset(fileName: "CascadiaCode-LICENSE.txt", url: "\(nerdFonts)/CascadiaCode/LICENSE",
                              sha256: "82c05d6c53dfa0c9025985c19e371810020b74ed2c61d51d370f2a8ab2506d52", bytes: 0)),
        Family(name: "JetBrainsMono Nerd Font", role: .terminal, licence: "SIL OFL 1.1", files: [
            Asset(fileName: "JetBrainsMonoNerdFont-Regular.ttf", url: "\(nerdFonts)/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFont-Regular.ttf",
                  sha256: "0ec29a68b539ece7078fc714cebff0c0accb2f4948f8f7963d9f5e86633b12d9", bytes: 2_469_104),
            Asset(fileName: "JetBrainsMonoNerdFont-Bold.ttf", url: "\(nerdFonts)/JetBrainsMono/Ligatures/Bold/JetBrainsMonoNerdFont-Bold.ttf",
                  sha256: "e82e27a7f37c9a0a13cc4e417503a149c6a0280586930772d2ebed803159c864", bytes: 2_472_872),
            Asset(fileName: "JetBrainsMonoNerdFont-Italic.ttf", url: "\(nerdFonts)/JetBrainsMono/Ligatures/Italic/JetBrainsMonoNerdFont-Italic.ttf",
                  sha256: "981133a258ef4c62769a7a7214a4b455ac1c63923784a70f50c48977b67f7025", bytes: 2_471_188),
            Asset(fileName: "JetBrainsMonoNerdFont-BoldItalic.ttf", url: "\(nerdFonts)/JetBrainsMono/Ligatures/BoldItalic/JetBrainsMonoNerdFont-BoldItalic.ttf",
                  sha256: "961222be7bce59f310b41a3e158368d5ea22a47a0ac31defd57caac9b9e82cb0", bytes: 2_474_096),
        ], licenceFile: Asset(fileName: "JetBrainsMono-OFL.txt", url: "\(nerdFonts)/JetBrainsMono/Ligatures/Regular/OFL.txt",
                              sha256: "30f0c136e3c88e422d0791acd97238870f9054a9729bc34cf2ff0d4ed8cac4ad", bytes: 0)),
        Family(name: "Material Symbols Rounded", role: .icons, licence: "Apache 2.0", files: [
            Asset(fileName: "MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf",
                  url: "\(materialIcons)/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf",
                  sha256: "7e74e36533ccee12c2b81e75bfcf3ccf123d3bb7e7e46d65d94445f23db0c97c", bytes: 15_235_612),
        ], licenceFile: Asset(fileName: "MaterialSymbols-LICENSE.txt", url: "\(materialIcons)/LICENSE",
                              sha256: "58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd", bytes: 0)),
    ]

    /// Families that make sense in a terminal (offered to kitty).
    public static var terminalFamilies: [Family] { families.filter { $0.role == .terminal || $0.role == .mono } }

    public static var totalBytes: Int { families.reduce(0) { $0 + $1.bytes } }

    /// Where downloaded fonts are kept (inside SkyRose's own folder; the uninstaller trashes it).
    public static var cacheDirectory: URL { Paths.appSupport.appendingPathComponent("Fonts", isDirectory: true) }
    /// The per-user font folder macOS and kitty read (no admin rights needed).
    public static var userFontsDirectory: URL { Paths.home.appendingPathComponent("Library/Fonts", isDirectory: true) }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(_ data: Data, _ asset: Asset) -> Bool { sha256Hex(data) == asset.sha256 }

    /// A cached file that is plausibly intact without hashing it again (size match; the hash was
    /// checked when it was written).
    public static func looksCached(_ asset: Asset, in directory: URL) -> Bool {
        let url = directory.appendingPathComponent(asset.fileName)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else { return false }
        return asset.bytes == 0 ? size > 0 : size == asset.bytes
    }

    public static func isCached(_ family: Family, in directory: URL = cacheDirectory) -> Bool {
        family.files.allSatisfy { looksCached($0, in: directory) }
    }
}
