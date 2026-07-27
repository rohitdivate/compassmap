import XCTest

/// Tests that launch the real app in a simulator and tap things.
///
/// These exist because two bugs reached a device that no test here could have caught: the app died in
/// `init()` on any build without an App Group, and Settings could not be opened from any screen. Both
/// were navigation and presentation problems, and both were invisible to a test bundle with no host
/// application — which is what `TradewindTests` deliberately is.
///
/// XCUITest is slower and blunter than the unit tests, so it is used only for what genuinely needs the
/// app running: that it launches at all, that the tabs work, and that every presentation actually
/// presents. Logic stays in the pure tests where it can be asserted precisely.
///
/// The simulator has no magnetometer, no camera, no home screen and no Lock Screen, so the compass,
/// capture, widgets and Live Activities are out of reach here and remain device-only.
final class NavigationUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Read by the app to start from a known state rather than whatever the last test left.
        app.launchArguments += ["-ui-testing"]
        app.launch()
        dismissOnboardingIfPresent()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Onboarding is a full-screen cover on first run. Skipping it is not the thing under test here,
    /// so it is stepped past when present and ignored when not.
    private func dismissOnboardingIfPresent() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) {
            skip.tap()
        }
    }

    private func tabBarButton(_ label: String) -> XCUIElement {
        app.buttons["tab-\(label)"]
    }

    private var settingsButton: XCUIElement { app.buttons["settings-button"] }

    /// Queries across every element type rather than guessing one.
    ///
    /// `otherElements[id]` failed for the gallery and the map on the first CI run: SwiftUI does not
    /// promise which element type an identified container becomes, and a bare identifier on a
    /// container may not create a queryable element at all. Screen identifiers are now anchored to
    /// concrete views, and this looks for them without caring what type they ended up as.
    private func screen(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // MARK: - The app starts at all

    /// Guards the launch crash. The app used to die in `init()` before any view existed, and the
    /// symptom was a white screen — which from the outside is indistinguishable from a slow launch,
    /// so it needs an assertion on something real appearing.
    func testAppLaunchesAndReachesTheGallery() throws {
        XCTAssertTrue(
            screen("gallery-screen").waitForExistence(timeout: 10),
            "The app did not reach the spots gallery. If the store failed to open, the startup report "
                + "screen is showing instead — check the test's captured screenshot."
        )
        // The startup failure screen is the other thing that can legitimately appear, and it means the
        // store could not be opened at all. Failing here with its text is far more useful than a
        // timeout on the gallery.
        XCTAssertFalse(
            app.staticTexts["Tradewind could not open its store"].exists,
            "The app launched but could not open any store."
        )
    }

    // MARK: - The bug this suite was written for

    /// Settings could not be opened. Two causes: three presentation modifiers competing on one host,
    /// and the only entry point living in the Spots masthead so it did not exist on the other tabs.
    /// This asserts the reachable-from-everywhere half directly.
    func testSettingsOpensFromEveryTab() throws {
        for tab in ["Spots", "Map", "Trips"] {
            let button = tabBarButton(tab)
            XCTAssertTrue(button.waitForExistence(timeout: 5), "No \(tab) tab")
            button.tap()

            XCTAssertTrue(
                settingsButton.waitForExistence(timeout: 5),
                "No way into Settings from the \(tab) tab — this is exactly the bug that shipped."
            )
            settingsButton.tap()

            XCTAssertTrue(
                screen("settings-screen").waitForExistence(timeout: 5),
                "Tapping Settings on the \(tab) tab did not present it. Competing presentation "
                    + "modifiers on one host is the known cause."
            )

            app.buttons["settings-done"].tap()
            XCTAssertTrue(
                settingsButton.waitForExistence(timeout: 5),
                "Settings did not dismiss back to the \(tab) tab"
            )
        }
    }

    // MARK: - Navigation

    func testTabsSwitchTheScreen() throws {
        tabBarButton("Map").tap()
        XCTAssertTrue(screen("map-screen").waitForExistence(timeout: 5), "Map did not appear")

        tabBarButton("Trips").tap()
        XCTAssertTrue(screen("trips-screen").waitForExistence(timeout: 5), "Trips did not appear")

        tabBarButton("Spots").tap()
        XCTAssertTrue(screen("gallery-screen").waitForExistence(timeout: 5), "Spots did not appear")
    }

    /// The capture flow is presented as a full-screen cover from a different host than Settings, which
    /// is the arrangement that fixed the conflict. Worth asserting that it still presents.
    func testCaptureSheetPresentsAndDismisses() throws {
        let shutter = app.buttons["capture-button"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()

        XCTAssertTrue(
            screen("capture-screen").waitForExistence(timeout: 5),
            "The capture cover did not present — check it has not started competing with Settings again."
        )
    }
}
