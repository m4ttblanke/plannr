//
//  ClassCodableTests.swift
//  PlannrTests
//
//  Persistence round-trip for the Class model, including the fields added for
//  structured schedules and class meetings, and backward compatibility with
//  JSON written by older builds.
//

import XCTest
@testable import Plannr

final class ClassCodableTests: XCTestCase {

    private func roundTrip(_ cls: Class) throws -> Class {
        let data = try JSONEncoder().encode(cls)
        return try JSONDecoder().decode(Class.self, from: data)
    }

    func testFullRoundTripPreservesEveryField() throws {
        var schedule = ClassSchedule()
        schedule.lectureDays = [Weekday.monday.rawValue, Weekday.wednesday.rawValue]
        schedule.lectureTime = TimeOfDay(hour: 10, minute: 30)
        schedule.sectionDays = [Weekday.friday.rawValue]
        schedule.sectionTime = TimeOfDay(hour: 14, minute: 0)

        var event = CalendarEvent(title: "HW1", date: "2026-03-01", type: "homework", description: "ch 1")
        event.googleEventId = "g-1"
        event.isEdited = true

        let original = Class(
            id: UUID(),
            name: "CS 101",
            schedule: schedule.displayString,
            colorHex: "AF52DE",
            events: [event],
            status: .active,
            googleCalendarId: "cal-abc",
            lastSynced: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_710_000_000),
            syncHistory: [SyncSession(events: [event])],
            hasUnsyncedChanges: true,
            structuredSchedule: schedule,
            meetingSyncEnabled: true,
            meetingEventIds: ["m-lecture", "m-section"]
        )

        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "CS 101")
        XCTAssertEqual(decoded.schedule, schedule.displayString)
        XCTAssertEqual(decoded.colorHex, "AF52DE")
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertEqual(decoded.events.first?.googleEventId, "g-1")
        XCTAssertEqual(decoded.status, .active)
        XCTAssertEqual(decoded.googleCalendarId, "cal-abc")
        XCTAssertEqual(decoded.endDate, original.endDate)
        XCTAssertEqual(decoded.hasUnsyncedChanges, true)
        XCTAssertEqual(decoded.structuredSchedule, schedule)
        XCTAssertEqual(decoded.meetingSyncEnabled, true)
        XCTAssertEqual(decoded.meetingEventIds, ["m-lecture", "m-section"])
        XCTAssertEqual(decoded.syncHistory.count, 1)
    }

    func testDecodesLegacyJSONWithoutNewFields() throws {
        // Shape written by a build before structuredSchedule / meeting fields.
        let legacy = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy Class",
          "schedule": "MWF 9am",
          "colorHex": "007AFF",
          "events": [],
          "status": "ACTIVE",
          "hasUnsyncedChanges": false,
          "syncHistory": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Class.self, from: legacy)

        XCTAssertEqual(decoded.name, "Legacy Class")
        XCTAssertEqual(decoded.schedule, "MWF 9am")
        XCTAssertNil(decoded.structuredSchedule)
        XCTAssertFalse(decoded.meetingSyncEnabled)
        XCTAssertTrue(decoded.meetingEventIds.isEmpty)
        XCTAssertNil(decoded.googleCalendarId)
        XCTAssertNil(decoded.endDate)
    }

    func testDecodesMinimalJSON() throws {
        let minimal = """
        { "id": "\(UUID().uuidString)", "name": "Bare" }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Class.self, from: minimal)
        XCTAssertEqual(decoded.name, "Bare")
        XCTAssertEqual(decoded.schedule, "")
        XCTAssertEqual(decoded.colorHex, "007AFF")
        XCTAssertEqual(decoded.status, .noSyllabus)
        XCTAssertTrue(decoded.events.isEmpty)
    }

    func testEqualityIsSensitiveToNewFields() {
        let base = Class(id: UUID(), name: "X")
        var withMeetings = base
        withMeetings.meetingSyncEnabled = true
        XCTAssertNotEqual(base, withMeetings)

        var withSchedule = base
        var s = ClassSchedule()
        s.lectureDays = [Weekday.tuesday.rawValue]
        s.lectureTime = TimeOfDay(hour: 8, minute: 0)
        withSchedule.structuredSchedule = s
        XCTAssertNotEqual(base, withSchedule)
    }
}
