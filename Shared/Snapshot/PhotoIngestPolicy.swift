import Foundation

/// The decisions behind the automatic photo-library ingest, kept pure so they can be tested.
///
/// The ingest itself — permission, scanning, writing spots — lives in `PhotoIngestService` in
/// the app target. What belongs here is everything that could quietly go wrong in a way a test
/// would catch: when a pass is due, which clusters are genuinely new, and what kind of spot a
/// cluster becomes.
enum PhotoIngestPolicy {

    /// A pass per day is plenty — photo libraries change slowly, and each pass costs a scan.
    static let interval: TimeInterval = 24 * 3600

    /// Clusters saved per pass. Bounds the geocoding queue (one request per second) and keeps a
    /// first launch against a decade of photos from dumping a hundred spots at once; the rest
    /// arrive on later passes, best first.
    static let maxPerPass = 12

    /// Whether a pass should run at all.
    static func isDue(lastRunAt: Date?, enabled: Bool, onboarded: Bool, now: Date) -> Bool {
        guard enabled, onboarded else { return false }
        guard let lastRunAt else { return true }
        return now.timeIntervalSince(lastRunAt) >= interval
    }

    /// A stable key for a cluster, from its centroid rounded to four decimal places (~11 m).
    ///
    /// Once ingested — or deleted by the person — a key stays remembered, so a place removed on
    /// purpose does not reappear after the trash purges the spot it would de-dupe against.
    static func placeKey(for coordinate: Coordinate) -> String {
        String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }

    /// The clusters a pass should save: not already a spot (including trashed ones), not seen by
    /// a previous pass, capped at `maxPerPass` in the ranked order `PhotoClusters` produced.
    static func clustersToIngest(
        places: [PhotoClusters.Place],
        existingSpotCoordinates: [Coordinate],
        seenKeys: Set<String>
    ) -> [PhotoClusters.Place] {
        let fresh = places.filter { place in
            guard !seenKeys.contains(placeKey(for: place.centroid)) else { return false }
            return !existingSpotCoordinates.contains {
                BearingMath.distance(from: $0, to: place.centroid) <= PhotoClusters.placeRadiusMetres
            }
        }
        return Array(fresh.prefix(maxPerPass))
    }

    /// The library's dominant cluster is saved as Home; everything else is just a place.
    static func kind(for place: PhotoClusters.Place) -> PlaceKind {
        place.isLikelyHome ? .home : .place
    }
}
