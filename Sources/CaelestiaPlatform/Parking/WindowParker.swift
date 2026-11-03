import AppKit
import CaelestiaCore
import CoreGraphics
import Foundation

/// Moves windows of hidden workspaces off-screen and back, journaling every parked window first
/// (spec 4.1, 4.4, 10.10). Main thread only (AX calls).
public final class WindowParker {
    public let journal: ParkingJournal

    public init(journal: ParkingJournal = ParkingJournal()) {
        self.journal = journal
    }

    /// Parks `window` on `display`. `restoreFrame` is where it goes when its workspace is shown
    /// again (normally its current tiled/floating frame). The journal is written before the move;
    /// if the write fails the window is NOT parked (never risk a lost window).
    @discardableResult
    public func park(_ window: AXWindow, restoreFrame: CGRect, on display: DisplayInfo, allDisplays: [DisplayInfo]) -> Bool {
        let record = ParkedWindowRecord(
            windowID: window.windowID, pid: window.pid, bundleID: window.bundleID, title: window.title,
            restoreFrame: restoreFrame, displayID: display.id
        )
        do {
            try journal.upsert(record)
        } catch {
            Log.wm.error("not parking #\(window.windowID): journal write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let others = allDisplays.filter { $0.id != display.id }.map(\.frame)
        let parked = ParkingPlanner.parkedFrame(size: restoreFrame.size, on: display.frame, others: others)
        _ = window.setPosition(parked.origin)
        return true
    }

    /// Brings a parked window back to `frame` (or its journaled frame) and forgets the record.
    @discardableResult
    public func unpark(_ window: AXWindow, to frame: CGRect? = nil) -> CGRect {
        let target = frame ?? journal.record(for: window.windowID)?.restoreFrame ?? window.frame
        let result = window.setFrame(target)
        try? journal.remove(window.windowID)
        return result
    }

    public func isParked(_ windowID: CGWindowID) -> Bool {
        journal.record(for: windowID) != nil
    }

    /// Restores every journaled window to a visible frame: on launch after a crash, for the panic
    /// chord, `caelestia wm restore-all` and uninstall (R6). Windows are found by CGWindowID in
    /// their pid, else by bundle id + title among running apps. Records of windows that no longer
    /// exist are dropped. Returns the number of windows moved back.
    @discardableResult
    public func restoreAll(displays: [DisplayInfo]) -> Int {
        var restored = 0
        var appCache: [pid_t: [AXWindow]] = [:]
        func windows(of pid: pid_t) -> [AXWindow] {
            if let cached = appCache[pid] { return cached }
            let list = AXApplication(pid: pid)?.windows() ?? []
            appCache[pid] = list
            return list
        }
        for record in journal.records() {
            var match = windows(of: record.pid).first { $0.windowID == record.windowID }
            if match == nil {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: record.bundleID) {
                    match = windows(of: app.processIdentifier).first { $0.title == record.title }
                    if match != nil { break }
                }
            }
            guard let window = match else {
                try? journal.remove(record.windowID)
                continue
            }
            let frame = ParkingPlanner.restoreFrame(
                remembered: record.restoreFrame, preferredDisplay: record.displayID, displays: displays
            )
            _ = window.setFrame(frame)
            try? journal.remove(record.windowID)
            restored += 1
        }
        return restored
    }

    /// Brings back any managed window found off-screen even without a journal record (belt and
    /// braces for the panic chord). Returns the number of windows moved.
    @discardableResult
    public func rescueOffScreen(_ windows: [AXWindow], displays: [DisplayInfo]) -> Int {
        let frames = displays.map(\.frame)
        var moved = 0
        for window in windows {
            let frame = window.frame
            guard !frame.isNull, ParkingPlanner.isOffScreen(frame, displays: frames) else { continue }
            let remembered = journal.record(for: window.windowID)?.restoreFrame ?? CGRect(origin: .zero, size: frame.size)
            _ = window.setFrame(ParkingPlanner.restoreFrame(remembered: remembered, preferredDisplay: nil, displays: displays))
            try? journal.remove(window.windowID)
            moved += 1
        }
        return moved
    }
}
