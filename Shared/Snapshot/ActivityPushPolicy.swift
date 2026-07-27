import Foundation

/// When an in-progress walk is worth pushing to the Live Activity.
///
/// The pointer on the Lock Screen looked frozen, and the policy was why. The old rule required
/// distance to have changed by 20 m **and** 8 seconds to have passed — and it did not look at bearing
/// at all. At walking pace 20 m is about fifteen seconds, so rounding a corner that swung the
/// direction sixty degrees moved nothing until you had also covered the distance.
///
/// Bearing is now a trigger in its own right, which is what makes the pointer track a walk. Note what
/// this cannot fix: bearing changes when you *move*, not when you turn on the spot. ActivityKit
/// cannot stream sensor data, so no policy makes this a live compass.
///
/// Foundation-only and pure, in a directory the test bundle compiles. A rule with four interacting
/// thresholds is not something to eyeball.
enum ActivityPushPolicy {

    /// What the previous push contained, or nil when nothing has been pushed yet.
    struct LastPush: Sendable, Equatable {
        var at: Date
        var distanceMetres: Double
        var bearingDegrees: Double
    }

    /// A push is never allowed more often than this, whatever else changed. ActivityKit's budget is
    /// finite and it silently drops updates from apps that spend it too fast.
    static let minimumInterval: TimeInterval = 2.0

    /// Above this, a push happens even with no meaningful change, so the card never looks abandoned.
    static let heartbeatInterval: TimeInterval = 30.0

    /// Bearing swing worth redrawing the pointer for.
    static let bearingThreshold: Double = 4.0

    /// How far you must move before the distance is worth restating — tighter as you close in,
    /// because the last stretch is where the readout is watched most and where 20 m is the whole
    /// remaining walk.
    static func distanceThreshold(forRemaining metres: Double) -> Double {
        switch metres {
        case ..<60: return 2
        case ..<250: return 5
        case ..<1_000: return 10
        default: return 25
        }
    }

    /// Whether to push now.
    ///
    /// - Parameters:
    ///   - last: the previous push, or nil if this is the first.
    ///   - now: current time, injected so the rule is testable.
    static func shouldPush(
        distanceMetres: Double,
        bearingDegrees: Double,
        isArrived: Bool,
        last: LastPush?,
        now: Date
    ) -> Bool {
        // Arrival is the one update that matters; it never waits and never gets rate-limited.
        if isArrived { return true }

        guard let last else { return true }

        let elapsed = now.timeIntervalSince(last.at)
        // The floor comes first, so nothing below can spend the budget.
        if elapsed < minimumInterval { return false }
        if elapsed >= heartbeatInterval { return true }

        let movedEnough = abs(last.distanceMetres - distanceMetres)
            >= distanceThreshold(forRemaining: distanceMetres)
        // Shortest way round the circle: 358° to 2° is a four-degree change, not 356.
        let turnedEnough = shortestAngleDelta(last.bearingDegrees, bearingDegrees)
            >= bearingThreshold

        return movedEnough || turnedEnough
    }

    /// Absolute difference between two bearings, along the shorter arc, in 0...180.
    static func shortestAngleDelta(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return raw > 180 ? 360 - raw : raw
    }
}

/// How far through the walk you are.
///
/// Previously `1 - distance / 1_000`, against a kilometre nobody chose: starting three kilometres out
/// pinned the bar at zero for the whole walk, and starting two hundred metres out began it at 80%.
/// Measuring against where you actually set out from is the only version of this that means anything.
enum ActivityProgressMath {

    /// Fraction walked, 0...1. Returns nil when there is nothing to measure against, so the caller
    /// can omit the bar rather than draw a misleading one.
    static func fraction(remaining: Double, startingFrom start: Double?) -> Double? {
        guard let start, start > 0 else { return nil }
        let covered = start - max(0, remaining)
        return min(1, max(0, covered / start))
    }
}
