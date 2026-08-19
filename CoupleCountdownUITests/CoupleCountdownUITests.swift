// CoupleCountdownUITests.swift — end-to-end coverage for onboarding, the
// apart/together toggle, important dates, stats, settings, thinking-of-you,
// and the milestone celebration overlay. Drives a real CoupleCountdown app
// instance against the real (free-tier) Firebase project — there is no
// mock backend, so these exercise real Firestore/Auth round-trips.
//
// Each test launches with "-uiTestReset" (see CoupleCountdownApp.init())
// so it starts from a genuinely fresh anonymous identity and an empty App
// Group suite, rather than depending on whatever a previous test left
// behind — tests are independent and order-agnostic.

import XCTest

final class CoupleCountdownUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchFreshApp(forceCelebration: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-uiTestReset"]
        if forceCelebration {
            args.append("-uiTestForceCelebration")
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    /// Drives name entry + "Create a Pairing" through to the countdown
    /// screen. Every real-flow test needs a paired couple to get anywhere
    /// past onboarding, so this is shared setup, not itself the thing
    /// under test in most callers.
    @discardableResult
    private func completeOnboardingByCreating(_ app: XCUIApplication, name: String = "Alex") -> String {
        let nameField = app.textFields["nameTextField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Name entry field never appeared")
        nameField.tap()
        nameField.typeText(name)
        app.buttons["continueButton"].tap()

        app.buttons["createPairingButton"].tap()

        let codeText = app.staticTexts["generatedCodeText"]
        XCTAssertTrue(codeText.waitForExistence(timeout: 15), "Pairing code was never generated — createCouple() Firestore write likely failed")
        let code = codeText.label
        XCTAssertEqual(code.count, 6, "Join code should be 6 characters, got \"\(code)\"")
        return code
    }

    // MARK: - Onboarding

    func testCreatePairingGeneratesJoinCode() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)
    }

    func testJoinPairingWithInvalidCodeShowsError() {
        let app = launchFreshApp()

        let nameField = app.textFields["nameTextField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Sam")
        app.buttons["continueButton"].tap()

        app.buttons["joinPairingButton"].tap()

        let codeField = app.textFields["joinCodeTextField"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 10))
        codeField.tap()
        codeField.typeText("ZZZZZZ")
        app.buttons["joinButton"].tap()

        let errorText = app.staticTexts["joinErrorText"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 15), "Joining a nonexistent code should surface an error, not hang or silently no-op")
    }

    // MARK: - Countdown / status toggle / date sheet

    func testToggleStatusAndSetMeetupDateShowsCountdown() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        // Fresh pairing: apart, no date set yet.
        XCTAssertTrue(app.staticTexts["noDateSetText"].waitForExistence(timeout: 10))

        let toggleButton = app.buttons["toggleStatusButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 10))
        XCTAssertTrue(toggleButton.label.contains("We're together now"))

        // Apart -> together needs no date, should succeed immediately.
        toggleButton.tap()
        let badge = app.staticTexts["statusBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        let becameTogether = NSPredicate(format: "label CONTAINS %@", "Together right now")
        expectation(for: becameTogether, evaluatedWith: badge, handler: nil)
        waitForExpectations(timeout: 10)

        // Together -> apart with no date queued should prompt for one
        // rather than silently failing (CountdownViewModel.toggleStatus).
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 10))
        toggleButton.tap()

        let saveDateButton = app.buttons["saveDateButton"]
        XCTAssertTrue(saveDateButton.waitForExistence(timeout: 10), "Leaving again with no date queued should open the date-prompt sheet")
        saveDateButton.tap() // accept the sheet's default (now + 7 days)

        let countdownText = app.staticTexts["countdownText"]
        XCTAssertTrue(countdownText.waitForExistence(timeout: 15), "Saving a meetup date should dismiss the sheet and show a live countdown")
    }

    // MARK: - Important Dates ("calendar" feature)

    func testAddImportantDateAppearsInList() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        app.buttons["importantDatesNavLink"].tap()

        let addButton = app.buttons["addImportantDateButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.tap()

        let labelField = app.textFields["dateLabelTextField"]
        XCTAssertTrue(labelField.waitForExistence(timeout: 10))
        labelField.tap()
        labelField.typeText("Anniversary")

        app.buttons["saveImportantDateButton"].tap()

        let row = app.staticTexts["Anniversary"].firstMatch
        let rowExists = app.otherElements["importantDateRow_Anniversary"].waitForExistence(timeout: 15)
            || row.waitForExistence(timeout: 5)
        XCTAssertTrue(rowExists, "Saved important date never appeared back in the list — addImportantDate() write or the subsequent reload likely failed")
    }

    // MARK: - Stats

    func testStatsScreenLoads() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        app.buttons["statsNavLink"].tap()

        let daysTogether = app.staticTexts["daysTogetherStat"]
        let daysApart = app.staticTexts["daysApartStat"]
        let loaded = daysTogether.waitForExistence(timeout: 15) || daysApart.waitForExistence(timeout: 5)
        XCTAssertTrue(loaded, "Stats screen never finished loading — fetchEvents()/CumulativeStatsCalculator likely failed for a brand-new couple with zero events")
    }

    // MARK: - Settings / theme

    func testSelectingThemeMarksItSelected() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        app.buttons["settingsNavLink"].tap()

        let sunsetRow = app.buttons["theme_sunset"]
        XCTAssertTrue(sunsetRow.waitForExistence(timeout: 10))
        sunsetRow.tap()

        XCTAssertTrue(sunsetRow.isSelected, "Tapping a theme should mark it selected — SettingsView must be reading/writing the same shared AppStorage store ThemedBackground reads from")
        XCTAssertFalse(app.buttons["theme_blush"].isSelected, "Only the tapped theme should be marked selected")
    }

    // MARK: - Thinking of You

    func testThinkingOfYouButtonSendsPing() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        let button = app.buttons["thinkingOfYouButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        let sentLabel = NSPredicate(format: "label CONTAINS %@", "Sent, with love")
        expectation(for: sentLabel, evaluatedWith: button, handler: nil)
        waitForExpectations(timeout: 15) // real Firestore write for sendPing()
    }

    // MARK: - Milestone celebration

    func testMilestoneCelebrationShowsAndDismissesOnTap() {
        let app = launchFreshApp(forceCelebration: true)
        completeOnboardingByCreating(app)

        let celebration = app.otherElements["milestoneCelebration"]
        XCTAssertTrue(celebration.waitForExistence(timeout: 10), "Forced celebration overlay never appeared")

        celebration.tap()
        XCTAssertTrue(
            waitForNonExistence(of: celebration, timeout: 5),
            "Tapping the celebration overlay should dismiss it (onTapGesture -> onDismiss)"
        )
    }

    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
