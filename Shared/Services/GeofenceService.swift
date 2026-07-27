import CoreLocation
import Foundation
import UserNotifications

/// Arms the "you're near your spot" geofences and turns an entry into a notification.
///
/// Owns its own `CLLocationManager`: region monitoring callbacks arrive on the manager that
/// registered the regions, and sharing `LocationService`'s manager would tangle a stream of
/// location updates with a set of long-lived registrations that outlive any screen.
///
/// Which regions to arm is not decided here — `GeofencePlan` does that, pure and tested. This
/// class only clears what it previously registered (never anything else: only identifiers with
/// the `tradewind-` prefix are touched) and registers the new set.
///
/// Honest limit: entry events wake a closed app only with Always authorization. With
/// When-In-Use they fire only while the app is foregrounded, which for an arrival alert is
/// nearly useless — the detail screen says so next to the toggle.
final class GeofenceService: NSObject, CLLocationManagerDelegate {

    static let shared = GeofenceService()

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Replaces every region this app monitors with the given plan. Cheap enough to call on
    /// every scene-activation and toggle change — CoreLocation deduplicates registrations by
    /// identifier, and the set is at most `GeofencePlan.defaultLimit` entries.
    func rearm(_ regions: [GeofencePlan.Region]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let wanted = Dictionary(uniqueKeysWithValues: regions.map {
            (GeofencePlan.regionIdentifier(spotID: $0.id), $0)
        })

        for monitored in manager.monitoredRegions
        where monitored.identifier.hasPrefix(GeofencePlan.regionPrefix)
            && wanted[monitored.identifier] == nil {
            manager.stopMonitoring(for: monitored)
        }

        for (identifier, region) in wanted {
            let circular = CLCircularRegion(
                center: CLLocationCoordinate2D(
                    latitude: region.coordinate.latitude,
                    longitude: region.coordinate.longitude
                ),
                radius: region.radiusMetres,
                identifier: identifier
            )
            circular.notifyOnEntry = true
            circular.notifyOnExit = false
            manager.startMonitoring(for: circular)
        }

        // What the notification should say when the region fires, possibly days from now in a
        // process that has no store open. Kept beside the registration so the two cannot drift.
        pendingContent = wanted.mapValues { region in
            (title: GeofencePlan.notificationTitle(spotName: region.name),
             body: GeofencePlan.notificationBody(note: region.note))
        }
    }

    /// Wording per region identifier, captured at arm time.
    private var pendingContent: [String: (title: String, body: String)] = [:]

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let spotID = GeofencePlan.spotID(fromRegionIdentifier: region.identifier) else { return }
        let wording = pendingContent[region.identifier]

        let content = UNMutableNotificationContent()
        content.title = wording?.title ?? GeofencePlan.notificationTitle(spotName: "a saved spot")
        content.body = wording?.body ?? GeofencePlan.notificationBody(note: nil)
        content.sound = .default
        // The same userInfo key the meter reminders use, so `ReminderService`'s tap delegate
        // routes this to the arrow with no new code.
        content.userInfo = ["spotID": spotID.uuidString]

        let request = UNNotificationRequest(
            identifier: "arrival-\(region.identifier)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        // A region that cannot be monitored (over the OS cap, or monitoring unsupported) is
        // worth a console line; taking anything down over it is not.
        print("[Tradewind] geofence failed for \(region?.identifier ?? "?"): \(error)")
    }
}
