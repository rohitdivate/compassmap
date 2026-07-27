import Testing
import Foundation

/// Guards the rule that fixed a launch crash.
///
/// Tradewind shipped to a device signed with a free Personal Team, which cannot carry an App Group
/// entitlement. The store's degradation ladder attempted a CloudKit configuration first, and that
/// configuration names a group container. SwiftData resolves the group path eagerly and calls
/// `fatalError` rather than throwing, so the `try?` around it caught nothing and the app died in
/// `init()` with a blank screen.
///
/// The rule below is the whole fix: without an App Group, nothing that names one may be attempted.
@Suite("Persistence plan")
struct PersistencePlanTests {

    // MARK: - The regression

    @Test("Without an App Group, only the private store is attempted", arguments: [true, false])
    func withoutAppGroupOnlyAppLocal(cloudSyncEnabled: Bool) {
        let attempts = PersistencePlan.attempts(
            hasAppGroup: false,
            cloudSyncEnabled: cloudSyncEnabled
        )
        // Exactly one rung, and it is the one that names no group container. The cloud toggle must
        // not be able to reintroduce a trapping configuration.
        #expect(attempts == [.appLocal])
    }

    @Test("No attempt that needs an App Group survives a missing one", arguments: [true, false])
    func noGroupAttemptsWithoutEntitlement(cloudSyncEnabled: Bool) {
        let attempts = PersistencePlan.attempts(
            hasAppGroup: false,
            cloudSyncEnabled: cloudSyncEnabled
        )
        // Stated a second way, against the attempt's own declaration rather than a literal list, so
        // adding a future group-backed configuration cannot slip past this suite.
        #expect(attempts.allSatisfy { !$0.requiresAppGroup })
    }

    // MARK: - The ordinary paths

    @Test("With an App Group and sync on, all three are tried, best first")
    func fullLadder() {
        let attempts = PersistencePlan.attempts(hasAppGroup: true, cloudSyncEnabled: true)
        #expect(attempts == [.cloudKit, .sharedLocal, .appLocal])
    }

    @Test("With sync off, CloudKit is skipped but the shared store is kept")
    func syncDisabled() {
        let attempts = PersistencePlan.attempts(hasAppGroup: true, cloudSyncEnabled: false)
        #expect(attempts == [.sharedLocal, .appLocal])
    }

    @Test("The private store is always the last resort, never absent", arguments: [
        (true, true), (true, false), (false, true), (false, false),
    ])
    func appLocalAlwaysLast(hasAppGroup: Bool, cloudSyncEnabled: Bool) {
        let attempts = PersistencePlan.attempts(
            hasAppGroup: hasAppGroup,
            cloudSyncEnabled: cloudSyncEnabled
        )
        #expect(attempts.last == .appLocal)
        #expect(attempts.isEmpty == false)
        // No configuration is offered twice; a repeat would mean a wasted open attempt.
        #expect(Set(attempts).count == attempts.count)
    }

    // MARK: - What Settings reports

    @Test("Only the shared-container modes count as healthy")
    func health() {
        #expect(PersistenceMode.syncing.isHealthy)
        #expect(PersistenceMode.sharedLocal.isHealthy)
        #expect(PersistenceMode.appLocal.isHealthy == false)
        #expect(PersistenceMode.memoryOnly.isHealthy == false)
    }

    @Test("Degraded modes explain themselves; healthy ones stay quiet")
    func explanations() {
        #expect(PersistenceMode.syncing.explanation == nil)
        #expect(PersistenceMode.sharedLocal.explanation == nil)
        // "widgets unavailable" invites a question, so it has to answer it.
        #expect(PersistenceMode.appLocal.explanation?.contains("App Group") == true)
        #expect(PersistenceMode.memoryOnly.explanation != nil)
    }

    @Test("Settings must not imply the iCloud toggle can fix a missing App Group")
    func cloudToggleRelevance() {
        #expect(PersistenceMode.syncing.respondsToCloudToggle)
        #expect(PersistenceMode.sharedLocal.respondsToCloudToggle)
        #expect(PersistenceMode.appLocal.respondsToCloudToggle == false)
        #expect(PersistenceMode.memoryOnly.respondsToCloudToggle == false)
    }

    @Test("Every mode has a non-empty summary")
    func summaries() {
        for mode in [
            PersistenceMode.syncing, .sharedLocal, .appLocal, .memoryOnly,
        ] {
            #expect(mode.summary.isEmpty == false)
        }
    }
}

/// The report is the only evidence that exists when the app misbehaves on someone else's phone,
/// so its content is worth pinning rather than trusting.
@Suite("Startup report")
struct StartupReportTests {

    private func report(appGroupResolved: Bool, cloudSyncRequested: Bool = true) -> StartupReport {
        StartupReport(
            appGroupIdentifier: "group.com.example.app",
            appGroupResolved: appGroupResolved,
            cloudSyncRequested: cloudSyncRequested
        )
    }

    @Test("A missing entitlement is named as such, not left as a bare 'no'")
    func namesTheMissingEntitlement() {
        let text = report(appGroupResolved: false).text
        #expect(text.contains("group.com.example.app"))
        #expect(text.contains("entitlement missing"))
    }

    @Test("An opened attempt reads as opened; a failed one carries its reason")
    func stepsReadClearly() {
        var subject = report(appGroupResolved: true)
        subject.record("cloudKit", failure: "CloudKit integration requires the iCloud entitlement.")
        subject.record("sharedLocal")

        #expect(subject.didOpen)
        #expect(subject.text.contains("cloudKit: failed — CloudKit integration requires"))
        #expect(subject.text.contains("sharedLocal: opened"))
    }

    @Test("A report with no attempts says so rather than showing an empty list")
    func noAttempts() {
        let subject = report(appGroupResolved: false)
        #expect(subject.didOpen == false)
        #expect(subject.text.contains("nothing was considered safe to try"))
    }

    @Test("Nothing opening is distinguishable from something opening")
    func failureIsDistinguishable() {
        var subject = report(appGroupResolved: false)
        subject.record("appLocal", failure: "disk full")
        subject.record("memoryOnly", failure: "schema invalid")
        #expect(subject.didOpen == false)
        #expect(subject.steps.count == 2)
    }

    @Test("Every attempt's raw value survives into the text, so modes cannot be mislabelled")
    func attemptNamesRoundTrip() {
        for attempt in PersistenceAttempt.allCases {
            var subject = report(appGroupResolved: true)
            subject.record(attempt.rawValue)
            #expect(subject.text.contains("\(attempt.rawValue): opened"))
        }
    }
}
