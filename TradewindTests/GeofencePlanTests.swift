import Foundation
import Testing

/// iOS caps region monitoring at 20 per app and silently drops the excess, so which spots get a
/// geofence is a rule worth pinning — a wrong sort here means someone's hotel quietly loses its
/// alert to a coffee shop saved yesterday.
@Suite("Geofence planning")
struct GeofencePlanTests {

    private static let london = Coordinate(latitude: 51.5074, longitude: -0.1278)

    /// A candidate near London, offset north by roughly `km` kilometres.
    private func candidate(
        kmNorth: Double,
        pinned: Bool = false,
        alerts: Bool = true,
        capturedAt: Date = Date(timeIntervalSince1970: 1_000_000),
        name: String = "Spot",
        note: String? = nil
    ) -> GeofencePlan.Candidate {
        GeofencePlan.Candidate(
            id: UUID(),
            coordinate: Coordinate(
                latitude: Self.london.latitude + kmNorth / 111.0,
                longitude: Self.london.longitude
            ),
            isPinned: pinned,
            alertsEnabled: alerts,
            capturedAt: capturedAt,
            name: name,
            note: note
        )
    }

    @Test("Only spots with alerts switched on are armed")
    func alertsOffExcluded() {
        let on = candidate(kmNorth: 1, alerts: true)
        let off = candidate(kmNorth: 2, alerts: false)
        let regions = GeofencePlan.regions(from: [off, on], origin: Self.london)
        #expect(regions.map(\.id) == [on.id])
    }

    @Test("The cap is respected")
    func capRespected() {
        let candidates = (0..<30).map { candidate(kmNorth: Double($0)) }
        let regions = GeofencePlan.regions(from: candidates, origin: Self.london)
        #expect(regions.count == GeofencePlan.defaultLimit)
        #expect(GeofencePlan.defaultLimit < 20)
    }

    @Test("The pinned spot beats a nearer unpinned one")
    func pinnedBeatsNearer() {
        let near = candidate(kmNorth: 1)
        let farButPinned = candidate(kmNorth: 50, pinned: true)
        let regions = GeofencePlan.regions(from: [near, farButPinned], origin: Self.london, limit: 1)
        #expect(regions.map(\.id) == [farButPinned.id])
    }

    @Test("With an origin, nearer spots win the remaining slots")
    func nearestFirst() {
        let far = candidate(kmNorth: 30)
        let near = candidate(kmNorth: 1)
        let middle = candidate(kmNorth: 10)
        let regions = GeofencePlan.regions(from: [far, near, middle], origin: Self.london)
        #expect(regions.map(\.id) == [near.id, middle.id, far.id])
    }

    @Test("With no origin, recency decides")
    func recencyWithoutOrigin() {
        let old = candidate(kmNorth: 1, capturedAt: Date(timeIntervalSince1970: 1_000))
        let recent = candidate(kmNorth: 30, capturedAt: Date(timeIntervalSince1970: 2_000_000))
        let regions = GeofencePlan.regions(from: [old, recent], origin: nil, limit: 1)
        #expect(regions.map(\.id) == [recent.id])
    }

    @Test("Every region carries the 200 m radius")
    func radius() {
        let regions = GeofencePlan.regions(from: [candidate(kmNorth: 1)], origin: nil)
        #expect(regions.first?.radiusMetres == 200)
        #expect(GeofencePlan.radiusMetres == 200)
    }

    @Test("The notification body is the note when one exists — that is the payload")
    func bodyCarriesNote() {
        #expect(GeofencePlan.notificationBody(note: "Level 3, aisle F") == "Level 3, aisle F")
        #expect(GeofencePlan.notificationBody(note: "") == GeofencePlan.notificationBody(note: nil))
        #expect(GeofencePlan.notificationTitle(spotName: "Harbour Hotel") == "You're near Harbour Hotel")
    }

    @Test("Region identifiers round-trip and reject what this app did not register")
    func identifierRoundTrip() {
        let id = UUID()
        let identifier = GeofencePlan.regionIdentifier(spotID: id)
        #expect(identifier.hasPrefix("tradewind-"))
        #expect(GeofencePlan.spotID(fromRegionIdentifier: identifier) == id)
        #expect(GeofencePlan.spotID(fromRegionIdentifier: "someone-else") == nil)
    }
}
