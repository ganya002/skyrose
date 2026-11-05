import CaelestiaCore
import CaelestiaServices
import SwiftUI

/// Debounced Open-Meteo city search for Settings › Bar and Shell › Weather.
@MainActor
final class CitySearchModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [WeatherPlace] = []
    @Published private(set) var searching = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    var search: (String) async throws -> [WeatherPlace] = { try await OpenMeteo.search($0) }

    func queryChanged() {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []; searching = false; error = nil
            return
        }
        searching = true
        let run = search
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                let r = try await run(q)
                guard !Task.isCancelled else { return }
                self?.results = r
                self?.error = r.isEmpty ? "No place called “\(q)”." : nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.results = []
                self?.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self?.searching = false
        }
    }

    func clear() {
        task?.cancel()
        query = ""; results = []; searching = false; error = nil
    }
}

struct WeatherSettingsCard: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var search = CitySearchModel()
    @Environment(\.look) var look
    var enabled: Bool

    var w: WeatherConfig { store.config.weather }

    var body: some View {
        Card {
            SectionLabel(text: "Weather")
            SettingRow(title: "City", detail: w.hasCity ? "\(w.city) · \(String(format: "%.2f, %.2f", w.latitude, w.longitude))" : "None: the dashboard shows no weather until you pick one.", icon: "mappin.and.ellipse") {
                if w.hasCity {
                    PillButton(title: "Remove", kind: .outline) { pick(nil) }
                        .accessibilityIdentifier("weather.removeCity")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(look[.onSurfaceVariant])
                    TextField("Search a city", text: $search.query)
                        .textFieldStyle(.plain).font(look.font(13.5)).foregroundStyle(look[.onSurface])
                        .onChange(of: search.query) { _, _ in search.queryChanged() }
                        .onSubmit { if let first = search.results.first { pick(first) } }
                        .accessibilityIdentifier("weather.citySearch")
                    if search.searching { ProgressView().controlSize(.small) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(look[.surfaceContainerHighest]))
                if let e = search.error {
                    Text(e).font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                }
                ForEach(search.results) { place in
                    Button { pick(place) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name).font(look.font(13.5, .medium)).foregroundStyle(look[.onSurface])
                                if !place.detail.isEmpty {
                                    Text(place.detail).font(look.font(11.5)).foregroundStyle(look[.onSurfaceVariant])
                                }
                            }
                            Spacer()
                            Text(String(format: "%.2f, %.2f", place.latitude, place.longitude)).font(look.mono(11)).foregroundStyle(look[.onSurfaceVariant])
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weather.result.\(place.id)")
                }
            }
            .padding(.leading, 40)
            .animation(look.motion.quick, value: search.results)
            SettingRow(title: "Use my location", detail: "Off by default. Asks for the Location permission; if it is not allowed, the city is used.", icon: "location") {
                PillToggle(isOn: store.bool(\.weather.useLocation, "weather.useLocation"), enabled: enabled, accessibilityLabel: "Use my location")
            }
            SettingRow(title: "Fahrenheit", detail: "Off: °C.", icon: "thermometer.medium") {
                PillToggle(isOn: store.bool(\.weather.fahrenheit, "weather.fahrenheit"), enabled: enabled, accessibilityLabel: "Fahrenheit")
            }
            Text(OpenMeteo.attribution + ". No account or API key.").font(look.font(11)).foregroundStyle(look[.onSurfaceVariant])
        }
    }

    /// Writes city, latitude and longitude together (one flush).
    func pick(_ place: WeatherPlace?) {
        let name = place?.displayName ?? ""
        let lat = place?.latitude ?? 0
        let lon = place?.longitude ?? 0
        store.set("weather.city", .string(name), update: { $0.weather.city = name }, coalesce: true)
        store.set("weather.latitude", .number(lat), update: { $0.weather.latitude = lat }, coalesce: true)
        store.set("weather.longitude", .number(lon), update: { $0.weather.longitude = lon })
        search.clear()
    }
}
