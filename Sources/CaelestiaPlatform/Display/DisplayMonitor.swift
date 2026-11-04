import AppKit
import CaelestiaCore
import CoreGraphics
import Foundation

/// Live display list. Reads `NSScreen.screens`, converts them with ``DisplayGeometry`` and calls
/// `onChange` (debounced) whenever the arrangement, resolution, menu-bar or Dock auto-hide changes
/// (spec 4.6). Main thread only.
public final class DisplayMonitor: NSObject {
    /// Receives the new display list on the main thread.
    public var onChange: (([DisplayInfo]) -> Void)?
    /// Bursts of screen notifications (e.g. a display waking up) are collapsed into one change.
    public var debounceInterval: TimeInterval = 0.1

    public private(set) var displays: [DisplayInfo] = []
    public private(set) var converter = CoordinateConverter(primaryHeight: 0)

    private var centers: [NotificationCenter] = []
    private let debounce = DelayedMainTask()

    override public init() {}

    deinit { stop() }

    /// Takes the first snapshot and starts observing.
    public func start() {
        refresh(notify: false)
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification)
        observe(workspace, NSWorkspace.didWakeNotification)
        // Dock position / auto-hide and menu-bar auto-hide changes.
        observe(distributed, Notification.Name("com.apple.dock.prefchanged"))
        observe(distributed, Notification.Name("AppleInterfaceMenuBarHidingChangedNotification"))
    }

    public func stop() {
        for center in centers { center.removeObserver(self) }
        centers.removeAll()
        debounce.cancel()
    }

    /// Re-reads the screens now; notifies only when something changed.
    public func refresh(notify: Bool = true) {
        let facts = Self.currentScreens()
        let next = DisplayGeometry.displays(from: facts)
        converter = DisplayGeometry.converter(for: facts)
        guard next != displays else { return }
        displays = next
        if notify { onChange?(next) }
    }

    /// The display under the mouse pointer (top-left space).
    public func displayUnderPointer() -> DisplayInfo? {
        DisplayGeometry.display(containing: converter.toTopLeft(NSEvent.mouseLocation), in: displays)
    }

    /// Facts for every connected screen, primary first.
    public static func currentScreens() -> [DisplayGeometry.ScreenFacts] {
        let autoHides = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
        return NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = number?.uint32Value ?? 0
            return DisplayGeometry.ScreenFacts(
                uuid: stableID(for: displayID), displayID: displayID, name: screen.localizedName,
                frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top,
                scale: screen.backingScaleFactor, auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                auxiliaryTopRight: screen.auxiliaryTopRightArea, menuBarAutoHides: autoHides
            )
        }
    }

    /// `CGDisplayCreateUUIDFromDisplayID` as a string; survives reconnects and reboots. Falls back
    /// to the numeric id if the UUID is unavailable.
    public static func stableID(for displayID: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return "display-\(displayID)" }
        return string
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        center.addObserver(self, selector: #selector(screensMayHaveChanged(_:)), name: name, object: nil)
        if !centers.contains(where: { $0 === center }) { centers.append(center) }
    }

    @objc private func screensMayHaveChanged(_ notification: Notification) {
        // Distributed notifications arrive on the main thread for an app with a main run loop.
        debounce.schedule(after: debounceInterval) { [weak self] in self?.refresh() }
    }
}
