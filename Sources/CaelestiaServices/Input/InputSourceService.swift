import Carbon
import Foundation

/// The keyboard input sources the user enabled (System Settings › Keyboard › Input Sources),
/// and switching between them (public Text Input Sources API).
public struct InputSource: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var selected: Bool
}

public enum InputSources {
    public static func list() -> [InputSource] {
        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource,
                      kTISPropertyInputSourceIsSelectCapable: true] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return sources.compactMap { s in
            guard let id = string(s, kTISPropertyInputSourceID), let name = string(s, kTISPropertyLocalizedName) else { return nil }
            let selected = (property(s, kTISPropertyInputSourceIsSelected) as? Bool) ?? false
            return InputSource(id: id, name: name, selected: selected)
        }
    }

    @discardableResult
    public static func select(_ id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let s = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first else { return false }
        return TISSelectInputSource(s) == noErr
    }

    private static func property(_ s: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let raw = TISGetInputSourceProperty(s, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }

    private static func string(_ s: TISInputSource, _ key: CFString) -> String? { property(s, key) as? String }
}
