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

    func submit(id: UInt32, pid: Int32, frame: CGRect, perform: @escaping (CGRect) -> Void) {
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

    private func drain(_ id: UInt32, _ perform: (CGRect) -> Void) {
        while true {
            lock.lock()
            guard let wanted = pending.removeValue(forKey: id) else {
                busy.remove(id)
                lock.unlock()
                return
            }
            // One step only. A newer frame that arrived during the write is picked up next
            // loop; the rest of a jump waits for the next display tick so the app can paint.
            let frame = Self.step(lastSent[id], toward: wanted, max: 2)
            lastSent[id] = frame
            lock.unlock()
            perform(frame)
        }
    }

    /// At most `max` points on each edge. A bigger jump is what macOS paints as a scaled,
    /// blurred frame until the app redraws.
    static func step(_ from: CGRect?, toward: CGRect, max: Double) -> CGRect {
        guard let from else { return toward }
        func axis(_ value: Double, _ was: Double) -> Double {
            let d = value - was
            if abs(d) <= max { return value }
            return was + max * (d < 0 ? -1 : 1)
        }
        return CGRect(
            x: axis(toward.minX, from.minX), y: axis(toward.minY, from.minY),
            width: axis(toward.width, from.width), height: axis(toward.height, from.height)
        )
    }

    private func queue(_ pid: Int32) -> DispatchQueue {
        if let existing = queues[pid] { return existing }
        let queue = DispatchQueue(label: "com.skyrose.mac.frames.\(pid)", qos: .userInteractive)
        queues[pid] = queue
        return queue
    }
}
