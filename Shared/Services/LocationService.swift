import CoreLocation
import Foundation
import Observation
import UIKit
import WidgetKit

/// Everything the app knows about where you are and which way you are facing.
///
/// One instance owns the single `CLLocationManager`. Two things matter here beyond the usual
/// wrapper boilerplate:
///
/// * **Heading is reported raw.** Smoothing belongs to whatever is drawing, because the
///   compass screen and a widget want very different amounts of it.
/// * **The widget snapshot is refreshed from here**, throttled by distance and time. Widgets
///   cannot poll location cheaply, so the app leaves a fresh fix behind whenever it has one.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    static let shared = LocationService()

    @ObservationIgnored private let manager = CLLocationManager()

    /// Last fix we were given.
    private(set) var currentLocation: CLLocation?
    /// Last heading we were given, unsmoothed.
    private(set) var currentHeading: CLHeading?

    /// The fix quantized to ~11 m, published only when the bucket changes. For consumers
    /// that rank and label rather than draw — reading `currentLocation` in a view body means
    /// re-rendering on every 3 m fix, which is how the gallery ended up re-sorting itself
    /// several times a second.
    private(set) var coarseCoordinate: Coordinate?
    /// Headings quantized to 5°, same idea: a card's mini arrow does not need degree-level
    /// updates, and the dial reads the raw heading through the engine, not through here.
    private(set) var coarseMagneticHeading: Double?
    private(set) var coarseTrueHeading: Double?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Set when the device has no magnetometer, or heading is unavailable for any other
    /// reason, so the UI can fall back to a map instead of showing a dead arrow.
    private(set) var headingUnavailable = false
    private(set) var isUpdatingLocation = false
    private(set) var isUpdatingHeading = false

    /// How far the person must move before the widget snapshot is rewritten.
    private let snapshotDistanceThreshold: CLLocationDistance = 40
    /// …and how long before it is rewritten regardless.
    private let snapshotTimeThreshold: TimeInterval = 120

    @ObservationIgnored private var lastPublishedLocation: CLLocation?
    @ObservationIgnored private var lastPublishedAt: Date?

    /// Called with every accepted fix, view lifecycle be damned — this is what keeps the Live
    /// Activity honest while the phone is locked. One consumer: `ActivityUpdateDriver`.
    @ObservationIgnored var onLocationFix: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.headingFilter = 1
        manager.headingOrientation = .portrait
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .fitness
    }

    // MARK: - Authorization

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Asked for only after "when in use" has been granted, and only because widgets and the
    /// Live Activity need location while the app is closed.
    func requestAlwaysAuthorization() {
        guard authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Updates

    func startUpdating() {
        guard isAuthorized else { return }
        if !isUpdatingLocation {
            manager.startUpdatingLocation()
            isUpdatingLocation = true
        }
        startHeading()
    }

    func stopUpdating() {
        if isUpdatingLocation {
            manager.stopUpdatingLocation()
            isUpdatingLocation = false
        }
        stopHeading()
    }

    func startHeading() {
        guard isAuthorized else { return }
        guard CLLocationManager.headingAvailable() else {
            headingUnavailable = true
            return
        }
        if !isUpdatingHeading {
            manager.startUpdatingHeading()
            isUpdatingHeading = true
        }
    }

    func stopHeading() {
        if isUpdatingHeading {
            manager.stopUpdatingHeading()
            isUpdatingHeading = false
        }
    }

    /// Keeps fixes flowing after the phone locks, for as long as a walk is being tracked.
    ///
    /// `UIBackgroundModes` includes `location`, but that entitlement does nothing until
    /// `allowsBackgroundLocationUpdates` is set — which is why the Live Activity used to freeze
    /// the moment the screen turned off. Scoped strictly to an active tracked spot: the blue
    /// indicator makes the cost visible, and `endBackgroundTracking` restores every default.
    func beginBackgroundTracking() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        startUpdating()
    }

    func endBackgroundTracking() {
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
    }

    /// Coarse background monitoring: enough to keep widgets roughly honest without holding
    /// GPS open. Requires "always" authorization to do anything useful.
    func startMonitoringSignificantChanges() {
        guard authorizationStatus == .authorizedAlways else { return }
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopMonitoringSignificantChanges() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    /// One fix, for the case where the app just needs a coordinate and does not want a stream.
    func requestOneShotLocation() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    // MARK: - Derived

    var coordinate: Coordinate? {
        guard let currentLocation, currentLocation.horizontalAccuracy >= 0 else { return nil }
        return Coordinate(
            latitude: currentLocation.coordinate.latitude,
            longitude: currentLocation.coordinate.longitude
        )
    }

    /// Heading in degrees from north, honouring the true-vs-magnetic preference and falling
    /// back to magnetic when a true-north fix is not yet available.
    func headingDegrees(preferTrueNorth: Bool) -> Double? {
        guard let currentHeading else { return nil }
        if preferTrueNorth, currentHeading.trueHeading >= 0 {
            return currentHeading.trueHeading
        }
        guard currentHeading.magneticHeading >= 0 else { return nil }
        return currentHeading.magneticHeading
    }

    /// The 5°-quantized counterpart, for card arrows and other decorations.
    func coarseHeadingDegrees(preferTrueNorth: Bool) -> Double? {
        if preferTrueNorth, let coarseTrueHeading { return coarseTrueHeading }
        return coarseMagneticHeading
    }

    /// Whether the magnetometer is reporting enough interference to be worth mentioning.
    var needsCalibration: Bool {
        guard let currentHeading else { return false }
        return currentHeading.headingAccuracy < 0 || currentHeading.headingAccuracy > 25
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            startUpdating()
            startMonitoringSignificantChanges()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        currentLocation = latest
        let coarse = Coordinate(
            latitude: (latest.coordinate.latitude * 10_000).rounded() / 10_000,
            longitude: (latest.coordinate.longitude * 10_000).rounded() / 10_000
        )
        if coarse != coarseCoordinate { coarseCoordinate = coarse }
        publishToSnapshotIfNeeded(latest)
        onLocationFix?(latest)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 || newHeading.magneticHeading >= 0 else { return }
        headingUnavailable = false
        currentHeading = newHeading

        let quantize: (Double) -> Double? = { value in
            value >= 0 ? (value / 5).rounded() * 5 : nil
        }
        let magnetic = quantize(newHeading.magneticHeading)
        if magnetic != coarseMagneticHeading { coarseMagneticHeading = magnetic }
        let true_ = quantize(newHeading.trueHeading)
        if true_ != coarseTrueHeading { coarseTrueHeading = true_ }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // Let the system show the figure-of-eight prompt when it thinks it is needed; hiding
        // it just leaves the arrow wrong with no explanation.
        true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError else { return }
        switch clError.code {
        case .headingFailure:
            headingUnavailable = true
        case .denied:
            stopUpdating()
        default:
            break
        }
    }

    // MARK: - Private

    /// Leaves a fresh coordinate in the shared snapshot for the widgets, but only when the
    /// person has actually moved or enough time has passed. Rewriting on every fix would
    /// thrash the file and burn the widget refresh budget for nothing.
    private func publishToSnapshotIfNeeded(_ location: CLLocation) {
        let movedFarEnough = lastPublishedLocation
            .map { location.distance(from: $0) >= snapshotDistanceThreshold } ?? true
        let waitedLongEnough = lastPublishedAt
            .map { Date().timeIntervalSince($0) >= snapshotTimeThreshold } ?? true

        guard movedFarEnough || waitedLongEnough else { return }

        lastPublishedLocation = location
        lastPublishedAt = Date()

        let coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let themeID = AppSettings.shared.themeID
        // Async: this runs inside a CoreLocation delegate callback on the main thread, and
        // blocking it on file I/O for a widget nicety is exactly backwards.
        SharedSnapshotStore.mutateAsync(defaultThemeID: themeID) { snapshot in
            snapshot.lastKnownLocation = coordinate
            snapshot.lastKnownLocationDate = Date()
        } completion: { _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
