//
//  UnifiedEventMeetingTests.swift
//  PlannrTests
//
//  Synthesizing a calendar row from a class-meeting occurrence.
//

import XCTest
@testable import Plannr

final class UnifiedEventMeetingTests: XCTestCase {

    private func occurrence(kind: ClassMeetingPattern.Kind) -> ClassMeetingOccurrence {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 10, minute: 0))!
        let end = cal.date(byAdding: .minute, value: 50, to: start)!
        return ClassMeetingOccurrence(
            id: "class-abc-\(kind.rawValue)-20260902",
            className: "CMPSC 111", classColorHex: "AF52DE",
            kind: kind, start: start, end: end
        )
    }

    func testDeterministicUUIDIsStable() {
        XCTAssertEqual(UUID(deterministic: "a-b-c"), UUID(deterministic: "a-b-c"))
        XCTAssertNotEqual(UUID(deterministic: "a-b-c"), UUID(deterministic: "a-b-d"))
    }

    func testLectureRow() {
        let row = UnifiedEvent(meeting: occurrence(kind: .lecture), classColor: .purple)
        XCTAssertTrue(row.isMeeting)
        XCTAssertEqual(row.event.title, "CMPSC 111")
        XCTAssertEqual(row.event.date, "2026-09-02")
        XCTAssertEqual(row.event.type, "meeting")
        XCTAssertTrue(row.event.description.contains("–"), "description carries the time range")
    }

    func testSectionAndFinalTitles() {
        XCTAssertEqual(
            UnifiedEvent(meeting: occurrence(kind: .section), classColor: .purple).event.title,
            "CMPSC 111 (Section)"
        )
        let final = UnifiedEvent(meeting: occurrence(kind: .final), classColor: .purple)
        XCTAssertEqual(final.event.title, "CMPSC 111 — Final Exam")
        XCTAssertEqual(final.event.type, "final")
    }

    func testRowIDIsStableAcrossRebuilds() {
        let occ = occurrence(kind: .lecture)
        XCTAssertEqual(
            UnifiedEvent(meeting: occ, classColor: .purple).id,
            UnifiedEvent(meeting: occ, classColor: .red).id
        )
    }
}
