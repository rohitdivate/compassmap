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

    /// Prefers the most specific useful thing: a named place, then a street, then a
    /// neighbourhood, then the town. Two components at most — this is a subtitle, not an
    /// address label.
    static func describe(_ placemark: CLPlacemark) -> String? {
        var parts: [String] = []

        if let poi = placemark.name, !poi.isEmpty, poi != placemark.thoroughfare {
            parts.append(poi)
        } else if let street = placemark.thoroughfare, !street.isEmpty {
            parts.append(street)
        } else if let area = placemark.subLocality, !area.isEmpty {
            parts.append(area)
        }

        if let town = placemark.locality, !town.isEmpty, !parts.contains(town) {
            parts.append(town)
        } else if let region = placemark.administrativeArea, !region.isEmpty, !parts.contains(region) {
            parts.append(region)
        } else if let country = placemark.country, !country.isEmpty, !parts.contains(country) {
            parts.append(country)
        }

        let joined = parts.prefix(2).joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }
}
