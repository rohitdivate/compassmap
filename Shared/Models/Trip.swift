import Foundation
import SwiftData

/// A group of spots — one island, one week, one very long afternoon.
@Model
final class Trip {

    var id: UUID = UUID()
    var name: String = ""
    var subtitle: String?
    var createdAt: Date = Date()

    /// A trip can carry its own look, so opening the Sri Lanka trip feels different from
    /// opening the Thailand one. Nil means "use whatever the app is set to".
    var themeID: String?

    /// Optional to-many, as CloudKit requires. The inverse is declared here so `Spot.trip`
    /// stays a plain reference.
    @Relationship(deleteRule: .nullify, inverse: \Spot.trip)
    var spots: [Spot]? = []

    init(
        id: UUID = UUID(),
        name: String = "",
        subtitle: String? = nil,
        createdAt: Date = Date(),
        themeID: String? = nil,
        spots: [Spot]? = []
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.themeID = themeID
        self.spots = spots
    }
}

extension Trip {
    /// Living spots only — a trip does not count what sits in the trash.
    var orderedSpots: [Spot] {
        (spots ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    var spotCount: Int { orderedSpots.count }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled trip" : name
    }

    /// The spot whose photo fronts the trip: the most recent one with a thumbnail on disk.
    /// Chosen by thumbnail rather than by photo so answering never faults a blob — the old
    /// `coverPhotoData` walked every spot in the trip pulling photos out of the database.
    var coverSpot: Spot? {
        orderedSpots.first { $0.thumbnailFilename != nil }
    }
}
