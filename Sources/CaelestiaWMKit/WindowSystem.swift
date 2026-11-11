import AppKit
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
    /// Keyboard focus. `raise` false still focuses the window but leaves it under whatever is already
    /// above it (hover focus, unless `raiseOnHover`).
    @discardableResult func focus(raise: Bool) -> Bool
    @discardableResult func raise() -> Bool
    @discardableResult func close() -> Bool
    func descriptor() -> WindowDescriptor
    /// The red close button's frame (top-left space), nil without one.
    func closeButtonFrame() -> CGRect?
}

extension WindowHandle {
    public func closeButtonFrame() -> CGRect? { nil }
    @discardableResult
    public func focus() -> Bool { focus(raise: true) }
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
    /// The left mouse button is held right now (the user may be dragging or resizing a window by
    /// its title bar or edge: frame changes then come from the user, not the app).
    var isLeftMouseDown: Bool { get }
    /// Any mouse button is held right now.
    var isMouseButtonDown: Bool { get }
    /// On-screen windows front to back, without SkyRose's own.
    func windowStack() -> [CGWindowSnapshot]
    /// The tracked window top-most under the pointer.
    func windowUnderCursor() -> WindowID?
    /// Finds a journaled window after a WM crash: by window id in its pid, else by bundle id and
    /// title among running apps. Works before `start()`.
    func findWindow(for record: ParkedWindowRecord) -> (any WindowHandle)?
    /// How many windows the app itself lists (AX `kAXWindows`, minimized ones included); nil
    /// when it cannot be read.
    func appWindowCount(pid: pid_t) -> Int?
}

extension WindowSystem {
    public func appWindowCount(pid: pid_t) -> Int? { nil }
}

/// Quits apps for `wm.closeQuitsApp`. Never force-quits.
@MainActor
public protocol AppTerminator: AnyObject {
    /// A running regular (Dock) app: menu-bar / background apps are never quit by the red button.
    func isRegularApp(pid: pid_t) -> Bool
    /// A normal quit (`NSRunningApplication.terminate()`): the app may ask to save or refuse.
    @discardableResult func terminate(pid: pid_t) -> Bool
}

/// The real `AppTerminator`.
@MainActor
public final class SystemAppTerminator: AppTerminator {
    public init() {}
    public func isRegularApp(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        return app.activationPolicy == .regular
    }
    public func terminate(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
    }
}

/// The live display list.
@MainActor
public protocol DisplayProvider: AnyObject {
    var displays: [DisplayInfo] { get }
    var onChange: (([DisplayInfo]) -> Void)? { get set }
    func start()
    func stop()
}
