import Darwin
import Foundation
import IOKit

/// Pure parsers and formatters behind the dashboard's Performance tab (unit-tested).
public enum SysInfo {
    /// Cumulative CPU ticks (user, system, idle, nice) summed over all cores.
    public struct CPUTicks: Equatable, Sendable {
        public var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
        public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
            self.user = user; self.system = system; self.idle = idle; self.nice = nice
        }
        public var total: UInt64 { user &+ system &+ idle &+ nice }
    }

    /// Busy fraction 0...1 between two samples (0 when no ticks elapsed or counters went back).
    public static func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double {
        guard current.total > previous.total, current.idle >= previous.idle else { return 0 }
        let total = Double(current.total - previous.total)
        let idle = Double(current.idle - previous.idle)
        return min(1, max(0, 1 - idle / total))
    }

    /// Used memory as Activity Monitor-style "active + wired + compressed" pages, in bytes.
    public static func memoryUsedBytes(active: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
        (active &+ wired &+ compressed) &* pageSize
    }

    /// "7.4 GiB", "512 MiB", "0 B".
    public static func bytes(_ n: UInt64) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var v = Double(n)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return "\(n) B" }
        return v >= 100 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }

    /// "1.2 MB/s"-style rate (decimal units, as network tools show).
    public static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var v = max(0, bytesPerSecond)
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }

    /// "up 15 hours, 11 min", "up 3 days, 2 hours", "up 5 min", "up 0 min".
    public static func uptime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86400, hours = (total % 86400) / 3600, minutes = (total % 3600) / 60
        func plural(_ n: Int, _ s: String) -> String { "\(n) \(s)\(n == 1 ? "" : "s")" }
        if days > 0 { return "up \(plural(days, "day")), \(plural(hours, "hour"))" }
        if hours > 0 { return "up \(plural(hours, "hour")), \(minutes) min" }
        return "up \(minutes) min"
    }

    /// "12 min", "1 h 05 min" for battery time remaining.
    public static func duration(minutes: Int) -> String {
        minutes >= 60 ? String(format: "%d h %02d min", minutes / 60, minutes % 60) : "\(minutes) min"
    }

    /// GPU busy percent from an IOAccelerator `PerformanceStatistics` dictionary, or nil.
    public static func gpuUtilization(_ stats: [String: Any]) -> Double? {
        for key in ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"] {
            if let n = stats[key] as? NSNumber { return min(100, max(0, n.doubleValue)) }
        }
        return nil
    }

    /// Appends to a rolling history capped at `limit`.
    public static func appended(_ history: [Double], _ value: Double, limit: Int = 60) -> [Double] {
        var h = history
        h.append(value)
        if h.count > limit { h.removeFirst(h.count - limit) }
        return h
    }

    /// Thermal pressure from `ProcessInfo.ThermalState` (public, no root). Degrees come from
    /// ``HIDTemperatureReader``.
    public static func thermalName(_ raw: Int) -> String {
        switch raw {
        case 0: return "Nominal"
        case 1: return "Fair"
        case 2: return "Serious"
        default: return "Critical"
        }
    }
}

public struct SystemStats: Equatable, Sendable {
    public var cpu: Double = 0
    public var gpu: Double? = nil
    public var memoryUsed: UInt64 = 0
    public var memoryTotal: UInt64 = 0
    public var diskUsed: UInt64 = 0
    public var diskTotal: UInt64 = 0
    public var uptime: Double = 0
    public var thermal: Int = 0
    public var temperatures = TemperatureSummary()
    public init() {}
}

/// Reads CPU, memory, disk, GPU and uptime with public APIs only. Not a timer owner: the shell
/// calls `sample()` once a second while the dashboard is open (spec 13: no idle polling).
public final class SystemStatsSampler: @unchecked Sendable {
    private var previous: SysInfo.CPUTicks?
    private let temperatures = HIDTemperatureReader()

    public init() {}

    public func sample() -> SystemStats {
        var s = SystemStats()
        if let ticks = Self.readTicks() {
            if let p = previous { s.cpu = SysInfo.cpuUsage(previous: p, current: ticks) }
            previous = ticks
        }
        s.memoryTotal = ProcessInfo.processInfo.physicalMemory
        s.memoryUsed = Self.readMemoryUsed()
        (s.diskUsed, s.diskTotal) = Self.readDisk()
        s.gpu = Self.readGPU()
        s.uptime = ProcessInfo.processInfo.systemUptime
        s.thermal = ProcessInfo.processInfo.thermalState.rawValue
        s.temperatures = TemperatureSummary.summarize(temperatures.read())
        return s
    }

    static func readTicks() -> SysInfo.CPUTicks? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var t = SysInfo.CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        for i in 0..<Int(count) {
            let base = i * Int(CPU_STATE_MAX)
            t.user &+= UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            t.system &+= UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            t.idle &+= UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            t.nice &+= UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
        return t
    }

    static func readMemoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return SysInfo.memoryUsedBytes(
            active: UInt64(stats.active_count), wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count),
            pageSize: UInt64(vm_kernel_page_size))
    }

    static func readDisk() -> (UInt64, UInt64) {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage else { return (0, 0) }
        return (UInt64(max(0, Int64(total) - free)), UInt64(total))
    }

    static func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let ref = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let dict = ref as? [String: Any], let u = SysInfo.gpuUtilization(dict) { return u }
        }
        return nil
    }
}
