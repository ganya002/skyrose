import Foundation
import CoreGraphics

/// What the rule engine and the layout engine know about a window, independent of AppKit/AX.
public struct WindowDescriptor: Hashable, Sendable, Codable {
    public var bundleID: String
    public var appName: String
    public var title: String
    /// AXRole (AXWindow) and AXSubrole (AXStandardWindow, AXDialog, AXSystemDialog, AXFloatingWindow, AXUnknown...).
    public var role: String
    public var subrole: String
    /// LSApplicationCategoryType of the app bundle (public.app-category.games etc.), empty if unknown.
    public var category: String
    public var pid: Int32
    public var windowID: UInt32
    public var isResizable: Bool
    public var isMovable: Bool
    public var isMinimized: Bool
    public var isNativeFullscreen: Bool
    public var isModal: Bool
    public var minSize: CGSize?
    public var maxSize: CGSize?

    public init(
        bundleID: String, appName: String = "", title: String = "", role: String = "AXWindow",
        subrole: String = "AXStandardWindow", category: String = "", pid: Int32 = 0, windowID: UInt32 = 0,
        isResizable: Bool = true, isMovable: Bool = true, isMinimized: Bool = false,
        isNativeFullscreen: Bool = false, isModal: Bool = false, minSize: CGSize? = nil, maxSize: CGSize? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.role = role
        self.subrole = subrole
        self.category = category
        self.pid = pid
        self.windowID = windowID
        self.isResizable = isResizable
        self.isMovable = isMovable
        self.isMinimized = isMinimized
        self.isNativeFullscreen = isNativeFullscreen
        self.isModal = isModal
        self.minSize = minSize
        self.maxSize = maxSize
    }

    /// Section 4.5 xwl_popup mapping: anything that is not a standard window is never tiled,
    /// gets no border overlay and never steals focus.
    public var isStandardWindow: Bool { role == "AXWindow" && subrole == "AXStandardWindow" }

    public var isDialogLike: Bool {
        ["AXDialog", "AXSystemDialog", "AXFloatingWindow", "AXSheet", "AXPopover", "AXSystemFloatingWindow"].contains(subrole)
            || role == "AXSheet" || role == "AXPopover" || isModal
    }

    /// Windows that cannot resize (no settable size, or min == max) float, centered.
    public var isFixedSize: Bool {
        if !isResizable { return true }
        if let mn = minSize, let mx = maxSize, mn.width >= mx.width, mn.height >= mx.height { return true }
        return false
    }
}
