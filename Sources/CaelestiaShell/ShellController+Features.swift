import AppKit
import CaelestiaCore

/// SkyRose's builtin features that SkyStore switches (`feature` addons, `BuiltinFeature`).
extension ShellController {
    /// Re-reads which builtin features are on (start, config reload, a Store change). A feature
    /// that went off stops at once: Clamshell lets the Mac sleep with the lid closed again.
    public func refreshFeatures() {
        let clamshellOn = store.addons.featureEnabled(BuiltinFeature.clamshell.id)
        if state.clamshellFeature != clamshellOn { state.clamshellFeature = clamshellOn }
        clamshell.keepAwakeWhenClosed = clamshellOn && state.config.clamshell.keepAwake
        if !clamshellOn, lidSleep.status.clamshellOn { lidSleep.setClamshell(false) }
    }

    /// `picker.color`: the macOS eyedropper; the picked colour's hex goes to the clipboard.
    func pickColor() {
        guard store.addons.featureEnabled(BuiltinFeature.colorPicker.id) else {
            _ = toast(.warn, title: "Colour picker is off", message: "Turn it on in SkyStore › Categories › Built in, or run: skyrose store enable \(BuiltinFeature.colorPicker.id)", icon: "colorize")
            return
        }
        NSColorSampler().show { [weak self] color in
            guard let self, let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = Self.hex(c)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            _ = self.toast(.info, title: hex, message: "Copied to the clipboard.", icon: "colorize")
        }
    }

    /// `#RRGGBB` of an sRGB colour.
    nonisolated static func hex(_ c: NSColor) -> String {
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
