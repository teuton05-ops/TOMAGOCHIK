import CoreLocation
import Foundation

/// Погода за окном: раз в полчаса узнаёт, где Мак (с точностью до километров), и спрашивает
/// у open-meteo.com, что там сейчас. Без разрешения на геолокацию погоды просто нет.
@MainActor
final class Weather: NSObject, CLLocationManagerDelegate {
    enum Kind { case clear, cloudy, rain, snow, fog }

    struct Now {
        let kind: Kind
        let temperature: Double
    }

    private(set) var current: Now?
    var onChange: ((Now?) -> Void)?
    private let location = CLLocationManager()
    private var timer: Timer?

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    private func refresh() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()  // ответ придёт в делегат
        case .authorizedAlways, .authorized: location.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        // Округляем до сотых: погоде хватает, а точное место никуда не уходит
        let lat = (c.latitude * 100).rounded() / 100, lon = (c.longitude * 100).rounded() / 100
        Task { @MainActor in await fetch(lat: lat, lon: lon) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func fetch(lat: Double, lon: Double) async {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let now = json["current"] as? [String: Any],
              let code = now["weather_code"] as? Int, let temperature = now["temperature_2m"] as? Double
        else { return }
        current = Now(kind: Self.kind(code), temperature: temperature)
        onChange?(current)
    }

    /// Коды WMO: https://open-meteo.com/en/docs
    private static func kind(_ code: Int) -> Kind {
        switch code {
        case 0, 1: .clear
        case 45, 48: .fog
        case 51...67, 80...82, 95...99: .rain
        case 71...77, 85, 86: .snow
        default: .cloudy
        }
    }
}
