import Foundation

/// Picks which spot to resurface as a memory — "One year ago today, this taverna in Naxos."
///
/// Pure and calendar-explicit, like every policy in this folder, so the choice is a table of
/// cases rather than a behaviour discovered on device. A memory is a spot photographed on this
/// exact month-and-day at least a year ago; when several qualify, the deepest one wins — three
/// years back says "you keep coming back here" in a way one year back cannot.
enum MemoryPolicy {

    struct Memory: Equatable {
        var spotID: UUID
        var yearsAgo: Int
    }

    static func memory(
        in candidates: [(id: UUID, capturedAt: Date?)],
        today: Date,
        calendar: Calendar = .current
    ) -> Memory? {
        let todayParts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let todayYear = todayParts.year else { return nil }

        var best: Memory?
        var bestCapture = Date.distantFuture
        for candidate in candidates {
            guard let captured = candidate.capturedAt else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: captured)
            guard let year = parts.year,
                  parts.month == todayParts.month,
                  parts.day == todayParts.day,
                  case let years = todayYear - year,
                  years >= 1
            else { continue }
            // Deeper wins; the earlier capture breaks a same-depth tie deterministically.
            if best == nil
                || years > best!.yearsAgo
                || (years == best!.yearsAgo && captured < bestCapture) {
                best = Memory(spotID: candidate.id, yearsAgo: years)
                bestCapture = captured
            }
        }
        return best
    }

    /// The card's eyebrow. Feb 29 memories only recur on leap years — an exact anniversary or
    /// none, never an approximate one.
    static func label(yearsAgo: Int) -> String {
        yearsAgo == 1 ? "One year ago today" : "\(yearsAgo) years ago today"
    }
}
