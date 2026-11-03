import CaelestiaCore
import Carbon
import Foundation

/// Characters a key code produces on the user's keyboard layout, for cheat sheets and the
/// conflict checker (binds are by key code; this is only for display).
///
/// Reconciliation note: Core's chord parser (`Sources/CaelestiaCore/Keymap/ChordParser.swift`)
/// is expected to declare this protocol. Until it does, it lives here with the same shape so
/// `CurrentKeyboardLayout` can be passed to the parser once the Core declaration lands.
public protocol KeyboardLayoutCharacters {
    func character(forKeyCode code: UInt16, shift: Bool) -> String?
    func optionCharacter(forKeyCode code: UInt16) -> String?
}

/// A snapshot of the current keyboard layout (`TISCopyCurrentKeyboardLayoutInputSource`),
/// translated with `UCKeyTranslate`. On Gabby's Norwegian layout `layoutName` is "Norwegian",
/// `character(forKeyCode: 0x1B /* Minus position */, shift: false)` is "+" and
/// `optionCharacter(forKeyCode: 0x1C /* 8 */)` is "[".
///
/// Construct on the main thread (Text Input Services is not thread-safe); the value itself is
/// immutable and can be used from anywhere. Re-create it when the input source changes
/// (`kTISNotifySelectedKeyboardInputSourceChanged`).
public struct CurrentKeyboardLayout: KeyboardLayoutCharacters, Equatable, Sendable {
    /// Localized layout name, e.g. "Norwegian", "U.S."; "Unknown" when no layout is available.
    public let layoutName: String
    /// Input source identifier, e.g. `com.apple.keylayout.Norwegian`.
    public let inputSourceID: String
    private let layoutData: [UInt8]?
    private let keyboardType: UInt32

    public init() {
        keyboardType = UInt32(LMGetKbdType())
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            layoutName = "Unknown"
            inputSourceID = ""
            layoutData = nil
            return
        }
        layoutName = Self.string(kTISPropertyLocalizedName, of: source) ?? "Unknown"
        inputSourceID = Self.string(kTISPropertyInputSourceID, of: source) ?? ""
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
            layoutData = [UInt8](data)
        } else {
            layoutData = nil
        }
    }

    /// A layout built from raw `uchr` data (tests, or layouts other than the current one).
    public init(layoutName: String, inputSourceID: String, uchrData: Data, keyboardType: UInt32 = UInt32(LMGetKbdType())) {
        self.layoutName = layoutName
        self.inputSourceID = inputSourceID
        self.layoutData = [UInt8](uchrData)
        self.keyboardType = keyboardType
    }

    /// Whether key translation is possible (some input methods carry no layout data).
    public var isAvailable: Bool { layoutData != nil }

    public func character(forKeyCode code: UInt16, shift: Bool) -> String? {
        translate(code, carbonModifiers: shift ? shiftKey : 0)
    }

    public func optionCharacter(forKeyCode code: UInt16) -> String? {
        translate(code, carbonModifiers: optionKey)
    }

    /// The character for any combination of Shift and Option.
    public func character(forKeyCode code: UInt16, shift: Bool, option: Bool) -> String? {
        translate(code, carbonModifiers: (shift ? shiftKey : 0) | (option ? optionKey : 0))
    }

    /// Runs `UCKeyTranslate` in display mode with dead keys resolved; returns `nil` for keys that
    /// yield nothing printable (arrows, function keys, Return, …).
    private func translate(_ code: UInt16, carbonModifiers: Int) -> String? {
        guard let layoutData else { return nil }
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status: OSStatus = layoutData.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return OSStatus(paramErr) }
            return base.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
                UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDisplay), UInt32((carbonModifiers >> 8) & 0xFF),
                    keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                    chars.count, &length, &chars)
            }
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: Int(length))
        let printable = s.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .privateUse, .unassigned: return false
            default: return true
            }
        }
        return printable ? s : nil
    }

    private static func string(_ key: CFString, of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
