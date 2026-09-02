//
//  ClassScheduleTests.swift
//  PlannrTests
//
//  Tests for ClassSchedule: display string, meeting patterns, and the
//  occurrence expansion used by Week at a Glance.
//

import XCTest
@testable import Plannr

final class ClassScheduleTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    /// Start-of-day for a y/m/d in the test calendar.
    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    // MARK: - TimeOfDay

    func testTimeOfDayFormatting() {
        let t = TimeOfDay(hour: 9, minute: 5)
        XCTAssertEqual(t.iso, "09:05")
        XCTAssertFalse(t.display.isEmpty)
    }

    func testTimeOfDayClampsOutOfRange() {
        XCTAssertEqual(TimeOfDay(hour: 30, minute: -4).hour, 23)
        XCTAssertEqual(TimeOfDay(hour: 30, minute: -4).minute, 0)
    }

    // MARK: - displayString

    func testDisplayStringLectureOnly() {
        var s = ClassSchedule()
        s.lectureDays = [Weekday.monday.rawValue, Weekday.wednesday.rawValue, Weekday.friday.rawValue]
        s.lectureTime = TimeOfDay(hour: 9, minute: 0)
        XCTAssertEqual(s.displayString, "MWF \(TimeOfDay(hour: 9, minute: 0).display)")
    }

    func testDisplayStringLecturePlusSection() {
        var s = ClassSchedule()
        s.lectureDays = [Weekday.tuesday.rawValue, Weekday.thursday.rawValue]
        s.lectureTime = TimeOfDay(hour: 11, minute: 0)
        s.sectionDays = [Weekday.friday.rawValue]
        s.sectionTime = TimeOfDay(hour: 15, minute: 0)
        let expected = "TTh \(TimeOfDay(hour: 11, minute: 0).display) · Section F \(TimeOfDay(hour: 15, minute: 0).display)"
        XCTAssertEqual(s.displayString, expected)
    }

    func testEmptyScheduleHasEmptyStringAndIsEmpty() {
        XCTAssertEqual(ClassSchedule().displayString, "")
        XCTAssertTrue(ClassSchedule().isEmpty)
    }

    // MARK: - patterns

    func testPatternsFromLectureAndSection() {
        var s = ClassSchedule()
        s.lectureDays = [Weekday.friday.rawValue, Weekday.monday.rawValue]
        s.lectureTime = TimeOfDay(hour: 9, minute: 0)
        s.lectureDurationMinutes = 75
        s.sectionDays = [Weekday.thursday.rawValue]
        s.sectionTime = TimeOfDay(hour: 14, minute: 0)

        let patterns = s.patterns
        XCTAssertEqual(patterns.count, 2)
        XCTAssertEqual(patterns[0].kind, .lecture)
        XCTAssertEqual(patterns[0].days, [Weekday.monday.rawValue, Weekday.friday.rawValue], "days are sorted")
        XCTAssertEqual(patterns[0].durationMinutes, 75)
        XCTAssertEqual(patterns[1].kind, .section)
    }

    func testPatternsSkipsIncompletePattern() {
        var s = ClassSchedule()
        s.lectureDays = [Weekday.monday.rawValue]   // no lectureTime
        XCTAssertTrue(s.patterns.isEmpty)
        XCTAssertTrue(s.isEmpty)
    }

    // MARK: - occurrences

    func testOccurrencesForOneWeekMWF() {
        var s = ClassSchedule()
        s.lectureDays = [Weekday.monday.rawValue, Weekday.wednesday.rawValue, Weekday.friday.rawValue]
        s.lectureTime = TimeOfDay(hour: 9, minute: 0)

        // Week of Mon 2026-01-05 through Sun 2026-01-11.
        let from = day(2026, 1, 5)
        let to = day(2026, 1, 12)
        let occ = s.occurrences(from: from, to: to,
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)

        XCTAssertEqual(occ.count, 3)
        XCTAssertEqual(occ.map { calendar.component(.day, from: $0.start) }, [5, 7, 9])
        XCTAssertTrue(occ.allSatisfy { calendar.component(.hour, from: $0.start) == 9 })
        XCTAssertTrue(occ.allSatisfy { $0.kind == .lecture })
        // 50-minute default duration.
        XCTAssertEqual(calendar.component(.minute, from: occ[0].end), 50)
    }

    func testOccurrencesIncludeSectionAndSort() {
        var s = ClassSchedule()
        s.lectureDays = [Weekday.monday.rawValue]
        s.lectureTime = TimeOfDay(hour: 9, minute: 0)
        s.sectionDays = [Weekday.monday.rawValue]      // same day, later time
        s.sectionTime = TimeOfDay(hour: 15, minute: 0)

        let from = day(2026, 1, 5)
        let to = day(2026, 1, 12)
        let occ = s.occurrences(from: from, to: to,
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)

        XCTAssertEqual(occ.count, 2)
        XCTAssertEqual(occ[0].kind, .lecture)
        XCTAssertEqual(occ[1].kind, .section)
        XCTAssertLessThan(occ[0].start, occ[1].start)
    }

    func testOccurrencesRespectRangeBounds() {
        var s = ClassSchedule()
        s.lectureDays = Weekday.allCases.map(\.rawValue)   // every day
        s.lectureTime = TimeOfDay(hour: 9, minute: 0)

        let from = day(2026, 1, 5)
        let to = day(2026, 1, 8)   // Mon, Tue, Wed only
        let occ = s.occurrences(from: from, to: to,
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)
        XCTAssertEqual(occ.count, 3)
    }

    func testOccurrenceIDsAreStableAndUnique() {
        var s = ClassSchedule()
        s.lectureDays = [Weekday.monday.rawValue, Weekday.wednesday.rawValue]
        s.lectureTime = TimeOfDay(hour: 9, minute: 0)
        let id = UUID()
        let from = day(2026, 1, 5)
        let to = day(2026, 1, 12)

        let a = s.occurrences(from: from, to: to, className: "CS101", classColorHex: "007AFF", classID: id, calendar: calendar)
        let b = s.occurrences(from: from, to: to, className: "CS101", classColorHex: "007AFF", classID: id, calendar: calendar)
        XCTAssertEqual(a.map(\.id), b.map(\.id), "same inputs → same ids")
        XCTAssertEqual(Set(a.map(\.id)).count, a.count, "ids are unique within a run")
    }

    // MARK: - Weekday tokens

    func testWeekdayBydayTokens() {
        XCTAssertEqual(Weekday.monday.byday, "MO")
        XCTAssertEqual(Weekday.thursday.byday, "TH")
        XCTAssertEqual(Weekday.sunday.byday, "SU")
        XCTAssertEqual(Weekday.monday.short, "M")
        XCTAssertEqual(Weekday.thursday.short, "Th")
    }
}
