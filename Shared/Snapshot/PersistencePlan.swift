import Foundation

/// Which store configurations are worth attempting, and in what order.
///
/// This lives here, apart from SwiftData, for a reason that cost a launch crash to learn.
///
/// `ModelConfiguration(groupContainer: .identifier(…))` does not *throw* when the App Group
/// entitlement is missing — SwiftData resolves the container path eagerly and calls `fatalError`
/// ("Unable to find App Group Container in Entitlements"). A `fatalError` cannot be caught by
/// `try?`, so a degradation ladder built out of `try?` never gets to degrade: the first rung that
/// names a group container takes the process down before any UI exists to report it.
///
/// The fix is to decide *before* constructing anything, which makes the decision a pure function of
/// two booleans — and a pure function belongs somewhere the test bundle can reach. `Shared/Models`
/// is excluded from the test target precisely because it imports SwiftData, so the rule that guards
/// against the crash could never have been asserted there.
enum PersistenceAttempt: String, CaseIterable, Sendable {
    /// Shared container plus CloudKit. Needs both the App Group and the iCloud entitlement.
    case cloudKit
    /// Shared container, no CloudKit. Needs the App Group.
    case sharedLocal
    /// Private container. Needs nothing, so it is always safe to try.
    case appLocal

    /// Whether this configuration names an App Group, and therefore traps without the entitlement.
    var requiresAppGroup: Bool {
        switch self {
        case .cloudKit, .sharedLocal: return true
        case .appLocal: return false
        }
    }
}

enum PersistencePlan {

    /// The configurations to attempt, best first.
    ///
    /// - Parameters:
    ///   - hasAppGroup: whether the App Group container actually resolved. Probe it with
    ///     `AppGroup.containerURL != nil`, which returns nil rather than trapping when unentitled.
    ///   - cloudSyncEnabled: the Settings toggle.
    ///
    /// `.appLocal` is always last and always present, so the result is never empty.
    static func attempts(hasAppGroup: Bool, cloudSyncEnabled: Bool) -> [PersistenceAttempt] {
        var attempts: [PersistenceAttempt] = []
        if hasAppGroup {
            if cloudSyncEnabled { attempts.append(.cloudKit) }
            attempts.append(.sharedLocal)
        }
        attempts.append(.appLocal)
        return attempts
    }
}

/// How the store ended up being opened. Surfaced in Settings so the person can see whether sync is
/// actually running rather than having to trust a toggle.
enum PersistenceMode: String, Sendable {
    /// Shared container plus CloudKit — spots follow you between devices.
    case syncing
    /// Shared container, no CloudKit. Widgets work, sync does not.
    case sharedLocal
    /// Private container. Widgets can see nothing; happens whenever there is no App Group.
    case appLocal
    /// Nothing on disk. The last resort, so the app opens instead of crashing.
    case memoryOnly

    var summary: String {
        switch self {
        case .syncing: return "Syncing with iCloud"
        case .sharedLocal: return "On this iPhone only"
        case .appLocal: return "On this iPhone (widgets unavailable)"
        case .memoryOnly: return "Temporary — nothing is being saved"
        }
    }

    /// The extra sentence Settings shows underneath, or nil when the summary says enough.
    ///
    /// `.appLocal` earns one because "widgets unavailable" invites the obvious question, and the
    /// answer is not something the person did wrong.
    var explanation: String? {
        switch self {
        case .syncing, .sharedLocal:
            return nil
        case .appLocal:
            return "This build has no App Group, so widgets and Live Activities cannot read your "
                + "spots. A free Apple ID cannot provide one — everything else works normally."
        case .memoryOnly:
            return "The store could not be opened at all. Spots will not survive being closed."
        }
    }

    var isHealthy: Bool { self == .syncing || self == .sharedLocal }

    /// Whether toggling iCloud sync could plausibly change this. Without an App Group it cannot,
    /// so Settings should not suggest reopening the app will help.
    var respondsToCloudToggle: Bool { self == .syncing || self == .sharedLocal }
}
