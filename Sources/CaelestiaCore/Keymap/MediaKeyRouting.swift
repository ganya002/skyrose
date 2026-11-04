import Foundation

/// A volume / brightness key Caelestia can handle itself.
public enum MediaKeyCommand: String, Equatable, Sendable, CaseIterable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    /// NX_KEYTYPE_* (ev_keymap.h): 0 sound up, 1 sound down, 2 brightness up, 3 brightness down,
    /// 7 mute. Everything else (play, next, keyboard illumination, ...) is not ours.
    public init?(nxKeyType: Int) {
        switch nxKeyType {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 7: self = .mute
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        default: return nil
        }
    }

    public var isVolume: Bool { self == .volumeUp || self == .volumeDown || self == .mute }
    public var isBrightness: Bool { !isVolume }
}

/// Which slider the OSD is shown for.
public enum OSDKind: String, Equatable, Sendable {
    case volume, brightness
}

/// One `NX_SYSDEFINED` aux-control event, decoded from its `data1` (ev_keymap.h): key type in
/// bits 16-31, key state in bits 8-15 (0x0A down, 0x0B up), the repeat flag in bit 0.
public struct MediaKeyEvent: Equatable, Sendable {
    public var nxKeyType: Int
    public var isDown: Bool
    public var isRepeat: Bool
    /// CGEventFlags raw value (⌥⇧ = quarter steps).
    public var flags: UInt64

    public init(nxKeyType: Int, isDown: Bool, isRepeat: Bool = false, flags: UInt64 = 0) {
        self.nxKeyType = nxKeyType
        self.isDown = isDown
        self.isRepeat = isRepeat
        self.flags = flags
    }

    public init(data1: Int, flags: UInt64 = 0) {
        nxKeyType = (data1 & 0xFFFF_0000) >> 16
        isDown = (data1 & 0xFF00) >> 8 == 0x0A
        isRepeat = data1 & 0x1 != 0
        self.flags = flags
    }

    public var command: MediaKeyCommand? { MediaKeyCommand(nxKeyType: nxKeyType) }

    /// Option + Shift held: macOS's fine (quarter) steps.
    public var isFine: Bool {
        let option: UInt64 = 0x0008_0000, shift: UInt64 = 0x0002_0000
        return flags & option != 0 && flags & shift != 0
    }
}

/// What happens to a media key: whether Caelestia swallows it (macOS never sees it, so Apple's HUD
/// stays away), what Caelestia then does, and which OSD it shows. Pure; the event tap evaluates it
/// on its own thread and the shell uses the same table for keybind actions.
public struct MediaKeyRoute: Equatable, Sendable {
    /// The event is dropped and `command` is performed by Caelestia.
    public var swallow: Bool
    public var command: MediaKeyCommand?
    /// Caelestia's OSD for this key (nil: none, e.g. a brightness key macOS handles alone).
    public var osd: OSDKind?

    public init(swallow: Bool, command: MediaKeyCommand?, osd: OSDKind?) {
        self.swallow = swallow
        self.command = command
        self.osd = osd
    }

    public static let passThrough = MediaKeyRoute(swallow: false, command: nil, osd: nil)
}

public enum MediaKeyRouting {
    /// - `intercept`: config `input.interceptMediaKeys`.
    /// - `volumeControllable`: the default output's volume is settable through CoreAudio.
    /// - `brightnessControllable`: DisplayServices (or IOKit) can set the target display's brightness.
    ///
    /// Volume keys: swallowed and done by Caelestia when it can; otherwise macOS does them and
    /// Caelestia's volume OSD shows next to Apple's only when interception is off (an output
    /// without volume control shows Apple's "not available" HUD alone). Brightness keys:
    /// swallowed when the brightness is controllable (brightness OSD), otherwise passed to macOS
    /// with no Caelestia OSD at all. A brightness key never shows the volume OSD.
    public static func route(_ command: MediaKeyCommand?, intercept: Bool, volumeControllable: Bool, brightnessControllable: Bool) -> MediaKeyRoute {
        guard let command else { return .passThrough }
        if command.isVolume {
            if intercept, volumeControllable { return MediaKeyRoute(swallow: true, command: command, osd: .volume) }
            return MediaKeyRoute(swallow: false, command: nil, osd: !intercept && volumeControllable ? .volume : nil)
        }
        if brightnessControllable {
            return intercept
                ? MediaKeyRoute(swallow: true, command: command, osd: .brightness)
                : MediaKeyRoute(swallow: false, command: nil, osd: .brightness)
        }
        return .passThrough
    }
}
