import CoreServices
import Foundation

/// Keeps the launcher's app list current: a live Spotlight query for every
/// `com.apple.application-bundle` plus an FSEvents stream on the app folders (so installs still
/// show up when Spotlight indexing is off). Each change calls `onChange` once, debounced.
@MainActor
public final class AppIndexWatcher {
    /// App paths Spotlight reported in its last result set (unfiltered; `AppIndex.scan` filters).
    public private(set) var spotlightURLs: [URL] = []
    public var onChange: (() -> Void)?
    public static let debounce: TimeInterval = 1.0

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    public init() {}

    public static let predicate = NSPredicate(format: "kMDItemContentTypeTree == 'com.apple.application-bundle'")

    public func start(roots: [URL] = AppIndex.searchRoots) {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.predicate = Self.predicate
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.collect() }
            })
        }
        query = q
        q.start()
        startFSEvents(roots)
    }

    public func stop() {
        query?.stop()
        query = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        pending?.cancel()
    }

    private func collect() {
        guard let q = query else { return }
        q.disableUpdates()
        var urls: [URL] = []
        urls.reserveCapacity(q.resultCount)
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            urls.append(URL(fileURLWithPath: path))
        }
        q.enableUpdates()
        spotlightURLs = urls
        changed()
    }

    /// Debounced: an install writes many files; one rescan follows the burst.
    func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }

    private func startFSEvents(_ roots: [URL]) {
        let paths = roots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) } as CFArray
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<AppIndexWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { watcher.changed() } }
        }
        guard let s = FSEventStreamCreate(nil, callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          2.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
        stream = s
    }
}
