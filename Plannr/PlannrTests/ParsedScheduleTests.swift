//
//  ParsedScheduleTests.swift
//  PlannrTests
//
//  The `schedule` object from POST /syllabus → ClassSchedule mapping, plus the
//  small parsing inits it relies on.
//

import XCTest
@testable import Plannr

final class ParsedScheduleTests: XCTestCase {

    private func decodeResponse(_ json: String) throws -> SyllabusResponse {
        try JSONDecoder().decode(SyllabusResponse.self, from: Data(json.utf8))
    }

    // MARK: - Building blocks

    func testWeekdayFromBydayToken() {
        XCTAssertEqual(Weekday(byday: "MO"), .monday)
        XCTAssertEqual(Weekday(byday: "th"), .thursday)   // case-insensitive
        XCTAssertEqual(Weekday(byday: "SU"), .sunday)
        XCTAssertNil(Weekday(byday: "XX"))
    }

    func testTimeOfDayFromISO() {
        XCTAssertEqual(TimeOfDay(iso: "09:00").map { [$0.hour, $0.minute] }, [9, 0])
        XCTAssertEqual(TimeOfDay(iso: "15:45").map { [$0.hour, $0.minute] }, [15, 45])
        XCTAssertNil(TimeOfDay(iso: "24:00"))
        XCTAssertNil(TimeOfDay(iso: "nonsense"))
    }

    // MARK: - Decoding

    func testResponseWithoutScheduleDecodesToNil() throws {
        let resp = try decodeResponse(#"{"events": [], "schedule": null}"#)
        XCTAssertNil(resp.schedule)
    }

    func testResponseMissingScheduleKeyIsNil() throws {
        let resp = try decodeResponse(#"{"events": []}"#)
        XCTAssertNil(resp.schedule)
    }

    // MARK: - Mapping

    func testFullScheduleMapsLectureSectionAndFinal() throws {
        let json = #"""
        {
          "events": [],
          "schedule": {
            "lecture_days": ["MO", "WE", "FR"], "lecture_start": "10:00", "lecture_end": "10:50",
            "section_days": ["TH"], "section_start": "15:00", "section_end": "16:15",
            "final_date": "2026-12-12", "final_start": "16:00", "final_end": "19:00"
          }
        }
        """#
        let schedule = try XCTUnwrap(decodeResponse(json).schedule?.toClassSchedule())

        XCTAssertEqual(schedule.lectureDays, [Weekday.monday, .wednesday, .friday].map(\.rawValue))
        XCTAssertEqual(schedule.lectureStart, TimeOfDay(hour: 10, minute: 0))
        XCTAssertEqual(schedule.lectureEnd, TimeOfDay(hour: 10, minute: 50))
        XCTAssertEqual(schedule.sectionDays, [Weekday.thursday.rawValue])
        XCTAssertEqual(schedule.sectionStart, TimeOfDay(hour: 15, minute: 0))
        XCTAssertEqual(schedule.sectionEnd, TimeOfDay(hour: 16, minute: 15))

        let final = try XCTUnwrap(schedule.finalExam)
        XCTAssertEqual(final.start, TimeOfDay(hour: 16, minute: 0))
        XCTAssertEqual(final.end, TimeOfDay(hour: 19, minute: 0))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: final.date),
                       DateComponents(year: 2026, month: 12, day: 12))
    }

    func testLectureDaysWithoutStartTimeAreDropped() throws {
        let json = #"""
        {"events": [], "schedule": {"lecture_days": ["MO","WE"], "lecture_start": null,
         "section_days": [], "final_date": null}}
        """#
        // Nothing usable → nil.
        XCTAssertNil(try decodeResponse(json).schedule?.toClassSchedule())
    }

    func testSectionOnlyStillProducesASchedule() throws {
        let json = #"""
        {"events": [], "schedule": {"lecture_days": [], "section_days": ["TU","TH"],
         "section_start": "13:00", "section_end": null, "final_date": null}}
        """#
        let schedule = try XCTUnwrap(decodeResponse(json).schedule?.toClassSchedule())
        XCTAssertTrue(schedule.lectureDays.isEmpty)
        XCTAssertEqual(schedule.sectionDays, [Weekday.tuesday, .thursday].map(\.rawValue))
        XCTAssertEqual(schedule.sectionStart, TimeOfDay(hour: 13, minute: 0))
        XCTAssertNil(schedule.sectionEnd)
        XCTAssertNil(schedule.finalExam)
    }

    func testFinalWithoutStartTimeDefaultsTo9AM() throws {
        let json = #"""
        {"events": [], "schedule": {"lecture_days": [], "section_days": [],
         "final_date": "2026-06-10", "final_start": null, "final_end": null}}
        """#
        let schedule = try XCTUnwrap(decodeResponse(json).schedule?.toClassSchedule())
        XCTAssertEqual(schedule.finalExam?.start, TimeOfDay(hour: 9, minute: 0))
        XCTAssertNil(schedule.finalExam?.end)
    }

    func testGarbageDayTokensAreIgnored() throws {
        let json = #"""
        {"events": [], "schedule": {"lecture_days": ["MO","banana","FR"], "lecture_start": "09:00",
         "section_days": [], "final_date": null}}
        """#
        let schedule = try XCTUnwrap(decodeResponse(json).schedule?.toClassSchedule())
        XCTAssertEqual(schedule.lectureDays, [Weekday.monday, .friday].map(\.rawValue))
    }
}
