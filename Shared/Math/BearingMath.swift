import Foundation

/// A latitude/longitude pair, deliberately independent of CoreLocation so the geometry
/// below can be exercised in unit tests without a device or a location manager.
struct Coordinate: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

/// Great-circle geometry for pointing an arrow at a place.
///
/// Everything here is a pure function of its inputs. The compass screen, the widgets and
/// the Live Activity all share these, so a bug fixed here is fixed everywhere.
enum BearingMath {

    /// Mean Earth radius (IUGG), in metres.
    static let earthRadius: Double = 6_371_008.8

    /// Comfortable walking pace, in metres per second (~4.9 km/h).
    static let walkingSpeed: Double = 1.36

    // MARK: - Angles

    /// Wraps any angle into `0..<360`.
    static func normalized(degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// The signed shortest turn from `from` to `to`, in `-180...180`.
    ///
    /// This is what keeps the arrow from taking the long way round when the heading
    /// crosses north: turning from 350° to 10° is `+20`, not `-340`.
    static func shortestDelta(from: Double, to: Double) -> Double {
        let raw = normalized(degrees: to - from)
        return raw > 180 ? raw - 360 : raw
    }

    /// How far off the target the phone is currently pointing, in `-180...180`.
    /// Negative means the target is to the left.
    static func relativeAngle(bearing: Double, heading: Double) -> Double {
        shortestDelta(from: heading, to: bearing)
    }

    // MARK: - Bearing and distance

    /// Initial great-circle bearing (forward azimuth) from one coordinate to another, in
    /// degrees clockwise from true north.
    static func initialBearing(from origin: Coordinate, to destination: Coordinate) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLon = (destination.longitude - origin.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)

        guard y != 0 || x != 0 else { return 0 }
        return normalized(degrees: atan2(y, x) * 180 / .pi)
    }

    /// Great-circle distance in metres, via the haversine formula.
    static func distance(from origin: Coordinate, to destination: Coordinate) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (destination.longitude - origin.longitude) * .pi / 180

        let a = pow(sin(deltaLat / 2), 2)
            + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadius * c
    }

    /// The point `fraction` of the way along the great circle between two coordinates.
    /// Used to draw the curved "you → there" line on the map.
    static func interpolate(from origin: Coordinate, to destination: Coordinate, fraction: Double) -> Coordinate {
        let clamped = min(max(fraction, 0), 1)
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180

        let angular = distance(from: origin, to: destination) / earthRadius
        guard angular > 1e-9 else { return origin }

        let a = sin((1 - clamped) * angular) / sin(angular)
        let b = sin(clamped * angular) / sin(angular)

        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)

        return Coordinate(
            latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    // MARK: - Derived readouts

    /// Rough walking time. Returns nil for distances short enough that a number would be
    /// noise rather than information.
    static func walkingDuration(forDistance metres: Double) -> TimeInterval? {
        guard metres.isFinite, metres > 30 else { return nil }
        return metres / walkingSpeed
    }

    /// One of the sixteen compass points for a bearing.
    static func compassPoint(forBearing bearing: Double) -> String {
        let points = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
        ]
        let index = Int((normalized(degrees: bearing) / 22.5).rounded()) % points.count
        return points[index]
    }

    // MARK: - Smoothing

    /// A low-pass filter that works on the circle instead of the number line.
    ///
    /// Feeding raw magnetometer values straight into a rotation makes the arrow jitter;
    /// naïvely averaging them makes it spin the wrong way past north. This does neither:
    /// it steps `current` toward `target` along the shortest arc.
    ///
    /// - Parameter factor: 0 keeps the current value, 1 snaps straight to the target.
    static func smoothed(current: Double, target: Double, factor: Double) -> Double {
        let clamped = min(max(factor, 0), 1)
        let delta = shortestDelta(from: current, to: target)
        return normalized(degrees: current + delta * clamped)
    }

    /// An unwrapped angle: the representation of `target` nearest to `reference`, which may
    /// fall outside `0..<360`.
    ///
    /// SwiftUI animates `.rotationEffect` between raw values, so handing it 359 → 1 spins
    /// the arrow 358° the wrong way. Handing it 359 → 361 spins it 2° the right way.
    static func unwrapped(target: Double, near reference: Double) -> Double {
        reference + shortestDelta(from: reference, to: target)
    }
}
