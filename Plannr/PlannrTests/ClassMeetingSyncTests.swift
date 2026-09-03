//
//  ClassMeetingSyncTests.swift
//  PlannrTests
//
//  The shared POST /calendar/meetings request builder + response handling.
//

import XCTest
@testable import Plannr

final class ClassMeetingSyncTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("student@example.com", forKey: "userEmail")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "userEmail")
        super.tearDown()
    }

    // MARK: - Fixtures

    private func scheduledClass(meetingSyncEnabled: Bool = true) -> Class {
        var schedule = ClassSchedule()
        schedule.lectureDays = [Weekday.monday, .wednesday, .friday].map(\.rawValue)
        schedule.lectureStart = TimeOfDay(hour: 10, minute: 0)
        schedule.lectureEnd = TimeOfDay(hour: 10, minute: 50)
        schedule.sectionDays = [Weekday.thursday.rawValue]
        schedule.sectionStart = TimeOfDay(hour: 15, minute: 0)
        return Class(
            name: "CMPSC 111",
            schedule: schedule.displayString,
            colorHex: "AF52DE",
            structuredSchedule: schedule,
            meetingSyncEnabled: meetingSyncEnabled
        )
    }

    private func http(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://x")!, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    private func decodeBody(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    // MARK: - Request shape

    func testEnabledScheduleSendsLectureAndSectionPatterns() async {
        var sent: URLRequest?
        _ = await ClassMeetingSync.run(for: scheduledClass(), term: nil) { req in
            sent = req
            return (Data(#"{"google_calendar_id":"c","meetings":[]}"#.utf8), self.http(200))
        }

        let body = decodeBody(try! XCTUnwrap(sent))
        XCTAssertEqual(body["class_name"] as? String, "CMPSC 111")
        let patterns = body["patterns"] as? [[String: Any]] ?? []
        XCTAssertEqual(patterns.count, 2)
        XCTAssertEqual(patterns.first?["byday"] as? [String], ["MO", "WE", "FR"])
        XCTAssertEqual(patterns.first?["start_time"] as? String, "10:00")
        XCTAssertEqual(patterns.first?["duration_minutes"] as? Int, 50)
        XCTAssertEqual(patterns.last?["kind"] as? String, "section")
        XCTAssertEqual(sent?.url?.path.hasSuffix("/calendar/meetings"), true)
        XCTAssertEqual(sent?.url?.query?.contains("email=student@example.com"), true)
    }

    func testDisabledClearsPatterns() async {
        var sent: URLRequest?
        _ = await ClassMeetingSync.run(for: scheduledClass(meetingSyncEnabled: false), term: nil) { req in
            sent = req
            return (Data(#"{"google_calendar_id":null,"meetings":[]}"#.utf8), self.http(200))
        }
        let body = decodeBody(try! XCTUnwrap(sent))
        XCTAssertEqual((body["patterns"] as? [[String: Any]])?.isEmpty, true)
    }

    // MARK: - Outcomes

    func testSuccessReturnsUpdatedClassWithIds() async {
        let json = #"{"google_calendar_id":"cal-42","meetings":[{"kind":"lecture","google_event_id":"e1"},{"kind":"section","google_event_id":"e2"}]}"#
        let outcome = await ClassMeetingSync.run(for: scheduledClass(), term: nil) { _ in
            (Data(json.utf8), self.http(200))
        }
        guard case .updated(let updated) = outcome else { return XCTFail("expected .updated, got \(outcome)") }
        XCTAssertEqual(updated.googleCalendarId, "cal-42")
        XCTAssertEqual(updated.meetingEventIds, ["e1", "e2"])
    }

    func testUnauthorizedIsDistinct() async {
        let outcome = await ClassMeetingSync.run(for: scheduledClass(), term: nil) { _ in
            (Data("{}".utf8), self.http(401))
        }
        guard case .unauthorized = outcome else { return XCTFail("expected .unauthorized") }
    }

    func testClientErrorIsMarkedRevertable() async {
        let outcome = await ClassMeetingSync.run(for: scheduledClass(), term: nil) { _ in
            (Data(#"{"error":"bad schedule"}"#.utf8), self.http(400))
        }
        guard case .failed(let message, let clientError) = outcome else { return XCTFail("expected .failed") }
        XCTAssertEqual(message, "bad schedule")
        XCTAssertTrue(clientError)
    }

    func testServerErrorIsNotRevertable() async {
        let outcome = await ClassMeetingSync.run(for: scheduledClass(), term: nil) { _ in
            (Data("upstream boom".utf8), self.http(503))
        }
        guard case .failed(_, let clientError) = outcome else { return XCTFail("expected .failed") }
        XCTAssertFalse(clientError)
    }

    func testTransportErrorIsReportedAsFailure() async {
        struct Boom: Error {}
        let outcome = await ClassMeetingSync.run(for: scheduledClass(), term: nil) { _ in
            throw Boom()
        }
        guard case .failed(_, let clientError) = outcome else { return XCTFail("expected .failed") }
        XCTAssertFalse(clientError)
    }
}
