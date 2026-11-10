import Foundation

/// Focus follows the pointer, after a delay, and only when nothing else owns the pointer.
///
/// Hyprland `follow_mouse = 1`: the window under the pointer is focused, and a floating window
/// is not raised unless asked. A warp, a click, a drag, a menu, a sheet, a password field, the
/// menu bar, a SkyRose drawer, or a fullscreen window on another Space holds focus where it is.
public struct HoverFocus: Equatable, Sendable {
    public enum Block: String, Equatable, Sendable {
        case off, drag, button, menu, popover, launcher, drawer, menuBar, sheet, password, otherSpaceFullscreen, warp, systemUI, retile, keyboard
    }

    public private(set) var window: UInt32?
    public private(set) var since: TimeInterval?

    public init() {}

    /// The window to focus now, when the pointer has rested on it for `delay` seconds.
    /// A block, or the pointer leaving every window, forgets the candidate.
    public mutating func update(over id: UInt32?, at now: TimeInterval, delay: TimeInterval, blocked: Block?) -> UInt32? {
        guard blocked == nil, let id else {
            window = nil
            since = nil
            return nil
        }
        if window != id {
            window = id
            since = now
        }
        guard let since, delay <= 0 || now - since + 0.0001 >= delay else { return nil }
        return id
    }
}
