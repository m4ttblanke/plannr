//
//  EventTypeTests.swift
//  PlannrTests
//
//  EventType — normalizes the free-form `CalendarEvent.type` string to one of
//  the standard categories used for filtering and colour-coding.
//

import XCTest
@testable import Plannr

final class EventTypeTests: XCTestCase {

    func testKnownValuesMapThrough() {
        XCTAssertEqual(EventType("homework"), .homework)
        XCTAssertEqual(EventType("exam"), .exam)
        XCTAssertEqual(EventType("quiz"), .quiz)
        XCTAssertEqual(EventType("lab"), .lab)
        XCTAssertEqual(EventType("other"), .other)
    }

    func testNormalizesCaseAndWhitespace() {
        XCTAssertEqual(EventType("Homework"), .homework)
        XCTAssertEqual(EventType("  EXAM "), .exam)
    }

    func testUnknownAndEmptyFallBackToOther() {
        XCTAssertEqual(EventType("test"), .other)
        XCTAssertEqual(EventType("HW"), .other)
        XCTAssertEqual(EventType(""), .other)
    }

    func testEveryCaseRoundTripsThroughItsRawValue() {
        for type in EventType.allCases {
            XCTAssertEqual(EventType(type.rawValue), type)
        }
    }

    func testPickerOptionsAreTheFiveStandardCategories() {
        XCTAssertEqual(EventType.allCases.map(\.rawValue),
                       ["homework", "exam", "quiz", "lab", "other"])
        XCTAssertEqual(EventType.exam.label, "Exam")
    }
}
