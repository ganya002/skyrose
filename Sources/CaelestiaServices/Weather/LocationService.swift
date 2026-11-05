import CoreLocation
import Foundation

/// One-shot CoreLocation fix for the weather (only when `weather.useLocation` is on, which is off
/// by default). Asks for the Location permission the first time; denied or failing → nil, and the
/// weather falls back to the city.
@MainActor
public final class LocationService: NSObject, CLLocationManagerDelegate {
    public struct Fix: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
        public var name: String
    }

    private var manager: CLLocationManager?
    private var waiting: [(Fix?) -> Void] = []

    public override init() { super.init() }

    public static var denied: Bool {
        let s = CLLocationManager().authorizationStatus
        return s == .denied || s == .restricted
    }

    public func locate(_ completion: @escaping (Fix?) -> Void) {
        guard CLLocationManager.locationServicesEnabled(), !Self.denied else { completion(nil); return }
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        let m = manager ?? CLLocationManager()
        manager = m
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        if m.authorizationStatus == .notDetermined {
            m.requestWhenInUseAuthorization()
        } else {
            m.requestLocation()
        }
    }

    private func finish(_ fix: Fix?) {
        let w = waiting
        waiting.removeAll()
        for c in w { c(fix) }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard !waiting.isEmpty else { return }
            switch status {
            case .authorized, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: finish(nil)
            default: break
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        MainActor.assumeIsolated {
            CLGeocoder().reverseGeocodeLocation(loc) { [weak self] marks, _ in
                let name = marks?.first.flatMap { $0.locality ?? $0.name } ?? "Current location"
                MainActor.assumeIsolated { self?.finish(Fix(latitude: lat, longitude: lon, name: name)) }
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }
}
