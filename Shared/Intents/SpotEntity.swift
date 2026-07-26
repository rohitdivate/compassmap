import AppIntents
import Foundation

/// A spot, as Siri, Shortcuts and the widget configuration screen see it.
///
/// Backed by the shared snapshot rather than by SwiftData: these queries run inside other
/// processes, sometimes while the app has never been launched in this session, and opening a
/// CloudKit-backed store to answer "which spots exist" would be both slow and fragile.
struct SpotEntity: AppEntity, Identifiable, Hashable {

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Spot", numericFormat: "\(placeholder: .int) spots")
    }

    static var defaultQuery = SpotEntityQuery()

    var id: UUID
    var name: String
    var placeName: String?
    var latitude: Double
    var longitude: Double

    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    var displayRepresentation: DisplayRepresentation {
        if let placeName, !placeName.isEmpty {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(placeName)")
        }
        return DisplayRepresentation(title: "\(name)")
    }

    init(_ spot: SharedSpot) {
        id = spot.id
        name = spot.name
        placeName = spot.placeName
        latitude = spot.coordinate.latitude
        longitude = spot.coordinate.longitude
    }
}

/// Looks spots up by identifier, offers them as suggestions, and matches them by name so
/// "how far to the waterfall" resolves without the person picking from a list.
struct SpotEntityQuery: EntityQuery, EntityStringQuery {

    func entities(for identifiers: [UUID]) async throws -> [SpotEntity] {
        let snapshot = SharedSnapshotStore.load()
        let spots = snapshot?.spots ?? []
        return identifiers.compactMap { id in
            spots.first { $0.id == id }.map(SpotEntity.init)
        }
    }

    /// Nearest first when a location is known, so the widget configuration list starts with the
    /// spot you most likely mean.
    func suggestedEntities() async throws -> [SpotEntity] {
        guard let snapshot = SharedSnapshotStore.load() else { return [] }
        return snapshot
            .spotsByDistance(from: snapshot.lastKnownLocation)
            .map { SpotEntity($0.spot) }
    }

    func entities(matching string: String) async throws -> [SpotEntity] {
        let needle = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return try await suggestedEntities() }

        let snapshot = SharedSnapshotStore.load()
        return (snapshot?.spots ?? [])
            .filter { spot in
                spot.name.lowercased().contains(needle)
                    || (spot.placeName?.lowercased().contains(needle) ?? false)
                    || (spot.tripName?.lowercased().contains(needle) ?? false)
            }
            .map(SpotEntity.init)
    }
}
