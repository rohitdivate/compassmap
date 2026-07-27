import Foundation
import MapKit

/// Asks Apple's router how far the walk really is.
///
/// MKDirections is the one walking-directions source that is free at any scale, needs no API
/// key, and covers the world as well as Apple Maps does — which is why it is the only router
/// this app talks to. `RoutePolicy` (pure, tested) decides *when* a request is worth making and
/// what to show when the answer is missing; this actor only performs the ask.
///
/// An actor because it owns a cache and an in-flight guard: the arrow screen re-renders on
/// every location fix, and only one ETA request should exist at a time.
actor WalkingRouteService {

    static let shared = WalkingRouteService()

    struct Answer: Equatable, Sendable {
        var distanceMetres: Double
        var expectedSeconds: TimeInterval
    }

    /// Keyed by origin and destination rounded to ~100 m — the same grid `RoutePolicy` refreshes
    /// on, so cache hits and refresh decisions agree with each other.
    private var cache: [String: Answer] = [:]
    private var inFlightKey: String?

    func walkingRoute(from origin: Coordinate, to destination: Coordinate) async -> Answer? {
        let key = cacheKey(from: origin, to: destination)
        if let cached = cache[key] { return cached }
        guard inFlightKey != key else { return nil }
        inFlightKey = key
        defer { inFlightKey = nil }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: origin.latitude, longitude: origin.longitude
        )))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: destination.latitude, longitude: destination.longitude
        )))
        request.transportType = .walking

        // The ETA call returns exactly the two numbers needed and is the cheapest thing
        // MKDirections offers — no polyline to download for a screen that only shows an arrow.
        guard let response = try? await MKDirections(request: request).calculateETA() else {
            return nil
        }
        let answer = Answer(
            distanceMetres: response.distance,
            expectedSeconds: response.expectedTravelTime
        )
        cache[key] = answer
        return answer
    }

    private func cacheKey(from origin: Coordinate, to destination: Coordinate) -> String {
        String(
            format: "%.3f,%.3f>%.3f,%.3f",
            origin.latitude, origin.longitude,
            destination.latitude, destination.longitude
        )
    }
}
