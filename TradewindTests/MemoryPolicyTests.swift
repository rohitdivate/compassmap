import Foundation
import Testing

/// Which spot gets resurfaced as "N years ago today". Anniversaries are exact month-and-day
/// matches, so the rules are small enough to pin completely.
@Suite("Memory resurfacing")
struct MemoryPolicyTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year, month: month, day: day, hour: hour
        ).date!
    }

    @Test("A spot captured on this day a year ago is the memory")
    func exactAnniversary() {
        let id = UUID()
        let memory = MemoryPolicy.memory(
            in: [(id: id, capturedAt: date(2025, 7, 29))],
            today: date(2026, 7, 29),
            calendar: calendar
        )
        #expect(memory == MemoryPolicy.Memory(spotID: id, yearsAgo: 1))
    }

    @Test("A day off is not an anniversary")
    func nearMissDoesNotCount() {
        let memory = MemoryPolicy.memory(
            in: [
                (id: UUID(), capturedAt: date(2025, 7, 28)),
                (id: UUID(), capturedAt: date(2025, 7, 30)),
                (id: UUID(), capturedAt: date(2025, 8, 29)),
            ],
            today: date(2026, 7, 29),
            calendar: calendar
        )
        #expect(memory == nil)
    }

    @Test("This year's photos are recent, not memories")
    func sameYearIsNotAMemory() {
        let memory = MemoryPolicy.memory(
            in: [(id: UUID(), capturedAt: date(2026, 7, 29, hour: 9))],
            today: date(2026, 7, 29),
            calendar: calendar
        )
        #expect(memory == nil)
    }

    @Test("The deepest anniversary wins over the nearest")
    func deepestWins() {
        let old = UUID(), recent = UUID()
        let memory = MemoryPolicy.memory(
            in: [
                (id: recent, capturedAt: date(2025, 7, 29)),
                (id: old, capturedAt: date(2023, 7, 29)),
            ],
            today: date(2026, 7, 29),
            calendar: calendar
        )
        #expect(memory == MemoryPolicy.Memory(spotID: old, yearsAgo: 3))
    }

    @Test("Same depth resolves to the earlier capture, deterministically")
    func sameDepthTieBreak() {
        let morning = UUID(), evening = UUID()
        let candidates = [
            (id: evening, capturedAt: date(2024, 7, 29, hour: 20)),
            (id: morning, capturedAt: date(2024, 7, 29, hour: 8)),
        ]
        let memory = MemoryPolicy.memory(
            in: candidates,
            today: date(2026, 7, 29),
            calendar: calendar
        )
        #expect(memory == MemoryPolicy.Memory(spotID: morning, yearsAgo: 2))
        // Order of the candidate list must not matter.
        let reversed = MemoryPolicy.memory(
            in: candidates.reversed(),
            today: date(2026, 7, 29),
            calendar: calendar
        )
        #expect(reversed == memory)
    }

    @Test("Spots without a capture date never resurface")
    func missingDateIsSkipped() {
        let memory = MemoryPolicy.memory(
            in: [(id: UUID(), capturedAt: nil)],
            today: date(2026, 7, 29),
            calendar: calendar
        )
        #expect(memory == nil)
    }

    @Test("A February 29 memory recurs only when February 29 exists")
    func leapDayIsExactOrNothing() {
        let id = UUID()
        let leap = (id: id, capturedAt: date(2024, 2, 29))
        // 2025 has no Feb 29, so neither Feb 28 nor Mar 1 claims it.
        #expect(MemoryPolicy.memory(in: [leap], today: date(2025, 2, 28), calendar: calendar) == nil)
        #expect(MemoryPolicy.memory(in: [leap], today: date(2025, 3, 1), calendar: calendar) == nil)
        // The next leap year lands it.
        #expect(
            MemoryPolicy.memory(in: [leap], today: date(2028, 2, 29), calendar: calendar)
                == MemoryPolicy.Memory(spotID: id, yearsAgo: 4)
        )
    }

    @Test("The eyebrow reads naturally at one year and counts after")
    func labels() {
        #expect(MemoryPolicy.label(yearsAgo: 1) == "One year ago today")
        #expect(MemoryPolicy.label(yearsAgo: 3) == "3 years ago today")
    }
}
