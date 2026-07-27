import Foundation
import UserNotifications

/// Schedules the "remind me about this spot" local notification.
///
/// Thin on purpose: the durations, wording and identifiers live in `MeterReminder`, where they are
/// pure and tested. This file is only the part that has to talk to the notification centre.
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = ReminderService()

    private override init() { super.init() }

    /// Call once at launch so notification taps route into the app.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// A tapped reminder opens the arrow at its spot, through the same one-shot channel the
    /// widgets and Siri already use — every entry point converges on the same router call.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let raw = response.notification.request.content.userInfo["spotID"] as? String,
           let id = UUID(uuidString: raw) {
            PendingAction.set(.openSpot(id))
        }
        completionHandler()
    }

    /// A reminder that fires while the app is open still shows — being in the gallery does not
    /// mean you remembered the meter.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Asks for permission the first time it is needed — at the moment of setting a reminder, when
    /// the person can see exactly why the app is asking — never at launch.
    func schedule(spotID: UUID, spotName: String, at fireDate: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = MeterReminder.notificationTitle(spotName: spotName)
            content.body = MeterReminder.notificationBody(spotName: spotName)
            content.sound = .default
            // The deep link the app already routes: tapping the notification opens the arrow.
            content.userInfo = ["spotID": spotID.uuidString]

            let interval = max(1, fireDate.timeIntervalSinceNow)
            let request = UNNotificationRequest(
                identifier: MeterReminder.notificationIdentifier(spotID: spotID),
                content: content,
                // The same identifier replaces any earlier reminder for this spot.
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            center.add(request)
        }
    }

    func cancel(spotID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [MeterReminder.notificationIdentifier(spotID: spotID)]
        )
    }
}
