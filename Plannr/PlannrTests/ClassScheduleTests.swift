//
//  ClassScheduleTests.swift
//  PlannrTests
//
//  Tests for ClassSchedule: display string, start/end times, meeting patterns,
//  the occurrence expansion used by Week at a Glance, and legacy decoding.
//

import XCTest
@testable import Plannr

final class ClassScheduleTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    /// A lecture-only schedule.
    private func lecture(days: [Weekday], start: TimeOfDay, end: TimeOfDay? = nil) -> ClassSchedule {
        var s = ClassSchedule()
        s.lectureDays = days.map(\.rawValue)
        s.lectureStart = start
        s.lectureEnd = end
        return s
    }

    // MARK: - TimeOfDay

    func testTimeOfDayFormatting() {
        XCTAssertEqual(TimeOfDay(hour: 9, minute: 5).iso, "09:05")
        XCTAssertFalse(TimeOfDay(hour: 9, minute: 5).display.isEmpty)
    }

    func testTimeOfDayClampsOutOfRange() {
        XCTAssertEqual(TimeOfDay(hour: 30, minute: -4).hour, 23)
        XCTAssertEqual(TimeOfDay(hour: 30, minute: -4).minute, 0)
    }

    // MARK: - displayString

    func testDisplayStringStartOnly() {
        let s = lecture(days: [.monday, .wednesday, .friday], start: TimeOfDay(hour: 9, minute: 0))
        XCTAssertEqual(s.displayString, "MWF \(TimeOfDay(hour: 9, minute: 0).display)")
    }

    func testDisplayStringWithEndShowsARange() {
        let s = lecture(days: [.monday, .wednesday, .friday],
                        start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 10, minute: 15))
        XCTAssertEqual(
            s.displayString,
            "MWF \(TimeOfDay(hour: 9, minute: 0).display) – \(TimeOfDay(hour: 10, minute: 15).display)"
        )
    }

    func testDisplayStringLecturePlusSection() {
        var s = lecture(days: [.tuesday, .thursday], start: TimeOfDay(hour: 11, minute: 0))
        s.sectionDays = [Weekday.friday.rawValue]
        s.sectionStart = TimeOfDay(hour: 15, minute: 0)
        s.sectionEnd = TimeOfDay(hour: 16, minute: 15)
        XCTAssertEqual(
            s.displayString,
            "TTh \(TimeOfDay(hour: 11, minute: 0).display) · Section F \(TimeOfDay(hour: 15, minute: 0).display) – \(TimeOfDay(hour: 16, minute: 15).display)"
        )
    }

    func testEmptyScheduleHasEmptyStringAndIsEmpty() {
        XCTAssertEqual(ClassSchedule().displayString, "")
        XCTAssertTrue(ClassSchedule().isEmpty)
    }

    // MARK: - patterns & duration

    func testDurationDerivedFromStartAndEnd() {
        var s = lecture(days: [.monday, .friday],
                        start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 10, minute: 15))
        s.sectionDays = [Weekday.thursday.rawValue]
        s.sectionStart = TimeOfDay(hour: 14, minute: 0)   // no end

        let patterns = s.patterns
        XCTAssertEqual(patterns.count, 2)
        XCTAssertEqual(patterns[0].kind, .lecture)
        XCTAssertEqual(patterns[0].days, [Weekday.monday.rawValue, Weekday.friday.rawValue])
        XCTAssertEqual(patterns[0].durationMinutes, 75)
        XCTAssertEqual(patterns[1].kind, .section)
        XCTAssertEqual(patterns[1].durationMinutes, defaultMeetingMinutes, "no end → default length")
    }

    func testEndBeforeStartFallsBackToDefaultDuration() {
        let s = lecture(days: [.monday],
                        start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 9, minute: 0))
        XCTAssertEqual(s.patterns[0].durationMinutes, defaultMeetingMinutes)
        // ...and the display string drops the bogus range.
        XCTAssertEqual(s.displayString, "M \(TimeOfDay(hour: 10, minute: 0).display)")
    }

    func testPatternsSkipsWhenNoStartTime() {
        var s = ClassSchedule()
        s.lectureDays = [Weekday.monday.rawValue]   // no start
        XCTAssertTrue(s.patterns.isEmpty)
        XCTAssertTrue(s.isEmpty)
    }

    // MARK: - occurrences

    func testOccurrencesForOneWeekMWF() {
        let s = lecture(days: [.monday, .wednesday, .friday], start: TimeOfDay(hour: 9, minute: 0))
        let occ = s.occurrences(from: day(2026, 1, 5), to: day(2026, 1, 12),
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)

        XCTAssertEqual(occ.count, 3)
        XCTAssertEqual(occ.map { calendar.component(.day, from: $0.start) }, [5, 7, 9])
        XCTAssertTrue(occ.allSatisfy { calendar.component(.hour, from: $0.start) == 9 })
        XCTAssertTrue(occ.allSatisfy { $0.kind == .lecture })
        XCTAssertEqual(calendar.component(.minute, from: occ[0].end), 50)   // default 50-min length
    }

    func testOccurrenceEndUsesTheScheduledEnd() {
        let s = lecture(days: [.monday], start: TimeOfDay(hour: 9, minute: 0),
                        end: TimeOfDay(hour: 10, minute: 20))
        let occ = s.occurrences(from: day(2026, 1, 5), to: day(2026, 1, 12),
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(calendar.component(.hour, from: occ[0].end), 10)
        XCTAssertEqual(calendar.component(.minute, from: occ[0].end), 20)
    }

    func testOccurrencesIncludeSectionAndSort() {
        var s = lecture(days: [.monday], start: TimeOfDay(hour: 9, minute: 0))
        s.sectionDays = [Weekday.monday.rawValue]
        s.sectionStart = TimeOfDay(hour: 15, minute: 0)

        let occ = s.occurrences(from: day(2026, 1, 5), to: day(2026, 1, 12),
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)
        XCTAssertEqual(occ.map(\.kind), [.lecture, .section])
        XCTAssertLessThan(occ[0].start, occ[1].start)
    }

    func testOccurrencesRespectRangeBounds() {
        let s = lecture(days: Weekday.allCases, start: TimeOfDay(hour: 9, minute: 0))
        let occ = s.occurrences(from: day(2026, 1, 5), to: day(2026, 1, 8),   // Mon–Wed
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)
        XCTAssertEqual(occ.count, 3)
    }

    func testOccurrenceIDsAreStableAndUnique() {
        let s = lecture(days: [.monday, .wednesday], start: TimeOfDay(hour: 9, minute: 0))
        let id = UUID()
        let a = s.occurrences(from: day(2026, 1, 5), to: day(2026, 1, 12),
                              className: "CS101", classColorHex: "007AFF", classID: id, calendar: calendar)
        let b = s.occurrences(from: day(2026, 1, 5), to: day(2026, 1, 12),
                              className: "CS101", classColorHex: "007AFF", classID: id, calendar: calendar)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(Set(a.map(\.id)).count, a.count)
    }

    // MARK: - Codable (round-trip + legacy migration)

    func testRoundTripPreservesStartAndEnd() throws {
        var s = lecture(days: [.tuesday, .thursday],
                        start: TimeOfDay(hour: 11, minute: 0), end: TimeOfDay(hour: 12, minute: 15))
        s.sectionDays = [Weekday.friday.rawValue]
        s.sectionStart = TimeOfDay(hour: 14, minute: 0)
        s.sectionEnd = TimeOfDay(hour: 15, minute: 50)

        let decoded = try JSONDecoder().decode(ClassSchedule.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testDecodesLegacyStartTimePlusDuration() throws {
        // Shape written before start/end times: `lectureTime` + `lectureDurationMinutes`.
        let legacy = """
        {
          "lectureDays": [2, 4, 6],
          "lectureTime": { "hour": 9, "minute": 0 },
          "lectureDurationMinutes": 75,
          "sectionDays": [],
          "sectionDurationMinutes": 50
        }
        """.data(using: .utf8)!

        let s = try JSONDecoder().decode(ClassSchedule.self, from: legacy)
        XCTAssertEqual(s.lectureStart, TimeOfDay(hour: 9, minute: 0))
        XCTAssertEqual(s.lectureEnd, TimeOfDay(hour: 10, minute: 15))   // 9:00 + 75 min
        XCTAssertEqual(s.patterns.first?.durationMinutes, 75)
        XCTAssertNil(s.sectionStart)
    }

    // MARK: - "Repeat for X weeks" window

    func testWeekCountBoundsTheOccurrenceWindow() {
        var s = lecture(days: [.monday, .wednesday, .friday], start: TimeOfDay(hour: 9, minute: 0))
        s.firstMeetingDate = day(2026, 1, 5)   // Monday
        s.weekCount = 2                          // Jan 5 through Jan 18

        // Week 3 (Jan 19–25) is past the window → no occurrences.
        let outside = s.occurrences(from: day(2026, 1, 19), to: day(2026, 1, 26),
                                    className: "CS101", classColorHex: "007AFF",
                                    classID: UUID(), calendar: calendar)
        XCTAssertTrue(outside.isEmpty)

        // Week 2 (Jan 12–18) is still inside → 3 meetings.
        let inside = s.occurrences(from: day(2026, 1, 12), to: day(2026, 1, 19),
                                   className: "CS101", classColorHex: "007AFF",
                                   classID: UUID(), calendar: calendar)
        XCTAssertEqual(inside.count, 3)
    }

    func testFirstMeetingDateExcludesEarlierWeeks() {
        var s = lecture(days: [.monday], start: TimeOfDay(hour: 9, minute: 0))
        s.firstMeetingDate = day(2026, 1, 12)   // classes start the 2nd week

        let earlier = s.occurrences(from: day(2026, 1, 5), to: day(2026, 1, 12),
                                    className: "CS101", classColorHex: "007AFF",
                                    classID: UUID(), calendar: calendar)
        XCTAssertTrue(earlier.isEmpty, "no meetings before the first class date")

        let onward = s.occurrences(from: day(2026, 1, 12), to: day(2026, 1, 19),
                                   className: "CS101", classColorHex: "007AFF",
                                   classID: UUID(), calendar: calendar)
        XCTAssertEqual(onward.count, 1)
    }

    func testMeetingWindowUsesFallbackWhenNoFirstDate() {
        let s = lecture(days: [.monday], start: TimeOfDay(hour: 9, minute: 0))
        let window = s.meetingWindow(fallbackStart: day(2026, 1, 5), calendar: calendar)
        XCTAssertEqual(window.start, day(2026, 1, 5))
        XCTAssertNil(window.end, "no weekCount → open-ended")
    }

    // MARK: - Final exam

    func testFinalExamShowsAsAnOccurrence() {
        var s = lecture(days: [.monday], start: TimeOfDay(hour: 9, minute: 0))
        s.firstMeetingDate = day(2026, 1, 5)
        s.weekCount = 2   // regular meetings end Jan 18
        s.finalExam = ClassFinalExam(date: day(2026, 1, 22),
                                     start: TimeOfDay(hour: 19, minute: 0),
                                     end: TimeOfDay(hour: 22, minute: 0))

        // Finals week (Jan 19–25) — no lecture (past window) but the final shows.
        let occ = s.occurrences(from: day(2026, 1, 19), to: day(2026, 1, 26),
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(occ[0].kind, .final)
        XCTAssertEqual(calendar.component(.hour, from: occ[0].start), 19)
        XCTAssertEqual(calendar.component(.hour, from: occ[0].end), 22)
    }

    func testFinalExamOutsideTheVisibleWeekIsNotIncluded() {
        var s = ClassSchedule()
        s.finalExam = ClassFinalExam(date: day(2026, 3, 15),
                                     start: TimeOfDay(hour: 9, minute: 0), end: nil)
        let occ = s.occurrences(from: day(2026, 1, 5), to: day(2026, 1, 12),
                                className: "CS101", classColorHex: "007AFF",
                                classID: UUID(), calendar: calendar)
        XCTAssertTrue(occ.isEmpty)
    }

    func testScheduleWithOnlyAFinalExamIsNotEmpty() {
        var s = ClassSchedule()
        XCTAssertTrue(s.isEmpty)
        s.finalExam = ClassFinalExam(date: day(2026, 3, 15),
                                     start: TimeOfDay(hour: 9, minute: 0), end: nil)
        XCTAssertFalse(s.isEmpty)
    }

    func testRoundTripPreservesWindowAndFinalExam() throws {
        var s = lecture(days: [.monday], start: TimeOfDay(hour: 9, minute: 0))
        s.firstMeetingDate = day(2026, 1, 5)
        s.weekCount = 12
        s.finalExam = ClassFinalExam(date: day(2026, 3, 16),
                                     start: TimeOfDay(hour: 8, minute: 0),
                                     end: TimeOfDay(hour: 11, minute: 0))
        let decoded = try JSONDecoder().decode(ClassSchedule.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    // MARK: - Weekday tokens

    func testWeekdayTokens() {
        XCTAssertEqual(Weekday.monday.byday, "MO")
        XCTAssertEqual(Weekday.thursday.byday, "TH")
        XCTAssertEqual(Weekday.sunday.byday, "SU")
        XCTAssertEqual(Weekday.monday.short, "M")
        XCTAssertEqual(Weekday.thursday.short, "Th")
    }
}
