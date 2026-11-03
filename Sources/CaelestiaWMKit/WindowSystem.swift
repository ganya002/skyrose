import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
import CoreGraphics
import Foundation

/// One window the WM can move. `AXWindow` is the real implementation; tests use fakes so the whole
/// manager runs without a screen. All rects are CG/AX top-left global points.
@MainActor
public protocol WindowHandle: AnyObject {
    var windowID: WindowID { get }
    var pid: pid_t { get }
    var bundleID: String { get }
    var title: String { get }
    /// Current frame; `.null` when it cannot be read (gone or hung app).
    var frame: CGRect { get }
    /// Moves and resizes; returns the frame read back (apps may clamp to a minimum size).
    @discardableResult func setFrame(_ target: CGRect) -> CGRect
    /// Moves without resizing; returns the origin read back.
    @discardableResult func setPosition(_ origin: CGPoint) -> CGPoint
    @discardableResult func focus() -> Bool
    @discardableResult func raise() -> Bool
    @discardableResult func close() -> Bool
    func descriptor() -> WindowDescriptor
}

/// What the window system reports to the manager (main thread).
public enum WindowSystemEvent {
    case created(any WindowHandle)
    case destroyed(WindowID)
    case focused(WindowID?)
    /// The window moved or resized. `isEcho` marks notifications caused by our own setFrame.
    case frameChanged(WindowID, frame: CGRect, isEcho: Bool)
    case minimized(WindowID)
    case deminiaturized(WindowID)
    case appHidden(pid_t)
    case appShown(pid_t)
    case appTerminated(pid_t)
}

/// Window discovery + lookups. `AXWindowSystem` wraps `WindowDiscovery`.
@MainActor
public protocol WindowSystem: AnyObject {
    var onEvent: ((WindowSystemEvent) -> Void)? { get set }
    /// Starts discovery; every existing window is announced with `.created`.
    func start()
    func stop()
    /// Every tracked window.
    var allWindows: [any WindowHandle] { get }
    var focusedWindowID: WindowID? { get }
    /// Pointer location in top-left space.
    var cursorLocation: CGPoint? { get }
    /// The tracked window top-most under the pointer.
    func windowUnderCursor() -> WindowID?
    /// Finds a journaled window after a WM crash: by window id in its pid, else by bundle id and
    /// title among running apps. Works before `start()`.
    func findWindow(for record: ParkedWindowRecord) -> (any WindowHandle)?
}

/// The live display list.
@MainActor
public protocol DisplayProvider: AnyObject {
    var displays: [DisplayInfo] { get }
    var onChange: (([DisplayInfo]) -> Void)? { get set }
    func start()
    func stop()
}
