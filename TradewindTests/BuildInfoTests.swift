import Testing
import Foundation

/// Settings reported "Version 1.0 (1)" — two Info.plist constants that never change. So when several
/// fixes in a row appeared not to work, nothing inside the app could answer "is this even a new
/// build?", and the answer was no, for three separate reasons at once. These assertions are about that
/// line carrying information rather than looking like it does.
@Suite("Build identity")
struct BuildInfoTests {

    private let built = Date(timeIntervalSince1970: 1_785_116_520)  // 2026-07-27 01:42 UTC

    private func info(
        identifier: String? = "com.rohitdivate.app",
        builtAt: Date? = nil
    ) -> BuildInfo {
        BuildInfo(version: "1.0", build: "1", bundleIdentifier: identifier, builtAt: builtAt)
    }

    // MARK: - Telling builds apart

    @Test("The summary carries a build time, which is the part that differs between builds")
    func summaryIncludesTime() {
        let summary = info(builtAt: built).summary(
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(summary.contains("1.0 (1)"))
        #expect(summary.contains("built"))
        #expect(summary.contains("27 Jul"))
        #expect(summary.contains("01:42"))
    }

    @Test("Two builds a minute apart do not read identically")
    func summariesDiffer() {
        // The whole failure being guarded against: a line that looks like a version but is constant.
        let earlier = info(builtAt: built).summary(timeZone: TimeZone(identifier: "UTC")!)
        let later = info(builtAt: built.addingTimeInterval(600))
            .summary(timeZone: TimeZone(identifier: "UTC")!)
        #expect(earlier != later)
    }

    @Test("Without a build date it degrades to the version rather than showing a wrong one")
    func missingDate() {
        let summary = info(builtAt: nil).summary()
        #expect(summary == "1.0 (1)")
        #expect(summary.contains("built") == false)
    }

    // MARK: - Proving the signing script ran

    @Test("The repository placeholder is recognised as such")
    func placeholderDetected() {
        // A build still reading com.tradewind.app has not had setup_signing.py applied, which is
        // otherwise invisible until Xcode refuses to sign.
        #expect(info(identifier: "com.tradewind.app").usesPlaceholderIdentifier)
        #expect(info(identifier: "com.tradewind.app.widgets").usesPlaceholderIdentifier)
    }

    @Test("A real identifier is not flagged")
    func realIdentifierAccepted() {
        #expect(info(identifier: "com.rohitdivate.app").usesPlaceholderIdentifier == false)
        #expect(info(identifier: "io.example.tradewind").usesPlaceholderIdentifier == false)
    }

    @Test("A missing identifier is neither shown nor treated as a placeholder")
    func missingIdentifier() {
        #expect(info(identifier: nil).identifierLine == nil)
        #expect(info(identifier: "").identifierLine == nil)
        #expect(info(identifier: nil).usesPlaceholderIdentifier == false)
    }

    @Test("The identifier is surfaced verbatim, so it can be compared with what was asked for")
    func identifierIsVerbatim() {
        #expect(info(identifier: "com.rohitdivate.app").identifierLine == "com.rohitdivate.app")
    }
}
