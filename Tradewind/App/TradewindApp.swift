import CoreSpotlight
import SwiftData
import SwiftUI

@main
struct TradewindApp: App {

    @State private var settings = AppSettings.shared
    @State private var router = AppRouter()

    private let outcome: AppModelContainer.Outcome

    init() {
        // Opening the store is the one thing that can fail before there is any UI to report it
        // with. It degrades in steps, and the App Group is *probed* rather than attempted — see
        // AppModelContainer for why that distinction is load-bearing rather than pedantic.
        let outcome = AppModelContainer.make(cloudSyncEnabled: AppSettings.shared.cloudSyncEnabled)
        self.outcome = outcome

        if case .opened(let result) = outcome {
            AppSettings.shared.persistenceMode = result.mode
        }

        // Printed on every build, not just DEBUG. This app is developed without a Mac, so when it
        // misbehaves on someone's phone this report is the only evidence that exists — and a report
        // that only prints in one configuration is the one you do not have when you need it.
        // Which build this is, first line of every launch. The report below is useless without it:
        // several rounds of "the fix did not work" turned out to be an old binary.
        print("[Tradewind] \(BuildInfo.current.summary()) — \(BuildInfo.current.identifierLine ?? "no bundle id")")
        print(outcome.report.text)

        // Notification taps (meter reminders) route into the app through PendingAction.
        ReminderService.shared.activate()

        #if DEBUG
        // A font that fails to register substitutes the system face silently, so the app just
        // looks a bit wrong. Worth one line in the console on the first run of a fresh build.
        Fonts.verifyRegistration()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch outcome {
        case .opened(let result):
            main.modelContainer(result.container)
        case .failed(let report):
            // No theme, no custom fonts, no environment — the fewest possible dependencies, since
            // this is the path taken when something fundamental is already wrong.
            StartupFailureView(report: report)
        }
    }

    private var main: some View {
        RootView()
            .environment(settings)
            .environment(router)
            .environment(\.theme, settings.theme)
            // Each theme fixes its own scheme: Tropical Spritz is a cream, light mood and
            // Nomad Money a near-black one, and neither survives being inverted.
            .preferredColorScheme(settings.theme.colorScheme)
            .tint(settings.theme.accent)
            .onOpenURL { url in
                router.handle(url: url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier]
                    as? String
                else { return }
                router.openSpot(identifier: identifier)
            }
    }
}
