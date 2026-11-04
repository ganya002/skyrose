import CaelestiaCore
import CoreGraphics
import Foundation

// MARK: - The hook between the WM and whatever animates real windows

/// One window whose frame changes in a layout pass. Frames are global AX/CG points (top-left).
public struct WindowFrameChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Retile, swap, resize, toggle float/fullscreen: from `from` to `to`.
        case move
        /// A new window (or one coming back from another workspace without a slide): pops in at `to`.
        case open
        /// The window was closed or minimized: shrinks and fades out from `from`.
        case close
        /// Moved to a hidden workspace (it gets parked): fades out from `from`.
        case leave
    }

    public var id: CGWindowID
    public var kind: Kind
    /// Where the window is on screen now (nil when unknown).
    public var from: CGRect?
    /// Where it will be (nil for close / leave).
    public var to: CGRect?

    public init(id: CGWindowID, kind: Kind, from: CGRect?, to: CGRect?) {
        self.id = id
        self.kind = kind
        self.from = from
        self.to = to
    }
}

/// A window that is visible after the pass (moving or not). Everything a cover must redraw.
public struct AnimatedWindow: Equatable, Sendable {
    public var id: CGWindowID
    /// Final frame after the pass.
    public var frame: CGRect
    public var displayID: CGDirectDisplayID
    public var isActive: Bool
    /// Draws a border ring (false for no-border rules and non-standard windows).
    public var decorated: Bool

    public init(id: CGWindowID, frame: CGRect, displayID: CGDirectDisplayID, isActive: Bool, decorated: Bool = true) {
        self.id = id
        self.frame = frame
        self.displayID = displayID
        self.isActive = isActive
        self.decorated = decorated
    }
}

/// What one layout pass is about to do.
public struct WindowAnimationRequest: Equatable, Sendable {
    public var changes: [WindowFrameChange]
    /// Every visible managed window after the pass, back to front.
    public var windows: [AnimatedWindow]
    /// Display frames (global top-left) by CGDirectDisplayID.
    public var displays: [CGDirectDisplayID: CGRect]

    public init(changes: [WindowFrameChange], windows: [AnimatedWindow], displays: [CGDirectDisplayID: CGRect]) {
        self.changes = changes
        self.windows = windows
        self.displays = displays
    }

    /// Displays that have at least one change.
    public var affectedDisplays: Set<CGDirectDisplayID> {
        var result: Set<CGDirectDisplayID> = []
        for c in changes {
            guard let rect = c.to ?? c.from else { continue }
            if let d = Self.display(for: rect, in: displays) { result.insert(d) }
        }
        return result
    }

    /// The display with the largest overlap, else none.
    public static func display(for rect: CGRect, in displays: [CGDirectDisplayID: CGRect]) -> CGDirectDisplayID? {
        var best: (CGDirectDisplayID, Double)?
        for (id, frame) in displays {
            let i = rect.intersection(frame)
            let area = i.isNull ? 0 : i.width * i.height
            if area > 0, area > (best?.1 ?? 0) { best = (id, area) }
        }
        return best?.0
    }
}

/// Animates the real windows of a layout pass. The WM calls `animate` once per pass, *before* it
/// writes any frame; the animator calls `commit` exactly once, either synchronously (instant move)
/// or as soon as whatever hides the real windows is on screen. `commit` does every AX write of the
/// pass (one setFrame per window, parking), so a real window only ever gets its final frame.
///
/// Implementations:
/// - ``InstantWindowAnimator``: commits at once (animations off, game mode, tests).
/// - ``SnapshotWindowAnimator`` (Standard mode, SIP on): an overlay cover shows ScreenCaptureKit
///   stills of the windows moving from the old to the new frames while the real windows are
///   moved once underneath it.
/// - A future Enhanced-mode animator (SIP partly off, scripting addition in the Dock) plugs in
///   here too: it would commit at once and animate the real windows' transforms/alpha through
///   the SA instead of a cover. See docs/ENHANCED_MODE.md, "Window animation hook".
@MainActor
public protocol WindowAnimator: AnyObject {
    func animate(_ request: WindowAnimationRequest, commit: @escaping () -> Void)
    /// True while `id` is drawn by the animator (its border window must snap, not fade).
    func isCovering(_ id: CGWindowID) -> Bool
    /// The WM itself is about to close `id` (its close action). Puts the cover up with every still
    /// first, so the close can shrink and fade a window that never vanished from the screen.
    /// Returns false when it cannot (the close then just happens).
    func prepareClose(_ id: CGWindowID, scene: WindowAnimationRequest) -> Bool
    /// A tiled window starts being dragged with the mouse. Returns false when the animator cannot
    /// show a live drag (then the WM just swaps on drop, as before).
    func beginDrag(_ id: CGWindowID, pointer: CGPoint, scene: WindowAnimationRequest) -> Bool
    /// The pointer moved: the dragged still follows it; `dropTarget` is the slot it would land in.
    func updateDrag(pointer: CGPoint, dropTarget: CGRect?)
    /// The drag ended. When nothing was swapped the still flies back to its slot; otherwise the
    /// layout pass that follows animates it from where it was dropped.
    func endDrag()
    /// Windows of the WM went away or were seen again: the snapshot cache follows.
    func windowsChanged(visible: [AnimatedWindow])
    /// Panic / quit / game mode: everything goes now.
    func cancel()
}

/// Commits at once. Used when window animations are off and as the test default.
@MainActor
public final class InstantWindowAnimator: WindowAnimator {
    public init() {}
    public func animate(_ request: WindowAnimationRequest, commit: @escaping () -> Void) { commit() }
    public func isCovering(_ id: CGWindowID) -> Bool { false }
    public func beginDrag(_ id: CGWindowID, pointer: CGPoint, scene: WindowAnimationRequest) -> Bool { false }
    public func prepareClose(_ id: CGWindowID, scene: WindowAnimationRequest) -> Bool { false }
    public func updateDrag(pointer: CGPoint, dropTarget: CGRect?) {}
    public func endDrag() {}
    public func windowsChanged(visible: [AnimatedWindow]) {}
    public func cancel() {}
}
