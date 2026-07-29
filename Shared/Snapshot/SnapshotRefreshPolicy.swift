import Foundation

/// When to actually rewrite the widget snapshot.
///
/// Every mutation used to rewrite it synchronously — rename a spot and the store fetched
/// every row, re-encoded JSON, wrote a file and reloaded the widgets before the keystroke
/// returned. The policy turns "after every mutation" into "shortly after the last mutation":
/// a trailing debounce, with a ceiling so a steady stream of writes (a restore, an ingest
/// pass) still lands within a couple of seconds.
enum SnapshotRefreshPolicy {

    /// Quiet period after the most recent request before the write happens.
    static let debounce: TimeInterval = 0.25
    /// No matter how busy the stream, a pending write lands within this of the first request.
    static let maxLatency: TimeInterval = 2.0

    /// The moment the pending write should fire, given when the current pending run started
    /// (nil if this request opens one) and when this request arrived.
    static func fireDate(pendingSince: Date?, requestedAt now: Date) -> Date {
        guard let pendingSince else { return now.addingTimeInterval(debounce) }
        return min(
            pendingSince.addingTimeInterval(maxLatency),
            now.addingTimeInterval(debounce)
        )
    }
}
