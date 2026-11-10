import CoreGraphics
import Foundation

/// One entry of `CGWindowListCopyWindowInfo`, already parsed. Bounds are in CG top-left space.
public struct CGWindowSnapshot: Equatable, Hashable, Sendable, Identifiable {
    public var id: CGWindowID
    public var pid: pid_t
    public var layer: Int
    public var bounds: CGRect
    public var alpha: Double
    public var ownerName: String
    public var isOnScreen: Bool

    public init(
        id: CGWindowID, pid: pid_t, layer: Int = 0, bounds: CGRect, alpha: Double = 1, ownerName: String = "",
        isOnScreen: Bool = true
    ) {
        self.id = id
        self.pid = pid
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
        self.ownerName = ownerName
        self.isOnScreen = isOnScreen
    }

    /// Normal application windows live on layer 0 (kCGNormalWindowLevel).
    public var isNormalLayer: Bool { layer == 0 }

    /// Parses raw window-info dictionaries (order preserved: front to back).
    public static func parse(_ infos: [[String: Any]]) -> [CGWindowSnapshot] {
        infos.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let pid = info[kCGWindowOwnerPID as String] as? NSNumber
            else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            return CGWindowSnapshot(
                id: CGWindowID(truncatingIfNeeded: number.int64Value),
                pid: pid_t(truncatingIfNeeded: pid.int64Value),
                layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                bounds: bounds,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                ownerName: (info[kCGWindowOwnerName as String] as? String) ?? "",
                isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            )
        }
    }

    /// Live query. `onScreenOnly` lists the current Space's visible windows front-to-back; otherwise
    /// every window of the session, including minimized ones and other Spaces.
    public static func current(onScreenOnly: Bool) -> [CGWindowSnapshot] {
        var options: CGWindowListOption = [.excludeDesktopElements]
        if onScreenOnly { options.insert(.optionOnScreenOnly) } else { options.insert(.optionAll) }
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return parse(infos)
    }

    /// On-screen layer-0 windows, front to back.
    public static func onScreenNormalWindows() -> [CGWindowSnapshot] {
        current(onScreenOnly: true).filter(\.isNormalLayer)
    }
}

/// What the pointer is really over, read from the on-screen stack (front to back).
public enum PointerHit: Equatable, Sendable {
    /// The topmost normal window.
    case window(CGWindowID)
    /// System UI, a menu, a popover, a floating panel, or a window's border: focus stays put.
    case blocked
    /// The desktop.
    case nothing
}

extension CGWindowSnapshot {
    /// Owners whose high-layer windows are system UI even when they are not menu-level.
    private static let systemOwners: Set<String> = [
        "Dock", "Spotlight", "Control Center", "Notification Center", "SystemUIServer", "WindowManager", "MenuBarAgent",
    ]

    /// Layer 101 is `kCGPopUpMenuWindowLevel` (menus and popovers). Layers 1...24 are floating panels and the Dock.
    /// Layers 25...100 from an ordinary app are not treated as UI: Hex keeps invisible overlays there.
    private var isPointerUI: Bool {
        layer >= 101 || (1...24).contains(layer) || Self.systemOwners.contains(ownerName)
    }

    /// Topmost-first hit test. `stack` excludes our own windows. A window covering nearly a whole
    /// display above layer 0 is an overlay, not UI, so it is looked through.
    public static func hit(at point: CGPoint, stack: [CGWindowSnapshot], borderWidth: CGFloat = 0, displayArea: CGFloat = 0) -> PointerHit {
        for w in stack where w.alpha >= 0.05 && w.ownerName != "Window Server" && w.layer >= 0 {
            if w.layer > 0 {
                guard w.bounds.contains(point), w.isPointerUI else { continue }
                if displayArea > 0, w.bounds.width * w.bounds.height >= displayArea * 0.6 { continue }
                return .blocked
            }
            if w.bounds.contains(point) { return .window(w.id) }
            if borderWidth > 0, w.bounds.insetBy(dx: -borderWidth, dy: -borderWidth).contains(point) { return .blocked }
        }
        return .nothing
    }
}
