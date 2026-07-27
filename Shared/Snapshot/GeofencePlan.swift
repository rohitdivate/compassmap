import Foundation

/// Which spots get a geofence, and what the alert says.
///
/// iOS monitors at most 20 regions per app and silently rejects the rest, so *which* spots are
/// armed is a real decision rather than "all of them". It lives here — pure, Foundation-only,
/// testable — because a selection rule with a cap, a priority tier and a distance sort is exactly
/// the kind of thing that looks right in a simulator and drops someone's hotel on device.
enum GeofencePlan {

    struct Candidate: Sendable {
        var id: UUID
        var coordinate: Coordinate
        var isPinned: Bool
        var alertsEnabled: Bool
        var capturedAt: Date
        var name: String
        var note: String?
    }

    struct Region: Equatable, Sendable {
        var id: UUID
        var coordinate: Coordinate
        var radiusMetres: Double
        var name: String
        var note: String?
    }

    /// 200 m: far enough that the alert lands while walking up, close enough to mean "near".
    /// Also comfortably above GPS error in a city, where 50 m radii flap.
    static let radiusMetres: Double = 200

    /// Two of headroom under the OS's 20, so nothing else the process registers gets evicted.
    static let defaultLimit = 18

    /// The regions worth arming, best first.
    ///
    /// Only spots with alerts switched on; the pinned spot always makes the cut (it is the one the
    /// widgets lead with, so it is the one being navigated to); the rest by distance from the
    /// origin, or by recency when there is no fix to measure from.
    static func regions(
        from candidates: [Candidate],
        origin: Coordinate?,
        limit: Int = defaultLimit
    ) -> [Region] {
        let enabled = candidates.filter(\.alertsEnabled)

        let sorted = enabled.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if let origin {
                let da = BearingMath.distance(from: origin, to: a.coordinate)
                let db = BearingMath.distance(from: origin, to: b.coordinate)
                if da != db { return da < db }
            }
            return a.capturedAt > b.capturedAt
        }

        var seen = Set<UUID>()
        var result: [Region] = []
        for candidate in sorted {
            guard result.count < max(0, limit) else { break }
            guard seen.insert(candidate.id).inserted else { continue }
            result.append(Region(
                id: candidate.id,
                coordinate: candidate.coordinate,
                radiusMetres: radiusMetres,
                name: candidate.name,
                note: candidate.note
            ))
        }
        return result
    }

    // MARK: - What the alert says

    static func notificationTitle(spotName: String) -> String {
        "You're near \(spotName)"
    }

    /// The note is the payload — "Level 3, aisle F" is what the person at the garage door needs.
    static func notificationBody(note: String?) -> String {
        if let note, !note.isEmpty { return note }
        return "About 200 m away. Tap to point the arrow at it."
    }

    /// Region identifiers carry a prefix so re-arming can clear only what this app registered.
    static let regionPrefix = "tradewind-"

    static func regionIdentifier(spotID: UUID) -> String {
        regionPrefix + spotID.uuidString
    }

    static func spotID(fromRegionIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(regionPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(regionPrefix.count)))
    }
}
