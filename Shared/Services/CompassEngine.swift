import CoreLocation
import Foundation
import Observation

/// Turns "where am I / which way am I facing / where is the spot" into the handful of numbers
/// the compass screen draws.
///
/// It runs its own 30 Hz tick rather than reacting to every magnetometer sample. Heading
/// arrives faster than a screen can usefully show, and a fixed tick makes the smoothing
/// behave predictably: one exponential step per frame, along the shortest arc.
@Observable
final class CompassEngine {

    /// How much of the gap to close each tick. 0.18 at 30 Hz settles in about a fifth of a
    /// second — fast enough to feel direct, slow enough to kill the jitter.
    private let smoothingFactor: Double = 0.18

    /// Within this many degrees counts as pointing at it.
    static let onTargetTolerance: Double = 8
    /// Within this many metres counts as arrived.
    static let arrivalRadius: Double = 25
    /// Distance at which the glow starts to warm up.
    static let proximityRange: Double = 400

    @ObservationIgnored private let location: LocationService
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var timer: Timer?

    /// Where we are heading. Set to nil to idle.
    var target: Coordinate? {
        didSet {
            guard target != oldValue else { return }
            hasEverBeenOnTarget = false
            arrivedAt = nil
            recompute()
        }
    }

    /// Altitude of the target, when known, so the readout can say "48 m above you".
    var targetAltitude: Double?

    // MARK: - Outputs

    /// Smoothed heading, unwrapped so SwiftUI rotates the rose the short way round.
    private(set) var roseAngle: Double = 0
    /// Smoothed angle from "straight up on screen" to the target, unwrapped.
    private(set) var arrowAngle: Double = 0
    /// Absolute bearing to the target, degrees from north.
    private(set) var bearing: Double?
    private(set) var distanceMetres: Double?
    /// Signed degrees off target, for the "turn left / turn right" hint.
    private(set) var offBy: Double?
    private(set) var onTarget: Bool = false
    private(set) var arrivedAt: Date?
    /// 0 far away, 1 practically standing on it.
    private(set) var proximity: Double = 0
    private(set) var hasEverBeenOnTarget = false

    /// True when there is no usable heading — no magnetometer, or too much interference. The
    /// UI switches to an absolute-bearing presentation rather than pretending.
    var headingIsUsable: Bool {
        !location.headingUnavailable && location.currentHeading != nil
    }

    var horizontalAccuracy: Double? {
        location.currentLocation?.horizontalAccuracy
    }

    var hasArrived: Bool { arrivedAt != nil }

    init(location: LocationService = .shared, settings: AppSettings = .shared) {
        self.location = location
        self.settings = settings
        // Start the rose wherever the device already is, so it does not sweep in from north.
        if let heading = location.headingDegrees(preferTrueNorth: settings.usesTrueNorth) {
            roseAngle = heading
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        location.startUpdating()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Common mode so the arrow keeps moving while a scroll view is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Maths

    private func tick() {
        let rawHeading = location.headingDegrees(preferTrueNorth: settings.usesTrueNorth) ?? 0
        let smoothed = BearingMath.smoothed(
            current: BearingMath.normalized(degrees: roseAngle),
            target: rawHeading,
            factor: smoothingFactor
        )
        roseAngle = BearingMath.unwrapped(target: smoothed, near: roseAngle)
        recompute()
    }

    private func recompute() {
        guard let target, target.isValid, let origin = location.coordinate else {
            bearing = nil
            distanceMetres = nil
            offBy = nil
            onTarget = false
            proximity = 0
            return
        }

        let bearingToTarget = BearingMath.initialBearing(from: origin, to: target)
        let metres = BearingMath.distance(from: origin, to: target)

        bearing = bearingToTarget
        distanceMetres = metres
        proximity = max(0, min(1, 1 - metres / Self.proximityRange))

        // With no usable heading the arrow shows the absolute bearing against a rose that is
        // frozen at north. It is still correct information, just held differently.
        let effectiveHeading = headingIsUsable ? BearingMath.normalized(degrees: roseAngle) : 0
        let relative = BearingMath.relativeAngle(bearing: bearingToTarget, heading: effectiveHeading)

        offBy = relative
        arrowAngle = BearingMath.unwrapped(target: relative, near: arrowAngle)

        let nowOnTarget = abs(relative) <= Self.onTargetTolerance
        if nowOnTarget, !onTarget { hasEverBeenOnTarget = true }
        onTarget = nowOnTarget

        if metres <= Self.arrivalRadius {
            if arrivedAt == nil { arrivedAt = Date() }
        } else if metres > Self.arrivalRadius * 2.5 {
            // Hysteresis: don't flicker the celebration on and off at the boundary.
            arrivedAt = nil
        }
    }

    // MARK: - Readouts

    func distanceReadout() -> DistanceReadout? {
        guard let distanceMetres else { return nil }
        return DistanceFormatting.readout(metres: distanceMetres, preference: settings.unitPreference)
    }

    func walkingTimeText() -> String? {
        guard let distanceMetres else { return nil }
        return DistanceFormatting.walkingTime(metres: distanceMetres)
    }

    func elevationText() -> String? {
        guard let targetAltitude, let here = location.currentLocation?.altitude else { return nil }
        return DistanceFormatting.elevationDelta(
            metres: targetAltitude - here,
            preference: settings.unitPreference
        )
    }

    /// "Turn left", "Turn right", "Straight ahead" — the one-glance instruction.
    func turnHint() -> String {
        guard let offBy else { return "Looking for a signal" }
        guard headingIsUsable else {
            guard let bearing else { return "Looking for a signal" }
            return "Head \(BearingMath.compassPoint(forBearing: bearing))"
        }
        if abs(offBy) <= Self.onTargetTolerance { return "Straight ahead" }
        if abs(offBy) > 150 { return "It's behind you" }
        return offBy > 0 ? "Turn right" : "Turn left"
    }

    /// Full sentence for VoiceOver, which cannot see an arrow.
    func accessibilityDescription(spotName: String) -> String {
        guard let distanceMetres else {
            return "\(spotName). Waiting for your location."
        }
        let distance = DistanceFormatting.string(
            metres: distanceMetres,
            preference: settings.unitPreference
        )
        guard let bearing else { return "\(spotName), \(distance) away." }
        let compass = BearingMath.compassPoint(forBearing: bearing)
        if let offBy, headingIsUsable {
            let direction = abs(offBy) <= Self.onTargetTolerance
                ? "straight ahead"
                : "\(Int(abs(offBy.rounded()))) degrees to your \(offBy > 0 ? "right" : "left")"
            return "\(spotName), \(distance) away, \(compass), \(direction)."
        }
        return "\(spotName), \(distance) away, \(compass)."
    }
}
