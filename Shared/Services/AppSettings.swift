import Foundation
import Observation
import WidgetKit

/// User preferences, stored in the shared App Group so the widgets pick up the same theme
/// and units the app is using.
@Observable
final class AppSettings {

    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    /// True when launched by the UI tests.
    ///
    /// Those tests assert on navigation, and navigation that depends on whatever the last run left
    /// behind is not an assertion. Under this flag the app reads and writes a throwaway defaults
    /// suite, so every run starts from a genuinely first-launch state — including onboarding, which is
    /// then part of what gets exercised rather than something skipped.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    /// A defaults suite that holds nothing between launches.
    private static func ephemeralDefaults() -> UserDefaults {
        let suite = "com.tradewind.uitesting"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    init(defaults: UserDefaults = AppSettings.isUITesting ? ephemeralDefaults() : AppGroup.defaults) {
        self.defaults = defaults
        themeID = defaults.string(forKey: Key.theme) ?? ThemeCatalog.fallback.id
        unitPreference = UnitPreference(rawValue: defaults.string(forKey: Key.units) ?? "")
            ?? .automatic
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        soundEnabled = defaults.object(forKey: Key.sound) as? Bool ?? false
        usesTrueNorth = defaults.object(forKey: Key.trueNorth) as? Bool ?? true
        cloudSyncEnabled = defaults.object(forKey: Key.cloudSync) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarded)
    }

    // MARK: - Stored preferences

    var themeID: String {
        didSet {
            defaults.set(themeID, forKey: Key.theme)
            publishToWidgets()
        }
    }

    var unitPreference: UnitPreference {
        didSet {
            defaults.set(unitPreference.rawValue, forKey: Key.units)
            publishToWidgets()
        }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }

    /// Off by default — an app that starts making noise unasked is not delightful.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.sound) }
    }

    /// True north needs a location fix; magnetic north always works. Defaults to true north
    /// because that is what matches a map.
    var usesTrueNorth: Bool {
        didSet { defaults.set(usesTrueNorth, forKey: Key.trueNorth) }
    }

    var cloudSyncEnabled: Bool {
        didSet { defaults.set(cloudSyncEnabled, forKey: Key.cloudSync) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarded) }
    }

    // MARK: - Derived

    var theme: Theme { ThemeCatalog.theme(id: themeID) }

    /// Set from `AppModelContainer` at launch; read by Settings to show the real state of
    /// persistence rather than the intended state.
    var persistenceMode: PersistenceMode = .sharedLocal

    // MARK: - Widgets

    /// Pushes theme and units into the snapshot and asks WidgetKit to redraw, so changing the
    /// theme restyles the home screen too.
    private func publishToWidgets() {
        let currentTheme = themeID
        let currentUnits = unitPreference
        SharedSnapshotStore.mutate(defaultThemeID: currentTheme) { snapshot in
            snapshot.themeID = currentTheme
            snapshot.unitPreference = currentUnits
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private enum Key {
        static let theme = "settings.themeID"
        static let units = "settings.unitPreference"
        static let haptics = "settings.haptics"
        static let sound = "settings.sound"
        static let trueNorth = "settings.trueNorth"
        static let cloudSync = "settings.cloudSync"
        static let onboarded = "settings.onboardingComplete"
    }
}
