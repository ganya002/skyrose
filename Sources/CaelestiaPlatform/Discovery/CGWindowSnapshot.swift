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
