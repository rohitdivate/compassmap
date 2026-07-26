import Foundation

/// A spot as the widgets see it: enough to draw a card, nothing more.
struct SharedSpot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var placeName: String?
    var coordinate: Coordinate
    var altitude: Double?
    var capturedAt: Date
    var thumbnailFilename: String?
    var tripName: String?
    var glyph: String?

    init(
        id: UUID,
        name: String,
        placeName: String? = nil,
        coordinate: Coordinate,
        altitude: Double? = nil,
        capturedAt: Date,
        thumbnailFilename: String? = nil,
        tripName: String? = nil,
        glyph: String? = nil
    ) {
        self.id = id
        self.name = name
        self.placeName = placeName
        self.coordinate = coordinate
        self.altitude = altitude
        self.capturedAt = capturedAt
        self.thumbnailFilename = thumbnailFilename
        self.tripName = tripName
        self.glyph = glyph
    }

    /// Where the widget can load this spot's thumbnail from, if one was written.
    var thumbnailURL: URL? {
        guard let thumbnailFilename else { return nil }
        return AppGroup.thumbnailsURL?.appendingPathComponent(thumbnailFilename)
    }

    /// `tradewind://spot?id=…` — opens the arrow screen for this spot. Coordinates ride along so
    /// the link still works for a recipient who does not have this spot saved.
    var deepLinkURL: URL {
        var components = URLComponents()
        components.scheme = AppGroup.urlScheme
        components.host = "spot"
        components.queryItems = [
            URLQueryItem(name: "id", value: id.uuidString),
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
            URLQueryItem(name: "name", value: name),
        ]
        // The fallback can only be reached if URLComponents rejects a scheme we control.
        return components.url ?? URL(string: "\(AppGroup.urlScheme)://spots")!
    }

    /// Human-facing subtitle: the geocoded place if we have one, else coordinates.
    var subtitle: String {
        if let placeName, !placeName.isEmpty { return placeName }
        return String(
            format: "%.4f°, %.4f°",
            coordinate.latitude,
            coordinate.longitude
        )
    }
}

/// Everything the widget extension and Live Activity need, in one small file that can be
/// decoded in a few milliseconds inside a timeline provider.
///
/// The app owns this file; widgets only ever read it. That means widgets never open the
/// SwiftData store, never wait on CloudKit, and never need the model schema to match.
struct SharedSnapshot: Codable, Sendable {

    /// Bumped if the shape changes incompatibly; a mismatch is treated as "no data" and
    /// the app rewrites it on next launch rather than failing loudly in a widget.
    static let currentVersion = 2

    var version: Int
    var updatedAt: Date
    var themeID: String
    var unitPreference: UnitPreference
    var spots: [SharedSpot]
    var pinnedSpotID: UUID?
    var lastKnownLocation: Coordinate?
    var lastKnownLocationDate: Date?

    init(
        version: Int = SharedSnapshot.currentVersion,
        updatedAt: Date = Date(),
        themeID: String,
        unitPreference: UnitPreference = .automatic,
        spots: [SharedSpot] = [],
        pinnedSpotID: UUID? = nil,
        lastKnownLocation: Coordinate? = nil,
        lastKnownLocationDate: Date? = nil
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.themeID = themeID
        self.unitPreference = unitPreference
        self.spots = spots
        self.pinnedSpotID = pinnedSpotID
        self.lastKnownLocation = lastKnownLocation
        self.lastKnownLocationDate = lastKnownLocationDate
    }

    /// A snapshot with nothing in it — what widgets show before the app has ever run.
    static func empty(themeID: String) -> SharedSnapshot {
        SharedSnapshot(themeID: themeID)
    }

    var isEmpty: Bool { spots.isEmpty }

    // MARK: - Queries the widgets run

    func spot(id: UUID?) -> SharedSpot? {
        guard let id else { return nil }
        return spots.first { $0.id == id }
    }

    /// Spots ordered by how far they are from `origin`, paired with that distance.
    func spotsByDistance(from origin: Coordinate?) -> [(spot: SharedSpot, metres: Double?)] {
        guard let origin, origin.isValid else {
            return spots
                .sorted { $0.capturedAt > $1.capturedAt }
                .map { ($0, nil) }
        }
        return spots
            .map { ($0, BearingMath.distance(from: origin, to: $0.coordinate)) }
            .sorted { lhs, rhs in lhs.1 < rhs.1 }
            .map { ($0.0, Optional($0.1)) }
    }

    /// The spot a widget should lead with: the pinned one if set, otherwise the nearest.
    func featuredSpot(from origin: Coordinate?) -> SharedSpot? {
        if let pinned = spot(id: pinnedSpotID) { return pinned }
        return spotsByDistance(from: origin).first?.spot
    }
}
