//
//  ClassSyncRequestTests.swift
//  PlannrTests
//
//  The shared POST /calendar/sync request builder + response model.
//

import XCTest
@testable import Plannr

final class ClassSyncRequestTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("student@example.com", forKey: "userEmail")
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "userEmail")
        super.tearDown()
    }

    private func event(_ title: String,
                       googleEventId: String? = nil,
                       edited: Bool = false,
                       deleted: Bool = false,
                       status: EventStatus = .pending) -> CalendarEvent {
        var e = CalendarEvent(title: title, date: "2026-03-01", type: "homework", description: title)
        e.googleEventId = googleEventId
        e.isEdited = edited
        e.isDeletedLocally = deleted
        e.status = status
        return e
    }

    private func decodeBody(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    // MARK: - EventBody

    func testEventBodyCopiesTheEventFields() {
        let e = event("HW1", googleEventId: "g-1")
        let body = ClassSyncRequest.EventBody(e, isDeleted: true)
        XCTAssertEqual(body.localId, e.id.uuidString)
        XCTAssertEqual(body.title, "HW1")
        XCTAssertEqual(body.googleEventId, "g-1")
        XCTAssertTrue(body.isDeleted)
    }

    // MARK: - fullSyncEvents

    func testFullSyncEventsAreAcceptedThenDeletions() {
        let accepted = [event("A"), event("B")]
        let deletions = [event("Old", googleEventId: "g-old")]
        let bodies = ClassSyncRequest.fullSyncEvents(accepted: accepted, deletions: deletions)
        XCTAssertEqual(bodies.map(\.title), ["A", "B", "Old"])
        XCTAssertEqual(bodies.map(\.isDeleted), [false, false, true])
    }

    // MARK: - incrementalEvents

    func testIncrementalSendsOnlyEventsThatNeedAction() {
        let events = [
            event("new"),                                       // insert
            event("edited", googleEventId: "g-e", edited: true), // update
            event("dropped", googleEventId: "g-d", deleted: true), // delete
            event("unchanged", googleEventId: "g-u"),            // skip
            event("never-synced-delete", deleted: true),         // skip (no id to delete)
        ]
        let bodies = ClassSyncRequest.incrementalEvents(from: events)
        XCTAssertEqual(bodies.map(\.title), ["new", "edited", "dropped"])
        XCTAssertEqual(bodies.first(where: { $0.title == "dropped" })?.isDeleted, true)
        XCTAssertEqual(bodies.first(where: { $0.title == "new" })?.isDeleted, false)
    }

    // MARK: - hashHex

    func testHashHexPrefixesWhenMissing() {
        XCTAssertEqual(ClassSyncRequest.hashHex("AF52DE"), "#AF52DE")
        XCTAssertEqual(ClassSyncRequest.hashHex("#AF52DE"), "#AF52DE")
    }

    // MARK: - makeRequest

    func testMakeRequestReturnsNilWithoutAnEmail() throws {
        let request = try ClassSyncRequest.makeRequest(
            email: nil, className: "CS", googleCalendarId: nil,
            classColorHex: "AF52DE", reminderMinutes: nil, events: []
        )
        XCTAssertNil(request)
    }

    func testMakeRequestShapesThePayload() throws {
        let events = ClassSyncRequest.fullSyncEvents(
            accepted: [event("A", googleEventId: "g-a")],
            deletions: [event("D", googleEventId: "g-d")]
        )
        let request = try XCTUnwrap(try ClassSyncRequest.makeRequest(
            email: "student@example.com",
            className: "CMPSC 111",
            googleCalendarId: "cal-1",
            classColorHex: "AF52DE",
            reminderMinutes: 2880,
            events: events
        ))

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path.hasSuffix("/calendar/sync"), true)
        XCTAssertEqual(request.url?.query?.contains("email=student@example.com"), true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = decodeBody(request)
        XCTAssertEqual(body["class_name"] as? String, "CMPSC 111")
        XCTAssertEqual(body["google_calendar_id"] as? String, "cal-1")
        XCTAssertEqual(body["background_color"] as? String, "#AF52DE")
        XCTAssertEqual(body["foreground_color"] as? String, "#FFFFFF")
        XCTAssertEqual(body["reminder_minutes"] as? Int, 2880)

        let payloadEvents = body["events"] as? [[String: Any]] ?? []
        XCTAssertEqual(payloadEvents.count, 2)
        XCTAssertEqual(payloadEvents.first?["google_event_id"] as? String, "g-a")
        XCTAssertEqual(payloadEvents.first?["is_deleted"] as? Bool, false)
        XCTAssertEqual(payloadEvents.last?["is_deleted"] as? Bool, true)
        XCTAssertNotNil(payloadEvents.first?["local_id"])
    }

    func testMakeRequestOmitsCalendarIdWhenNil() throws {
        let request = try XCTUnwrap(try ClassSyncRequest.makeRequest(
            email: "x@e.com", className: "CS", googleCalendarId: nil,
            classColorHex: "#123456", reminderMinutes: nil, events: []
        ))
        let body = decodeBody(request)
        XCTAssertNil(body["google_calendar_id"])          // encoded as absent, not null
        XCTAssertNil(body["reminder_minutes"])
        XCTAssertEqual(body["background_color"] as? String, "#123456")
    }

    // MARK: - Response

    func testResponseDecodesTheBackendShape() throws {
        let json = #"""
        {"google_calendar_id": "cal-9",
         "synced_events": [{"local_id": "L1", "google_event_id": "G1"},
                           {"local_id": "L2", "google_event_id": "G2"}]}
        """#
        let resp = try JSONDecoder().decode(ClassSyncRequest.Response.self, from: Data(json.utf8))
        XCTAssertEqual(resp.googleCalendarId, "cal-9")
        XCTAssertEqual(resp.syncedEvents.map { [$0.localId, $0.googleEventId] },
                       [["L1", "G1"], ["L2", "G2"]])
    }
}
