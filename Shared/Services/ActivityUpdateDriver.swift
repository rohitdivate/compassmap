import CoreLocation
import Foundation

/// Feeds the Live Activity while the phone is locked.
///
/// The arrow screen used to be the only thing pushing updates, which meant the Lock Screen
/// card froze the moment the screen turned off — the update chain ran through a SwiftUI
/// `.onChange` on a view whose timer the app stops on backgrounding. This driver is that chain
/// rebuilt outside the view: it turns on background location for the walk, recomputes distance
/// and bearing on every fix, and re-pushes on a real timer so the thirty-second heartbeat in
/// `ActivityPushPolicy` actually fires when you stand still.
@MainActor
final class ActivityUpdateDriver {

    private let target: Coordinate
    private unowned let service: LiveActivityService
    private let location: LocationService

    private var heartbeat: Timer?
    private var lastDistance: Double?
    private var lastBearing: Double?

    init(target: Coordinate, service: LiveActivityService, location: LocationService = .shared) {
        self.target = target
        self.service = service
        self.location = location
    }

    func start() {
        location.beginBackgroundTracking()
        location.onLocationFix = { [weak self] fix in
            Task { @MainActor [weak self] in self?.handle(fix: fix) }
        }
        let timer = Timer(timeInterval: ActivityPushPolicy.heartbeatInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.pushLatest() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        location.onLocationFix = nil
        location.endBackgroundTracking()
    }

    private func handle(fix: CLLocation) {
        guard fix.horizontalAccuracy >= 0 else { return }
        let origin = Coordinate(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        let distance = BearingMath.distance(from: origin, to: target)
        let bearing = BearingMath.initialBearing(from: origin, to: target)
        lastDistance = distance
        lastBearing = bearing

        if distance <= CompassEngine.arrivalRadius {
            service.finish(distanceMetres: distance, bearing: bearing)
        } else {
            service.update(distanceMetres: distance, bearing: bearing, isArrived: false)
        }
    }

    /// The heartbeat: re-offers the last computed pair so a stationary walk still refreshes
    /// before the activity goes stale. `ActivityPushPolicy` decides whether it goes through.
    private func pushLatest() {
        guard let lastDistance, let lastBearing else { return }
        service.update(distanceMetres: lastDistance, bearing: lastBearing, isArrived: false)
    }
}
