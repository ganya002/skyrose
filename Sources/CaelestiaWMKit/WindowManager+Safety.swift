import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
import CoreGraphics
import Foundation

/// Window safety (spec 4.4, 10.10, R6): every path that ends management brings every window back
/// to a visible frame and empties the journal.
extension WindowManager {
    /// Replays the parking journal: every journaled window found (tracked, or looked up by the
    /// window system) is moved to a visible frame; records of windows that no longer exist are
    /// dropped. Returns the number of windows moved back.
    @discardableResult
    func restoreJournal() -> Int {
        var restored = 0
        for record in journal.records() {
            if let handle = handles[record.windowID] ?? windowSystem.findWindow(for: record) {
                let frame = ParkingPlanner.restoreFrame(
                    remembered: record.restoreFrame, preferredDisplay: record.displayID, displays: displays
                )
                counters.setFrameCalls += 1
                handle.setFrame(frame)
                applied[record.windowID] = nil
                restored += 1
            }
            parked[record.windowID] = nil
            try? journal.remove(record.windowID)
        }
        return restored
    }

    /// Stops managing and brings every window on-screen: parked windows go back to their last
    /// visible frame, the rest of the journal is replayed, and any tracked window still found
    /// off-screen is rescued. Returns the number of windows moved.
    @discardableResult
    public func restoreEverything() -> Int {
        isManaging = false
        decorations?.removeAll()  // R2: no border outlives management
        lastSceneIDs = []
        var restored = restoreJournal()
        let frames = displays.map(\.frame)
        for id in handles.keys.sorted() {
            guard let handle = handles[id] else { continue }
            let frame = handle.frame
            guard !frame.isNull, !displays.isEmpty, ParkingPlanner.isOffScreen(frame, displays: frames) else { continue }
            let remembered = applied[id] ?? CGRect(origin: .zero, size: frame.size)
            counters.setFrameCalls += 1
            handle.setFrame(ParkingPlanner.restoreFrame(remembered: remembered, preferredDisplay: nil, displays: displays))
            restored += 1
        }
        parked.removeAll()
        return restored
    }

    /// `wm.restoreAll`: brings every parked window back without quitting by moving the windows of
    /// hidden workspaces onto the visible numbered workspace of their display (inactive group tabs
    /// stay grouped), then replays any journal records for windows the WM does not track.
    public func restoreAllKeepingManagement() {
        for id in managedWindowIDs {
            guard let wsID = state.workspace(of: id), !state.isVisible(wsID), let ws = state[wsID],
                  let n = state.activeNumberedWorkspace(forDisplay: ws.displayID) else { continue }
            state.moveWindow(id, to: .numbered(n), follow: false, env: environment)
        }
        for record in journal.records() where handles[record.windowID] == nil {
            if let handle = windowSystem.findWindow(for: record) {
                counters.setFrameCalls += 1
                handle.setFrame(ParkingPlanner.restoreFrame(
                    remembered: record.restoreFrame, preferredDisplay: record.displayID, displays: displays
                ))
            }
            try? journal.remove(record.windowID)
        }
        setNeedsLayout()
    }
}
