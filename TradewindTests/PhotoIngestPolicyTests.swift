import Foundation
import Testing

/// The rules behind the automatic photo ingest. The stakes are quiet ones: a wrong de-dupe
/// radius resurrects a place someone deleted, a wrong gate scans a library that was told not
/// to be scanned.
@Suite("Photo ingest policy")
struct PhotoIngestPolicyTests {

    private let cafe = Coordinate(latitude: 51.5065, longitude: -0.0920)
    private let lookout = Coordinate(latitude: 51.5387, longitude: -0.1607)
    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    private func place(
        _ id: String,
        at coordinate: Coordinate,
        photoCount: Int = 3,
        isLikelyHome: Bool = false
    ) -> PhotoClusters.Place {
        PhotoClusters.Place(
            centroid: coordinate,
            photoIDs: [id],
            representativeID: id,
            photoCount: photoCount,
            visitCount: 1,
            firstAt: t0,
            lastAt: t0,
            isLikelyHome: isLikelyHome
        )
    }

    // MARK: - Gating

    @Test("A pass is due only when enabled, onboarded, and a day has passed")
    func gating() {
        #expect(PhotoIngestPolicy.isDue(lastRunAt: nil, enabled: true, onboarded: true, now: t0))
        #expect(!PhotoIngestPolicy.isDue(lastRunAt: nil, enabled: false, onboarded: true, now: t0))
        #expect(!PhotoIngestPolicy.isDue(lastRunAt: nil, enabled: true, onboarded: false, now: t0))

        let recent = t0.addingTimeInterval(-3600)
        #expect(!PhotoIngestPolicy.isDue(lastRunAt: recent, enabled: true, onboarded: true, now: t0))

        let yesterday = t0.addingTimeInterval(-PhotoIngestPolicy.interval)
        #expect(PhotoIngestPolicy.isDue(lastRunAt: yesterday, enabled: true, onboarded: true, now: t0))
    }

    // MARK: - Keys

    @Test("A place key is the centroid at four decimal places, stable and locale-proof")
    func keyRounding() {
        let key = PhotoIngestPolicy.placeKey(for: Coordinate(latitude: 51.50654, longitude: -0.09204))
        #expect(key == "51.5065,-0.0920")
        // Two coordinates ~1 m apart share a key; the key is a memory, not a search index.
        let nudged = PhotoIngestPolicy.placeKey(for: Coordinate(latitude: 51.506542, longitude: -0.092041))
        #expect(key == nudged)
    }

    // MARK: - Selection

    @Test("A cluster within the place radius of an existing spot is not ingested again")
    func geometryDeDupe() {
        // ~100 m north of the cafe: inside the 150 m radius, so still "the same place".
        let nearCafe = Coordinate(latitude: cafe.latitude + 100 / 111_000, longitude: cafe.longitude)
        let chosen = PhotoIngestPolicy.clustersToIngest(
            places: [place("cafe", at: cafe), place("lookout", at: lookout)],
            existingSpotCoordinates: [nearCafe],
            seenKeys: []
        )
        #expect(chosen.map(\.id) == ["lookout"])
    }

    @Test("A cluster well clear of every spot is ingested")
    func distantClusterSurvives() {
        // ~300 m away: outside the radius, a different place.
        let farFromCafe = Coordinate(latitude: cafe.latitude + 300 / 111_000, longitude: cafe.longitude)
        let chosen = PhotoIngestPolicy.clustersToIngest(
            places: [place("cafe", at: cafe)],
            existingSpotCoordinates: [farFromCafe],
            seenKeys: []
        )
        #expect(chosen.map(\.id) == ["cafe"])
    }

    @Test("A seen key suppresses a cluster even with no spot left to de-dupe against")
    func seenKeysSuppress() {
        let chosen = PhotoIngestPolicy.clustersToIngest(
            places: [place("cafe", at: cafe)],
            existingSpotCoordinates: [],
            seenKeys: [PhotoIngestPolicy.placeKey(for: cafe)]
        )
        #expect(chosen.isEmpty)
    }

    @Test("A pass takes the first dozen in ranked order and leaves the rest for next time")
    func capKeepsRankedOrder() {
        let places = (0..<20).map { index in
            place(
                "p\(index)",
                at: Coordinate(latitude: 40.0 + Double(index) * 0.01, longitude: -70.0)
            )
        }
        let chosen = PhotoIngestPolicy.clustersToIngest(
            places: places,
            existingSpotCoordinates: [],
            seenKeys: []
        )
        #expect(chosen.count == PhotoIngestPolicy.maxPerPass)
        #expect(chosen.map(\.id) == (0..<PhotoIngestPolicy.maxPerPass).map { "p\($0)" })
    }

    // MARK: - Kinds

    @Test("The library's dominant cluster is saved as Home; everything else is a place")
    func homeKind() {
        #expect(PhotoIngestPolicy.kind(for: place("home", at: cafe, isLikelyHome: true)) == .home)
        #expect(PhotoIngestPolicy.kind(for: place("cafe", at: cafe)) == .place)
    }
}
