//
//  OnboardingUITests.swift
//  PlannrUITests
//
//  The first-run walkthrough. Launched with -uiTestShowOnboarding so it appears
//  regardless of what a previous run recorded.
//

import XCTest

final class OnboardingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestShowOnboarding"]
        app.launch()
    }

    func testWalkThroughAllThreeCardsLandsOnSignIn() {
        XCTAssertTrue(app.staticTexts["Upload your syllabus"].waitForExistence(timeout: 5),
                      "First onboarding card should show")

        let next = app.buttons["onboardingNext"]
        XCTAssertTrue(next.exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["Review & edit"].waitForExistence(timeout: 3))

        app.buttons["onboardingNext"].tap()
        XCTAssertTrue(app.staticTexts["Sync to Google Calendar"].waitForExistence(timeout: 3))

        let getStarted = app.buttons["onboardingGetStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 3))
        getStarted.tap()

        XCTAssertTrue(app.buttons["Sign in with Google"].waitForExistence(timeout: 5),
                      "Finishing onboarding should reveal the sign-in screen")
    }

    func testSkipJumpsStraightToSignIn() {
        let skip = app.buttons["onboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        XCTAssertTrue(app.buttons["Sign in with Google"].waitForExistence(timeout: 5),
                      "Skip should reveal the sign-in screen")
        XCTAssertTrue(app.buttons["Continue as Guest"].exists)
    }

    func testOnboardingDoesNotReturnAfterItIsDismissed() {
        app.buttons["onboardingSkip"].tap()
        XCTAssertTrue(app.buttons["Sign in with Google"].waitForExistence(timeout: 5))

        // Relaunch with no flags so nothing re-seeds the flag — the walkthrough
        // should stay gone because "Skip" persisted `onboarding.hasSeen`.
        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.buttons["Sign in with Google"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Upload your syllabus"].exists)
    }
}
