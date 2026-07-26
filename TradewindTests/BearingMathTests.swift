import Testing
import Foundation

@Suite("Bearing and distance")
struct BearingMathTests {

    // Reference values cross-checked against the standard great-circle formulae.
    let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
    let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
    let honolulu = Coordinate(latitude: 21.3069, longitude: -157.8583)
    let colombo = Coordinate(latitude: 6.9271, longitude: 79.8612)

    @Test("London to Paris is roughly south-east")
    func londonToParis() {
        let bearing = BearingMath.initialBearing(from: london, to: paris)
        #expect(abs(bearing - 148.12) < 0.5)

        let metres = BearingMath.distance(from: london, to: paris)
        #expect(abs(metres - 343_557) < 1_500)
    }

    @Test("Reversing the pair reverses the bearing")
    func reciprocalBearing() {
        let out = BearingMath.initialBearing(from: colombo, to: honolulu)
        let back = BearingMath.initialBearing(from: honolulu, to: colombo)
        // Only approximately reciprocal on a sphere over long distances, but the two must sit
        // in opposite half-planes.
        let delta = abs(BearingMath.shortestDelta(from: out, to: back))
        #expect(delta > 90)
    }

    @Test("Due north, east, south and west come out exactly")
    func cardinalBearings() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        #expect(abs(BearingMath.initialBearing(from: origin, to: Coordinate(latitude: 1, longitude: 0))) < 0.001)
        #expect(abs(BearingMath.initialBearing(from: origin, to: Coordinate(latitude: 0, longitude: 1)) - 90) < 0.001)
        #expect(abs(BearingMath.initialBearing(from: origin, to: Coordinate(latitude: -1, longitude: 0)) - 180) < 0.001)
        #expect(abs(BearingMath.initialBearing(from: origin, to: Coordinate(latitude: 0, longitude: -1)) - 270) < 0.001)
    }

    @Test("Distance to yourself is zero, and bearing does not blow up")
    func degenerateCase() {
        #expect(BearingMath.distance(from: london, to: london) == 0)
        #expect(BearingMath.initialBearing(from: london, to: london).isFinite)
    }

    @Test("Crossing the antimeridian takes the short way")
    func antimeridian() {
        let west = Coordinate(latitude: 0, longitude: 179.5)
        let east = Coordinate(latitude: 0, longitude: -179.5)
        let metres = BearingMath.distance(from: west, to: east)
        // One degree of longitude at the equator, not 359 of them.
        #expect(metres < 120_000)
        let bearing = BearingMath.initialBearing(from: west, to: east)
        #expect(abs(bearing - 90) < 1.0)
    }

    @Test("A degree of latitude is about 111 km anywhere")
    func latitudeScale() {
        for latitude in stride(from: -80.0, through: 80.0, by: 20.0) {
            let a = Coordinate(latitude: latitude, longitude: 12)
            let b = Coordinate(latitude: latitude + 1, longitude: 12)
            let metres = BearingMath.distance(from: a, to: b)
            #expect(abs(metres - 111_195) < 400)
        }
    }
}

@Suite("Angle handling")
struct AngleTests {

    @Test("Normalising wraps into 0..<360")
    func normalise() {
        #expect(BearingMath.normalized(degrees: 0) == 0)
        #expect(BearingMath.normalized(degrees: 360) == 0)
        #expect(BearingMath.normalized(degrees: 370) == 10)
        #expect(BearingMath.normalized(degrees: -10) == 350)
        #expect(BearingMath.normalized(degrees: -730) == 350)
        #expect(BearingMath.normalized(degrees: .nan) == 0)
    }

    @Test("Shortest turn crosses north the short way")
    func shortestDelta() {
        #expect(BearingMath.shortestDelta(from: 350, to: 10) == 20)
        #expect(BearingMath.shortestDelta(from: 10, to: 350) == -20)
        #expect(BearingMath.shortestDelta(from: 0, to: 180) == 180)
        #expect(BearingMath.shortestDelta(from: 0, to: 181) == -179)
        #expect(BearingMath.shortestDelta(from: 90, to: 90) == 0)
    }

    @Test("Turn direction matches which side the target is on")
    func relativeAngle() {
        // Facing north, target to the east: turn right.
        #expect(BearingMath.relativeAngle(bearing: 90, heading: 0) == 90)
        // Facing north, target to the west: turn left.
        #expect(BearingMath.relativeAngle(bearing: 270, heading: 0) == -90)
        // Facing north-ish across the wrap point.
        #expect(BearingMath.relativeAngle(bearing: 5, heading: 355) == 10)
    }

    @Test("Unwrapping keeps rotation continuous")
    func unwrap() {
        // Coming up to north from below: the next value must be greater, not 358 less.
        let unwrapped = BearingMath.unwrapped(target: 1, near: 359)
        #expect(unwrapped == 361)

        // And going the other way.
        #expect(BearingMath.unwrapped(target: 359, near: 361) == 359)

        // Repeatedly unwrapping a rotating heading must accumulate rather than reset.
        var current: Double = 0
        for step in stride(from: 0.0, to: 1_080.0, by: 30.0) {
            current = BearingMath.unwrapped(target: BearingMath.normalized(degrees: step), near: current)
        }
        #expect(current > 1_000)
    }

    @Test("Smoothing converges without spinning the long way")
    func smoothing() {
        var value: Double = 350
        for _ in 0..<200 {
            value = BearingMath.smoothed(current: value, target: 10, factor: 0.18)
        }
        #expect(abs(BearingMath.shortestDelta(from: value, to: 10)) < 0.5)

        // A factor of zero must not move at all, and one must snap.
        #expect(BearingMath.smoothed(current: 100, target: 200, factor: 0) == 100)
        #expect(BearingMath.smoothed(current: 100, target: 200, factor: 1) == 200)
    }

    @Test("Compass points land on the right sixteenth")
    func compassPoints() {
        #expect(BearingMath.compassPoint(forBearing: 0) == "N")
        #expect(BearingMath.compassPoint(forBearing: 359) == "N")
        #expect(BearingMath.compassPoint(forBearing: 45) == "NE")
        #expect(BearingMath.compassPoint(forBearing: 90) == "E")
        #expect(BearingMath.compassPoint(forBearing: 180) == "S")
        #expect(BearingMath.compassPoint(forBearing: 247.5) == "WSW")
    }

    @Test("Interpolating stays on the great circle")
    func interpolation() {
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 0, longitude: 10)
        let midpoint = BearingMath.interpolate(from: a, to: b, fraction: 0.5)
        #expect(abs(midpoint.latitude) < 0.001)
        #expect(abs(midpoint.longitude - 5) < 0.001)

        // Ends are exact, and out-of-range fractions clamp.
        #expect(BearingMath.interpolate(from: a, to: b, fraction: 0).longitude == 0)
        #expect(abs(BearingMath.interpolate(from: a, to: b, fraction: 2).longitude - 10) < 0.001)
    }
}
