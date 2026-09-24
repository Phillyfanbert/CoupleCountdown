// CoupleCountdownUITests.swift — end-to-end coverage for onboarding, the
// apart/together toggle, important dates, stats, settings, thinking-of-you,
// and the milestone celebration overlay. Drives a real CoupleCountdown app
// instance against the real (free-tier) Firebase project — there is no
// mock backend, so these exercise real Firestore/Auth round-trips.
//
// Each test launches with "-uiTestReset" (see CoupleCountdownApp) so it
// starts signed out with an empty App Group suite, then creates its own
// account on the reserved, undeliverable test.couplecountdown.invalid domain.
// The reset hook deletes the previous test's account, and the class tearDown
// runs it once more, so CI doesn't leave test users in the Firebase project.

import XCTest

final class CoupleCountdownUITests: XCTestCase {

    private let testPassword = "uitest-pw-1234"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override class func tearDown() {
        // One more reset so the last test's account is deleted too.
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()
        _ = app.textFields["authNameField"].waitForExistence(timeout: 30)
        app.terminate()
        super.tearDown()
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

    private func makeTestEmail() -> String {
        "uitest-\(UUID().uuidString.prefix(8).lowercased())@test.couplecountdown.invalid"
    }

    /// Creates a fresh account from the sign-up screen and waits for
    /// onboarding. Returns the account's email.
    @discardableResult
    private func signUp(_ app: XCUIApplication, name: String = "Alex") -> String {
        let nameField = app.textFields["authNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 30), "Sign-up screen never appeared")
        nameField.tap()
        nameField.typeText(name)

        let email = makeTestEmail()
        let emailField = app.textFields["authEmailField"]
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["authPasswordField"]
        passwordField.tap()
        passwordField.typeText(testPassword + "\n") // Return submits

        XCTAssertTrue(app.buttons["createPairingButton"].waitForExistence(timeout: 20), "Creating the account never reached onboarding")
        declineSavePasswordPrompt(app)
        return email
    }

    /// iOS's own "Save Password?" prompt (from the Passwords app) appears
    /// anywhere from immediately to ~8s after a successful sign-up or sign-in
    /// and covers the app — confirmed from the failure recordings, where it
    /// sat over onboarding's Create/Join buttons. Real users answer it; the
    /// tests decline it. Waits for it (returning as soon as it's handled) so
    /// it can't arrive in the middle of a later step.
    private func declineSavePasswordPrompt(_ app: XCUIApplication, within timeout: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if tapNotNowIfShown(app) { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    @discardableResult
    private func tapNotNowIfShown(_ app: XCUIApplication) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for notNow in [app.buttons["Not Now"], springboard.buttons["Not Now"]] where notNow.exists {
            notNow.tap()
            // Let it finish animating away — a tap made while it's still
            // leaving can be swallowed.
            Thread.sleep(forTimeInterval: 1)
            return true
        }
        return false
    }

    /// Taps `element` and waits for `next` to appear, tapping again if the
    /// tap was swallowed. A real run showed that a tap made in the same
    /// instant a screen is changing (a prompt animating away, a view swapping
    /// in) is sometimes lost: the button stays put and nothing happens.
    private func tap(
        _ element: XCUIElement,
        until next: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<attempts {
            tapWhenReady(element, in: app, file: file, line: line)
            let tappedAt = Date()
            while Date().timeIntervalSince(tappedAt) < 20 {
                if next.exists { return }
                // Still there and tappable a few seconds later: the tap was
                // lost. (A registered tap moves on, covers, or disables it.)
                if Date().timeIntervalSince(tappedAt) > 3, element.exists, element.isHittable, element.isEnabled { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
            if next.exists { return }
        }
        XCTFail("Tapping \(element) never led to \(next)", file: file, line: line)
    }

    /// Taps `element` once it's actually tappable (existing isn't enough —
    /// an earlier run tapped buttons that were covered and the taps went
    /// nowhere: "hit point {-1, -1}"), declining the save-password prompt if
    /// it's the thing in the way.
    private func tapWhenReady(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var unobstructedChecks = 0
        while Date() < deadline {
            if tapNotNowIfShown(app) {
                unobstructedChecks = 0
            } else if element.exists {
                if element.isHittable {
                    element.tap()
                    return
                }
                // Present but not hittable with nothing covering it: it's
                // below the fold of a scroll view, and tap() scrolls it into
                // view itself.
                unobstructedChecks += 1
                if unobstructedChecks >= 4 {
                    element.tap()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("\(element) never became tappable", file: file, line: line)
    }

    private func signIn(_ app: XCUIApplication, email: String, password: String) {
        let toggle = app.buttons["authToggleButton"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "Sign-in screen never appeared")
        toggle.tap()
        let emailField = app.textFields["authEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["authPasswordField"]
        passwordField.tap()
        passwordField.typeText(password + "\n")
    }

    /// Signs up, then drives "Create a Pairing" through to the countdown
    /// screen. Every real-flow test needs a paired couple to get anywhere
    /// past onboarding, so this is shared setup, not itself the thing
    /// under test in most callers. Returns the account email and join code.
    @discardableResult
    private func completeOnboardingByCreating(_ app: XCUIApplication, name: String = "Alex") -> (email: String, code: String) {
        let email = signUp(app, name: name)

        let codeText = app.staticTexts["generatedCodeText"]
        tap(app.buttons["createPairingButton"], until: codeText, in: app)
        XCTAssertTrue(codeText.exists, "Pairing code was never generated — createCouple() Firestore write likely failed")
        let code = codeText.label
        XCTAssertEqual(code.count, 6, "Join code should be 6 characters, got \"\(code)\"")

        tap(app.buttons["continueToCountdownButton"], until: app.buttons["toggleStatusButton"], in: app)
        return (email, code)
    }

    /// CountdownView's toolbar puts calendarNavLink/settingsNavLink
    /// at .secondaryAction placement — on the iPhone widths CI runs
    /// against, iOS collapses those into a "More" overflow button
    /// (identifier "OverflowBarButtonItem") rather than showing them
    /// directly, confirmed via a real failed run's accessibility snapshot.
    /// statsNavLink is .primaryAction and stays directly tappable, which
    /// is why only these two needed this.
    private func tapToolbarItem(_ app: XCUIApplication, identifier: String, label: String) {
        let direct = app.buttons[identifier]
        if direct.waitForExistence(timeout: 2) {
            direct.tap()
            return
        }
        let overflow = app.buttons["OverflowBarButtonItem"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 5), "Neither \"\(identifier)\" nor the toolbar overflow button was found")
        overflow.tap()
        // A real run showed identifier-only matching (scoped to `.any`'s
        // default identifier-only subscript behavior) didn't find the item
        // once inside the overflow menu — its exact XCUIElementType and
        // whether the SwiftUI accessibilityIdentifier survives UIKit's
        // overflow-menu synthesis are both unconfirmed, so match broadly
        // by either identifier or the visible label text instead.
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", identifier, label)
        let item = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\"\(identifier)\" (\"\(label)\") wasn't found in the overflow menu either")
        item.tap()
    }

    // MARK: - Onboarding

    func testCreatePairingGeneratesJoinCode() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)
    }

    func testCreatePairingCodeStaysVisibleUntilContinueIsTapped() {
        // Regression coverage for a real bug this suite caught: setting
        // coupleId as soon as the Firestore write succeeded advanced the
        // whole app past this screen before a user could ever read, copy,
        // or share the code (see CreatePairingView.createPairing()).
        let app = launchFreshApp()
        signUp(app)
        let codeText = app.staticTexts["generatedCodeText"]
        tap(app.buttons["createPairingButton"], until: codeText, in: app)

        // Give the app every opportunity to have wrongly auto-advanced;
        // the code screen (and its Continue button) should still be here.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(codeText.exists, "Generated code screen should stay visible until the user taps Continue")
        XCTAssertTrue(app.buttons["continueToCountdownButton"].exists)
    }

    func testJoinPairingWithInvalidCodeShowsError() {
        let app = launchFreshApp()
        signUp(app, name: "Sam")

        let codeField = app.textFields["joinCodeTextField"]
        tap(app.buttons["joinPairingButton"], until: codeField, in: app)
        codeField.tap()
        codeField.typeText("ZZZZZZ")
        app.buttons["joinButton"].tap()

        let errorText = app.staticTexts["joinErrorText"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 15), "Joining a nonexistent code should surface an error, not hang or silently no-op")
    }

    // MARK: - Accounts

    func testSignOutAndBackInKeepsThePairing() {
        // The pairing lives on the account, not the device: signing back in
        // (as a second device would) goes straight to the same pairing.
        let app = launchFreshApp()
        let (email, code) = completeOnboardingByCreating(app)

        let waitingCode = app.staticTexts["waitingCodeText"]
        XCTAssertTrue(waitingCode.waitForExistence(timeout: 15), "Waiting-for-partner card should show the code after Continue")
        XCTAssertEqual(waitingCode.label, code)

        tapToolbarItem(app, identifier: "settingsNavLink", label: "Settings")
        tapWhenReady(app.buttons["signOutButton"], in: app)

        signIn(app, email: email, password: testPassword)
        XCTAssertTrue(waitingCode.waitForExistence(timeout: 20), "Signing back in should land on the same pairing, not onboarding")
        declineSavePasswordPrompt(app)
        XCTAssertEqual(waitingCode.label, code)
        XCTAssertFalse(app.buttons["createPairingButton"].exists)
    }

    func testWrongPasswordShowsError() {
        let app = launchFreshApp()
        signIn(app, email: makeTestEmail(), password: "definitely-wrong")
        let error = app.staticTexts["authErrorText"]
        XCTAssertTrue(error.waitForExistence(timeout: 15), "A failed sign-in should say so, not hang or silently no-op")
        XCTAssertTrue(error.label.contains("incorrect"), "Unexpected error text: \(error.label)")
    }

    func testCancelPairingReturnsToOnboarding() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        tapWhenReady(app.buttons["cancelPairingButton"], in: app)
        let confirm = app.buttons["Cancel pairing"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Cancelling should ask for confirmation")
        tap(confirm, until: app.buttons["createPairingButton"], in: app)
        XCTAssertTrue(app.buttons["createPairingButton"].exists, "Cancelling should return the account to onboarding")
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
        XCTAssertTrue(saveDateButton.waitForExistence(timeout: 10), "Leaving again with nothing planned should ask when you'll see each other next")
        // Accept the sheet's default (a week from today, 6 PM).
        let countdownText = app.staticTexts["countdownText"]
        tap(saveDateButton, until: countdownText, in: app)
        XCTAssertTrue(countdownText.exists, "Saving a visit should dismiss the sheet and show a live countdown")
        XCTAssertTrue(app.staticTexts["meetupTargetText"].exists, "The countdown should say what it's counting down to")
    }

    func testLeavingAgainCountsDownToThePlannedVisit() {
        // Regression: after the first trip, "Leaving again" reused the old,
        // already-passed date and never asked for the next one. It now
        // counts down to the next planned visit, and only asks when nothing
        // is planned.
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        tap(app.buttons["planVisitButton"], until: app.buttons["saveDateButton"], in: app)
        let countdownText = app.staticTexts["countdownText"]
        tap(app.buttons["saveDateButton"], until: countdownText, in: app)
        let target = app.staticTexts["meetupTargetText"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let plannedLabel = target.label

        let toggle = app.buttons["toggleStatusButton"]
        tap(toggle, until: app.staticTexts["togetherText"], in: app) // together
        XCTAssertFalse(countdownText.exists, "Together should replace the countdown, not keep ticking")

        tapWhenReady(toggle, in: app) // leaving again
        XCTAssertTrue(countdownText.waitForExistence(timeout: 15), "Leaving again should count down to the planned visit")
        XCTAssertFalse(app.buttons["saveDateButton"].exists, "With a visit already planned, leaving shouldn't ask again")
        XCTAssertEqual(target.label, plannedLabel)
    }

    func testPlanVisitFromCalendarShowsInComingUpAndCountdown() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        tapToolbarItem(app, identifier: "calendarNavLink", label: "Calendar")
        tap(app.buttons["planVisitFromCalendarButton"], until: app.buttons["saveDateButton"], in: app)
        let visitRow = app.descendants(matching: .any)["visitRow"].firstMatch
        tap(app.buttons["saveDateButton"], until: visitRow, in: app)
        XCTAssertTrue(visitRow.exists, "A planned visit should appear under Coming up")

        // The main countdown follows the plan.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["countdownText"].waitForExistence(timeout: 15), "The countdown should follow the newly planned visit")
    }

    // MARK: - Important Dates ("calendar" feature)

    func testAddImportantDateAppearsInList() {
        let app = launchFreshApp()
        completeOnboardingByCreating(app)

        tapToolbarItem(app, identifier: "calendarNavLink", label: "Calendar")

        let labelField = app.textFields["dateLabelTextField"]
        tap(app.buttons["addImportantDateButton"], until: labelField, in: app)
        labelField.tap()
        labelField.typeText("Anniversary")

        app.buttons["saveImportantDateButton"].tap()

        // Distinguish "the sheet never dismissed" (the write itself
        // failed — AddImportantDateView only calls dismiss() after a
        // successful write) from "the list never reflected the new item"
        // (a reload/rendering issue), rather than one bare assertion that
        // can't tell those apart.
        XCTAssertTrue(
            waitForNonExistence(of: labelField, timeout: 10),
            "Add Important Date sheet never dismissed after tapping Save — the addImportantDate() write itself likely failed"
        )

        // .otherElements assumed the wrong resolved type for another
        // .accessibilityElement(children: .combine) view elsewhere in this
        // suite (see testMilestoneCelebrationShowsAndDismissesOnTap) —
        // search by identifier across any type here too, with the label
        // text as a second fallback.
        let row = app.staticTexts["Anniversary"].firstMatch
        let rowExists = app.descendants(matching: .any)["importantDateRow_Anniversary"].waitForExistence(timeout: 15)
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

        tapToolbarItem(app, identifier: "settingsNavLink", label: "Settings")

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

        // Scoped to .otherElements this failed on a real run even with a
        // generous 30s auto-dismiss window under test — .accessibilityElement
        // (children: .combine) on a Text-only VStack doesn't reliably
        // resolve to XCUIElementType.other, so search by identifier across
        // any element type instead of guessing the resolved type.
        let celebration = app.descendants(matching: .any)["milestoneCelebration"]
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
