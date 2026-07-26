import Foundation
import SwiftData

/// How the store ended up being opened. Surfaced in Settings so the person can see whether
/// sync is actually running rather than having to trust a toggle.
enum PersistenceMode: String, Sendable {
    /// Shared container plus CloudKit — spots follow you between devices.
    case syncing
    /// Shared container, no CloudKit. Widgets work, sync does not.
    case sharedLocal
    /// Private container. Widgets will show nothing; only happens without the App Group.
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

    var isHealthy: Bool { self == .syncing || self == .sharedLocal }
}

/// Opens the SwiftData store, degrading rather than crashing.
///
/// A CloudKit-backed container refuses to open when the iCloud entitlement is missing or the
/// container identifier does not exist — which is the normal state of a fresh clone before
/// signing is set up. Rather than trap on `try!`, each configuration is attempted in turn and
/// the app reports what it got.
enum AppModelContainer {

    static let schema = Schema([Spot.self, Trip.self])

    struct Result {
        let container: ModelContainer
        let mode: PersistenceMode
    }

    static func make(cloudSyncEnabled: Bool) -> Result {
        if cloudSyncEnabled, let container = try? cloudKitContainer() {
            return Result(container: container, mode: .syncing)
        }
        if let container = try? sharedLocalContainer() {
            return Result(container: container, mode: .sharedLocal)
        }
        if let container = try? appLocalContainer() {
            return Result(container: container, mode: .appLocal)
        }
        // If even an in-memory store cannot be built the process is unusable, and a trap here
        // is more honest than an empty screen.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        return Result(container: container, mode: .memoryOnly)
    }

    /// An empty in-memory container for SwiftUI previews.
    static func preview() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema)
    }

    // MARK: - Private

    private static func cloudKitContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Tradewind",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .private(AppGroup.cloudKitContainer)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func sharedLocalContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Tradewind",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func appLocalContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Tradewind",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
