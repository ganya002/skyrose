import AppKit
import Carbon.HIToolbox
import Foundation
import CaelestiaCore

/// The selected keyboard input source, for the bar's kbLayout icon and the layout OSD.
public struct KeyboardLayoutState: Hashable, Sendable {
    /// Localized name, e.g. "Norwegian", "U.S.", "ABC".
    public var name: String = ""
    /// Input source id, e.g. "com.apple.keylayout.Norwegian".
    public var sourceID: String = ""
    /// Two-letter code from the source's first language ("no", "en"), for the compact bar label.
    public var code: String = ""
    public init() {}
}

/// Text Input Source (TIS) status. The selection change is delivered by
/// `kTISNotifySelectedKeyboardInputSourceChanged` over the distributed notification center.
///
/// Caps Lock is not observed here: the WM's event tap already sees every `flagsChanged` and calls
/// `capsLockState()` then, so no timer is needed.
@MainActor
public final class KeyboardLayoutService {
    public private(set) var state = KeyboardLayoutState()
    public var onChange: ((KeyboardLayoutState) -> Void)?

    private var observer: NSObjectProtocol?
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            onMain { self.refresh() }
        }
        refresh()
    }

    public func stop() {
        guard running else { return }
        running = false
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    /// Current Caps Lock state from the hardware modifier flags (call on `flagsChanged`).
    public nonisolated func capsLockState() -> Bool {
        NSEvent.modifierFlags.contains(.capsLock)
    }

    public func refresh() {
        let s = Self.currentLayout()
        if s != state {
            state = s
            onChange?(s)
        }
    }

    /// Reads the selected keyboard input source.
    public nonisolated static func currentLayout() -> KeyboardLayoutState {
        var s = KeyboardLayoutState()
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return s }
        s.name = property(source, kTISPropertyLocalizedName) as? String ?? ""
        s.sourceID = property(source, kTISPropertyInputSourceID) as? String ?? ""
        if let languages = property(source, kTISPropertyInputSourceLanguages) as? [String], let first = languages.first {
            s.code = String(first.prefix(2)).lowercased()
        } else {
            s.code = String(s.name.prefix(2)).lowercased()
        }
        return s
    }

    private nonisolated static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}
