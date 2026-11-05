import CaelestiaCore
import CaelestiaServices
import Foundation

/// Keeps `ShellState.weather` fresh from Open-Meteo: on start, whenever `[weather]` changes and
/// every `refreshMinutes`. Without a city (and with the location off) nothing is fetched and the
/// state says `.notConfigured`; a failed fetch keeps the last report and says why.
@MainActor
public final class WeatherController {
    let state: ShellState
    private var config: WeatherConfig?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private let location = LocationService()
    /// Swappable for tests.
    var fetchForecast: (Double, Double) async throws -> WeatherReport = { try await OpenMeteo.forecast(latitude: $0, longitude: $1) }
    public private(set) var lastFetch: Date?

    public init(state: ShellState) {
        self.state = state
    }

    /// Applies `[weather]`; refetches only when the place or unit source changed.
    public func configure(_ c: WeatherConfig) {
        let old = config
        config = c
        guard c.isConfigured else {
            stop()
            state.weather = nil
            state.weatherStatus = .notConfigured
            return
        }
        let placeChanged = old == nil || old!.useLocation != c.useLocation || old!.latitude != c.latitude
            || old!.longitude != c.longitude || old!.city != c.city
        if placeChanged {
            if old?.isConfigured == true { state.weather = nil }
            refresh()
        }
        if placeChanged || old?.refreshMinutes != c.refreshMinutes || timer == nil { schedule(c.refreshMinutes) }
    }

    /// Refetches if the last report is older than the refresh interval (dashboard opened).
    public func refreshIfStale() {
        guard let c = config, c.isConfigured else { return }
        if let last = lastFetch, Date().timeIntervalSince(last) < Double(c.refreshMinutes) * 60 { return }
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
    }

    private func schedule(_ minutes: Int) {
        timer?.invalidate()
        let t = Timer(timeInterval: Double(max(5, minutes)) * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func refresh() {
        guard let c = config, c.isConfigured else { return }
        if state.weather == nil { state.weatherStatus = .loading }
        if c.useLocation {
            location.locate { [weak self] fix in
                guard let self else { return }
                if let fix {
                    self.fetch(latitude: fix.latitude, longitude: fix.longitude, name: fix.name)
                } else if c.hasCity {
                    self.fetch(latitude: c.latitude, longitude: c.longitude, name: c.city)
                } else {
                    self.state.weatherStatus = .failed("Location is off or not allowed. Set a city in Settings › Bar and Shell.")
                }
            }
        } else {
            fetch(latitude: c.latitude, longitude: c.longitude, name: c.city)
        }
    }

    private func fetch(latitude: Double, longitude: Double, name: String) {
        task?.cancel()
        let get = fetchForecast
        task = Task { [weak self] in
            do {
                let report = try await get(latitude, longitude)
                guard !Task.isCancelled else { return }
                self?.apply(report, name: name)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state.weatherStatus = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                Log.services.notice("weather: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func apply(_ r: WeatherReport, name: String) {
        lastFetch = r.fetchedAt
        state.weather = Self.info(from: r, location: name)
        state.weatherStatus = .ready
    }

    /// Open-Meteo report → what the dashboard draws.
    public static func info(from r: WeatherReport, location: String) -> WeatherInfo {
        WeatherInfo(
            temperatureC: r.temperatureC, description: OpenMeteo.describe(r.code), icon: OpenMeteo.symbol(r.code, isDay: r.isDay),
            location: location,
            hourly: r.hourly.map { .init(time: $0.time, temperatureC: $0.temperatureC, icon: OpenMeteo.symbol($0.code, isDay: $0.isDay), precipitationChance: $0.precipitationChance) },
            daily: r.daily.map { .init(date: $0.date, minC: $0.minC, maxC: $0.maxC, icon: OpenMeteo.symbol($0.code), description: OpenMeteo.describe($0.code), precipitationChance: $0.precipitationChance) },
            feelsLikeC: r.feelsLikeC, humidity: r.humidity, windKmh: r.windKmh, sunrise: r.sunrise, sunset: r.sunset, updated: r.fetchedAt)
    }
}
