//
//  ClassRestoreTests.swift
//  PlannrTests
//
//  Planning a "restore this sync session" — what the events become and which
//  Google Calendar events to delete.
//

import XCTest
@testable import Plannr

final class ClassRestoreTests: XCTestCase {

    private func event(_ title: String,
                       date: String = "2026-03-01",
                       googleEventId: String? = nil,
                       edited: Bool = false,
                       deleted: Bool = false) -> CalendarEvent {
        var e = CalendarEvent(title: title, date: date, type: "homework", description: title)
        e.googleEventId = googleEventId
        e.isEdited = edited
        e.isDeletedLocally = deleted
        return e
    }

    func testRestoredEventsComeFromTheSnapshotButKeepMatchingGoogleIds() {
        let snapshot = [
            event("HW1", googleEventId: "snap-1"),
            event("HW2", googleEventId: "snap-2"),
        ]
        let current = [
            event("HW1", googleEventId: "cur-1", edited: true),   // user edited since
        ]

        let plan = ClassRestore.plan(snapshot: snapshot, current: current)

        XCTAssertEqual(plan.restored.map(\.title).sorted(), ["HW1", "HW2"])
        // HW1 still exists on the calendar → patch it in place (keep cur-1).
        XCTAssertEqual(plan.restored.first(where: { $0.title == "HW1" })?.googleEventId, "cur-1")
        // HW2 isn't on the calendar now → carried with its snapshot id so the
        // backend patches-or-recreates it.
        XCTAssertEqual(plan.restored.first(where: { $0.title == "HW2" })?.googleEventId, "snap-2")
        // Restored events are clean (no lingering "edited" badge).
        XCTAssertTrue(plan.restored.allSatisfy { !$0.isEdited && !$0.isDeletedLocally })
    }

    func testEventsAddedSinceTheSnapshotAreQueuedForDeletion() {
        let snapshot = [event("HW1", googleEventId: "g-1")]
        let current = [
            event("HW1", googleEventId: "g-1"),
            event("HW2 added later", googleEventId: "g-2"),   // not in the snapshot
            event("HW3 never synced"),                        // no google id → nothing to delete
        ]

        let plan = ClassRestore.plan(snapshot: snapshot, current: current)

        XCTAssertEqual(plan.restored.map(\.title), ["HW1"])
        XCTAssertEqual(plan.deletions.map(\.title), ["HW2 added later"])
    }

    func testIsNoOpWhenTheKeysMatch() {
        let snapshot = [event("HW1"), event("HW2", date: "2026-04-01")]
        let current = [event("HW2", date: "2026-04-01", googleEventId: "g"), event("HW1", googleEventId: "g2")]
        XCTAssertTrue(ClassRestore.isNoOp(snapshot: snapshot, current: current))

        let changed = [event("HW1", googleEventId: "g2")]
        XCTAssertFalse(ClassRestore.isNoOp(snapshot: snapshot, current: changed))
    }
}
