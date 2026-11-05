import CaelestiaCore
import CaelestiaServices
import XCTest

@testable import CaelestiaShell

@MainActor
final class WeatherControllerTests: XCTestCase {
    private func makeState() -> ShellState {
        ShellState(scheme: ShellTheme.gabby.scheme, config: Config(), animations: AnimationTable.gabbySpringy,
                   displays: [], converter: CoordinateConverter(primaryHeight: 956))
    }

    private func report(_ t: Double = 12.4, code: Int = 61) -> WeatherReport {
        WeatherReport(temperatureC: t, feelsLikeC: 10, humidity: 80, windKmh: 14, code: code, isDay: true, sunrise: nil, sunset: nil,
                      hourly: [.init(time: Date(), temperatureC: t, code: code, isDay: true, precipitationChance: 40)],
                      daily: [.init(date: Date(), minC: 8, maxC: 14, code: 3, precipitationChance: 10)], fetchedAt: Date())
    }

    func testNoCityMeansNoFetchAndNoValues() {
        let state = makeState()
        let c = WeatherController(state: state)
        var calls = 0
        c.fetchForecast = { _, _ in calls += 1; throw ServiceError.network("x") }
        c.configure(WeatherConfig())
        XCTAssertEqual(calls, 0)
        XCTAssertNil(state.weather)
        XCTAssertEqual(state.weatherStatus, .notConfigured)
    }

    func testCityFetchesAndFills() async throws {
        let state = makeState()
        let c = WeatherController(state: state)
        var asked: (Double, Double)?
        let r = report()
        c.fetchForecast = { lat, lon in asked = (lat, lon); return r }
        var w = WeatherConfig()
        w.city = "Oslo, Norway"; w.latitude = 59.91; w.longitude = 10.75
        c.configure(w)
        XCTAssertEqual(state.weatherStatus, .loading)
        for _ in 0..<50 where state.weather == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(asked?.0, 59.91)
        let info = try XCTUnwrap(state.weather)
        XCTAssertEqual(info.location, "Oslo, Norway")
        XCTAssertEqual(info.description, "Light rain")
        XCTAssertEqual(info.hourly.first?.precipitationChance, 40)
        XCTAssertEqual(state.weatherStatus, .ready)
        c.stop()
    }

    func testFailureSaysWhy() async throws {
        let state = makeState()
        let c = WeatherController(state: state)
        c.fetchForecast = { _, _ in throw ServiceError.network("offline") }
        var w = WeatherConfig()
        w.city = "Oslo"; w.latitude = 1; w.longitude = 2
        c.configure(w)
        for _ in 0..<50 where state.weatherStatus == .loading { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(state.weatherStatus, .failed("offline"))
        XCTAssertNil(state.weather)
        c.stop()
    }

    func testRemovingTheCityClears() {
        let state = makeState()
        let c = WeatherController(state: state)
        c.apply(report(), name: "Oslo")
        XCTAssertNotNil(state.weather)
        c.configure(WeatherConfig())
        XCTAssertNil(state.weather)
        XCTAssertEqual(state.weatherStatus, .notConfigured)
    }

    func testTemperatureText() {
        XCTAssertEqual(WeatherText.temperature(12.4, fahrenheit: false), "12°C")
        XCTAssertEqual(WeatherText.temperature(0, fahrenheit: true), "32°F")
        XCTAssertEqual(WeatherText.temperature(-3.6, fahrenheit: false, unit: false), "-4°")
    }

    func testWeatherConfigDefaultsOff() {
        let w = Config().weather
        XCTAssertFalse(w.useLocation, "CoreLocation is off by default")
        XCTAssertFalse(w.isConfigured)
        XCTAssertEqual(DashboardTab(config: "weather"), .weather)
    }
}
