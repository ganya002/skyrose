import AppKit
import ApplicationServices
import CaelestiaCore
import CoreGraphics
import Foundation

/// Pure helpers that turn raw AX role/subrole strings into the vocabulary `WindowDescriptor` uses.
public enum AXRoleMapping {
    public static let unknown = "AXUnknown"

    /// Normalises missing/empty role and subrole strings to `AXUnknown`. Windows without a subrole
    /// (some Java/Qt apps) are deliberately NOT promoted to standard windows: the rule engine
    /// treats `AXUnknown` as "never tile" (section 4.5), which is the safe default.
    public static func normalize(role: String?, subrole: String?) -> (role: String, subrole: String) {
        let role = role.flatMap { $0.isEmpty ? nil : $0 } ?? unknown
        let subrole = subrole.flatMap { $0.isEmpty ? nil : $0 } ?? unknown
        return (role, subrole)
    }

    /// A tileable top-level window: role AXWindow with subrole AXStandardWindow.
    public static func isStandardWindow(role: String?, subrole: String?) -> Bool {
        let n = normalize(role: role, subrole: subrole)
        return n.role == kAXWindowRole && n.subrole == kAXStandardWindowSubrole
    }

    /// Dialog-like windows (sheets, popovers, floating panels, system dialogs) per `WindowDescriptor.isDialogLike`.
    public static func isDialogLike(role: String?, subrole: String?, isModal: Bool = false) -> Bool {
        let n = normalize(role: role, subrole: subrole)
        return WindowDescriptor(bundleID: "", role: n.role, subrole: n.subrole, isModal: isModal).isDialogLike
    }
}

/// Static facts about a running application that never change for its lifetime.
public struct AppInfo: Equatable, Sendable {
    public var bundleID: String
    public var name: String
    /// `LSApplicationCategoryType` from the bundle's Info.plist, empty when unknown.
    public var category: String

    public init(bundleID: String, name: String, category: String) {
        self.bundleID = bundleID
        self.name = name
        self.category = category
    }
}

/// Caches `LSApplicationCategoryType` per bundle URL (reading Info.plist is a disk access).
public final class AppInfoCache: @unchecked Sendable {
    public static let shared = AppInfoCache()

    private let lock = NSLock()
    private var categories: [URL: String] = [:]

    public init() {}

    /// Info for `pid`, or `nil` when the process is not a LaunchServices-visible application.
    public func info(for pid: pid_t) -> AppInfo? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return info(for: app)
    }

    public func info(for app: NSRunningApplication) -> AppInfo {
        AppInfo(
            bundleID: app.bundleIdentifier ?? "",
            name: app.localizedName ?? "",
            category: app.bundleURL.map(category(forBundleAt:)) ?? ""
        )
    }

    public func category(forBundleAt url: URL) -> String {
        lock.lock()
        if let cached = categories[url] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let category = (Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String) ?? ""
        lock.lock()
        categories[url] = category
        lock.unlock()
        return category
    }
}

/// A top-level window of another application, addressed through the Accessibility API.
///
/// Frames are in CG/AX global top-left space (the space AX natively uses; no conversion happens
/// here). Identity is the `CGWindowID`. All methods are synchronous IPC to the owning app; use
/// them from the main thread.
public final class AXWindow: Hashable, Identifiable, CustomStringConvertible {
    public let element: AXElement
    public let windowID: CGWindowID
    public let pid: pid_t
    public let bundleID: String
    /// The owning application's element (local object, no IPC to create).
    public let appElement: AXElement

    /// Called by `setFrame`/`setPosition` with the frames the window was asked to take and the one it
    /// reported back, so `WindowDiscovery` can tag the resulting AX move/resize notifications as echoes.
    public var frameExpectationSink: ((CGWindowID, CGRect) -> Void)?
    /// While SkyRose is driving frames, AppKit must not animate them. Turning
    /// `AXEnhancedUserInterface` back on makes the next size change scale and blur.
    private let animationLock = NSLock()
    private var holdFrameAnimationOff = false

    public var id: CGWindowID { windowID }

    /// Fails when the element has no CG window id (not a real window yet, or the private symbol is missing).
    public convenience init?(element: AXElement) {
        guard let windowID = element.windowID else { return nil }
        self.init(element: element, windowID: windowID)
    }

    public init(element: AXElement, windowID: CGWindowID) {
        self.element = element
        self.windowID = windowID
        self.pid = element.pid
        self.appElement = .application(pid: element.pid)
        self.bundleID = NSRunningApplication(processIdentifier: element.pid)?.bundleIdentifier ?? ""
    }

    public static func == (lhs: AXWindow, rhs: AXWindow) -> Bool { lhs.windowID == rhs.windowID }
    public func hash(into hasher: inout Hasher) { hasher.combine(windowID) }
    public var description: String { "AXWindow(#\(windowID) pid \(pid) \(bundleID))" }

    // MARK: - Geometry

    /// Current frame in top-left global space; `.null` when it cannot be read (gone/hung app).
    public var frame: CGRect {
        get { element.rect() ?? .null }
        set { setFrame(newValue) }
    }

    /// Frame read with the failure reason preserved.
    public func readFrame() -> Result<CGRect, AXFailure> { element.rectResult() }

    /// The next AX frame changes must be instant. One attribute write, no read-back.
    /// Live resize calls this off the main thread, before the frames, and leaves it off
    /// until SkyRose quits: turning it back on is what scales the window.
    public func suppressSystemFrameAnimation() {
        animationLock.lock()
        holdFrameAnimationOff = true
        animationLock.unlock()
        let attribute = AXElement.enhancedUserInterfaceAttribute
        if appElement.bool(attribute) == true { appElement.setBool(attribute, false) }
    }

    /// Set on the main thread before the background write, so a `setFrame` on main cannot
    /// turn the animation back on in the gap.
    public func holdSystemFrameAnimationOff() {
        animationLock.lock()
        holdFrameAnimationOff = true
        animationLock.unlock()
    }

    public func releaseSystemFrameAnimationHold() {
        animationLock.lock()
        holdFrameAnimationOff = false
        animationLock.unlock()
    }

    /// Puts `AXEnhancedUserInterface` back. Only SkyRose's shutdown calls this.
    public func restoreSystemFrameAnimation() {
        appElement.setBool(AXElement.enhancedUserInterfaceAttribute, true)
    }

    private var systemFrameAnimationHeldOff: Bool {
        animationLock.lock()
        defer { animationLock.unlock() }
        return holdFrameAnimationOff
    }

    /// Moves and resizes the window: size, then position, then size again (the second size
    /// write handles apps that clamp to a minimum size or reject the first write). Returns the
    /// frame read back afterwards, which may differ from `target` (min size, screen clamping).
    /// Unchanged frames (within 0.5 pt) are not written. Apps with `AXEnhancedUserInterface`
    /// (Chrome/Electron) get it switched off for the write. A live resize holds it off so the
    /// window is never scaled.
    @discardableResult
    public func setFrame(_ target: CGRect) -> CGRect {
        let target = target.integralPoints
        let before = frame
        if !before.isNull, before.approximatelyEquals(target, tolerance: 0.5) { return before }
        let result = withEnhancedUserInterfaceDisabled { () -> CGRect in
            if before.isNull || before.size != target.size { element.setSize(kAXSizeAttribute, target.size) }
            element.setPoint(kAXPositionAttribute, target.origin)
            element.setSize(kAXSizeAttribute, target.size)
            return element.rect() ?? target
        }
        publishExpectation(target, readBack: result)
        return result
    }

    /// Moves the window without touching its size. Returns the origin read back (macOS may clamp).
    @discardableResult
    public func setPosition(_ origin: CGPoint) -> CGPoint {
        let origin = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        let before = frame
        let result = withEnhancedUserInterfaceDisabled { () -> CGPoint in
            element.setPoint(kAXPositionAttribute, origin)
            return element.point(kAXPositionAttribute) ?? origin
        }
        let size = before.isNull ? (element.size(kAXSizeAttribute) ?? .zero) : before.size
        publishExpectation(CGRect(origin: origin, size: size), readBack: CGRect(origin: result, size: size))
        return result
    }

    private func publishExpectation(_ target: CGRect, readBack: CGRect) {
        guard let sink = frameExpectationSink else { return }
        sink(windowID, readBack)
        if !readBack.approximatelyEquals(target, tolerance: 0.5) { sink(windowID, target) }
    }

    private func withEnhancedUserInterfaceDisabled<T>(_ body: () -> T) -> T {
        let attribute = AXElement.enhancedUserInterfaceAttribute
        let wasEnhanced = appElement.bool(attribute) == true
        if wasEnhanced { appElement.setBool(attribute, false) }
        defer { if wasEnhanced, !systemFrameAnimationHeldOff { appElement.setBool(attribute, true) } }
        return body()
    }

    // MARK: - Properties

    public var title: String { element.title ?? "" }
    public var role: String { element.role ?? "" }
    public var subrole: String { element.subrole ?? "" }

    public var isMinimized: Bool { element.bool(kAXMinimizedAttribute) ?? false }

    @discardableResult
    public func setMinimized(_ minimized: Bool) -> Bool {
        element.setBool(kAXMinimizedAttribute, minimized) == nil
    }

    /// Native (green button) fullscreen state.
    public var isNativeFullscreen: Bool { element.bool(AXElement.fullScreenAttribute) ?? false }

    @discardableResult
    public func setNativeFullscreen(_ fullscreen: Bool) -> Bool {
        element.setBool(AXElement.fullScreenAttribute, fullscreen) == nil
    }

    public var isModal: Bool { element.bool(kAXModalAttribute) ?? false }
    public var isResizable: Bool { element.isSettable(kAXSizeAttribute) }
    public var isMovable: Bool { element.isSettable(kAXPositionAttribute) }

    /// AX does not expose size limits; the WM infers a minimum when `setFrame` reads back larger.
    public var minSize: CGSize? { nil }
    /// AX does not expose size limits.
    public var maxSize: CGSize? { nil }

    /// True while the window still exists in its app.
    public var isAlive: Bool { element.isValid }

    /// Role AXWindow + subrole AXStandardWindow (one IPC per attribute).
    public var isStandard: Bool { AXRoleMapping.isStandardWindow(role: element.role, subrole: element.subrole) }

    // MARK: - Actions

    /// Brings the window to the front within its app (kAXRaiseAction).
    @discardableResult
    public func raise() -> Bool {
        element.perform(kAXRaiseAction) == nil
    }

    /// Makes this the app's focused + main window, raises it and activates the app.
    @discardableResult
    public func focus() -> Bool {
        var ok = appElement.setAttribute(kAXFocusedWindowAttribute, element.ref) == nil
        element.setBool(kAXMainAttribute, true)
        ok = raise() && ok
        if let app = NSRunningApplication(processIdentifier: pid), !app.isActive {
            // activateIgnoringOtherApps is a no-op since macOS 14; plain activation is honoured for
            // Accessibility-trusted clients, which is what AeroSpace relies on too.
            ok = app.activate(options: []) && ok
        }
        return ok
    }

    /// The close button's frame in top-left global space (one AX read per attribute).
    public func closeButtonFrame() -> CGRect? {
        guard let button = element.element(kAXCloseButtonAttribute),
              let origin = button.point(kAXPositionAttribute), let size = button.size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Presses the window's close button (the app may show "save changes?" and keep the window).
    @discardableResult
    public func close() -> Bool {
        guard let button = element.element(kAXCloseButtonAttribute) else { return false }
        return button.perform(kAXPressAction) == nil
    }

    /// Snapshot for the rule/layout engines (6 attribute reads + 2 settable checks).
    public func descriptor() -> WindowDescriptor {
        let info = AppInfoCache.shared.info(for: pid)
        let roles = AXRoleMapping.normalize(role: element.role, subrole: element.subrole)
        return WindowDescriptor(
            bundleID: info?.bundleID ?? bundleID,
            appName: info?.name ?? "",
            title: title,
            role: roles.role,
            subrole: roles.subrole,
            category: info?.category ?? "",
            pid: pid,
            windowID: windowID,
            isResizable: isResizable,
            isMovable: isMovable,
            isMinimized: isMinimized,
            isNativeFullscreen: isNativeFullscreen,
            isModal: isModal,
            minSize: minSize,
            maxSize: maxSize
        )
    }
}
