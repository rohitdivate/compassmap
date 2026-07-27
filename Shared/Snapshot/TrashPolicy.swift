import Foundation

/// When a deleted spot is really gone.
///
/// Deletion is soft: the spot gets a `deletedAt` stamp, disappears from every list, and sits in
/// Recently Deleted where it can be restored — the pattern of Photos, Notes and Mail, and the
/// reason delete needs no confirmation dialog. This type owns the retention arithmetic and the
/// copy, pure and tested, so the purge that permanently destroys someone's memory of a place is
/// driven by a rule that provably does what the screen says it does.
enum TrashPolicy {

    /// Thirty days, matching the convention every built-in app trained people on.
    static let retentionDays = 30

    static var retention: TimeInterval { TimeInterval(retentionDays) * 24 * 60 * 60 }

    /// True when a spot deleted at `deletedAt` should be purged for good.
    static func isExpired(deletedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(deletedAt) >= retention
    }

    /// Whole days until a deleted spot is purged, never negative. Zero means "any moment now".
    static func daysRemaining(deletedAt: Date, now: Date) -> Int {
        let remaining = retention - now.timeIntervalSince(deletedAt)
        guard remaining > 0 else { return 0 }
        return Int((remaining / (24 * 60 * 60)).rounded(.up))
    }

    /// The line under a spot in Recently Deleted.
    static func remainingLabel(deletedAt: Date, now: Date) -> String {
        let days = daysRemaining(deletedAt: deletedAt, now: now)
        switch days {
        case 0: return "Deleting soon"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }

    /// Restoring is safe and silent; only *permanent* deletion warrants a confirmation.
    static let permanentDeleteTitle = "Delete permanently?"
    static let permanentDeleteMessage = "The photo goes with it. This cannot be undone."

    /// The undo toast after a soft delete.
    static func undoMessage(spotName: String) -> String {
        "Deleted \(spotName)"
    }

    /// How long the undo toast stays up.
    static let undoWindow: TimeInterval = 5
}
