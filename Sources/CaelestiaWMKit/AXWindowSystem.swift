import AppKit
import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
import CoreGraphics
import Foundation

extension AXWindow: WindowHandle {}

extension DisplayMonitor: DisplayProvider {}

/// The real window system: `WindowDiscovery` (NSWorkspace + AXObserver + CG reconcile). Echo
/// tagging comes from discovery's `FrameEchoFilter`, fed by every tracked `AXWindow`'s writes.
@MainActor
public final class AXWindowSystem: WindowSystem {
    public let discovery = WindowDiscovery()
    public var onEvent: ((WindowSystemEvent) -> Void)?

    public init() {
        discovery.onEvent = { [weak self] event in
            // WindowDiscovery delivers on the main thread.
            MainActor.assumeIsolated { self?.forward(event) }
        }
    }

    public func start() { discovery.start() }
    public func stop() { discovery.stop() }

    public var allWindows: [any WindowHandle] { Array(discovery.windows.values) }
    public var focusedWindowID: WindowID? { discovery.focusedWindowID }
    public var cursorLocation: CGPoint? { CGEvent(source: nil)?.location }
    public var isLeftMouseDown: Bool { CGEventSource.buttonState(.combinedSessionState, button: .left) }

    public func windowUnderCursor() -> WindowID? {
        cursorLocation.flatMap { discovery.windowUnder(point: $0) }?.windowID
    }

    public func appWindowCount(pid: pid_t) -> Int? {
        AXApplication(pid: pid).map { $0.windows().count }
    }

    public func findWindow(for record: ParkedWindowRecord) -> (any WindowHandle)? {
        if let w = discovery.window(for: record.windowID) { return w }
        if let w = AXApplication(pid: record.pid)?.windows().first(where: { $0.windowID == record.windowID }) { return w }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: record.bundleID) {
            if let w = AXApplication(runningApplication: app).windows().first(where: { $0.title == record.title }) { return w }
        }
        return nil
    }

    private func forward(_ event: WindowDiscovery.WindowEvent) {
        let mapped: WindowSystemEvent?
        switch event {
        case .created(let w): mapped = .created(w)
        case .destroyed(let id): mapped = .destroyed(id)
        case .focused(let w): mapped = .focused(w?.windowID)
        case .moved(let w, let frame, let isEcho), .resized(let w, let frame, let isEcho):
            mapped = .frameChanged(w.windowID, frame: frame, isEcho: isEcho)
        case .minimized(let w): mapped = .minimized(w.windowID)
        case .deminiaturized(let w): mapped = .deminiaturized(w.windowID)
        case .appHidden(let pid): mapped = .appHidden(pid)
        case .appShown(let pid): mapped = .appShown(pid)
        case .appTerminated(let pid): mapped = .appTerminated(pid)
        case .titleChanged, .appActivated: mapped = nil
        }
        if let mapped { onEvent?(mapped) }
    }
}
