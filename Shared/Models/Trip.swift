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

    /// The photo used for the trip's cover: the most recent spot that has one.
    var coverPhotoData: Data? {
        orderedSpots.first(where: { $0.photoData != nil })?.photoData
    }
}
