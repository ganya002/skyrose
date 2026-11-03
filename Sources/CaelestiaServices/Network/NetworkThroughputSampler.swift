import Darwin
import Foundation

/// Up/down rate between two samples of the interface byte counters.
public struct NetworkThroughput: Hashable, Sendable {
    public var uploadBytesPerSecond: Double
    public var downloadBytesPerSecond: Double
    public init(uploadBytesPerSecond: Double, downloadBytesPerSecond: Double) {
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
    }
    public static let zero = NetworkThroughput(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0)
}

/// Reads the per-interface byte counters (`getifaddrs` → `if_data`) and turns consecutive samples
/// into bytes/s. It has no timer of its own: the Performance tab calls `sample()` at 1 Hz while
/// open and drops the sampler when closed (section 13).
///
/// The `if_data` counters are 32-bit on Darwin and wrap every 4 GiB; `rate(previous:current:...)`
/// compensates for one wrap per interval.
public final class NetworkThroughputSampler: @unchecked Sendable {
    /// Which interfaces count. Default: physical `en*` (Wi-Fi, Ethernet, Thunderbolt), which avoids
    /// double counting VPN tunnels (`utun*`) and bridges.
    public var includeInterface: (String) -> Bool

    private var previous: (sent: UInt64, received: UInt64, at: Date)?

    public init(includeInterface: @escaping (String) -> Bool = { $0.hasPrefix("en") }) {
        self.includeInterface = includeInterface
    }

    /// Takes a sample; the first call returns `.zero` (no delta yet).
    public func sample(now: Date = Date()) -> NetworkThroughput {
        let counters = Self.readCounters(include: includeInterface)
        defer { previous = (counters.sent, counters.received, now) }
        guard let prev = previous else { return .zero }
        let interval = now.timeIntervalSince(prev.at)
        return NetworkThroughput(
            uploadBytesPerSecond: Self.rate(previous: prev.sent, current: counters.sent, interval: interval),
            downloadBytesPerSecond: Self.rate(previous: prev.received, current: counters.received, interval: interval))
    }

    /// Forgets the previous sample so the next `sample()` starts a fresh delta.
    public func reset() { previous = nil }

    /// Bytes/s between two counter readings; handles a single 32-bit wrap and returns 0 for a
    /// non-positive interval.
    public static func rate(previous: UInt64, current: UInt64, interval: TimeInterval, counterBits: Int = 32) -> Double {
        guard interval > 0 else { return 0 }
        let delta: UInt64
        if current >= previous {
            delta = current - previous
        } else if counterBits < 64 {
            delta = (UInt64(1) << UInt64(counterBits)) - previous + current
        } else {
            delta = UInt64.max - previous + current + 1
        }
        return Double(delta) / interval
    }

    /// Sums the sent/received byte counters of every matching `AF_LINK` interface.
    static func readCounters(include: (String) -> Bool) -> (sent: UInt64, received: UInt64) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }
        var sent: UInt64 = 0
        var received: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard include(name), let raw = entry.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            sent &+= UInt64(data.ifi_obytes)
            received &+= UInt64(data.ifi_ibytes)
        }
        return (sent, received)
    }
}
