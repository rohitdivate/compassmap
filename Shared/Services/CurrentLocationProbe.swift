import CoreLocation
import Foundation

/// Gets one coordinate, from wherever it can, for code running outside the app.
///
/// Widget timeline providers and App Intents cannot keep a location manager alive; they get a
/// short window to do their work. So this asks CoreLocation for a single fix with a hard timeout,
/// and falls back to whatever the app last wrote into the shared snapshot. A slightly stale
/// coordinate makes a widget slightly wrong; no coordinate makes it useless.
final class CurrentLocationProbe: NSObject, CLLocationManagerDelegate {

    /// How long to wait for a fresh fix before giving up and using the cached one.
    static let defaultTimeout: TimeInterval = 4

    /// How old the cached coordinate may be before it stops being offered at all.
    static let cacheLifetime: TimeInterval = 60 * 60 * 6

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinate?, Never>?
    private var hasResumed = false
    private let lock = NSLock()

    /// A fresh fix if one arrives in time, otherwise the last coordinate the app recorded.
    static func coordinate(timeout: TimeInterval = CurrentLocationProbe.defaultTimeout) async -> Coordinate? {
        if let fresh = await CurrentLocationProbe().requestOnce(timeout: timeout) {
            return fresh
        }
        return cachedCoordinate()
    }

    /// The last coordinate the app wrote, if it is recent enough to be worth showing.
    static func cachedCoordinate() -> Coordinate? {
        guard let snapshot = SharedSnapshotStore.load(),
              let coordinate = snapshot.lastKnownLocation,
              coordinate.isValid
        else { return nil }

        guard let recordedAt = snapshot.lastKnownLocationDate else { return coordinate }
        guard Date().timeIntervalSince(recordedAt) <= cacheLifetime else { return nil }
        return coordinate
    }

    private func requestOnce(timeout: TimeInterval) async -> Coordinate? {
        // Widgets are only allowed location when the containing app has been granted it and the
        // widget has been authorised; asking anyway logs noise and never succeeds.
        guard manager.isAuthorizedForWidgetUpdates else { return nil }

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        return await withCheckedContinuation { (continuation: CheckedContinuation<Coordinate?, Never>) in
            self.continuation = continuation
            manager.requestLocation()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    private func finish(with coordinate: Coordinate?) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: coordinate)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else {
            finish(with: nil)
            return
        }
        finish(with: Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }
}
