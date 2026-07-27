import Foundation

/// Turns a photo library's metadata into places.
///
/// PhotoKit cannot filter by location and deprecated Moments without replacement, so grouping
/// geotagged photos into "the hotel", "that beach" is this app's own arithmetic — and it lives
/// here, pure and tested, because a wrong radius quietly splits one hotel into three places or
/// merges a neighbourhood into one.
///
/// Two-stage: photos sorted by time become *sessions* (a visit ends after a three-hour gap or on
/// leaving the place radius), then sessions merge into *places* across days when their centres
/// fall within the radius. Score favours places visited repeatedly over one long photo spree.
enum PhotoClusters {

    /// One geotagged photo, metadata only — no pixels are ever needed for clustering.
    struct PhotoPoint: Equatable, Sendable {
        var id: String
        var latitude: Double
        var longitude: Double
        var capturedAt: Date
        var isFavorite: Bool = false

        var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    }

    /// A suggested place: where, how often, and which photo should stand for it.
    struct Place: Equatable, Sendable, Identifiable {
        var id: String { representativeID }
        var centroid: Coordinate
        var photoIDs: [String]
        var representativeID: String
        var photoCount: Int
        var visitCount: Int
        var firstAt: Date
        var lastAt: Date
        /// The library's dominant cluster over a long span is almost certainly home (or work) —
        /// presented separately, never as an ordinary suggestion.
        var isLikelyHome: Bool
    }

    /// Venue scale: below ~50 m GPS error fragments one hotel; above ~500 m a district merges.
    static let placeRadiusMetres: Double = 150
    /// A gap longer than this ends a visit.
    static let sessionGap: TimeInterval = 3 * 60 * 60
    /// A "session" that sprawls further than this was a walk or a drive, not a place.
    static let movingSessionSpreadMetres: Double = 400
    /// Fewer photos than this is noise, not a place worth suggesting.
    static let minimumPhotos = 2

    // MARK: - Clustering

    static func places(from points: [PhotoPoint], now: Date) -> [Place] {
        let sessions = sessions(from: points)
        let merged = merge(sessions: sessions)
        return rank(merged, now: now)
    }

    /// One visit: consecutive photos close in time and space.
    struct Session: Equatable, Sendable {
        var points: [PhotoPoint]
        var centroid: Coordinate
        var startedAt: Date
        var endedAt: Date
    }

    static func sessions(from points: [PhotoPoint]) -> [Session] {
        let sorted = points.sorted { $0.capturedAt < $1.capturedAt }
        var sessions: [Session] = []
        var current: [PhotoPoint] = []

        func close(_ batch: [PhotoPoint]) {
            guard !batch.isEmpty else { return }
            let centroid = centroid(of: batch)
            // A batch that sprawls was movement, not a stay.
            let spread = batch.map { BearingMath.distance(from: centroid, to: $0.coordinate) }.max() ?? 0
            guard spread <= movingSessionSpreadMetres else { return }
            sessions.append(Session(
                points: batch,
                centroid: centroid,
                startedAt: batch.first?.capturedAt ?? Date.distantPast,
                endedAt: batch.last?.capturedAt ?? Date.distantPast
            ))
        }

        for point in sorted {
            guard let last = current.last else {
                current = [point]
                continue
            }
            let gap = point.capturedAt.timeIntervalSince(last.capturedAt)
            let distance = BearingMath.distance(from: centroid(of: current), to: point.coordinate)
            if gap > sessionGap || distance > placeRadiusMetres {
                close(current)
                current = [point]
            } else {
                current.append(point)
            }
        }
        close(current)
        return sessions
    }

    /// Sessions whose centres share a radius are the same place on different days.
    private static func merge(sessions: [Session]) -> [Place] {
        var buckets: [[Session]] = []
        for session in sessions {
            if let index = buckets.firstIndex(where: { bucket in
                guard let anchor = bucket.first else { return false }
                return BearingMath.distance(from: anchor.centroid, to: session.centroid) <= placeRadiusMetres
            }) {
                buckets[index].append(session)
            } else {
                buckets.append([session])
            }
        }

        return buckets.compactMap { bucket in
            let points = bucket.flatMap(\.points)
            guard points.count >= minimumPhotos else { return nil }
            let sorted = points.sorted { $0.capturedAt < $1.capturedAt }
            return Place(
                centroid: centroid(of: points),
                photoIDs: sorted.map(\.id),
                representativeID: representative(of: sorted).id,
                photoCount: points.count,
                visitCount: bucket.count,
                firstAt: sorted.first?.capturedAt ?? .distantPast,
                lastAt: sorted.last?.capturedAt ?? .distantPast,
                isLikelyHome: false
            )
        }
    }

    /// Best first: photos × log(visits), a favourite photo counting extra. Home flagged, not
    /// ranked — it goes to its own row in the UI.
    private static func rank(_ places: [Place], now: Date) -> [Place] {
        guard !places.isEmpty else { return [] }
        let totalPhotos = places.reduce(0) { $0 + $1.photoCount }

        var ranked = places
        for index in ranked.indices {
            let place = ranked[index]
            let share = Double(place.photoCount) / Double(max(1, totalPhotos))
            let span = place.lastAt.timeIntervalSince(place.firstAt)
            // Dominant share of the library, visited across months: nobody's holiday looks like
            // that. Home is a fine thing to save — but knowingly, not as suggestion #1.
            ranked[index].isLikelyHome = share >= 0.3 && span > 60 * 24 * 3_600 && place.visitCount >= 5
        }

        return ranked.sorted { a, b in
            score(a) > score(b)
        }
    }

    static func score(_ place: Place) -> Double {
        Double(place.photoCount) * log(1 + Double(place.visitCount)) + Double(place.visitCount)
    }

    /// The photo that stands for the place: a favourite if there is one, else the middle of the
    /// stay — first and last photos are usually the walk in and the walk out.
    static func representative(of sorted: [PhotoPoint]) -> PhotoPoint {
        if let favorite = sorted.first(where: \.isFavorite) { return favorite }
        return sorted[sorted.count / 2]
    }

    static func centroid(of points: [PhotoPoint]) -> Coordinate {
        guard !points.isEmpty else { return Coordinate(latitude: 0, longitude: 0) }
        let lat = points.reduce(0.0) { $0 + $1.latitude } / Double(points.count)
        let lon = points.reduce(0.0) { $0 + $1.longitude } / Double(points.count)
        return Coordinate(latitude: lat, longitude: lon)
    }

    // MARK: - Copy

    static func summary(_ place: Place, calendar: Calendar = .current) -> String {
        let photos = "\(place.photoCount) \(place.photoCount == 1 ? "photo" : "photos")"
        let visits = "\(place.visitCount) \(place.visitCount == 1 ? "visit" : "visits")"
        return "\(photos) · \(visits)"
    }
}
