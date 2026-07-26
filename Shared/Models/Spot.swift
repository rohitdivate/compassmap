import Foundation
import SwiftData

/// A place you photographed and might want to walk back to.
///
/// Every property is optional or defaulted and there are no unique constraints, because
/// those are CloudKit's rules for a SwiftData store that syncs. Breaking any of them makes
/// the container fail to open on a device with iCloud enabled — a failure that only shows up
/// on real hardware, so the constraints are respected here rather than discovered later.
@Model
final class Spot {

    /// Stable identity used by widgets, deep links and App Intents. Not a unique attribute
    /// (CloudKit forbids those) — uniqueness is maintained by only ever creating one.
    var id: UUID = UUID()

    /// What the person called it. Never empty in practice; `displayName` covers the gap.
    var name: String = ""

    /// Reverse-geocoded description, filled in asynchronously after capture.
    var placeName: String?

    var latitude: Double = 0
    var longitude: Double = 0
    /// Metres above sea level at capture, when the fix included it.
    var altitude: Double?
    /// Horizontal accuracy of the fix, in metres. Shown so a bad fix is visible rather than
    /// silently making the arrow wrong.
    var horizontalAccuracy: Double?

    var capturedAt: Date = Date()
    /// Which way the phone was facing when the shutter fired, so the photo can be shown the
    /// right way up relative to north on the map.
    var headingAtCapture: Double?

    var note: String?
    /// An emoji the person picked, used as the spot's mark where a photo would be too big.
    var glyph: String?

    /// The spot the widgets lead with. Only one spot is pinned at a time; `SpotStore`
    /// enforces that.
    var isPinned: Bool = false

    /// Full-size JPEG. External storage keeps the database small and lets CloudKit move the
    /// bytes as an asset rather than inline.
    @Attribute(.externalStorage) var photoData: Data?

    /// Filename of the widget-sized copy inside the App Group container.
    var thumbnailFilename: String?

    var trip: Trip?

    init(
        id: UUID = UUID(),
        name: String = "",
        placeName: String? = nil,
        latitude: Double = 0,
        longitude: Double = 0,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        capturedAt: Date = Date(),
        headingAtCapture: Double? = nil,
        note: String? = nil,
        glyph: String? = nil,
        isPinned: Bool = false,
        photoData: Data? = nil,
        thumbnailFilename: String? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.name = name
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.capturedAt = capturedAt
        self.headingAtCapture = headingAtCapture
        self.note = note
        self.glyph = glyph
        self.isPinned = isPinned
        self.photoData = photoData
        self.thumbnailFilename = thumbnailFilename
        self.trip = trip
    }
}

extension Spot {

    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Never blank: falls back to the place name, then to a date.
    var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let placeName, !placeName.isEmpty { return placeName }
        return Self.fallbackNameFormatter.string(from: capturedAt)
    }

    var subtitle: String {
        if let placeName, !placeName.isEmpty { return placeName }
        return String(format: "%.4f°, %.4f°", latitude, longitude)
    }

    /// The lightweight form the widgets read.
    var sharedForm: SharedSpot {
        SharedSpot(
            id: id,
            name: displayName,
            placeName: placeName,
            coordinate: coordinate,
            altitude: altitude,
            capturedAt: capturedAt,
            thumbnailFilename: thumbnailFilename,
            tripName: trip?.name,
            glyph: glyph
        )
    }

    /// `tradewind://spot?id=…` — opens straight onto the arrow for this spot.
    var deepLinkURL: URL? {
        var components = URLComponents()
        components.scheme = AppGroup.urlScheme
        components.host = "spot"
        components.queryItems = [
            URLQueryItem(name: "id", value: id.uuidString),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "name", value: displayName),
        ]
        return components.url
    }

    private static let fallbackNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
