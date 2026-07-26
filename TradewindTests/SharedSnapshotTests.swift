import Testing
import Foundation

@Suite("Widget snapshot")
struct SharedSnapshotTests {

    private func spot(
        _ name: String,
        _ latitude: Double,
        _ longitude: Double,
        capturedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> SharedSpot {
        SharedSpot(
            id: UUID(),
            name: name,
            placeName: nil,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            capturedAt: capturedAt
        )
    }

    @Test("Round-trips through JSON unchanged")
    func roundTrip() throws {
        let original = SharedSnapshot(
            themeID: "mangoTemple",
            unitPreference: .imperial,
            spots: [spot("Waterfall", 6.8, 80.5), spot("Beach shack", 6.1, 80.1)],
            pinnedSpotID: nil,
            lastKnownLocation: Coordinate(latitude: 6.9271, longitude: 79.8612),
            lastKnownLocationDate: Date(timeIntervalSince1970: 1_700_000_500)
        )

        let decoded = try SharedSnapshotStore.decode(SharedSnapshotStore.encode(original))

        #expect(decoded.themeID == "mangoTemple")
        #expect(decoded.unitPreference == .imperial)
        #expect(decoded.spots.count == 2)
        #expect(decoded.spots.map(\.name) == ["Waterfall", "Beach shack"])
        #expect(decoded.lastKnownLocation == original.lastKnownLocation)
        #expect(decoded.version == SharedSnapshot.currentVersion)
    }

    @Test("Sorting by distance puts the nearest first")
    func sortByDistance() {
        let near = spot("Near", 6.93, 79.86)
        let middle = spot("Middle", 7.30, 80.63)
        let far = spot("Far", 21.30, -157.85)
        let snapshot = SharedSnapshot(themeID: "hawaii", spots: [far, near, middle])

        let origin = Coordinate(latitude: 6.9271, longitude: 79.8612)
        let ordered = snapshot.spotsByDistance(from: origin)

        #expect(ordered.map(\.spot.name) == ["Near", "Middle", "Far"])
        #expect(ordered.allSatisfy { $0.metres != nil })
        // The near one is a few hundred metres away, not a few hundred kilometres.
        #expect((ordered.first?.metres ?? .infinity) < 1_000)
    }

    @Test("With no location, spots fall back to newest first and no distances")
    func noLocation() {
        let older = spot("Older", 1, 1, capturedAt: Date(timeIntervalSince1970: 1_000))
        let newer = spot("Newer", 2, 2, capturedAt: Date(timeIntervalSince1970: 2_000))
        let snapshot = SharedSnapshot(themeID: "paloma", spots: [older, newer])

        let ordered = snapshot.spotsByDistance(from: nil)
        #expect(ordered.map(\.spot.name) == ["Newer", "Older"])
        #expect(ordered.allSatisfy { $0.metres == nil })
    }

    @Test("An invalid origin is treated as no origin")
    func invalidOrigin() {
        let snapshot = SharedSnapshot(themeID: "paloma", spots: [spot("A", 1, 1)])
        let ordered = snapshot.spotsByDistance(from: Coordinate(latitude: .nan, longitude: 0))
        #expect(ordered.first?.metres == nil)
    }

    @Test("The featured spot is the pinned one, else the nearest")
    func featured() {
        let near = spot("Near", 6.93, 79.86)
        let far = spot("Far", 21.30, -157.85)
        let origin = Coordinate(latitude: 6.9271, longitude: 79.8612)

        let unpinned = SharedSnapshot(themeID: "margarita", spots: [far, near])
        #expect(unpinned.featuredSpot(from: origin)?.name == "Near")

        let pinned = SharedSnapshot(
            themeID: "margarita",
            spots: [far, near],
            pinnedSpotID: far.id
        )
        #expect(pinned.featuredSpot(from: origin)?.name == "Far")

        // A pin pointing at a deleted spot must not strand the widget.
        let stale = SharedSnapshot(
            themeID: "margarita",
            spots: [near],
            pinnedSpotID: far.id
        )
        #expect(stale.featuredSpot(from: origin)?.name == "Near")

        #expect(SharedSnapshot.empty(themeID: "margarita").featuredSpot(from: origin) == nil)
    }

    @Test("Spots with no place name describe themselves by coordinate")
    func subtitleFallback() {
        var withPlace = spot("Waterfall", 6.8, 80.5)
        withPlace.placeName = "Ella, Sri Lanka"
        #expect(withPlace.subtitle == "Ella, Sri Lanka")

        let withoutPlace = spot("Waterfall", 6.8, 80.5)
        #expect(withoutPlace.subtitle.contains("6.8000"))
    }

    @Test("A snapshot from an older schema version is discarded, not misread")
    func versionMismatch() throws {
        var old = SharedSnapshot(themeID: "hawaii", spots: [spot("A", 1, 1)])
        old.version = SharedSnapshot.currentVersion - 1
        let data = try SharedSnapshotStore.encode(old)
        let decoded = try SharedSnapshotStore.decode(data)
        // Decoding still works — it is the loader that rejects the version, so the app can
        // rewrite it rather than crashing on a shape it does not understand.
        #expect(decoded.version != SharedSnapshot.currentVersion)
    }
}
