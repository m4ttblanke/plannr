//
//  CalendarEventDecodingTests.swift
//  PlannrTests
//
//  CalendarEvent's decoder is deliberately lenient — it tolerates missing keys
//  and the LLM occasionally emitting `isSyllabus` as a string. These lock that
//  behavior in.
//

import XCTest
@testable import Plannr

final class CalendarEventDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> CalendarEvent {
        try JSONDecoder().decode(CalendarEvent.self, from: json.data(using: .utf8)!)
    }

    func testMissingOptionalFieldsGetDefaults() throws {
        let e = try decode(#"{ "title": "HW1", "date": "2026-03-01" }"#)
        XCTAssertEqual(e.title, "HW1")
        XCTAssertEqual(e.date, "2026-03-01")
        XCTAssertEqual(e.type, "other")
        XCTAssertEqual(e.description, "")
        XCTAssertEqual(e.colorHex, "007AFF")
        XCTAssertEqual(e.status, .pending)
        XCTAssertFalse(e.isEdited)
        XCTAssertFalse(e.isTaskCompleted)
        XCTAssertFalse(e.isDeletedLocally)
        XCTAssertNil(e.googleEventId)
        XCTAssertTrue(e.isSyllabus)
    }

    func testTotallyEmptyObjectDecodes() throws {
        let e = try decode("{}")
        XCTAssertEqual(e.title, "Untitled")
        XCTAssertEqual(e.date, "")
    }

    func testIsSyllabusAcceptsBoolean() throws {
        XCTAssertFalse(try decode(#"{ "title": "x", "date": "d", "isSyllabus": false }"#).isSyllabus)
        XCTAssertTrue(try decode(#"{ "title": "x", "date": "d", "isSyllabus": true }"#).isSyllabus)
    }

    func testIsSyllabusAcceptsStringVariants() throws {
        XCTAssertFalse(try decode(#"{ "title": "x", "date": "d", "isSyllabus": "false" }"#).isSyllabus)
        XCTAssertFalse(try decode(#"{ "title": "x", "date": "d", "isSyllabus": "False" }"#).isSyllabus)
        XCTAssertTrue(try decode(#"{ "title": "x", "date": "d", "isSyllabus": "true" }"#).isSyllabus)
        XCTAssertTrue(try decode(#"{ "title": "x", "date": "d", "isSyllabus": "TRUE" }"#).isSyllabus)
    }

    func testRoundTripPreservesFlags() throws {
        var e = CalendarEvent(title: "Lab 2", date: "2026-04-01", type: "lab", description: "d")
        e.status = .accepted
        e.googleEventId = "g-lab2"
        e.isTaskCompleted = true
        let again = try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(again.id, e.id)
        XCTAssertEqual(again.status, .accepted)
        XCTAssertEqual(again.googleEventId, "g-lab2")
        XCTAssertTrue(again.isTaskCompleted)
    }
}
