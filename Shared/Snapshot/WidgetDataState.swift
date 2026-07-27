import Foundation

/// Why a widget has nothing to show.
///
/// These were previously one case, and the message covering both told people to save a spot. On a
/// build with no App Group entitlement the snapshot is *always* absent, so that message asked someone
/// who had already saved several spots to go and save one — which reads as the widget being broken
/// rather than the build being limited.
enum WidgetDataState: String, CaseIterable, Sendable {
    /// There is a snapshot with spots in it.
    case ready
    /// No App Group, so the widget cannot reach the app's data at all. Nothing the person does in the
    /// app will change this.
    case noAppGroup
    /// The App Group works; there is genuinely nothing saved yet.
    case noSpots

    /// Order matters: a missing App Group has to be checked first, because it makes the snapshot
    /// unreadable and would otherwise be indistinguishable from an empty one.
    static func state(hasAppGroup: Bool, snapshotIsEmpty: Bool) -> WidgetDataState {
        if !hasAppGroup { return .noAppGroup }
        if snapshotIsEmpty { return .noSpots }
        return .ready
    }

    /// What the widget says, or nil when it has real data to show instead.
    var message: String? {
        switch self {
        case .ready:
            return nil
        case .noAppGroup:
            return "This build can't share data with its widgets."
        case .noSpots:
            return "Save a spot in Tradewind to see it here."
        }
    }
}
