import Foundation

/// Everything the arrow screen shows, quantized to display granularity and pre-formatted.
///
/// The compass engine ticks at 30 Hz, but almost nothing on screen changes 30 times a
/// second: a distance readout flips when its *string* flips, a turn hint when the advice
/// changes, the glow when proximity crosses a 2% band. This frame is built raw-maths-in,
/// strings-out on every tick and published only when it compares unequal to the previous
/// one — so a phone lying still on a table produces zero view updates, and the views that
/// host menus and sheets never re-render just because the magnetometer breathed.
struct CompassFrame: Equatable {

    /// Within this many degrees counts as pointing at it.
    static let onTargetTolerance: Double = 8
    /// Within this many metres counts as arrived.
    static let arrivalRadius: Double = 25
    /// Hysteresis: once arrived, you stay arrived until this far away again, so the
    /// celebration cannot flicker on and off at the boundary.
    static let arrivalExitRadius: Double = arrivalRadius * 2.5
    /// Distance at which the glow starts to warm up.
    static let proximityRange: Double = 400
    /// Proximity is published in steps of 1/proximityStepCount, i.e. 2% bands.
    static let proximityStepCount = 50

    /// Absolute bearing to the target, whole degrees from north.
    var bearingDegrees: Int?
    /// Signed whole degrees off target; positive means the target is to the right.
    var offByDegrees: Int?
    /// 0 far away ... `proximityStepCount` practically standing on it.
    var proximityStep: Int = 0
    var onTarget = false
    var hasArrived = false
    var headingIsUsable = false
    /// The headline number, already formatted. Nil while there is no fix.
    var distanceText: DistanceReadout?
    /// "~12 min walk" — the detour-factored estimate for when no routed answer exists.
    var walkingTimeText: String?
    /// "48 m above you", when the altitude difference is worth mentioning.
    var elevationText: String?
    /// "Turn left", "Straight ahead" — the one-glance instruction.
    var turnHint = "Looking for a signal"

    /// Crow-flies metres rounded to 5 m, for route-policy decisions. Kept on the frame
    /// (rather than re-read from the engine) so consumers see one consistent tick, and
    /// quantized so a kilometre-scale readout — which only changes every 100 m on screen —
    /// does not republish the frame for every metre walked.
    var crowMetres: Double?

    var proximity: Double { Double(proximityStep) / Double(Self.proximityStepCount) }

    /// "NW 312°" for the bearing pill.
    var bearingLabel: String? {
        guard let bearingDegrees else { return nil }
        let point = BearingMath.compassPoint(forBearing: Double(bearingDegrees))
        return "\(point) \(bearingDegrees)°"
    }

    static let empty = CompassFrame()

    // MARK: - Construction

    static func make(
        bearing: Double?,
        distanceMetres: Double?,
        offBy: Double?,
        headingIsUsable: Bool,
        elevationDeltaMetres: Double?,
        wasArrived: Bool,
        unitPreference: UnitPreference,
        locale: Locale = .current
    ) -> CompassFrame {
        var frame = CompassFrame()
        frame.headingIsUsable = headingIsUsable

        if let bearing {
            frame.bearingDegrees = Int(BearingMath.normalized(degrees: bearing).rounded()) % 360
        }
        if let offBy {
            frame.offByDegrees = Int(offBy.rounded())
            frame.onTarget = abs(offBy) <= onTargetTolerance
        }
        if let distanceMetres {
            frame.crowMetres = (distanceMetres / 5).rounded() * 5
            frame.proximityStep = proximityStep(forMetres: distanceMetres)
            frame.hasArrived = arrived(previous: wasArrived, metres: distanceMetres)
            frame.distanceText = DistanceFormatting.readout(
                metres: distanceMetres, preference: unitPreference, locale: locale
            )
            frame.walkingTimeText = DistanceFormatting.walkingTime(metres: distanceMetres, locale: locale)
        }
        if let elevationDeltaMetres {
            frame.elevationText = DistanceFormatting.elevationDelta(
                metres: elevationDeltaMetres, preference: unitPreference, locale: locale
            )
        }
        frame.turnHint = turnHint(
            offBy: offBy, bearing: bearing, headingIsUsable: headingIsUsable
        )
        return frame
    }

    /// Proximity banded into 2% steps so tiny GPS drift does not publish a new frame.
    static func proximityStep(forMetres metres: Double) -> Int {
        let raw = max(0, min(1, 1 - metres / proximityRange))
        return Int((raw * Double(proximityStepCount)).rounded())
    }

    /// Arrival with hysteresis: enter inside `arrivalRadius`, leave beyond `arrivalExitRadius`.
    static func arrived(previous: Bool, metres: Double) -> Bool {
        if metres <= arrivalRadius { return true }
        if metres > arrivalExitRadius { return false }
        return previous
    }

    static func turnHint(offBy: Double?, bearing: Double?, headingIsUsable: Bool) -> String {
        guard let offBy else { return "Looking for a signal" }
        guard headingIsUsable else {
            guard let bearing else { return "Looking for a signal" }
            return "Head \(BearingMath.compassPoint(forBearing: bearing))"
        }
        if abs(offBy) <= onTargetTolerance { return "Straight ahead" }
        if abs(offBy) > 150 { return "It's behind you" }
        return offBy > 0 ? "Turn right" : "Turn left"
    }

    /// Full sentence for VoiceOver, which cannot see an arrow.
    func accessibilityDescription(spotName: String) -> String {
        guard let distanceText else {
            return "\(spotName). Waiting for your location."
        }
        let distance = distanceText.combined
        guard let bearingDegrees else { return "\(spotName), \(distance) away." }
        let compass = BearingMath.compassPoint(forBearing: Double(bearingDegrees))
        if let offByDegrees, headingIsUsable {
            let direction = onTarget
                ? "straight ahead"
                : "\(abs(offByDegrees)) degrees to your \(offByDegrees > 0 ? "right" : "left")"
            return "\(spotName), \(distance) away, \(compass), \(direction)."
        }
        return "\(spotName), \(distance) away, \(compass)."
    }
}
