import Darwin
import Foundation

/// CPU/GPU/battery/SSD temperatures from the IOKit HID temperature services, the way the Stats app
/// reads them on Apple Silicon: no root, no SMC writes, no helper. An event-system client matches
/// `PrimaryUsagePage 0xff00 / PrimaryUsage 5` (the AppleARM PMU, battery gas gauge and NAND
/// sensors) and copies one temperature event per service.
///
/// `IOHIDEventSystemClientCreate`, `…SetMatching`, `IOHIDServiceClientCopyEvent` and
/// `IOHIDEventGetFloatValue` are private IOKit exports, so they are looked up with `dlsym`: a macOS
/// that drops one gives `available == false` and the dashboard hides the temperatures instead of
/// crashing. Intel Macs have no such services (also `available == false`).
public final class HIDTemperatureReader: @unchecked Sendable {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloat = @convention(c) (CFTypeRef, Int32) -> Double

    private struct API {
        let create: Create, setMatching: SetMatching, copyServices: CopyServices
        let copyProperty: CopyProperty, copyEvent: CopyEvent, getFloat: GetFloat
    }

    /// kIOHIDEventTypeTemperature and its first field (`type << 16`).
    static let temperatureEvent: Int64 = 15
    static let temperatureField = Int32(15 << 16)

    private let api: API?
    private var client: CFTypeRef?
    private var services: [(name: String, service: CFTypeRef)] = []
    private let lock = NSLock()

    public init() {
        api = Self.loadAPI()
    }

    public var available: Bool { api != nil }

    private static func loadAPI() -> API? {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let create = sym("IOHIDEventSystemClientCreate", Create.self),
              let setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let copyProperty = sym("IOHIDServiceClientCopyProperty", CopyProperty.self),
              let copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEvent.self),
              let getFloat = sym("IOHIDEventGetFloatValue", GetFloat.self) else { return nil }
        return API(create: create, setMatching: setMatching, copyServices: copyServices,
                   copyProperty: copyProperty, copyEvent: copyEvent, getFloat: getFloat)
    }

    /// One reading per sensor: (product name, °C). Empty when unavailable.
    public func read() -> [(name: String, celsius: Double)] {
        guard let api else { return [] }
        lock.lock()
        defer { lock.unlock() }
        if client == nil {
            guard let c = api.create(kCFAllocatorDefault)?.takeRetainedValue() else { return [] }
            _ = api.setMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
            client = c
            let list = (api.copyServices(c)?.takeRetainedValue() as? [CFTypeRef]) ?? []
            services = list.map { s in
                (api.copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String ?? "", s)
            }
        }
        var out: [(String, Double)] = []
        for (name, s) in services {
            guard let ev = api.copyEvent(s, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            out.append((name, api.getFloat(ev, Self.temperatureField)))
        }
        return out
    }
}

/// The dashboard's temperatures, grouped from raw HID sensor names. Pure (unit-tested).
public struct TemperatureSummary: Equatable, Sendable {
    /// Average of the SoC die sensors (CPU area); nil when none reads a sane value.
    public var cpuC: Double?
    /// Hottest die sensor.
    public var cpuMaxC: Double?
    /// GPU sensors (M1-style "GPU MTR Temp Sensor"); nil on chips without a named GPU sensor.
    public var gpuC: Double?
    public var batteryC: Double?
    public var ssdC: Double?

    public init(cpuC: Double? = nil, cpuMaxC: Double? = nil, gpuC: Double? = nil, batteryC: Double? = nil, ssdC: Double? = nil) {
        self.cpuC = cpuC; self.cpuMaxC = cpuMaxC; self.gpuC = gpuC; self.batteryC = batteryC; self.ssdC = ssdC
    }

    public var isEmpty: Bool { cpuC == nil && gpuC == nil && batteryC == nil && ssdC == nil }

    /// Disconnected or idle sensors report nonsense (-22 °C, 0, 128+); those are dropped.
    static func sane(_ v: Double) -> Bool { v.isFinite && v > 5 && v < 125 }

    public static func summarize(_ readings: [(name: String, celsius: Double)]) -> TemperatureSummary {
        var cpu: [Double] = [], gpu: [Double] = [], battery: [Double] = [], ssd: [Double] = []
        for r in readings where sane(r.celsius) {
            let n = r.name.lowercased()
            if n.contains("gpu") {
                gpu.append(r.celsius)
            } else if n.contains("tdie") || n.contains("pacc") || n.contains("eacc") || n.contains("soc mtr") || n.contains("cpu") {
                cpu.append(r.celsius)
            } else if n.contains("battery") {
                battery.append(r.celsius)
            } else if n.contains("nand") {
                ssd.append(r.celsius)
            }
        }
        func avg(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        return TemperatureSummary(cpuC: avg(cpu), cpuMaxC: cpu.max(), gpuC: avg(gpu), batteryC: avg(battery), ssdC: avg(ssd))
    }
}
