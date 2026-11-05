import Foundation
import CaelestiaCore

/// A place found by Open-Meteo's geocoding search (Settings › Bar and Shell › Weather).
public struct WeatherPlace: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// "Region, Country" for the search list ("Bavaria, Germany").
    public var detail: String
    public var timezone: String

    public init(id: Int, name: String, latitude: Double, longitude: Double, detail: String = "", timezone: String = "") {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.detail = detail
        self.timezone = timezone
    }

    /// The name stored in `weather.city`: "Munich, Germany".
    public var displayName: String {
        let country = detail.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return country.isEmpty || country == name ? name : "\(name), \(country)"
    }
}

/// One weather report, already in display form (°C; the shell converts for °F).
public struct WeatherReport: Equatable, Sendable {
    public struct Hour: Equatable, Sendable {
        public var time: Date
        public var temperatureC: Double
        public var code: Int
        public var isDay: Bool
        public var precipitationChance: Int?
        public init(time: Date, temperatureC: Double, code: Int, isDay: Bool, precipitationChance: Int? = nil) {
            self.time = time; self.temperatureC = temperatureC; self.code = code; self.isDay = isDay; self.precipitationChance = precipitationChance
        }
    }

    public struct Day: Equatable, Sendable {
        public var date: Date
        public var minC: Double
        public var maxC: Double
        public var code: Int
        public var precipitationChance: Int?
        public init(date: Date, minC: Double, maxC: Double, code: Int, precipitationChance: Int? = nil) {
            self.date = date; self.minC = minC; self.maxC = maxC; self.code = code; self.precipitationChance = precipitationChance
        }
    }

    public var temperatureC: Double
    public var feelsLikeC: Double?
    public var humidity: Int?
    public var windKmh: Double?
    public var code: Int
    public var isDay: Bool
    public var sunrise: Date?
    public var sunset: Date?
    public var hourly: [Hour]
    public var daily: [Day]
    public var fetchedAt: Date

    public init(temperatureC: Double, feelsLikeC: Double? = nil, humidity: Int? = nil, windKmh: Double? = nil, code: Int, isDay: Bool,
                sunrise: Date? = nil, sunset: Date? = nil, hourly: [Hour] = [], daily: [Day] = [], fetchedAt: Date = Date()) {
        self.temperatureC = temperatureC; self.feelsLikeC = feelsLikeC; self.humidity = humidity; self.windKmh = windKmh
        self.code = code; self.isDay = isDay; self.sunrise = sunrise; self.sunset = sunset
        self.hourly = hourly; self.daily = daily; self.fetchedAt = fetchedAt
    }
}

/// Open-Meteo (open-meteo.com): free forecast and geocoding APIs, no API key. Weather data by
/// Open-Meteo.com under CC BY 4.0. Request building and JSON parsing are pure (unit-tested);
/// ``fetch(_:session:)`` does the network call.
public enum OpenMeteo {
    public static let attribution = "Weather data by Open-Meteo.com (CC BY 4.0)"

    public static func searchURL(_ query: String, count: Int = 8, language: String = "en") -> URL? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return nil }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "name", value: q),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url
    }

    public static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return c.url
    }

    // MARK: Parsing

    private struct GeoResponse: Decodable {
        struct R: Decodable {
            var id: Int?
            var name: String
            var latitude: Double
            var longitude: Double
            var country: String?
            var admin1: String?
            var timezone: String?
        }
        var results: [R]?
    }

    public static func parsePlaces(_ data: Data) throws -> [WeatherPlace] {
        let r = try JSONDecoder().decode(GeoResponse.self, from: data)
        return (r.results ?? []).enumerated().map { i, p in
            let detail = [p.admin1, p.country].compactMap { $0 }.filter { !$0.isEmpty && $0 != p.name }.joined(separator: ", ")
            return WeatherPlace(id: p.id ?? i, name: p.name, latitude: p.latitude, longitude: p.longitude, detail: detail, timezone: p.timezone ?? "")
        }
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var apparent_temperature: Double?
            var relative_humidity_2m: Double?
            var weather_code: Int
            var wind_speed_10m: Double?
            var is_day: Int?
        }
        struct Hourly: Decodable {
            var time: [Double]
            var temperature_2m: [Double?]
            var weather_code: [Int?]
            var is_day: [Int?]?
            var precipitation_probability: [Double?]?
        }
        struct Daily: Decodable {
            var time: [Double]
            var weather_code: [Int?]
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
            var sunrise: [Double?]?
            var sunset: [Double?]?
            var precipitation_probability_max: [Double?]?
        }
        var current: Current
        var hourly: Hourly?
        var daily: Daily?
    }

    /// Parses a forecast (unixtime). `now` picks the next 24 hours from the hourly series.
    public static func parseForecast(_ data: Data, now: Date = Date()) throws -> WeatherReport {
        let r = try JSONDecoder().decode(ForecastResponse.self, from: data)
        var hours: [WeatherReport.Hour] = []
        if let h = r.hourly {
            let start = now.timeIntervalSince1970 - 3600
            for (i, t) in h.time.enumerated() where t >= start {
                guard i < h.temperature_2m.count, let temp = h.temperature_2m[i], i < h.weather_code.count, let code = h.weather_code[i] else { continue }
                let day = (h.is_day?[safe: i] ?? nil).map { $0 != 0 } ?? true
                let p = (h.precipitation_probability?[safe: i] ?? nil).map { Int($0.rounded()) }
                hours.append(.init(time: Date(timeIntervalSince1970: t), temperatureC: temp, code: code, isDay: day, precipitationChance: p))
                if hours.count == 24 { break }
            }
        }
        var days: [WeatherReport.Day] = []
        var sunrise: Date?
        var sunset: Date?
        if let d = r.daily {
            for (i, t) in d.time.enumerated() {
                guard let code = d.weather_code[safe: i] ?? nil, let mx = d.temperature_2m_max[safe: i] ?? nil,
                      let mn = d.temperature_2m_min[safe: i] ?? nil else { continue }
                let p = (d.precipitation_probability_max?[safe: i] ?? nil).map { Int($0.rounded()) }
                days.append(.init(date: Date(timeIntervalSince1970: t), minC: mn, maxC: mx, code: code, precipitationChance: p))
            }
            sunrise = (d.sunrise?[safe: 0] ?? nil).map { Date(timeIntervalSince1970: $0) }
            sunset = (d.sunset?[safe: 0] ?? nil).map { Date(timeIntervalSince1970: $0) }
        }
        let c = r.current
        return WeatherReport(temperatureC: c.temperature_2m, feelsLikeC: c.apparent_temperature,
                             humidity: c.relative_humidity_2m.map { Int($0.rounded()) }, windKmh: c.wind_speed_10m,
                             code: c.weather_code, isDay: (c.is_day ?? 1) != 0, sunrise: sunrise, sunset: sunset,
                             hourly: hours, daily: days, fetchedAt: now)
    }

    // MARK: WMO codes

    /// Plain-English name of a WMO weather code (Open-Meteo `weather_code`).
    public static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Light snow"
        case 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81: return "Rain showers"
        case 82: return "Violent rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }

    /// SF Symbol for a WMO code, day or night variant.
    public static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    // MARK: Network

    /// GETs `url` and returns the body; non-2xx and transport errors become `ServiceError.network`.
    public static func fetch(_ url: URL, session: URLSession = .shared) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("SkyRose/\(CaelestiaVersion.string)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ServiceError.network("Open-Meteo answered HTTP \(http.statusCode)")
            }
            return data
        } catch let e as ServiceError {
            throw e
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }
    }

    public static func search(_ query: String, session: URLSession = .shared) async throws -> [WeatherPlace] {
        guard let url = searchURL(query) else { return [] }
        return try parsePlaces(try await fetch(url, session: session))
    }

    public static func forecast(latitude: Double, longitude: Double, session: URLSession = .shared) async throws -> WeatherReport {
        guard let url = forecastURL(latitude: latitude, longitude: longitude) else { throw ServiceError.failed("bad coordinates") }
        return try parseForecast(try await fetch(url, session: session))
    }
}

extension Array {
    /// Element at `i`, or nil past the end (Open-Meteo series can be shorter than `time`).
    fileprivate subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
