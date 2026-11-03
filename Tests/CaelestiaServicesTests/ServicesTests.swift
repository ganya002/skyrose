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
