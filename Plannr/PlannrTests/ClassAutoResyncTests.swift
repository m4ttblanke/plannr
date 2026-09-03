//
//  ClassAutoResyncTests.swift
//  PlannrTests
//
//  The silent "sync when the network comes back" path.
//

import XCTest
@testable import Plannr

final class ClassAutoResyncTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("student@example.com", forKey: "userEmail")
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "userEmail")
        super.tearDown()
    }

    private func event(_ title: String, googleEventId: String? = nil, edited: Bool = false) -> CalendarEvent {
        var e = CalendarEvent(title: title, date: "2026-03-01", type: "homework", description: title)
        e.googleEventId = googleEventId
        e.isEdited = edited
        return e
    }

    private func pendingClass(_ events: [CalendarEvent],
                              googleCalendarId: String? = "cal-1",
                              isSample: Bool = false) -> Class {
        Class(name: "CS", colorHex: "007AFF", events: events, status: .active,
              googleCalendarId: googleCalendarId, hasUnsyncedChanges: true, isSample: isSample)
    }

    private func ok(_ json: String) -> (URLRequest) async throws -> (Data, HTTPURLResponse) {
        { req in (Data(json.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
    }

    func testAppliesTheResponseOnSuccess() async throws {
        let new = event("new")
        let cls = pendingClass([new])
        let send = ok(#"{"google_calendar_id":"cal-9","synced_events":[{"local_id":"\#(new.id.uuidString)","google_event_id":"g-new"}]}"#)

        let result = await ClassAutoResync.run(cls, reminderMinutes: nil, send: send)
        let updated = try XCTUnwrap(result)

        XCTAssertEqual(updated.googleCalendarId, "cal-9")
        XCTAssertEqual(updated.events.first?.googleEventId, "g-new")
        XCTAssertFalse(updated.hasUnsyncedChanges)
    }

    func testReturnsNilWhenThereIsNothingPendingAndNeverCallsSend() async {
        var calls = 0
        let send: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
            calls += 1
            return (Data(), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // All events already synced, no edits/deletes → incrementalEvents is empty.
        let cls = pendingClass([event("synced", googleEventId: "g-s")])

        let result = await ClassAutoResync.run(cls, reminderMinutes: nil, send: send)

        XCTAssertNil(result)
        XCTAssertEqual(calls, 0)
    }

    func testReturnsNilForAClassThatNeverSynced() async {
        let cls = pendingClass([event("new")], googleCalendarId: nil)
        let result = await ClassAutoResync.run(cls, reminderMinutes: nil, send: ok("{}"))
        XCTAssertNil(result)
    }

    func testReturnsNilForASampleClass() async {
        let cls = pendingClass([event("new")], isSample: true)
        let result = await ClassAutoResync.run(cls, reminderMinutes: nil, send: ok("{}"))
        XCTAssertNil(result)
    }

    func testReturnsNilOnAServerError() async {
        let cls = pendingClass([event("new")])
        let send: (URLRequest) async throws -> (Data, HTTPURLResponse) = { req in
            (Data("down".utf8), HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        let result = await ClassAutoResync.run(cls, reminderMinutes: nil, send: send)
        XCTAssertNil(result, "a failed sync leaves the class untouched for a later manual retry")
    }

    func testReturnsNilWhenSendThrows() async {
        struct Boom: Error {}
        let cls = pendingClass([event("new")])
        let result = await ClassAutoResync.run(cls, reminderMinutes: nil, send: { _ in throw Boom() })
        XCTAssertNil(result)
    }
}
