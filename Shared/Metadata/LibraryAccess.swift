import Foundation

/// How much of the photo library this app is allowed to see, and which picker that implies.
///
/// `PHAuthorizationStatus` is mapped to this at the `PhotoService` boundary for two reasons. It keeps
/// the Photos framework out of the decision, so the decision is testable — and this is precisely the
/// decision that was got wrong: the app presented the picker that only shows *authorized* photos
/// without ever having asked for authorization, so the library came up empty and the permission
/// prompt was unreachable.
enum LibraryAccess: String, CaseIterable, Sendable {
    /// Never asked. The state a fresh install is in, and the one that produced an empty picker.
    case notDetermined
    /// Full library.
    case granted
    /// A subset the person chose. The picker shows only that subset, plus a way to add to it.
    case limited
    /// Refused, or blocked by device policy.
    case denied

    /// Which picker to present.
    ///
    /// The distinction matters more than it looks. `PhotosPicker` with `photoLibrary: .shared()` runs
    /// in-process and shows only what the app may already see — nothing, if it has not asked. Without
    /// that argument the picker runs out-of-process, needs no permission at all, and always shows the
    /// whole library. The tradeoff is `PhotosPickerItem.itemIdentifier`, which is nil unless the
    /// picker was given a library, and that identifier is what the `PHAsset` location lookup needs.
    ///
    /// So: prefer the in-process picker when it will actually show something, and fall back to the
    /// out-of-process one rather than showing an empty grid.
    var picker: PickerKind? {
        switch self {
        case .notDetermined:
            // Nothing should be presented in this state — ask first. Returning nil rather than a
            // default is deliberate: a default here is how the original bug happened.
            return nil
        case .granted, .limited:
            return .sharedLibrary
        case .denied:
            return .outOfProcess
        }
    }

    /// Whether the person should be told the location may be missing before they pick.
    ///
    /// Without library access there is no `PHAsset` to consult, so a photo whose GPS block the picker
    /// stripped has no second chance at a coordinate.
    var canReadAssetLocations: Bool {
        switch self {
        case .granted, .limited: return true
        case .notDetermined, .denied: return false
        }
    }
}

enum PickerKind: String, Sendable {
    /// `PhotosPicker(..., photoLibrary: .shared())` — in-process, needs authorization, gives
    /// `itemIdentifier`.
    case sharedLibrary
    /// `PhotosPicker(...)` with no library — out-of-process, needs nothing, no `itemIdentifier`.
    case outOfProcess
}
