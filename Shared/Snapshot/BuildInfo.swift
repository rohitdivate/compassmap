import Foundation

/// Which build of Tradewind this actually is.
///
/// Settings used to show "Version 1.0 (1)", read from the Info.plist — constants that never change,
/// so the line looked like information while carrying none. That cost real time: after several fixes
/// failed to appear on a device, there was no way to tell from inside the app whether a new build had
/// been installed at all, and the answer turned out to be no for three different reasons at once.
///
/// So this reports two things that genuinely differ between builds: when the binary was compiled, and
/// which bundle identifier it was signed with. The second answers "did the signing script actually
/// run?" without opening Xcode.
///
/// Foundation-only, in a directory the test bundle compiles, with the values injectable so the
/// formatting can be asserted rather than eyeballed against a live bundle.
struct BuildInfo: Equatable, Sendable {

    var version: String
    var build: String
    var bundleIdentifier: String?
    /// When the executable was written. Changes on every compile, which is the whole point.
    var builtAt: Date?

    /// Read from the running bundle.
    static var current: BuildInfo {
        let info = Bundle.main.infoDictionary
        return BuildInfo(
            version: info?["CFBundleShortVersionString"] as? String ?? "1.0",
            build: info?["CFBundleVersion"] as? String ?? "1",
            bundleIdentifier: Bundle.main.bundleIdentifier,
            builtAt: executableDate()
        )
    }

    /// Modification date of the app's own binary.
    ///
    /// Xcode rewrites and re-signs the executable on every build, so its timestamp is a reliable
    /// "when was this compiled" without needing a build step to stamp anything in.
    private static func executableDate() -> Date? {
        guard let url = Bundle.main.executableURL else { return nil }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    /// `1.0 (1) · built 27 Jul 01:42`
    ///
    /// Deliberately to the minute. Seconds are noise; the day and time are what distinguish "the build
    /// I just made" from "the one from an hour ago".
    func summary(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var line = "\(version) (\(build))"
        guard let builtAt else { return line }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        line += " · built \(formatter.string(from: builtAt))"
        return line
    }

    /// The identifier the build was signed with, or nil when there is nothing useful to say.
    ///
    /// Shown because it is the one thing in the app that proves whether `setup_signing.py` applied
    /// your prefix: a build still reading `com.tradewind.app` is the placeholder, not yours.
    var identifierLine: String? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        return bundleIdentifier
    }

    /// Whether this build is still using the repository's placeholder identifier.
    var usesPlaceholderIdentifier: Bool {
        bundleIdentifier?.hasPrefix("com.tradewind") ?? false
    }
}
