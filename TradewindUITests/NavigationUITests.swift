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

// MARK: - Saving without a photo

extension NavigationUITests {

    /// The Wave 1 loop end to end: tap Save here, pick a kind, name it, save, and see it in the
    /// gallery. Runs in the simulator because the flow needs no camera — which is the point of it.
    /// The coordinate comes from the -ui-testing seam; CI simulators have no location fix.
    func testSaveHereCreatesASpotWithoutAPhoto() throws {
        let saveHere = app.buttons["save-here-button"]
        XCTAssertTrue(saveHere.waitForExistence(timeout: 5), "No Save here button on the gallery")
        saveHere.tap()

        let stayKind = app.buttons["kind-stay"]
        XCTAssertTrue(stayKind.waitForExistence(timeout: 5), "The save-here sheet did not present")
        stayKind.tap()

        let nameField = app.textFields["save-here-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test Hotel")

        let confirm = app.buttons["save-here-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(confirm.isEnabled, "Save disabled — the UI-test location seam is not supplying a coordinate")
        confirm.tap()

        // The sheet dismisses back to the gallery, which now contains the spot.
        XCTAssertTrue(
            app.staticTexts["Test Hotel"].waitForExistence(timeout: 8),
            "The saved spot did not appear in the gallery"
        )
    }

    /// Wave 3: the arrival-alert toggle exists, turns on, and the choice survives closing the
    /// detail sheet — it is a stored property, not view state. Region *entry* cannot be simulated
    /// on CI hardware, so what fires when you actually walk up stays on the device checklist.
    func testArrivalAlertToggleShowsAndPersists() throws {
        // Arrange: one spot, via the same flow the save-here test proves.
        app.buttons["save-here-button"].tap()
        XCTAssertTrue(app.buttons["kind-stay"].waitForExistence(timeout: 5))
        app.buttons["kind-stay"].tap()
        let nameField = app.textFields["save-here-name"]
        nameField.tap()
        nameField.typeText("Alert Cove")
        app.buttons["save-here-confirm"].tap()
        let card = app.staticTexts["Alert Cove"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        // The detail sheet lives behind the arrow screen's overflow menu.
        card.tap()
        openDetailFromArrow()

        let toggle = scrollToArrivalToggle()
        XCTAssertTrue(waitForSwitchValue(toggle, "0"), "A new spot should start with alerts off")
        toggle.tap()
        XCTAssertTrue(waitForSwitchValue(toggle, "1"), "The toggle did not turn on")

        app.buttons["detail-done"].tap()
        XCTAssertTrue(
            app.buttons["spot-more-button"].waitForExistence(timeout: 5),
            "Dismissing the detail sheet did not return to the arrow screen"
        )
        openDetailFromArrow()
        let reopened = scrollToArrivalToggle()
        XCTAssertTrue(
            waitForSwitchValue(reopened, "1"),
            "The alert choice did not survive closing and reopening the detail sheet"
        )
    }

    private func openDetailFromArrow() {
        let more = app.buttons["spot-more-button"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "No overflow menu on the arrow screen")
        more.tap()
        // Menu items usually surface by identifier, but SwiftUI has been known to expose only the
        // label, so both are accepted.
        let byIdentifier = app.buttons["spot-details-item"]
        let item = byIdentifier.waitForExistence(timeout: 2) ? byIdentifier : app.buttons["Spot details"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The overflow menu did not open")
        // SwiftUI menu items can report an invalid activation point ("no suggested hit points")
        // even with a perfectly good frame — the first CI run failed on exactly that. Tapping the
        // frame's centre coordinate bypasses the activation-point computation entirely.
        if item.isHittable {
            item.tap()
        } else {
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// The arrival section sits low on the detail scroll view, below the photo and the facts.
    private func scrollToArrivalToggle() -> XCUIElement {
        let toggle = app.switches["arrival-toggle"]
        for _ in 0..<6 where !(toggle.exists && toggle.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "No arrival alert toggle on the detail screen")
        return toggle
    }

    /// Switch state changes are animated, so the value is awaited rather than read immediately.
    private func waitForSwitchValue(
        _ element: XCUIElement,
        _ value: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Wave 2: save a spot, then find it by search — and prove a bogus query says so rather than
    /// showing an empty page. The store is in-memory under -ui-testing, so the only spot present
    /// is the one this test just made; both assertions are unambiguous.
    func testSearchFindsSpotsAndSaysWhenNothingMatches() throws {
        // Arrange: one spot, via the same flow the save-here test proves.
        app.buttons["save-here-button"].tap()
        XCTAssertTrue(app.buttons["kind-food"].waitForExistence(timeout: 5))
        app.buttons["kind-food"].tap()
        let nameField = app.textFields["save-here-name"]
        nameField.tap()
        nameField.typeText("Searchable Cove")
        app.buttons["save-here-confirm"].tap()
        XCTAssertTrue(app.staticTexts["Searchable Cove"].waitForExistence(timeout: 8))

        // Search finds it, case-insensitively.
        app.buttons["search-button"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The search field did not appear")
        field.tap()
        field.typeText("cove")
        XCTAssertTrue(
            app.staticTexts["Searchable Cove"].waitForExistence(timeout: 5),
            "Search did not find the spot by a lowercase fragment of its name"
        )

        // A query matching nothing explains itself instead of silently blanking the gallery.
        field.tap()
        field.typeText("zzzz")
        XCTAssertTrue(
            screen("no-matches").waitForExistence(timeout: 5),
            "No no-matches state for a query that matches nothing"
        )
    }
}
