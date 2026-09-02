//
//  NotificationManagerTests.swift
//  PlannrTests
//
//  plannedReminders — the pure selection behind sync(): future only, soonest
//  first, capped below iOS's 64-pending-notification limit.
//

import XCTest
@testable import Plannr

final class NotificationManagerTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func now() -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 1, day: 1, hour: 12))!
    }

    private func classWith(_ dates: [String], name: String = "CS 101") -> Class {
        Class(name: name, events: dates.enumerated().map { i, d in
            CalendarEvent(title: "HW\(i + 1)", date: d, type: "homework", description: "")
        })
    }

    private func plan(_ classes: [Class], leadDays: Int = 0, limit: Int = 60) -> [NotificationManager.PlannedReminder] {
        NotificationManager.plannedReminders(for: classes, leadDays: leadDays,
                                             now: now(), calendar: calendar, limit: limit)
    }

    // MARK: - Selection

    func testPastDeadlinesAreExcluded() {
        let reminders = plan([classWith(["2029-12-15", "2030-06-01", "2030-07-01"])])
        XCTAssertEqual(reminders.map(\.body), ["HW2 is due today", "HW3 is due today"])
    }

    func testSortedSoonestFirstAcrossClasses() {
        let a = classWith(["2030-05-01", "2030-02-01"], name: "A")
        let b = classWith(["2030-03-01"], name: "B")
        let reminders = plan([a, b])
        XCTAssertEqual(reminders.map(\.fireComponents.month), [2, 3, 5])
        XCTAssertEqual(reminders.map(\.title), ["A", "B", "A"])
    }

    func testCappedAtLimitAndKeepsTheNearest() {
        // 80 future deadlines, one per day.
        let dates = (0..<80).map { offset -> String in
            let d = calendar.date(byAdding: .day, value: 10 + offset, to: now())!
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = calendar; f.timeZone = calendar.timeZone
            return f.string(from: d)
        }
        let reminders = plan([classWith(dates)], limit: 60)
        XCTAssertEqual(reminders.count, 60, "never schedule more than the cap")
        // They are the 60 soonest, still in order.
        XCTAssertEqual(reminders.map(\.fireDate), reminders.map(\.fireDate).sorted())
        XCTAssertLessThan(reminders.last!.fireDate,
                          calendar.date(byAdding: .day, value: 10 + 60, to: now())!)
        XCTAssertLessThanOrEqual(NotificationManager.maxScheduledReminders, 63)
    }

    func testDefaultLimitIsMaxScheduledReminders() {
        let dates = (0..<100).map { "2030-\(String(format: "%02d", ($0 % 11) + 2))-\(String(format: "%02d", ($0 % 27) + 1))" }
        let reminders = NotificationManager.plannedReminders(
            for: [classWith(dates)], leadDays: 0, now: now(), calendar: calendar)
        XCTAssertEqual(reminders.count, NotificationManager.maxScheduledReminders)
    }

    // MARK: - Filters

    func testDeletedEventsAreSkipped() {
        var cls = classWith(["2030-04-01", "2030-04-02"])
        cls.events[0].isDeletedLocally = true
        let reminders = plan([cls])
        XCTAssertEqual(reminders.map(\.body), ["HW2 is due today"])
    }

    func testGoogleDefaultLeadTimeSchedulesNothing() {
        XCTAssertTrue(plan([classWith(["2030-05-01"])], leadDays: -1).isEmpty)
    }

    func testZeroLimitSchedulesNothing() {
        XCTAssertTrue(plan([classWith(["2030-05-01"])], limit: 0).isEmpty)
    }

    // MARK: - Content

    func testLeadDaysShapeTheFireDateAndBodyText() {
        let three = plan([classWith(["2030-05-10"])], leadDays: 3)
        XCTAssertEqual(three.first?.body, "HW1 is due in 3 days")
        XCTAssertEqual(three.first?.fireComponents.day, 7)   // 10th − 3 days
        XCTAssertEqual(three.first?.fireComponents.hour, 9)

        let one = plan([classWith(["2030-05-10"])], leadDays: 1)
        XCTAssertEqual(one.first?.body, "HW1 is due in 1 day")
    }

    func testIdentifierIsTheEventID() {
        let cls = classWith(["2030-05-01"])
        let reminders = plan([cls])
        XCTAssertEqual(reminders.first?.identifier, cls.events[0].id.uuidString)
    }
}
