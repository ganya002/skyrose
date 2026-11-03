import Foundation

/// A unit of work that is created and run on the main thread only. It exists so main-thread
/// confined objects can schedule delayed work on the main queue without every capture having to
/// be `Sendable`: the box crosses the (trivial) main → main hop, the closure never leaves it.
final class MainThreadWork: @unchecked Sendable {
    private let block: () -> Void

    init(_ block: @escaping () -> Void) {
        self.block = block
    }

    func run() {
        block()
    }
}

/// A cancellable, main-thread delayed task (used for debouncing and retry backoff).
final class DelayedMainTask {
    private var item: DispatchWorkItem?

    init() {}

    /// Cancels any pending run and schedules `block` after `delay` seconds on the main queue.
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        cancel()
        let work = MainThreadWork(block)
        let item = DispatchWorkItem { work.run() }
        self.item = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    var isPending: Bool { item.map { !$0.isCancelled } ?? false }

    func cancel() {
        item?.cancel()
        item = nil
    }
}

/// Runs `block` on the main queue after `delay` seconds. Fire-and-forget variant of `DelayedMainTask`.
func onMainAfter(_ delay: TimeInterval, _ block: @escaping () -> Void) {
    let work = MainThreadWork(block)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work.run() }
}

/// Runs `block` on the main thread: synchronously when already there, otherwise asynchronously.
func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        let work = MainThreadWork(block)
        DispatchQueue.main.async { work.run() }
    }
}
