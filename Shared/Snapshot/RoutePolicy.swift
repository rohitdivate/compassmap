import Foundation

/// When to ask for a real walking route, and what to say about the answer.
///
/// The compass's distance is a straight line, and streets are not straight — Google Maps says
/// 12 minutes where the crow says 700 m. The fix is a real routing request (MKDirections:
/// Apple's own router, free, no key, worldwide — the only walking API that costs nothing at any
/// scale and needs no account). But route requests are rate-limited and cost battery, so *when*
/// to ask is a decision: this type owns it, pure and tested, along with the honest fallback for
/// the middle of a lake where no router has an answer.
enum RoutePolicy {

    /// A route request that was made, and where from.
    struct Request: Equatable, Sendable {
        var origin: Coordinate
        var destination: Coordinate
        var at: Date
    }

    /// Re-ask once the person has moved this far from where the last answer was computed —
    /// a street network does not change meaningfully in fewer metres than this.
    static let refreshDistanceMetres: Double = 120

    /// …or when the answer is this old, whatever the movement. Traffic does not matter on foot,
    /// but a stale route after a wrong turn does.
    static let refreshInterval: TimeInterval = 180

    /// Below this crow-flies distance a route adds nothing: the arrow is already the answer,
    /// and routers routinely return "unroutable" for two points on the same plaza.
    static let minimumUsefulCrowMetres: Double = 120

    static func shouldRequest(
        previous: Request?,
        origin: Coordinate,
        destination: Coordinate,
        crowMetres: Double,
        now: Date
    ) -> Bool {
        guard crowMetres >= minimumUsefulCrowMetres else { return false }
        guard let previous else { return true }
        if previous.destination != destination { return true }
        if now.timeIntervalSince(previous.at) >= refreshInterval { return true }
        return BearingMath.distance(from: previous.origin, to: origin) >= refreshDistanceMetres
    }

    // MARK: - The fallback estimate

    /// Streets detour. Across cities the walked distance runs ~20–50% over the straight line;
    /// 1.35 is the well-worn planning factor. Used only when routing has no answer, and always
    /// labelled as an estimate.
    static let detourFactor: Double = 1.35

    static func estimatedWalkMetres(crowMetres: Double) -> Double {
        crowMetres * detourFactor
    }

    // MARK: - Presentation

    /// What the walking pill should say.
    ///
    /// A real route reads as fact ("14 min · 1.1 km on foot"); the estimate admits itself
    /// ("~9 min walk"); and a route wildly shorter than the straight line is impossible, so it
    /// is treated as no answer rather than shown.
    enum Readout: Equatable {
        case routed(minutes: Int, distanceMetres: Double)
        case estimated(minutes: Int)
        case none
    }

    static func readout(
        routeMetres: Double?,
        routeSeconds: TimeInterval?,
        crowMetres: Double?
    ) -> Readout {
        if let routeMetres, let routeSeconds, routeSeconds > 0 {
            // A router claiming a walking path meaningfully shorter than the straight line is
            // broken data, not a shortcut through the earth.
            if let crowMetres, routeMetres < crowMetres * 0.8 {
                return fallback(crowMetres: crowMetres)
            }
            return .routed(minutes: minutes(from: routeSeconds), distanceMetres: routeMetres)
        }
        return fallback(crowMetres: crowMetres)
    }

    private static func fallback(crowMetres: Double?) -> Readout {
        guard let crowMetres, crowMetres >= minimumUsefulCrowMetres else { return .none }
        // 4.7 km/h, the same pace the old crow-flies label assumed — applied to the detoured
        // distance, which is what makes this a better guess than before rather than a new lie.
        let seconds = estimatedWalkMetres(crowMetres: crowMetres) / (4.7 / 3.6)
        return .estimated(minutes: minutes(from: seconds))
    }

    private static func minutes(from seconds: TimeInterval) -> Int {
        max(1, Int((seconds / 60).rounded()))
    }
}
