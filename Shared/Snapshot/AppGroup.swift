import Foundation

/// The one place bundle and container identifiers are written down.
///
/// Changing these to your own team's identifiers is the only edit required to build and
/// run Tradewind — see `docs/BUILD.md`. Keep them in step with `Tradewind.entitlements`,
/// `TradewindWidgets.entitlements` and `Tools/gen_xcodeproj.py`.
enum AppGroup {

    /// App Group shared by the app and the widget extension.
    static let identifier = "group.com.tradewind.app"

    /// CloudKit container backing iCloud sync.
    static let cloudKitContainer = "iCloud.com.tradewind.app"

    /// URL scheme for `tradewind://spot?id=…` deep links.
    static let urlScheme = "tradewind"

    /// The shared container, or nil when the App Group entitlement is missing — which is
    /// exactly what happens on a fresh clone before signing is configured. Every caller
    /// treats nil as "fall back to something local" rather than crashing.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Shared defaults, falling back to standard defaults when the group is unavailable.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Directory holding widget-sized thumbnails, created on demand.
    static var thumbnailsURL: URL? {
        guard let base = containerURL else { return nil }
        let url = base.appendingPathComponent("Thumbnails", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Location of the JSON snapshot the widgets read.
    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("snapshot.json", isDirectory: false)
    }
}
