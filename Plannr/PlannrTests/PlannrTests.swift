//
//  PlannrTests.swift
//  PlannrTests
//
//  Small, standalone unit tests: settings math, time-of-day helpers, sync
//  session model.
//

import XCTest
@testable import Plannr

final class PlannrTests: XCTestCase {

    // MARK: - SettingsManager.reminderMinutes

    func testReminderMinutesMath() {
        let settings = SettingsManager.shared
        defer { settings.resetToDefaults() }

        settings.reminderLeadTimeDays = -1
        XCTAssertNil(settings.reminderMinutes, "-1 means 'use Google's default'")

        settings.reminderLeadTimeDays = 0
        XCTAssertEqual(settings.reminderMinutes, 0)

        settings.reminderLeadTimeDays = 1
        XCTAssertEqual(settings.reminderMinutes, 24 * 60)

        settings.reminderLeadTimeDays = 7
        XCTAssertEqual(settings.reminderMinutes, 7 * 24 * 60)
    }

    func testReminderLeadTimeOptionsAreSaneAndOrdered() {
        XCTAssertEqual(reminderLeadTimeOptions.first, -1)
        XCTAssertEqual(reminderLeadTimeOptions, reminderLeadTimeOptions.sorted())
        XCTAssertTrue(reminderLeadTimeOptions.contains(0))
    }

    func testResetToDefaults() {
        let settings = SettingsManager.shared
        settings.reminderLeadTimeDays = 3
        settings.autoSyncEnabled = true
        settings.notificationsEnabled = true
        settings.showClassMeetingsInWeekView = true
        settings.term = TermSettings(label: "Fall", startDate: Date(), endDate: Date())

        settings.resetToDefaults()

        XCTAssertEqual(settings.reminderLeadTimeDays, -1)
        XCTAssertFalse(settings.autoSyncEnabled)
        XCTAssertFalse(settings.notificationsEnabled)
        XCTAssertFalse(settings.showClassMeetingsInWeekView)
        XCTAssertEqual(settings.term, TermSettings())
    }

    // MARK: - TimeOfDay

    func testTimeOfDayDateOnDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 4))!

        let t = TimeOfDay(hour: 14, minute: 15)
        let dt = t.date(on: day, calendar: cal)

        XCTAssertEqual(cal.component(.hour, from: dt), 14)
        XCTAssertEqual(cal.component(.minute, from: dt), 15)
        XCTAssertTrue(cal.isDate(dt, inSameDayAs: day))
    }

    func testTimeOfDayInitFromDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let d = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8, minute: 5))!
        let t = TimeOfDay(from: d, calendar: cal)
        XCTAssertEqual(t.hour, 8)
        XCTAssertEqual(t.minute, 5)
        XCTAssertEqual(t.iso, "08:05")
    }

    // MARK: - SyncSession

    func testSyncSessionCapturesEvents() {
        let events = [
            CalendarEvent(title: "A", date: "2026-03-01", type: "homework", description: ""),
            CalendarEvent(title: "B", date: "2026-03-02", type: "exam", description: ""),
        ]
        let session = SyncSession(events: events)
        XCTAssertEqual(session.events.count, 2)

        let decoded = try? JSONDecoder().decode(
            SyncSession.self, from: JSONEncoder().encode(session)
        )
        XCTAssertEqual(decoded?.id, session.id)
        XCTAssertEqual(decoded?.events.map(\.title), ["A", "B"])
    }
}
