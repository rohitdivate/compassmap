import CoreLocation
import Foundation
import Observation

/// The rotating parts of the compass, published on their own so only the dial redraws at
/// dial rate. Angles are unwrapped (continuous) so SwiftUI rotates the short way round,
/// and guarded to a tenth of a degree — a phone lying still publishes nothing.
@Observable
final class DialState {
    private(set) var roseAngle: Double = 0
    private(set) var arrowAngle: Double = 0
    /// The arrow angle quantized to 3°, for the backdrop parallax: close enough to feel
    /// physical, coarse enough that the blurred photo is not re-composited every tick.
    private(set) var parallaxAngle: Double = 0

    func seed(rose: Double) {
        roseAngle = rose
    }

    func update(rose: Double, arrow: Double) {
        if abs(rose - roseAngle) >= 0.1 { roseAngle = rose }
        if abs(arrow - arrowAngle) >= 0.1 { arrowAngle = arrow }
        let quantized = (arrow / 3).rounded() * 3
        if quantized != parallaxAngle { parallaxAngle = quantized }
    }
}

/// The slow half of the compass: everything that is *about* the target rather than about
/// which way the phone is facing right now. Publishes a new `CompassFrame` only when the
/// frame actually differs, so the views reading it — readout, pills, hints, actions —
/// update a few times a minute, not thirty times a second.
@Observable
final class TargetSolution {
    private(set) var frame: CompassFrame = .empty
    private(set) var arrivedAt: Date?
    /// Horizontal accuracy rounded up to the nearest 10 m, nil when unknown. Bucketed so
    /// GPS jitter does not republish; the status note only cares about "roughly how bad".
    private(set) var accuracyBucket: Int?

    func publish(frame: CompassFrame, accuracy: Double?) {
        if frame != self.frame {
            if frame.hasArrived, !self.frame.hasArrived { arrivedAt = Date() }
            if !frame.hasArrived, arrivedAt != nil { arrivedAt = nil }
            self.frame = frame
        }
        let bucket = accuracy.map { Int((($0 / 10).rounded(.up)) * 10) }
        if bucket != accuracyBucket { accuracyBucket = bucket }
    }

    func reset() {
        if frame != .empty { frame = .empty }
        if arrivedAt != nil { arrivedAt = nil }
        if accuracyBucket != nil { accuracyBucket = nil }
    }
}

/// Turns "where am I / which way am I facing / where is the spot" into the handful of numbers
/// the compass screen draws.
///
/// It runs its own 30 Hz tick rather than reacting to every magnetometer sample. Heading
/// arrives faster than a screen can usefully show, and a fixed tick makes the smoothing
/// behave predictably: one exponential step per frame, along the shortest arc.
///
/// Deliberately not `@Observable`. The engine publishes through exactly two channels —
/// `dial` (high rate, read only by the rotating leaves) and `solution` (low rate, read by
/// everything else) — so no view can accidentally couple itself to the 30 Hz tick. The raw
/// properties below are for imperative code (event handlers, the Live Activity); reading
/// them outside a view body costs nothing.
final class CompassEngine {

    /// How much of the gap to close each tick. 0.18 at 30 Hz settles in about a fifth of a
    /// second — fast enough to feel direct, slow enough to kill the jitter.
    private let smoothingFactor: Double = 0.18

    static let onTargetTolerance = CompassFrame.onTargetTolerance
    static let arrivalRadius = CompassFrame.arrivalRadius
    static let proximityRange = CompassFrame.proximityRange

    let dial = DialState()
    let solution = TargetSolution()

    private let location: LocationService
    private let settings: AppSettings
    private var timer: Timer?

    /// Where we are heading. Set to nil to idle.
    var target: Coordinate? {
        didSet {
            guard target != oldValue else { return }
            wasArrived = false
            solution.reset()
            recompute()
        }
    }

    /// Altitude of the target, when known, so the readout can say "48 m above you".
    var targetAltitude: Double?

    // MARK: - Raw values, for imperative consumers only

    /// Continuous rose angle; the smoothing filter's own state.
    private var roseAngle: Double = 0
    private var arrowAngle: Double = 0
    private var wasArrived = false
    private(set) var bearing: Double?
    private(set) var distanceMetres: Double?

    var hasArrived: Bool { wasArrived }

    /// True when there is no usable heading — no magnetometer, or too much interference. The
    /// UI switches to an absolute-bearing presentation rather than pretending.
    var headingIsUsable: Bool {
        !location.headingUnavailable && location.currentHeading != nil
    }

    init(location: LocationService = .shared, settings: AppSettings = .shared) {
        self.location = location
        self.settings = settings
        // Start the rose wherever the device already is, so it does not sweep in from north.
        if let heading = location.headingDegrees(preferTrueNorth: settings.usesTrueNorth) {
            roseAngle = heading
            dial.seed(rose: heading)
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
            wasArrived = false
            dial.update(rose: roseAngle, arrow: arrowAngle)
            solution.publish(
                frame: CompassFrame.make(
                    bearing: nil, distanceMetres: nil, offBy: nil,
                    headingIsUsable: headingIsUsable, elevationDeltaMetres: nil,
                    wasArrived: false, unitPreference: settings.unitPreference
                ),
                accuracy: location.currentLocation?.horizontalAccuracy
            )
            return
        }

        let bearingToTarget = BearingMath.initialBearing(from: origin, to: target)
        let metres = BearingMath.distance(from: origin, to: target)

        bearing = bearingToTarget
        distanceMetres = metres

        // With no usable heading the arrow shows the absolute bearing against a rose that is
        // frozen at north. It is still correct information, just held differently.
        let effectiveHeading = headingIsUsable ? BearingMath.normalized(degrees: roseAngle) : 0
        let relative = BearingMath.relativeAngle(bearing: bearingToTarget, heading: effectiveHeading)
        arrowAngle = BearingMath.unwrapped(target: relative, near: arrowAngle)

        dial.update(rose: roseAngle, arrow: arrowAngle)

        let elevationDelta: Double? = {
            guard let targetAltitude, let here = location.currentLocation?.altitude else { return nil }
            return targetAltitude - here
        }()

        let frame = CompassFrame.make(
            bearing: bearingToTarget,
            distanceMetres: metres,
            offBy: relative,
            headingIsUsable: headingIsUsable,
            elevationDeltaMetres: elevationDelta,
            wasArrived: wasArrived,
            unitPreference: settings.unitPreference
        )
        wasArrived = frame.hasArrived
        solution.publish(frame: frame, accuracy: location.currentLocation?.horizontalAccuracy)
    }
}
