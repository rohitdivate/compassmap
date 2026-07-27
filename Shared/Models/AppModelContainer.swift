import Foundation
import SwiftData

/// Opens the SwiftData store, degrading rather than crashing.
///
/// Two different failure modes, and they need different handling — conflating them cost a launch
/// crash on the first real device build:
///
/// * **A missing iCloud entitlement or container** makes `ModelContainer(for:)` *throw*, so `try?`
///   handles it and the next rung down is attempted.
/// * **A missing App Group entitlement does not throw.** SwiftData resolves the group container
///   path eagerly and calls `fatalError` ("Unable to find App Group Container in Entitlements"),
///   which no amount of `try?` can catch. So any configuration naming a group container must be
///   ruled out *before* it is constructed, not caught afterwards.
///
/// `PersistencePlan` decides which rungs are safe from a probe of the App Group; this type only
/// walks the list it is given. The probe itself, `AppGroup.containerURL`, returns nil rather than
/// trapping, which makes it the one safe way to ask the question.
enum AppModelContainer {

    static let schema = Schema([Spot.self, Trip.self])

    struct Result {
        let container: ModelContainer
        let mode: PersistenceMode
    }

    static func make(cloudSyncEnabled: Bool) -> Result {
        // Resolved once: it touches the filesystem, and the answer cannot change mid-launch.
        let hasAppGroup = AppGroup.containerURL != nil
        let attempts = PersistencePlan.attempts(
            hasAppGroup: hasAppGroup,
            cloudSyncEnabled: cloudSyncEnabled
        )

        for attempt in attempts {
            guard let result = open(attempt) else { continue }
            return result
        }

        // If even an in-memory store cannot be built the process is unusable, and a trap here
        // is more honest than an empty screen.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        return Result(container: container, mode: .memoryOnly)
    }

    /// Attempts one configuration. Safe to call only for attempts `PersistencePlan` allowed.
    private static func open(_ attempt: PersistenceAttempt) -> Result? {
        switch attempt {
        case .cloudKit:
            guard let container = try? cloudKitContainer() else { return nil }
            return Result(container: container, mode: .syncing)
        case .sharedLocal:
            guard let container = try? sharedLocalContainer() else { return nil }
            return Result(container: container, mode: .sharedLocal)
        case .appLocal:
            guard let container = try? appLocalContainer() else { return nil }
            return Result(container: container, mode: .appLocal)
        }
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
