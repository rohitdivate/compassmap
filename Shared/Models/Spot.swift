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

    /// Local indexes for the three predicates every fetch runs on: alive-vs-trash, the
    /// newest-first sort, and id lookup. Indexes are store metadata, not schema — CloudKit
    /// never sees them, so the sync rules above are untouched.
    #Index<Spot>([\.deletedAt], [\.capturedAt], [\.id])

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

    /// When a "remind me" notification is due to fire, or nil when none is set. A past date means
    /// the notification already fired; `MeterReminder.isActive` is the read that matters.
    var reminderAt: Date?

    /// What sort of place this is — `PlaceKind.rawValue`.
    ///
    /// Stored as an optional string rather than the enum so CloudKit's rules hold and so an
    /// unrecognised value from a future build degrades to the default instead of failing to decode.
    /// Read it through `placeKind`, never directly.
    var kindRaw: String?

    /// The spot the widgets lead with. Only one spot is pinned at a time; `SpotStore`
    /// enforces that.
    var isPinned: Bool = false

    /// Whether to notify on coming within range of this spot. Off by default: a geofence per
    /// spot would burn the 20-region budget on places nobody is walking back to.
    var alertsEnabled: Bool = false

    /// Set when the spot is deleted. Deletion is soft — the spot vanishes from every list but
    /// sits in Recently Deleted for `TrashPolicy.retentionDays`, so a slip of the thumb is not
    /// the end of a memory. Nil means alive. Optional, so CloudKit's rules hold.
    var deletedAt: Date?

    /// Where the spot came from, when it was not made by hand — `"photoLibrary"` for places the
    /// automatic ingest found. Nil for captures and imports. Optional string, not an enum, for
    /// the same CloudKit and forward-compatibility reasons as `kindRaw`.
    var sourceRaw: String?

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
        kind: PlaceKind = .place,
        sourceRaw: String? = nil,
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
        self.kindRaw = kind.rawValue
        self.sourceRaw = sourceRaw
        self.trip = trip
    }
}

extension Spot {

    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    /// The spot's kind, tolerating anything unexpected on disk.
    var placeKind: PlaceKind {
        get { PlaceKind.from(rawValue: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    /// True when there is no photograph — a station or a hotel saved from a link or the calendar.
    /// The gallery and detail screens lean on the kind's symbol instead of a picture.
    var hasPhoto: Bool {
        guard let photoData else { return false }
        return !photoData.isEmpty
    }

    /// The `sourceRaw` value for spots the automatic photo-library ingest created.
    static let photoLibrarySource = "photoLibrary"

    /// True when the automatic photo-library ingest created this spot.
    var isFromPhotoLibrary: Bool { sourceRaw == Self.photoLibrarySource }

    /// Never blank: falls back to the place name, then — for an ingested place still waiting on
    /// the geocoder — to "Somewhere you've been", then to a date.
    var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let placeName, !placeName.isEmpty { return placeName }
        if isFromPhotoLibrary { return "Somewhere you've been" }
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
            glyph: glyph,
            kindRaw: kindRaw
        )
    }

    /// This spot as a line in the backup file — every stored field, so a restore is faithful.
    var backupRecord: BackupArchive.SpotRecord {
        BackupArchive.SpotRecord(
            id: id,
            name: name,
            placeName: placeName,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            capturedAt: capturedAt,
            headingAtCapture: headingAtCapture,
            note: note,
            glyph: glyph,
            kindRaw: kindRaw,
            isPinned: isPinned,
            alertsEnabled: alertsEnabled,
            deletedAt: deletedAt,
            reminderAt: reminderAt,
            sourceRaw: sourceRaw,
            tripID: trip?.id,
            photoFilename: hasPhoto ? BackupArchive.photoFilename(spotID: id) : nil
        )
    }

    /// What `GeofencePlan` needs to know to decide whether this spot deserves one of the
    /// twenty regions iOS will monitor.
    var geofenceCandidate: GeofencePlan.Candidate {
        GeofencePlan.Candidate(
            id: id,
            coordinate: coordinate,
            isPinned: isPinned,
            alertsEnabled: alertsEnabled,
            capturedAt: capturedAt,
            name: displayName,
            note: note
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
