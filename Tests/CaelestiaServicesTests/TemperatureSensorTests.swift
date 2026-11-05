import XCTest
@testable import CaelestiaServices

final class TemperatureSensorTests: XCTestCase {
    /// Names and values read on an Apple M4 MacBook Air (2026-11-05).
    let m4: [(name: String, celsius: Double)] = [
        ("NAND CH0 temp", 34.0), ("PMU tcal", 51.8), ("PMU tdev1", -22.1), ("PMU tdev2", 37.8),
        ("PMU tdie1", 37.2), ("PMU tdie2", 36.8), ("PMU tdie6", 39.0), ("PMU2 tdie1", 35.6), ("PMU2 tdev3", -22.0),
        ("als-temp", .nan), ("gas gauge battery", 29.5), ("gas gauge battery", 29.0),
    ]

    func testM4Grouping() throws {
        let t = TemperatureSummary.summarize(m4)
        XCTAssertEqual(try XCTUnwrap(t.cpuC), (37.2 + 36.8 + 39.0 + 35.6) / 4, accuracy: 0.001, "die sensors only, tcal/tdev ignored")
        XCTAssertEqual(t.cpuMaxC, 39.0)
        XCTAssertNil(t.gpuC, "M4 has no named GPU sensor: hidden, not guessed")
        XCTAssertEqual(try XCTUnwrap(t.batteryC), 29.25, accuracy: 0.001)
        XCTAssertEqual(t.ssdC, 34.0)
        XCTAssertFalse(t.isEmpty)
    }

    func testM1StyleNames() {
        let t = TemperatureSummary.summarize([("pACC MTR Temp Sensor0", 50), ("eACC MTR Temp Sensor1", 40), ("GPU MTR Temp Sensor1", 45)])
        XCTAssertEqual(t.cpuC, 45)
        XCTAssertEqual(t.gpuC, 45)
    }

    func testNonsenseValuesDropped() {
        let t = TemperatureSummary.summarize([("PMU tdie1", -22), ("PMU tdie2", 0), ("PMU tdie3", 200), ("PMU tdie4", .infinity)])
        XCTAssertTrue(t.isEmpty)
        XCTAssertTrue(TemperatureSummary.summarize([]).isEmpty)
    }

    /// The real reader never crashes; on Apple Silicon it finds die sensors without root.
    func testLiveReaderIsSafe() {
        let r = HIDTemperatureReader()
        let readings = r.read()
        #if arch(arm64)
        if r.available, !readings.isEmpty {
            XCTAssertNotNil(TemperatureSummary.summarize(readings).cpuC)
        }
        #endif
        _ = r.read()
    }
}
