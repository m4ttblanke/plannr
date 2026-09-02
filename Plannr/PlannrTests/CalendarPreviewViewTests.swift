//
//  CalendarPreviewViewTests.swift
//  PlannrTests
//
//  Unit tests for CalendarPreviewView event filtering and display logic
//

import XCTest
import SwiftUI
@testable import Plannr

/// Unit tests for CalendarPreviewView component
/// Tests the core functionality of filtering events by date and type
class CalendarPreviewViewTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var testEvents: [CalendarEvent]!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        // Create sample test events
        testEvents = [
            CalendarEvent(
                title: "Math Homework",
                date: "2024-02-15",
                type: "homework",
                description: "Chapter 5 problems"
            ),
            CalendarEvent(
                title: "Physics Exam",
                date: "2024-02-20",
                type: "exam",
                description: "Midterm exam"
            ),
            CalendarEvent(
                title: "Chemistry Lab",
                date: "2024-02-18",
                type: "lab",
                description: "Lab 3"
            ),
            CalendarEvent(
                title: "History Quiz",
                date: "2024-02-20",
                type: "quiz",
                description: "Civil War quiz"
            )
        ]
    }
    
    override func tearDown() {
        testEvents = nil
        super.tearDown()
    }
    
    // MARK: - Event Filtering Tests
    
    /// Test filtering events by a specific date
    /// This is critical for the calendar view to show events on the correct day
    func testFilterEventsByDate() {
        // Given - events on different dates
        let targetDate = "2024-02-20"
        
        // When - we filter events for a specific date (like the calendar does)
        let eventsOnDate = testEvents.filter { $0.date == targetDate }
        
        // Then - we should only get events on that date
        XCTAssertEqual(eventsOnDate.count, 2, "Should have exactly 2 events on Feb 20")
        XCTAssertTrue(
            eventsOnDate.allSatisfy { $0.date == targetDate },
            "All filtered events should be on the target date"
        )
        XCTAssertTrue(
            eventsOnDate.contains { $0.title == "Physics Exam" },
            "Should include Physics Exam"
        )
        XCTAssertTrue(
            eventsOnDate.contains { $0.title == "History Quiz" },
            "Should include History Quiz"
        )
    }
    
    /// Test filtering events by type
    /// Verifies that event type filtering works correctly
    func testFilterEventsByType() {
        // Given - events of different types
        let targetType = "exam"
        
        // When - we filter events by type
        let examEvents = testEvents.filter { $0.type.lowercased() == targetType }
        
        // Then - we should only get exam events
        XCTAssertEqual(examEvents.count, 1, "Should have exactly 1 exam event")
        XCTAssertEqual(examEvents.first?.title, "Physics Exam", "The exam should be Physics Exam")
        XCTAssertTrue(
            examEvents.allSatisfy { $0.type.lowercased() == targetType },
            "All filtered events should be of type exam"
        )
    }
    
    /// Test that event count is accurate
    /// Ensures the "X items found" display is correct
    func testEventCount() {
        // Given - our test events array
        
        // When - we check the count
        let count = testEvents.count
        
        // Then - it should match the number of events we created
        XCTAssertEqual(count, 4, "Should have exactly 4 events")
    }
    
    /// Test filtering events when no matches exist
    /// Edge case: ensures empty results are handled properly
    func testFilterEventsWithNoMatches() {
        // Given - events with specific dates
        let nonExistentDate = "2025-12-31"
        
        // When - we filter for a date with no events
        let eventsOnDate = testEvents.filter { $0.date == nonExistentDate }
        
        // Then - we should get an empty array
        XCTAssertTrue(eventsOnDate.isEmpty, "Should return empty array when no events match")
        XCTAssertEqual(eventsOnDate.count, 0, "Count should be 0 for no matches")
    }
    
    // MARK: - Class-meeting preview rows

    /// One occurrence per kind, in the app's own calendar/time zone so the row's
    /// formatted `date` matches the day it was placed on — the preview grid then
    /// filters these by that date string exactly like assignment events.
    private func occurrence(kind: ClassMeetingPattern.Kind, hour: Int = 10) -> ClassMeetingOccurrence {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: hour, minute: 0))!
        return ClassMeetingOccurrence(
            id: "cls-\(kind.rawValue)-20260304",
            className: "CS 101", classColorHex: "AF52DE",
            kind: kind, start: start, end: cal.date(byAdding: .minute, value: 50, to: start)!
        )
    }

    func testMeetingOccurrenceBecomesADateFilterableRow() {
        let cal = Calendar.current
        let rows = [occurrence(kind: .lecture), occurrence(kind: .section, hour: 15), occurrence(kind: .final, hour: 16)]
            .map { CalendarEvent(meeting: $0) }

        let dayString: String = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: cal.date(from: DateComponents(year: 2026, month: 3, day: 4))!)
        }()

        // All three land on the same day and the grid's date filter picks them up.
        XCTAssertEqual(rows.filter { $0.date == dayString }.count, 3)
        XCTAssertEqual(rows.map(\.title),
                       ["CS 101", "CS 101 (Section)", "CS 101 — Final Exam"])
        XCTAssertEqual(rows.map(\.type), ["meeting", "meeting", "final"])
        XCTAssertTrue(rows.allSatisfy { $0.description.contains("–") }, "time range in the description")

        // A different day has none.
        XCTAssertTrue(rows.filter { $0.date == "2026-03-05" }.isEmpty)
    }

    func testMeetingRowIDsAreStableAcrossRebuilds() {
        let occ = occurrence(kind: .lecture)
        XCTAssertEqual(CalendarEvent(meeting: occ).id, CalendarEvent(meeting: occ).id,
                       "deterministic ids keep SwiftUI list identity stable")
    }

    /// Test that all events have required properties
    /// Ensures data integrity for calendar display
    func testAllEventsHaveRequiredProperties() {
        // Given - our test events
        
        // Then - all events should have non-empty titles and dates
        XCTAssertTrue(
            testEvents.allSatisfy { !$0.title.isEmpty },
            "All events should have non-empty titles"
        )
        XCTAssertTrue(
            testEvents.allSatisfy { !$0.date.isEmpty },
            "All events should have non-empty dates"
        )
        XCTAssertTrue(
            testEvents.allSatisfy { !$0.type.isEmpty },
            "All events should have non-empty types"
        )
    }
}
