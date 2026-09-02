//
//  GuestFlowUITests.swift
//  PlannrUITests
//
//  End-to-end UI coverage that needs no backend or Google account: everything
//  reachable through Guest mode. Launched with -uiTestReset so each run starts
//  signed out with cleared preferences.
//

import XCTest

final class GuestFlowUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()
    }

    // MARK: - Helpers

    private func enterGuestMode(file: StaticString = #filePath, line: UInt = #line) {
        let guestButton = app.buttons["Continue as Guest"]
        XCTAssertTrue(guestButton.waitForExistence(timeout: 5), "Sign-in screen should show the guest button", file: file, line: line)
        guestButton.tap()
        XCTAssertTrue(app.staticTexts["Guest Mode - data won't be saved between sessions"].waitForExistence(timeout: 5),
                      "Guest banner should appear", file: file, line: line)
    }

    private func addClass(named name: String) {
        app.buttons["Add New Class"].tap()
        XCTAssertTrue(app.staticTexts["Add New Class"].waitForExistence(timeout: 3))

        let nameField = app.textFields.firstMatch
        nameField.tap()
        nameField.typeText(name)

        app.buttons["Add Class"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 3), "New class card should appear")
    }

    // MARK: - Sign-in screen

    func testSignInScreenShowsBothOptions() {
        XCTAssertTrue(app.staticTexts["Plannr"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign in with Google"].exists)
        XCTAssertTrue(app.buttons["Continue as Guest"].exists)
    }

    // MARK: - Guest home

    func testGuestModeReachesHome() {
        enterGuestMode()
        XCTAssertTrue(app.buttons["Add New Class"].exists)
        XCTAssertTrue(app.staticTexts["tabTitle"].exists || app.staticTexts["My Classes"].exists)
    }

    // MARK: - Add class + validation + schedule picker

    func testAddClassButtonDisabledUntilNameEntered() {
        enterGuestMode()
        app.buttons["Add New Class"].tap()
        XCTAssertTrue(app.staticTexts["Add New Class"].waitForExistence(timeout: 3))

        XCTAssertFalse(app.buttons["Add Class"].isEnabled, "disabled with an empty name")

        let nameField = app.textFields.firstMatch
        nameField.tap()
        nameField.typeText("Physics 1A")
        XCTAssertTrue(app.buttons["Add Class"].isEnabled, "enabled once a name is typed")
    }

    func testSchedulePickerBuildsDisplayString() {
        enterGuestMode()
        app.buttons["Add New Class"].tap()
        XCTAssertTrue(app.staticTexts["Add New Class"].waitForExistence(timeout: 3))

        // Weekday chips are buttons labeled with their short names. Only the
        // lecture row exists yet, so each label is unambiguous.
        app.buttons["M"].tap()
        app.buttons["W"].tap()
        app.buttons["F"].tap()

        // The preview line reads "MWF <time>" once days are chosen.
        let preview = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'MWF'")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3), "schedule preview should read 'MWF <time>'")

        // Turning the section on reveals a second weekday row (labeled "Section").
        app.switches["Has a separate section / lab"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Section"].waitForExistence(timeout: 3),
                      "the section sub-section should appear")

        // Pick a section day — now there are two "Th" chips, so target the second.
        let thChips = app.buttons.matching(NSPredicate(format: "label == %@", "Th"))
        if thChips.count >= 2 {
            thChips.element(boundBy: 1).tap()
        } else {
            thChips.firstMatch.tap()
        }
        let withSection = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Section '")).firstMatch
        XCTAssertTrue(withSection.waitForExistence(timeout: 3), "preview should mention the section")
    }

    func testAddedClassPersistsInListAndOpens() {
        enterGuestMode()
        addClass(named: "Chem 1")

        // "NO SYLLABUS" badge on a brand-new class.
        XCTAssertTrue(app.staticTexts["NO SYLLABUS"].exists)

        app.staticTexts["Chem 1"].tap()
        // Class edit screen: events section + the upload button.
        XCTAssertTrue(app.buttons["Upload New Syllabus"].waitForExistence(timeout: 3))
        // Guests never see the meetings toggle.
        XCTAssertFalse(app.switches["Add class meetings to Google Calendar"].exists)
    }

    // MARK: - Navigation

    func testHamburgerMenuSwitchesTabs() {
        enterGuestMode()

        app.buttons["menuButton"].tap()
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Week at a Glance"].exists)
        XCTAssertTrue(app.buttons["Report an Issue"].exists)
        app.buttons["Calendar"].tap()

        XCTAssertEqual(app.staticTexts["tabTitle"].label, "Calendar")

        app.buttons["menuButton"].tap()
        app.buttons["Week at a Glance"].tap()
        XCTAssertEqual(app.staticTexts["tabTitle"].label, "Week at a Glance")
    }

    func testReportAnIssueFromMenu() {
        enterGuestMode()
        app.buttons["menuButton"].tap()
        app.buttons["Report an Issue"].tap()

        // No Mail account on the simulator → the mailto fallback alert.
        let alert = app.alerts["Report an Issue"]
        if alert.waitForExistence(timeout: 3) {
            XCTAssertTrue(alert.staticTexts.element(matching: NSPredicate(format: "label CONTAINS[c] 'mattheweblanke@gmail.com'")).exists)
            alert.buttons["OK"].tap()
        } else {
            // A real Mail account: the compose sheet came up instead. Just make
            // sure the app didn't crash and something is on screen.
            XCTAssertTrue(app.navigationBars.firstMatch.exists || app.otherElements.firstMatch.exists)
        }
    }

    // MARK: - Profile & Settings

    func testProfileSheetShowsGuestAndSettings() {
        enterGuestMode()
        app.buttons["profileButton"].tap()

        XCTAssertTrue(app.staticTexts["Guest User"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Current Term"].exists)
        XCTAssertTrue(app.staticTexts["Deadline Reminders"].exists)
        XCTAssertTrue(app.staticTexts["Week at a Glance"].exists)     // the "Show class meetings" section
        XCTAssertTrue(app.staticTexts["Notifications"].exists)

        // Auto-sync is disabled for guests.
        let autoSync = app.switches["Auto-sync changes"]
        if autoSync.exists { XCTAssertFalse(autoSync.isEnabled) }

        XCTAssertTrue(app.buttons["Exit Guest Mode"].exists || app.buttons["Sign Out"].exists)
    }

    func testShowClassMeetingsToggleFlips() {
        enterGuestMode()
        app.buttons["profileButton"].tap()

        let toggle = app.switches["Show class meetings"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        let before = toggle.value as? String
        toggle.tap()
        XCTAssertNotEqual(toggle.value as? String, before, "toggle value should change")
    }

    // MARK: - Guest data does not persist

    func testGuestClassesDoNotSurviveRelaunch() {
        enterGuestMode()
        addClass(named: "Ephemeral 101")
        XCTAssertTrue(app.staticTexts["Ephemeral 101"].exists)

        app.terminate()
        app.launch()   // still -uiTestReset

        // Straight back to the sign-in screen (guest session is gone).
        XCTAssertTrue(app.buttons["Continue as Guest"].waitForExistence(timeout: 5))
        app.buttons["Continue as Guest"].tap()
        XCTAssertTrue(app.buttons["Add New Class"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ephemeral 101"].exists, "the guest class should not have persisted")
    }
}
