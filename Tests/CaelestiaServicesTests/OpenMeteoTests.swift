import XCTest
@testable import CaelestiaServices

final class OpenMeteoTests: XCTestCase {
    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/openmeteo", isDirectory: true)
    }

    func testSearchURLNeedsTwoCharacters() throws {
        XCTAssertNil(OpenMeteo.searchURL("a"))
        XCTAssertNil(OpenMeteo.searchURL("  "))
        let url = try XCTUnwrap(OpenMeteo.searchURL("San José"))
        XCTAssertEqual(url.host, "geocoding-api.open-meteo.com")
        XCTAssertTrue(url.absoluteString.contains("name=San%20Jos%C3%A9"))
        XCTAssertFalse(url.absoluteString.contains("apikey"), "no API key")
    }

    func testForecastURL() throws {
        let url = try XCTUnwrap(OpenMeteo.forecastURL(latitude: 59.91273, longitude: 10.74609))
        XCTAssertEqual(url.host, "api.open-meteo.com")
        let s = url.absoluteString
        XCTAssertTrue(s.contains("latitude=59.9127"))
        XCTAssertTrue(s.contains("longitude=10.7461"))
        XCTAssertTrue(s.contains("timeformat=unixtime"))
        XCTAssertTrue(s.contains("timezone=auto"))
    }

    func testParsePlaces() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("search-oslo.json"))
        let places = try OpenMeteo.parsePlaces(data)
        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(places[0].name, "Oslo")
        XCTAssertEqual(places[0].detail, "Norway", "admin1 equal to the name is dropped")
        XCTAssertEqual(places[0].displayName, "Oslo, Norway")
        XCTAssertEqual(places[0].latitude, 59.91273, accuracy: 1e-5)
        XCTAssertEqual(places[1].displayName, "Oslo, United States")
        XCTAssertEqual(try OpenMeteo.parsePlaces(Data("{\"generationtime_ms\":0.1}".utf8)), [], "no results key = empty")
    }

    func testParseForecast() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("forecast-oslo.json"))
        let now = Date(timeIntervalSince1970: 1_793_872_800)
        let r = try OpenMeteo.parseForecast(data, now: now)
        XCTAssertEqual(r.temperatureC, 2.9, accuracy: 0.01)
        XCTAssertEqual(r.feelsLikeC ?? 0, 0.4, accuracy: 0.01)
        XCTAssertEqual(r.humidity, 75)
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.isDay)
        XCTAssertEqual(r.hourly.count, 24)
        XCTAssertGreaterThanOrEqual(r.hourly[0].time, now.addingTimeInterval(-3600), "series starts at the current hour")
        XCTAssertEqual(r.daily.count, 7)
        XCTAssertNotNil(r.sunrise)
        XCTAssertNotNil(r.sunset)
        XCTAssertLessThan(r.sunrise!, r.sunset!)
        for d in r.daily { XCTAssertLessThanOrEqual(d.minC, d.maxC) }
    }

    func testCorruptForecastThrows() {
        XCTAssertThrowsError(try OpenMeteo.parseForecast(Data("{\"current\":{}}".utf8)))
    }

    func testWMOCodes() {
        XCTAssertEqual(OpenMeteo.describe(0), "Clear sky")
        XCTAssertEqual(OpenMeteo.describe(63), "Rain")
        XCTAssertEqual(OpenMeteo.describe(95), "Thunderstorm")
        XCTAssertEqual(OpenMeteo.symbol(0, isDay: true), "sun.max.fill")
        XCTAssertEqual(OpenMeteo.symbol(0, isDay: false), "moon.stars.fill")
        XCTAssertEqual(OpenMeteo.symbol(73), "cloud.snow.fill")
        for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
            XCTAssertNotEqual(OpenMeteo.describe(code), "Unknown", "code \(code)")
        }
    }
}
