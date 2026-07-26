import Foundation

/// A spot plus where it is relative to you right now.
struct RankedSpot: Identifiable {
    let spot: Spot
    let metres: Double?
    let bearing: Double?

    var id: UUID { spot.id }

    /// Rotation for a mini arrow on a card, given the direction the phone is facing.
    func arrowAngle(heading: Double?) -> Double {
        guard let bearing else { return 0 }
        guard let heading else { return bearing }
        return BearingMath.relativeAngle(bearing: bearing, heading: heading)
    }
}

/// Orders spots by how far away they are — the ordering the whole app is built around.
///
/// With no location fix there is nothing to sort by, so it falls back to most recent first
/// rather than leaving the list in database order.
enum SpotRanking {

    static func rank(_ spots: [Spot], from origin: Coordinate?) -> [RankedSpot] {
        guard let origin, origin.isValid else {
            return spots
                .sorted { $0.capturedAt > $1.capturedAt }
                .map { RankedSpot(spot: $0, metres: nil, bearing: nil) }
        }

        return spots
            .map { spot in
                RankedSpot(
                    spot: spot,
                    metres: BearingMath.distance(from: origin, to: spot.coordinate),
                    bearing: BearingMath.initialBearing(from: origin, to: spot.coordinate)
                )
            }
            .sorted { lhs, rhs in
                (lhs.metres ?? .greatestFiniteMagnitude) < (rhs.metres ?? .greatestFiniteMagnitude)
            }
    }

    /// The pinned spot if there is one, otherwise the nearest. Matches what the widgets show, so
    /// the app and the home screen never disagree about which spot is "yours".
    static func featured(in ranked: [RankedSpot]) -> RankedSpot? {
        ranked.first { $0.spot.isPinned } ?? ranked.first
    }
}
