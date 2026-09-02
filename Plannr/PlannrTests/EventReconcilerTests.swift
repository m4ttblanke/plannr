//
//  EventReconcilerTests.swift
//  PlannrTests
//
//  Tests for EventReconciler.reconcile — merging a re-parsed syllabus against a
//  class's existing events so a re-upload only touches what changed.
//

import XCTest
@testable import Plannr

final class EventReconcilerTests: XCTestCase {

    /// Build a CalendarEvent and set the fields the reconciler cares about.
    private func makeEvent(
        title: String,
        date: String,
        description: String = "",
        googleEventId: String? = nil,
        isEdited: Bool = false,
        isTaskCompleted: Bool = false,
        isDeletedLocally: Bool = false
    ) -> CalendarEvent {
        var e = CalendarEvent(title: title, date: date, type: "homework", description: description)
        e.googleEventId = googleEventId
        e.isEdited = isEdited
        e.isTaskCompleted = isTaskCompleted
        e.isDeletedLocally = isDeletedLocally
        return e
    }

    // MARK: - First upload (no existing events)

    func testNoExistingEventsPassesParsedThrough() {
        let parsed = [makeEvent(title: "HW1", date: "2026-03-01"),
                      makeEvent(title: "Midterm 1", date: "2026-03-10")]

        let result = EventReconciler.reconcile(parsed: parsed, existing: [])

        XCTAssertEqual(result.merged.map(\.id), parsed.map(\.id))
        XCTAssertTrue(result.toDelete.isEmpty)
    }

    // MARK: - Matched, not edited → refresh details, keep the Google link

    func testMatchedUneditedRefreshesDetailsAndCarriesGoogleId() {
        let existing = makeEvent(title: "HW1", date: "2026-03-01",
                                 description: "old wording",
                                 googleEventId: "g-hw1",
                                 isTaskCompleted: true)
        let parsed = makeEvent(title: "HW1", date: "2026-03-01",
                               description: "new wording from updated syllabus")

        let result = EventReconciler.reconcile(parsed: [parsed], existing: [existing])

        XCTAssertEqual(result.merged.count, 1)
        let merged = result.merged[0]
        XCTAssertEqual(merged.description, "new wording from updated syllabus", "should take the new syllabus text")
        XCTAssertEqual(merged.googleEventId, "g-hw1", "should keep the link to the existing Google event")
        XCTAssertTrue(merged.isTaskCompleted, "should keep the user's completion state")
        XCTAssertTrue(result.toDelete.isEmpty)
    }

    func testMatchIsCaseAndWhitespaceInsensitive() {
        let existing = makeEvent(title: "hw1", date: "2026-03-01", googleEventId: "g-hw1")
        let parsed = makeEvent(title: "  HW1 ", date: "2026-03-01")

        let result = EventReconciler.reconcile(parsed: [parsed], existing: [existing])

        XCTAssertEqual(result.merged.first?.googleEventId, "g-hw1")
        XCTAssertTrue(result.toDelete.isEmpty)
    }

    // MARK: - Matched, edited locally → local edit wins

    func testMatchedEditedKeepsTheLocalVersion() {
        let existing = makeEvent(title: "HW1", date: "2026-03-01",
                                 description: "user's own notes",
                                 googleEventId: "g-hw1",
                                 isEdited: true)
        let parsed = makeEvent(title: "HW1", date: "2026-03-01",
                               description: "syllabus wording")

        let result = EventReconciler.reconcile(parsed: [parsed], existing: [existing])

        XCTAssertEqual(result.merged.count, 1)
        XCTAssertEqual(result.merged[0].id, existing.id, "should be the existing (edited) event, not the parsed one")
        XCTAssertEqual(result.merged[0].description, "user's own notes")
        XCTAssertTrue(result.toDelete.isEmpty)
    }

    // MARK: - New event in the syllabus

    func testNewParsedEventIsAddedWithNoGoogleId() {
        let existing = makeEvent(title: "HW1", date: "2026-03-01", googleEventId: "g-hw1")
        let newlyAdded = makeEvent(title: "HW2", date: "2026-03-08")

        let result = EventReconciler.reconcile(parsed: [existing, newlyAdded], existing: [existing])

        let hw2 = result.merged.first { $0.title == "HW2" }
        XCTAssertNotNil(hw2)
        XCTAssertNil(hw2?.googleEventId, "a brand-new event has no Google id yet")
        XCTAssertTrue(result.toDelete.isEmpty)
    }

    // MARK: - Event removed from the syllabus

    func testRemovedSyncedEventGoesToDelete() {
        let kept = makeEvent(title: "HW1", date: "2026-03-01", googleEventId: "g-hw1")
        let removed = makeEvent(title: "Quiz 4", date: "2026-03-05", googleEventId: "g-quiz4")

        // New parse no longer contains Quiz 4.
        let result = EventReconciler.reconcile(parsed: [kept], existing: [kept, removed])

        XCTAssertEqual(result.merged.map(\.title), ["HW1"])
        XCTAssertEqual(result.toDelete.map(\.id), [removed.id])
    }

    func testRemovedEventThatWasNeverSyncedIsNotDeleted() {
        let kept = makeEvent(title: "HW1", date: "2026-03-01", googleEventId: "g-hw1")
        let removedNeverSynced = makeEvent(title: "Quiz 4", date: "2026-03-05", googleEventId: nil)

        let result = EventReconciler.reconcile(parsed: [kept], existing: [kept, removedNeverSynced])

        XCTAssertTrue(result.toDelete.isEmpty, "nothing to delete in Google if it was never pushed there")
    }

    // MARK: - Date change is treated as remove + add

    func testDateChangeIsRemoveOldPlusAddNew() {
        let oldHw3 = makeEvent(title: "HW3", date: "2026-03-15", googleEventId: "g-hw3")
        let movedHw3 = makeEvent(title: "HW3", date: "2026-03-22")  // professor pushed the deadline

        let result = EventReconciler.reconcile(parsed: [movedHw3], existing: [oldHw3])

        XCTAssertEqual(result.merged.map(\.id), [movedHw3.id], "the new-date event is added fresh")
        XCTAssertNil(result.merged.first?.googleEventId)
        XCTAssertEqual(result.toDelete.map(\.id), [oldHw3.id], "the old-date event is removed from Google")
    }

    // MARK: - Locally-deleted existing events are ignored

    func testLocallyDeletedExistingEventsAreNotConsidered() {
        let queuedForDeletion = makeEvent(title: "HW1", date: "2026-03-01",
                                          googleEventId: "g-hw1", isDeletedLocally: true)
        let parsed = makeEvent(title: "HW1", date: "2026-03-01")

        let result = EventReconciler.reconcile(parsed: [parsed], existing: [queuedForDeletion])

        // The queued-for-deletion event is invisible to reconcile: HW1 reads as new.
        XCTAssertEqual(result.merged.count, 1)
        XCTAssertNil(result.merged[0].googleEventId)
        XCTAssertTrue(result.toDelete.isEmpty)
    }
}
