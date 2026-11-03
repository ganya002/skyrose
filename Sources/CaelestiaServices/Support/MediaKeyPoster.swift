import AppKit
import Foundation

/// The special keys macOS routes through `NX_KEYTYPE_*` system-defined events (ev_keymap.h).
/// Raw values are the `NX_KEYTYPE_*` constants.
public enum MediaKeyKind: Int32, Sendable, CaseIterable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
    case fast = 19
    case rewind = 20
}

/// Posts media/brightness keys the public way: an `NSEvent` of type `.systemDefined`, subtype 8
/// (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`), converted to a CGEvent and posted at the HID tap. This is the
/// same event the physical F-keys produce, so the stock volume/brightness HUD appears as it would
/// for a keypress (section 5.9 documents that both HUDs may show).
///
/// The WM owns the event tap and may prefer to post from its own thread; services therefore
/// accept an injectable `(MediaKeyKind) -> Void` and use this poster only as the default.
public enum MediaKeyPoster {
    /// Modifier bits that encode key-down (0xA) / key-up (0xB) in the `data1` field, per ev_keymap.h.
    private static let downState: Int32 = 0xA
    private static let upState: Int32 = 0xB

    /// Posts a down+up pair for `key`.
    public static func post(_ key: MediaKeyKind) {
        for state in [downState, upState] {
            let data1 = Int((key.rawValue << 16) | (state << 8))
            let flags = NSEvent.ModifierFlags(rawValue: UInt(state) << 8)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
