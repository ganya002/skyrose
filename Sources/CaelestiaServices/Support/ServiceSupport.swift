import Foundation
import CaelestiaCore

/// Errors shared by the services. Each case carries a human-readable reason that the shell can
/// show verbatim (toasts, "unavailable" chips).
public enum ServiceError: Error, LocalizedError, Equatable, Sendable {
    /// A TCC permission (Screen Recording, Microphone, Location, Automation) is missing.
    case permissionMissing(String)
    /// The hardware or system service is not present on this Mac (no battery, no Wi-Fi card, ...).
    case unavailable(String)
    /// A system call failed; `message` is the OSStatus/IOReturn/NSError description.
    case failed(String)
    /// A network request failed or returned an unexpected payload.
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .permissionMissing(let what): return "\(what) permission is missing"
        case .unavailable(let what): return what
        case .failed(let message): return message
        case .network(let message): return message
        }
    }
}

/// Small JSON persistence helper for the services' state files in
/// `~/Library/Application Support/SkyRose`. Writes are atomic; a missing or corrupt file
/// reads as `nil` so a bad file can never stop a service from starting.
public enum ServiceStorage {
    /// Returns `Paths.appSupport/<name>`, creating the directory on first use.
    public static func url(_ name: String) -> URL {
        let dir = Paths.appSupport
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(name)
    }

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.services.error("corrupt state file \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(value)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.services.error("could not save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Locates files under `Sources/CaelestiaServices/Resources` (SwiftPM `.copy("Resources")`, which
/// lands in the `SkyRose_CaelestiaServices.bundle` next to the executable or inside the app's
/// `Contents/Resources`). The lookup mirrors SwiftPM's generated `Bundle.module` accessor so the
/// module compiles with or without the manifest declaring the resources, and falls back to the
/// source tree for `swift test` runs from a checkout.
enum ServiceResources {
    static let bundleName = "SkyRose_CaelestiaServices"

    private final class Finder {}

    static let bundle: Bundle? = {
        var candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle(for: Finder.self).resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: Finder.self).bundleURL.deletingLastPathComponent(),
        ]
        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            candidates.insert(URL(fileURLWithPath: override), at: 0)
        }
        for candidate in candidates {
            guard let url = candidate?.appendingPathComponent(bundleName + ".bundle") else { continue }
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }()

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let bundle {
            for sub in ["Resources", nil] {
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: sub) { return url }
            }
        }
        // Development fallback: the source tree of this very file (…/Sources/CaelestiaServices/Support/).
        let sourceTree = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let inTree = sourceTree.appendingPathComponent("Resources/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: inTree.path) { return inTree }
        return nil
    }
}

/// Runs `body` on the main actor from a callback that arrives on an arbitrary thread
/// (CoreAudio listeners, IOKit run-loop sources, NWPathMonitor queues, …).
@inline(__always)
func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { body() }
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
}

/// A repeating main-queue timer that exists only between `start` and `stop`, so an idle shell holds
/// no timers at all (section 13). The handler runs on the main actor.
@MainActor
final class MainTimer {
    private var source: DispatchSourceTimer?

    var isRunning: Bool { source != nil }

    func start(interval: TimeInterval, leeway: TimeInterval = 0.1, fireNow: Bool = false, _ handler: @escaping @MainActor () -> Void) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + (fireNow ? 0 : interval), repeating: interval, leeway: .milliseconds(Int(leeway * 1000)))
        timer.setEventHandler { MainActor.assumeIsolated { handler() } }
        timer.resume()
        source = timer
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}

/// Clamps `value` into `range`.
@inline(__always)
func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
    min(max(value, range.lowerBound), range.upperBound)
}
