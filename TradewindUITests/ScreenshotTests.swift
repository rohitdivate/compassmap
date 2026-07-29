import XCTest

/// Photographs every screen over the seeded demo library, on every CI run.
///
/// Tradewind is developed without a Mac, so these attachments — exported by the workflow into
/// the `Screenshots` artifact — are the only way the person building it ever sees it. They are
/// review material, not assertions: each screen is asserted to *exist* (a screenshot of the
/// wrong screen is worse than a failure) and then photographed as it is.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-demo-data"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testPhotographEveryScreen() throws {
        // Onboarding is first-run state, photographed before it is skipped.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) {
            snap("00-onboarding")
            skip.tap()
        }

        XCTAssertTrue(screen("gallery-screen").waitForExistence(timeout: 10), "No gallery")
        snap("01-gallery")

        // The arrow, on the pinned demo hotel.
        let hotel = app.staticTexts["Harbour Hotel"].firstMatch
        XCTAssertTrue(hotel.waitForExistence(timeout: 5), "Demo data did not seed")
        hotel.tap()
        let title = app.buttons["spot-title-button"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "No arrow screen")
        snap("02-arrow")

        title.tap()
        XCTAssertTrue(app.buttons["detail-done"].waitForExistence(timeout: 5), "No detail sheet")
        snap("03-detail-top")
        app.swipeUp()
        snap("04-detail-sections")
        app.buttons["detail-done"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()

        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(screen("map-screen").waitForExistence(timeout: 5), "No map")
        snap("05-map")

        app.tabBars.buttons["Trips"].tap()
        XCTAssertTrue(screen("trips-screen").waitForExistence(timeout: 5), "No trips")
        snap("06-trips")

        // No Nearby screenshot any more: photo-library places ingest themselves into the gallery.
        // (The canned scan's clusters share coordinates with the demo data here, so de-dupe
        // suppresses them — expected.)
        app.tabBars.buttons["Spots"].tap()
        XCTAssertTrue(screen("gallery-screen").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(screen("settings-screen").waitForExistence(timeout: 5), "No settings")
        snap("07-settings-themes")
        app.swipeUp()
        snap("08-settings-data")
        app.buttons["settings-done"].tap()

        // Last, so nothing has to dismiss it — a sheet's swipe-to-close is exactly the kind of
        // gesture XCUITest half-lands.
        XCTAssertTrue(app.buttons["save-here-button"].waitForExistence(timeout: 5))
        app.buttons["save-here-button"].tap()
        XCTAssertTrue(app.buttons["save-here-confirm"].waitForExistence(timeout: 5), "No save-here sheet")
        snap("09-save-here")
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func screen(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
