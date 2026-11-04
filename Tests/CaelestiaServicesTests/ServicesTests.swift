import XCTest
import IOKit.ps
@testable import CaelestiaServices

/// Pure parts of the services the bar and OSDs read (battery, network, persisted state, bundled
/// resources). The live services need hardware and permissions and are not exercised here.
final class ServicesTests: XCTestCase {
    func testBatteryParsesTheInternalBattery() {
        let sources: [[String: Any]] = [
            [kIOPSTypeKey: "UPS", kIOPSCurrentCapacityKey: 10],
            [
                kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 41, kIOPSMaxCapacityKey: 50,
                kIOPSIsChargingKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSTimeToFullChargeKey: 35,
            ],
        ]
        let s = BatteryState.parse(powerSources: sources, lowPowerMode: true)
        XCTAssertTrue(s.hasBattery)
        XCTAssertEqual(s.percent, 82)
        XCTAssertTrue(s.isCharging)
        XCTAssertTrue(s.isPluggedIn)
        XCTAssertEqual(s.timeRemainingMinutes, 35)
        XCTAssertTrue(s.isLowPowerMode)
    }

    func testBatteryAbsentOnDesktops() {
        let s = BatteryState.parse(powerSources: [], lowPowerMode: false)
        XCTAssertFalse(s.hasBattery)
        XCTAssertNil(s.timeRemainingMinutes)
    }

    func testBatteryIgnoresCalculatingEstimate() {
        let sources: [[String: Any]] = [[
            kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 100, kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: false, kIOPSTimeToEmptyKey: -1,
        ]]
        XCTAssertNil(BatteryState.parse(powerSources: sources, lowPowerMode: false).timeRemainingMinutes)
    }

    func testThroughputRateHandlesWrapAndBadIntervals() {
        XCTAssertEqual(NetworkThroughputSampler.rate(previous: 1000, current: 3000, interval: 2), 1000)
        XCTAssertEqual(NetworkThroughputSampler.rate(previous: UInt64(UInt32.max) - 99, current: 100, interval: 1), 200)
        XCTAssertEqual(NetworkThroughputSampler.rate(previous: 5, current: 10, interval: 0), 0)
    }

    func testWifiBars() {
        XCTAssertEqual(NetworkState.strength(fromRSSI: 0), 0)
        XCTAssertEqual(NetworkState.strength(fromRSSI: -85), 1)
        XCTAssertEqual(NetworkState.strength(fromRSSI: -75), 2)
        XCTAssertEqual(NetworkState.strength(fromRSSI: -65), 3)
        XCTAssertEqual(NetworkState.strength(fromRSSI: -40), 4)
    }

    func testStorageRoundTripAndCorruptFile() throws {
        struct State: Codable, Equatable { var dnd: Bool; var count: Int }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ServiceStorage.load(State.self, from: url))
        ServiceStorage.save(State(dnd: true, count: 3), to: url)
        XCTAssertEqual(ServiceStorage.load(State.self, from: url), State(dnd: true, count: 3))
        try Data("{".utf8).write(to: url)
        XCTAssertNil(ServiceStorage.load(State.self, from: url))
    }

    func testBundledEmojiResourceIsFoundAndValid() throws {
        let url = try XCTUnwrap(ServiceResources.url(forResource: "emoji", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let emoji = try XCTUnwrap(json["emoji"] as? [[String: Any]])
        XCTAssertGreaterThan(emoji.count, 1000)
        XCTAssertTrue(emoji.allSatisfy { $0["c"] is String && $0["n"] is String })
    }
}

final class SysInfoTests: XCTestCase {
    func testCPUUsageFromTickDeltas() {
        let a = SysInfo.CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let b = SysInfo.CPUTicks(user: 200, system: 100, idle: 850, nice: 50)
        XCTAssertEqual(SysInfo.cpuUsage(previous: a, current: b), 0.75, accuracy: 1e-9)
        XCTAssertEqual(SysInfo.cpuUsage(previous: a, current: a), 0)
        XCTAssertEqual(SysInfo.cpuUsage(previous: b, current: a), 0, "counters going back")
        let idleOnly = SysInfo.CPUTicks(user: 100, system: 50, idle: 1800, nice: 50)
        XCTAssertEqual(SysInfo.cpuUsage(previous: a, current: idleOnly), 0, accuracy: 1e-9)
    }

    func testMemoryAndFormatting() {
        XCTAssertEqual(SysInfo.memoryUsedBytes(active: 100, wired: 50, compressed: 25, pageSize: 16384), 175 * 16384)
        XCTAssertEqual(SysInfo.bytes(0), "0 B")
        XCTAssertEqual(SysInfo.bytes(1536), "1.5 KiB")
        XCTAssertEqual(SysInfo.bytes(7_948_206_080), "7.4 GiB")
        XCTAssertEqual(SysInfo.bytes(500 * 1024 * 1024 * 1024), "500 GiB")
        XCTAssertEqual(SysInfo.rate(0), "0 B/s")
        XCTAssertEqual(SysInfo.rate(1_500_000), "1.5 MB/s")
        XCTAssertEqual(SysInfo.uptime(15 * 3600 + 11 * 60 + 5), "up 15 hours, 11 min")
        XCTAssertEqual(SysInfo.uptime(3600), "up 1 hour, 0 min")
        XCTAssertEqual(SysInfo.uptime(2 * 86400 + 3600), "up 2 days, 1 hour")
        XCTAssertEqual(SysInfo.duration(minutes: 125), "2 h 05 min")
        XCTAssertEqual(SysInfo.duration(minutes: 9), "9 min")
        XCTAssertEqual(SysInfo.thermalName(0), "Nominal")
        XCTAssertEqual(SysInfo.thermalName(2), "Serious")
    }

    func testGPUParsingAndHistory() {
        XCTAssertEqual(SysInfo.gpuUtilization(["Device Utilization %": 37]), 37)
        XCTAssertEqual(SysInfo.gpuUtilization(["Device Utilization %": 400]), 100)
        XCTAssertNil(SysInfo.gpuUtilization([:]))
        XCTAssertNil(SysInfo.gpuUtilization(["Other": 1]))
        var h: [Double] = []
        for i in 0..<100 { h = SysInfo.appended(h, Double(i)) }
        XCTAssertEqual(h.count, 60)
        XCTAssertEqual(h.last, 99)
        XCTAssertEqual(h.first, 40)
    }

    func testLiveSamplerReturnsSaneValues() {
        let s = SystemStatsSampler()
        _ = s.sample()
        let r = s.sample()
        XCTAssertGreaterThan(r.memoryTotal, 0)
        XCTAssertGreaterThan(r.memoryUsed, 0)
        XCTAssertLessThanOrEqual(r.memoryUsed, r.memoryTotal)
        XCTAssertGreaterThan(r.diskTotal, 0)
        XCTAssertLessThanOrEqual(r.diskUsed, r.diskTotal)
        XCTAssertGreaterThanOrEqual(r.cpu, 0)
        XCTAssertLessThanOrEqual(r.cpu, 1)
        XCTAssertGreaterThan(r.uptime, 0)
    }

    // MARK: Brightness stepping

    func testBrightnessSteppingSnapsToTheStepGrid() {
        let step = BrightnessService.keyStep
        XCTAssertEqual(step, 0.0625)
        func up(_ v: Double, _ s: Double = step) -> Double { BrightnessService.stepped(v, up: true, step: s) }
        func down(_ v: Double, _ s: Double = step) -> Double { BrightnessService.stepped(v, up: false, step: s) }
        XCTAssertEqual(up(0.53), 0.5625, accuracy: 1e-9)
        XCTAssertEqual(down(0.53), 0.5, accuracy: 1e-9)
        XCTAssertEqual(up(0.5), 0.5625, accuracy: 1e-9, "on the grid: a full step")
        XCTAssertEqual(down(0.5), 0.4375, accuracy: 1e-9)
        XCTAssertEqual(up(0), step, accuracy: 1e-9)
        XCTAssertEqual(down(step), 0, accuracy: 1e-9)
    }

    func testBrightnessSteppingClamps() {
        let step = BrightnessService.keyStep
        XCTAssertEqual(BrightnessService.stepped(1, up: true, step: step), 1)
        XCTAssertEqual(BrightnessService.stepped(0.99, up: true, step: step), 1)
        XCTAssertEqual(BrightnessService.stepped(0, up: false, step: step), 0)
        XCTAssertEqual(BrightnessService.stepped(0.01, up: false, step: step), 0)
        XCTAssertEqual(BrightnessService.stepped(2, up: false, step: step), 1, "out-of-range input is clamped")
        XCTAssertEqual(BrightnessService.stepped(-1, up: true, step: step), 0)
    }

    func testFineBrightnessStepsAreAQuarter() {
        let fine = BrightnessService.keyStep / 4
        XCTAssertEqual(BrightnessService.stepped(0.5, up: true, step: fine), 0.5 + fine, accuracy: 1e-9)
        XCTAssertEqual(BrightnessService.stepped(0.5, up: false, step: fine), 0.5 - fine, accuracy: 1e-9)
        var v = 0.0
        for _ in 0..<64 { v = BrightnessService.stepped(v, up: true, step: fine) }
        XCTAssertEqual(v, 1, accuracy: 1e-9)
        for _ in 0..<64 { v = BrightnessService.stepped(v, up: false, step: fine) }
        XCTAssertEqual(v, 0, accuracy: 1e-9)
    }

    func testRepeatedStepsWalkTheWholeGridExactly() {
        var v = 0.0
        var seen = [v]
        for _ in 0..<16 {
            v = BrightnessService.stepped(v, up: true, step: BrightnessService.keyStep)
            seen.append(v)
        }
        XCTAssertEqual(seen, (0...16).map { Double($0) / 16 })
    }
}
