import Foundation
import Observation

/// The one place a just-deleted spot waits for its undo.
///
/// Deletion happens in three places — the gallery's context menu, the detail screen, and one
/// day a swipe — and the five-second toast must appear regardless of which. So the toast is a
/// root-level overlay fed from here, not a per-screen widget: `SpotStore.delete` announces,
/// `RootView` renders, and no screen needs to remember to participate.
@Observable
final class UndoCenter {

    static let shared = UndoCenter()
    private init() {}

    struct Candidate: Equatable {
        let spotID: UUID
        let name: String
        /// Distinguishes deleting the same spot twice, so the toast timer restarts.
        let shownAt: Date
    }

    private(set) var candidate: Candidate?

    func show(spotID: UUID, name: String) {
        candidate = Candidate(spotID: spotID, name: name, shownAt: Date())
    }

    func clear() {
        candidate = nil
    }
}
