import CoreSpotlight
import SwiftData
import SwiftUI

@main
struct TradewindApp: App {

    @State private var settings = AppSettings.shared
    @State private var router = AppRouter()

    private let persistence: AppModelContainer.Result

    init() {
        // Opening the store is the one thing that can fail before there is any UI to report it
        // with, so it degrades in steps and records what it managed. Settings shows the result.
        let result = AppModelContainer.make(cloudSyncEnabled: AppSettings.shared.cloudSyncEnabled)
        persistence = result
        AppSettings.shared.persistenceMode = result.mode
    }

    var body: some Scene {
        WindowGroup {
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
        .modelContainer(persistence.container)
    }
}
