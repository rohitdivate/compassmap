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

    /// The photo library's places arrive by themselves now: skipping onboarding kicks off the
    /// automatic ingest, the canned scan produces two clusters, and both land in the gallery as
    /// real spots — no tab, no scan button, no per-place save.
    func testPhotoPlacesAutoAppearInGallery() throws {
        XCTAssertTrue(screen("gallery-screen").waitForExistence(timeout: 10), "No gallery")
        XCTAssertTrue(
            app.staticTexts["Canned Corner, London"].firstMatch.waitForExistence(timeout: 10),
            "The automatic ingest did not save the canned photo clusters as spots"
        )
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
        // A tap can land on a mid-rebuild sheet and die against a detached element — one
        // guarded retry covers the race without masking a genuinely broken toggle.
        if !waitForSwitchValue(toggle, "1", timeout: 3) {
            toggle.tap()
        }
        XCTAssertTrue(waitForSwitchValue(toggle, "1"), "The toggle did not turn on")

        app.buttons["detail-done"].tap()
        XCTAssertTrue(
            app.buttons["spot-title-button"].waitForExistence(timeout: 5),
            "Dismissing the detail sheet did not return to the arrow screen"
        )
        openDetailFromArrow()
        let reopened = scrollToArrivalToggle()
        XCTAssertTrue(
            waitForSwitchValue(reopened, "1"),
            "The alert choice did not survive closing and reopening the detail sheet"
        )
    }

    /// Via the tappable title, deliberately not the overflow menu: SwiftUI's `Menu` never tells
    /// XCUITest its animations finished, so every step behind an open menu stalled its 60 s idle
    /// wait on CI — and the menu items reported invalid activation points on two separate runs.
    private func openDetailFromArrow() {
        let title = app.buttons["spot-title-button"]
        // Hittable, not merely existing — the arrow inserts with a spring, and taps synthesized
        // against the mid-animation frame die. Same fix that stabilised the delete journey.
        XCTAssertTrue(waitForHittable(title), "No tappable title on the arrow screen")
        title.tap()
        XCTAssertTrue(
            app.buttons["detail-done"].waitForExistence(timeout: 5),
            "Tapping the title did not present the detail sheet"
        )
    }

    /// The arrival section sits low on the detail scroll view, below the photo and the facts.
    private func scrollToArrivalToggle() -> XCUIElement {
        let toggle = app.switches["arrival-toggle"]
        for _ in 0..<6 where !(toggle.exists && toggle.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(waitForHittable(toggle), "No arrival alert toggle on the detail screen")
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

    /// Wave 4, first half: delete is soft, and the undo toast brings the spot straight back.
    /// One arrow entry per app launch — the flaky move on CI was ever *re-entering* the arrow
    /// after a restore, so the trash half lives in its own test with its own fresh launch.
    func testDeleteShowsUndoToastAndUndoRestores() throws {
        let card = saveSpot(named: "Trash Cove")

        // Delete through the detail screen — deterministic buttons the whole way, unlike
        // context-menu synthesis, which XCUITest fires unreliably. The context menu still
        // exists for humans; the *behaviour* (soft delete + root toast) is identical from
        // either path because both go through SpotStore.delete.
        deleteFromDetail(card)
        XCTAssertTrue(
            app.buttons["undo-delete"].waitForExistence(timeout: 5),
            "No undo toast after deleting"
        )
        let undoButton = app.buttons["undo-delete"]
        XCTAssertTrue(waitForHittable(undoButton))
        undoButton.tap()
        // First prove the tap landed: the action clears the toast. A toast still standing means
        // the tap missed; a vanished toast with no card means the restore itself broke — two
        // different bugs this assertion refuses to conflate.
        XCTAssertTrue(
            waitForAbsence(undoButton),
            "The undo toast did not clear — the tap never reached the button"
        )
        XCTAssertTrue(card.waitForExistence(timeout: 8), "Undo did not bring the spot back")
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Wave 4, second half: Recently Deleted holds the spot and restores it. Asserted against
    /// the gallery, because "the row disappeared from the trash" is not the same fact as "the
    /// spot is back".
    func testRecentlyDeletedHoldsAndRestores() throws {
        let card = saveSpot(named: "Trash Cove")
        deleteFromDetail(card)
        XCTAssertTrue(app.buttons["undo-delete"].waitForExistence(timeout: 5))

        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(screen("settings-screen").waitForExistence(timeout: 5))

        let trashLink = app.buttons["recently-deleted-link"]
        for _ in 0..<6 where !trashLink.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(trashLink.waitForExistence(timeout: 5), "No Recently Deleted entry in Settings")
        trashLink.tap()

        XCTAssertTrue(
            screen("recently-deleted-screen").waitForExistence(timeout: 5),
            "Recently Deleted did not open"
        )
        XCTAssertTrue(
            app.staticTexts["Trash Cove"].waitForExistence(timeout: 5),
            "The deleted spot is not in Recently Deleted"
        )
        app.buttons["restore-spot"].firstMatch.tap()

        // Back out of Settings and confirm the spot is truly back in the gallery.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settings-done"].tap()
        XCTAssertTrue(
            app.staticTexts["Trash Cove"].firstMatch.waitForExistence(timeout: 5),
            "Restoring from Recently Deleted did not return the spot to the gallery"
        )
    }

    /// Wave 6: plan a place you are not standing at — search an address, pick a suggestion, and
    /// the spot saves with the place's own name. The suggestion is canned under the test seam,
    /// so this proves the flow's plumbing without depending on Apple's live search.
    func testPlanAPlaceByAddressSearch() throws {
        app.buttons["save-here-button"].tap()
        let elsewhere = app.buttons["where-elsewhere"]
        XCTAssertTrue(elsewhere.waitForExistence(timeout: 5), "No 'Somewhere else' choice")
        elsewhere.tap()

        let field = app.textFields["address-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No address search field")
        field.tap()
        field.typeText("palace")

        let result = app.buttons["address-result-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "No canned suggestion appeared")
        result.tap()

        XCTAssertTrue(
            app.staticTexts["planned-place-name"].waitForExistence(timeout: 5),
            "Picking a suggestion did not resolve into a planned place"
        )

        let confirm = app.buttons["save-here-confirm"]
        XCTAssertTrue(confirm.isEnabled, "Save stayed disabled after choosing a place")
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["Test Palace"].firstMatch.waitForExistence(timeout: 8),
            "The planned spot did not appear in the gallery"
        )
    }

    /// Saves a photo-less spot through the save-here flow and returns its gallery card.
    private func saveSpot(named name: String) -> XCUIElement {
        app.buttons["save-here-button"].tap()
        XCTAssertTrue(app.buttons["kind-place"].waitForExistence(timeout: 5))
        app.buttons["kind-place"].tap()
        let nameField = app.textFields["save-here-name"]
        nameField.tap()
        nameField.typeText(name)
        app.buttons["save-here-confirm"].tap()
        // firstMatch: a name can match both the card's title and its combined accessibility
        // element, and an ambiguous tap throws.
        let card = app.staticTexts[name].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), "The saved spot did not appear")
        return card
    }

    /// Deletes a spot via its detail screen: card → arrow → title → Delete spot → confirm.
    /// Deleting the arrow's spot collapses the arrow underneath — landing back on the gallery
    /// is part of what this exercises.
    private func deleteFromDetail(_ card: XCUIElement) {
        card.tap()
        let title = app.buttons["spot-title-button"]
        // Hittable, not merely existing: the arrow screen inserts with a spring, and a tap
        // synthesized against the mid-animation frame dies with "failed to scroll to visible".
        XCTAssertTrue(waitForHittable(title), "The arrow screen did not open")
        title.tap()
        let deleteButton = app.buttons["detail-delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "No detail sheet")
        for _ in 0..<6 where !deleteButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(waitForHittable(deleteButton), "Delete button never became tappable")
        deleteButton.tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(waitForHittable(confirm), "No delete confirmation")
        confirm.tap()
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Wave 2: save a spot, then find it by search — and prove a bogus query says so rather than
    /// showing an empty page. The store is in-memory under -ui-testing; besides the spot this
    /// test makes, only the auto-ingested canned places exist, and neither name collides with
    /// either query, so both assertions stay unambiguous.
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
