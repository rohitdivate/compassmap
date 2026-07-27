import Foundation
import Testing

/// The compass's number is a straight line and streets are not — these pin when the app asks
/// Apple's router for the truth, and what it admits when there is no answer.
@Suite("Walking route policy")
struct RoutePolicyTests {

    private let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
    private let camden = Coordinate(latitude: 51.5390, longitude: -0.1426)
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func moved(_ metres: Double, from origin: Coordinate) -> Coordinate {
        Coordinate(latitude: origin.latitude + metres / 111_000, longitude: origin.longitude)
    }

    @Test("First sight of a destination asks")
    func firstAsk() {
        #expect(RoutePolicy.shouldRequest(
            previous: nil, origin: london, destination: camden, crowMetres: 3_600, now: t0
        ))
    }

    @Test("Standing still with a fresh answer does not re-ask")
    func noChurn() {
        let previous = RoutePolicy.Request(origin: london, destination: camden, at: t0)
        #expect(!RoutePolicy.shouldRequest(
            previous: previous,
            origin: moved(20, from: london),
            destination: camden,
            crowMetres: 3_600,
            now: t0.addingTimeInterval(30)
        ))
    }

    @Test("Moving far enough re-asks; so does staleness; so does a new destination")
    func refreshTriggers() {
        let previous = RoutePolicy.Request(origin: london, destination: camden, at: t0)
        #expect(RoutePolicy.shouldRequest(
            previous: previous,
            origin: moved(RoutePolicy.refreshDistanceMetres + 5, from: london),
            destination: camden,
            crowMetres: 3_400,
            now: t0.addingTimeInterval(30)
        ))
        #expect(RoutePolicy.shouldRequest(
            previous: previous,
            origin: london,
            destination: camden,
            crowMetres: 3_600,
            now: t0.addingTimeInterval(RoutePolicy.refreshInterval)
        ))
        #expect(RoutePolicy.shouldRequest(
            previous: previous,
            origin: london,
            destination: moved(500, from: camden),
            crowMetres: 3_100,
            now: t0.addingTimeInterval(10)
        ))
    }

    @Test("Standing next to the spot never asks — the arrow is the answer")
    func tooCloseToBother() {
        #expect(!RoutePolicy.shouldRequest(
            previous: nil, origin: london, destination: camden, crowMetres: 80, now: t0
        ))
    }

    @Test("A real route reads as fact")
    func routedReadout() {
        let readout = RoutePolicy.readout(routeMetres: 1_100, routeSeconds: 840, crowMetres: 800)
        #expect(readout == .routed(minutes: 14, distanceMetres: 1_100))
    }

    @Test("No route falls back to a detour-factored estimate that admits itself")
    func estimatedReadout() {
        let readout = RoutePolicy.readout(routeMetres: nil, routeSeconds: nil, crowMetres: 1_000)
        // 1350 m at 4.7 km/h is about 17 minutes.
        #expect(readout == .estimated(minutes: 17))
    }

    @Test("A route shorter than the straight line is broken data, not a shortcut")
    func impossibleRouteRejected() {
        let readout = RoutePolicy.readout(routeMetres: 300, routeSeconds: 240, crowMetres: 1_000)
        #expect(readout == .estimated(minutes: 17))
    }

    @Test("Nothing to say when close and unrouted")
    func noneWhenClose() {
        #expect(RoutePolicy.readout(routeMetres: nil, routeSeconds: nil, crowMetres: 60) == .none)
        #expect(RoutePolicy.readout(routeMetres: nil, routeSeconds: nil, crowMetres: nil) == .none)
    }
}
