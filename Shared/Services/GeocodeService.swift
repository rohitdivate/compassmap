import CoreLocation
import Foundation

/// Turns coordinates into something a person would say.
///
/// An actor because it owns a cache, and because Apple rate-limits reverse geocoding hard
/// enough that serialising requests is a feature rather than a compromise. Failures are
/// silent: a spot with no place name simply shows its coordinates.
actor GeocodeService {

    static let shared = GeocodeService()

    private let geocoder = CLGeocoder()
    /// Keyed by coordinate rounded to ~11 m, which is well inside "same place".
    private var cache: [String: String] = [:]
    private var lastRequestAt: Date?
    /// Apple's limit is undocumented; one request per second has proved comfortable.
    private let minimumInterval: TimeInterval = 1.0

    func placeName(for coordinate: Coordinate) async -> String? {
        guard coordinate.isValid else { return nil }
        let key = cacheKey(for: coordinate)
        if let cached = cache[key] { return cached }

        if let lastRequestAt {
            let elapsed = Date().timeIntervalSince(lastRequestAt)
            if elapsed < minimumInterval {
                try? await Task.sleep(nanoseconds: UInt64((minimumInterval - elapsed) * 1_000_000_000))
            }
        }
        lastRequestAt = Date()

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
              let placemark = placemarks.first,
              let name = Self.describe(placemark)
        else { return nil }

        cache[key] = name
        return name
    }

    private func cacheKey(for coordinate: Coordinate) -> String {
        String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }

    /// Street, neighbourhood, town — never `placemark.name`, which for an arbitrary coordinate
    /// is usually the nearest business: a "random place" nobody asked about. The formatting rule
    /// itself lives in `PlaceNameFormatter`, pure and tested; this is only the CLPlacemark adapter,
    /// and `PlaceFields` has no slot the POI name could even be poured into.
    static func describe(_ placemark: CLPlacemark) -> String? {
        PlaceNameFormatter.line(from: PlaceFields(
            thoroughfare: placemark.thoroughfare,
            subLocality: placemark.subLocality,
            locality: placemark.locality,
            subAdministrativeArea: placemark.subAdministrativeArea,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country
        ))
    }
}
