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
        let report: StartupReport
    }

    enum Outcome {
        case opened(Result)
        /// Nothing opened, not even in memory. The app shows the report rather than dying, because
        /// a white screen tells whoever is holding the phone nothing at all.
        case failed(StartupReport)

        var report: StartupReport {
            switch self {
            case .opened(let result): return result.report
            case .failed(let report): return report
            }
        }
    }

    static func make(cloudSyncEnabled: Bool) -> Outcome {
        // Resolved once: it touches the filesystem, and the answer cannot change mid-launch.
        let hasAppGroup = AppGroup.containerURL != nil
        var report = StartupReport(
            appGroupIdentifier: AppGroup.identifier,
            appGroupResolved: hasAppGroup,
            cloudSyncRequested: cloudSyncEnabled
        )

        let attempts = PersistencePlan.attempts(
            hasAppGroup: hasAppGroup,
            cloudSyncEnabled: cloudSyncEnabled
        )
        for attempt in attempts {
            do {
                let container = try open(attempt)
                report.record(attempt.rawValue)
                return .opened(Result(container: container, mode: attempt.mode, report: report))
            } catch {
                report.record(attempt.rawValue, failure: String(describing: error))
            }
        }

        // In-memory is not in the plan because it is not a place to keep someone's spots; it is
        // what stops a broken disk from being a broken app.
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            report.record("memoryOnly")
            return .opened(Result(container: container, mode: .memoryOnly, report: report))
        } catch {
            report.record("memoryOnly", failure: String(describing: error))
        }

        // Every rung failed. There used to be a `try!` here, which turned this into a crash with no
        // explanation — the same class of mistake as catching a fatalError. Report it instead.
        return .failed(report)
    }

    /// Attempts one configuration. Safe to call only for attempts `PersistencePlan` allowed.
    private static func open(_ attempt: PersistenceAttempt) throws -> ModelContainer {
        switch attempt {
        case .cloudKit: return try cloudKitContainer()
        case .sharedLocal: return try sharedLocalContainer()
        case .appLocal: return try appLocalContainer()
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
