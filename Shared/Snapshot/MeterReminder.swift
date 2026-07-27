import Foundation

/// The "remind me about this spot" timer — parking meters, checkout times, "the market closes at".
///
/// Every parking app in the competitor set has this, and most charge for it. The mechanics are a
/// single local notification; what deserves care is the wording and the arithmetic, so both live
/// here, pure and tested, while the `UNUserNotificationCenter` calls stay in `ReminderService`.
enum MeterReminder {

    /// The durations offered. A fixed set beats a wheel picker for the real cases — meters and
    /// check-outs come in round numbers, and one tap beats scrolling three drums.
    static let presets: [TimeInterval] = [
        15 * 60, 30 * 60, 60 * 60, 2 * 60 * 60, 4 * 60 * 60,
    ]

    static func fireDate(after duration: TimeInterval, from now: Date) -> Date {
        now.addingTimeInterval(duration)
    }

    /// "15 min", "1 h", "2 h" — chip labels, so they have to stay short.
    static func label(for duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    /// Whether a stored reminder is still worth showing. A fire date in the past is stale UI, not
    /// a pending reminder — the notification already fired or was never delivered.
    static func isActive(_ fireDate: Date?, now: Date) -> Bool {
        guard let fireDate else { return false }
        return fireDate > now
    }

    /// Notification content. The spot's name is the payload — "Time's almost up" with no name would
    /// make someone open the app to find out which meter.
    static func notificationTitle(spotName: String) -> String {
        "Time's almost up at \(spotName)"
    }

    static func notificationBody(spotName: String) -> String {
        "You set a reminder for this spot. Tap to point the arrow back at it."
    }

    /// Stable notification identifier, so re-setting a reminder replaces rather than stacks.
    static func notificationIdentifier(spotID: UUID) -> String {
        "meter-\(spotID.uuidString)"
    }
}
