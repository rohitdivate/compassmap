import Foundation

/// A one-shot instruction left for the app by something outside it.
///
/// Widgets, Siri and Shortcuts all run in other processes, and an App Intent that opens the app
/// cannot hand it a payload directly. So the intent writes what it wants here, the app reads it
/// once on becoming active, and clears it. Small, boring, and it means every entry point into
/// the app converges on the same router call.
enum PendingAction {

    private static let key = "com.tradewind.pendingAction"

    enum Kind: Equatable {
        case openSpot(UUID)
        case openCapture
    }

    static func set(_ kind: Kind) {
        switch kind {
        case .openSpot(let id):
            AppGroup.defaults.set("spot:\(id.uuidString)", forKey: key)
        case .openCapture:
            AppGroup.defaults.set("capture", forKey: key)
        }
    }

    /// Reads and clears in one step — an action that fires twice is worse than one that is missed.
    static func take() -> Kind? {
        guard let raw = AppGroup.defaults.string(forKey: key) else { return nil }
        AppGroup.defaults.removeObject(forKey: key)

        if raw == "capture" { return .openCapture }
        if raw.hasPrefix("spot:"), let id = UUID(uuidString: String(raw.dropFirst(5))) {
            return .openSpot(id)
        }
        return nil
    }
}
