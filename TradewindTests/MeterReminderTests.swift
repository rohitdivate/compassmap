import Testing
import Foundation

/// The reminder is a promise about time made to someone who walked away from a parking meter.
/// The arithmetic is trivial, which is exactly when it goes untested and then wrong.
@Suite("Meter reminder")
struct MeterReminderTests {

    private let now = Date(timeIntervalSince1970: 1_785_200_000)

    @Test("Presets are round, ascending and unique")
    func presets() {
        #expect(MeterReminder.presets == MeterReminder.presets.sorted())
        #expect(Set(MeterReminder.presets).count == MeterReminder.presets.count)
        // One tap must cover the common cases: a short meter and a half-day.
        #expect(MeterReminder.presets.first == 15 * 60)
        #expect(MeterReminder.presets.contains(60 * 60))
        #expect(MeterReminder.presets.last == 4 * 60 * 60)
    }

    @Test("Fire date is now plus the duration, exactly")
    func fireDate() {
        let fire = MeterReminder.fireDate(after: 1_800, from: now)
        #expect(fire.timeIntervalSince(now) == 1_800)
    }

    @Test("Labels stay chip-sized", arguments: [
        (TimeInterval(15 * 60), "15 min"),
        (TimeInterval(30 * 60), "30 min"),
        (TimeInterval(60 * 60), "1 h"),
        (TimeInterval(2 * 60 * 60), "2 h"),
        (TimeInterval(90 * 60), "1 h 30 min"),
    ])
    func labels(duration: TimeInterval, expected: String) {
        #expect(MeterReminder.label(for: duration) == expected)
    }

    @Test("A past fire date is stale, not active")
    func staleness() {
        // Showing "reminder set" for a notification that already fired is a small lie the detail
        // screen would tell forever, since nothing else clears the field.
        #expect(MeterReminder.isActive(now.addingTimeInterval(-60), now: now) == false)
        #expect(MeterReminder.isActive(now.addingTimeInterval(60), now: now))
        #expect(MeterReminder.isActive(nil, now: now) == false)
    }

    @Test("The notification names the spot, because 'time's up' alone sends someone hunting")
    func content() {
        #expect(MeterReminder.notificationTitle(spotName: "Level 3, aisle F").contains("Level 3, aisle F"))
        #expect(MeterReminder.notificationBody(spotName: "Car").isEmpty == false)
    }

    @Test("Re-setting a reminder replaces it rather than stacking")
    func identifierIsStable() {
        let id = UUID()
        #expect(
            MeterReminder.notificationIdentifier(spotID: id)
                == MeterReminder.notificationIdentifier(spotID: id)
        )
        #expect(
            MeterReminder.notificationIdentifier(spotID: id)
                != MeterReminder.notificationIdentifier(spotID: UUID())
        )
    }
}
