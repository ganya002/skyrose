import Carbon.HIToolbox
import CaelestiaCore
import Foundation

/// While another app holds Secure Event Input (a password field in Firefox, a sudo prompt in kitty)
/// the event tap gets no key events, so binds like SUPER + 1 stopped working for those seconds.
/// Carbon hot keys still arrive then, so the keymap's key + modifier binds are registered as hot
/// keys for exactly that time. Left/right modifier sides are not distinguishable here: while secure
/// input is on, either Option key works for SUPER.
@MainActor
final class SecureInputHotkeys {
    struct Entry: Equatable {
        var code: UInt32
        var carbonModifiers: UInt32
        var bind: Bind
        var chord: KeyChord
    }

    private let fire: @Sendable ([Fired]) -> Void
    private var registered: [UInt32: (EventHotKeyRef, Entry)] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x534B_5952  // "SKYR"

    init(fire: @escaping @Sendable ([Fired]) -> Void) { self.fire = fire }

    /// Key + modifier binds Carbon can register. Skips modifier taps, mouse and media binds, binds
    /// without a modifier (they would steal plain typing) and modifiers Carbon has no flag for.
    nonisolated static func entries(for keymap: Keymap) -> [Entry] {
        var out: [Entry] = []
        var seen = Set<[UInt32]>()
        for bind in keymap.binds where bind.enabled && !bind.flags.contains(.mouse) {
            for chord in bind.chords {
                guard case .code(let code) = chord.key, !chord.modifiers.isEmpty else { continue }
                var mods: UInt32 = 0
                var ok = true
                for m in chord.modifiers {
                    switch keymap.modifiers[m] {
                    case .lopt, .ropt, .opt: mods |= UInt32(optionKey)
                    case .lcmd, .rcmd, .cmd: mods |= UInt32(cmdKey)
                    case .lctrl, .rctrl, .ctrl: mods |= UInt32(controlKey)
                    case .lshift, .rshift, .shift: mods |= UInt32(shiftKey)
                    case .capslock, .fn: ok = false
                    }
                }
                guard ok, seen.insert([UInt32(code), mods]).inserted else { continue }
                out.append(Entry(code: UInt32(code), carbonModifiers: mods, bind: bind, chord: chord))
            }
        }
        return out
    }

    func activate(_ keymap: Keymap) {
        deactivate()
        installHandler()
        for (i, e) in Self.entries(for: keymap).enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(i))
            if RegisterEventHotKey(e.code, e.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                registered[UInt32(i)] = (ref, e)
            }
        }
        Log.input.notice("secure input: \(self.registered.count) binds kept working as hot keys")
    }

    func deactivate() {
        for (ref, _) in registered.values { UnregisterEventHotKey(ref) }
        registered.removeAll()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let me = Unmanaged<SecureInputHotkeys>.fromOpaque(data).takeUnretainedValue()
            return MainActor.assumeIsolated { me.hit(id, pressed: pressed) } ? noErr : OSStatus(eventNotHandledErr)
        }, specs.count, &specs, me, &handler)
    }

    private func hit(_ id: EventHotKeyID, pressed: Bool) -> Bool {
        guard id.signature == Self.signature, let e = registered[id.id]?.1 else { return false }
        // Release binds fire on the key-up, every other bind on the key-down (as in the matcher).
        guard pressed != e.bind.flags.contains(.release) else { return true }
        fire([Fired(bind: e.bind, chord: e.chord, phase: pressed ? .press : .release)])
        return true
    }
}
