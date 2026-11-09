import CaelestiaCore
import CoreGraphics
import Foundation

/// Latest-frame AX writes, one serial queue per app. The display link never waits on them, and
/// a slow app only delays its own queue. A newer frame replaces one that has not been written yet.
final class AsyncFrameWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [Int32: DispatchQueue] = [:]
    private var pending: [UInt32: CGRect] = [:]
    private var lastSent: [UInt32: CGRect] = [:]
    private var busy: Set<UInt32> = []

    func submit(id: UInt32, pid: Int32, frame: CGRect, perform: @escaping (CGRect, Bool) -> Void) {
        lock.lock()
        if let last = lastSent[id], pending[id] == nil, last.approximatelyEquals(frame, tolerance: 0.5), !busy.contains(id) {
            lock.unlock()
            return
        }
        pending[id] = frame
        let start = busy.insert(id).inserted
        lock.unlock()
        guard start else { return }
        queue(pid).async { [weak self] in self?.drain(id, perform) }
    }

    /// Runs on the same serial queue as this app's frame writes, after whatever is already queued.
    func sync(pid: Int32, _ work: @escaping () -> Void) {
        queue(pid).async(execute: work)
    }

    /// Like `sync`, after `seconds`. A min-size read waits here so a frame the app has not applied
    /// yet is not recorded as its minimum.
    func later(pid: Int32, seconds: Double, _ work: @escaping () -> Void) {
        queue(pid).asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func drain(_ id: UInt32, _ perform: (CGRect, Bool) -> Void) {
        while true {
            lock.lock()
            guard let wanted = pending.removeValue(forKey: id) else {
                busy.remove(id)
                lock.unlock()
                return
            }
            // The exact frame. A 2 pt cap made keyboard resizes take seconds, and a drag trailed
            // the cursor until it caught up. A newer frame that arrived during the write replaces
            // this one on the next loop, so a slow app jumps to the cursor instead of replaying
            // the points it missed. Size is written only when it changed: repeating it is what
            // makes the window server scale the old buffer.
            let write = Self.plan(last: lastSent[id], next: wanted)
            lastSent[id] = write.frame
            lock.unlock()
            perform(write.frame, write.resize)
        }
    }

    /// The frame to write, and whether the size attribute has to change. Position-only writes
    /// do not scale the window's buffer.
    static func plan(last: CGRect?, next: CGRect) -> (frame: CGRect, resize: Bool) {
        let resize = last.map {
            abs($0.width - next.width) > 0.5 || abs($0.height - next.height) > 0.5
        } ?? true
        return (next, resize)
    }

    private func queue(_ pid: Int32) -> DispatchQueue {
        if let existing = queues[pid] { return existing }
        let queue = DispatchQueue(label: "com.skyrose.mac.frames.\(pid)", qos: .userInteractive)
        queues[pid] = queue
        return queue
    }
}
