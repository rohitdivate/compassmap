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

    // Plain assertions rather than `arguments:` — the tuple-array literal inside the @Test macro
    // expansion was more than the type-checker would take, the same budget that keeps splitting
    // view bodies in this project.
    @Test("Labels stay chip-sized")
    func labels() {
        #expect(MeterReminder.label(for: 15 * 60) == "15 min")
        #expect(MeterReminder.label(for: 30 * 60) == "30 min")
        #expect(MeterReminder.label(for: 60 * 60) == "1 h")
        #expect(MeterReminder.label(for: 2 * 60 * 60) == "2 h")
        #expect(MeterReminder.label(for: 90 * 60) == "1 h 30 min")
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
