import CoreGraphics
import Foundation

/// When the bar shows (spec 5.2; Caelestia `bar.persistent` / `bar.showOnHover`). Pure: the
/// controller feeds it pointer positions and asks for the target.
///
/// - persistent: always shown, always reserved.
/// - auto-hide: the pointer touching the left band shows it; leaving the bar strip (plus a small
///   margin) hides it after `hideDelay`, unless something keeps it open (a drawer opened from it).
public struct BarVisibility: Equatable, Sendable {
    public var persistent: Bool
    public var showOnHover: Bool
    public private(set) var shown: Bool
    /// When the pointer left the bar (hide is pending).
    public private(set) var leftAt: TimeInterval?
    /// Something (a popout, the session menu opened from the power button) holds the bar open.
    public var pinned = false
    public static let hideDelay: TimeInterval = 0.25
    /// Extra room to the right of the bar before the pointer counts as gone.
    public static let leaveMargin: Double = 8

    public init(persistent: Bool, showOnHover: Bool = true) {
        self.persistent = persistent
        self.showOnHover = showOnHover
        shown = persistent
    }

    public var isShown: Bool { persistent || shown }

    /// Feeds one pointer sample. Returns true when `isShown` changed.
    @discardableResult
    public mutating func pointer(inHotZone: Bool, overBar: Bool, at now: TimeInterval) -> Bool {
        let before = isShown
        guard !persistent else { return false }
        if inHotZone, showOnHover {
            shown = true
            leftAt = nil
        } else if shown, overBar || pinned {
            leftAt = nil
        } else if shown {
            if let t = leftAt {
                if now - t >= Self.hideDelay { shown = false; leftAt = nil }
            } else {
                leftAt = now
            }
        }
        return before != isShown
    }

    /// Called from a timer while a hide is pending (the pointer may not move again).
    @discardableResult
    public mutating func tick(at now: TimeInterval) -> Bool {
        guard !persistent, shown, !pinned, let t = leftAt, now - t >= Self.hideDelay else { return false }
        shown = false
        leftAt = nil
        return true
    }

    /// Explicit show/hide (IPC, a keybind).
    public mutating func set(shown value: Bool) {
        guard !persistent else { return }
        shown = value
        leftAt = nil
    }

    public mutating func setPersistent(_ value: Bool) {
        persistent = value
        if value { shown = true }
        leftAt = nil
    }

    public var hidePending: Bool { leftAt != nil }
}
