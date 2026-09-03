//
//  ClassRestore.swift
//  Plannr
//
//  Turns "restore this sync session" into a concrete plan: what the class's
//  events become, and which Google Calendar events to remove. The actual push
//  reuses the normal /calendar/sync path (patch / insert / delete), never a
//  rebuild.
//

import Foundation

enum ClassRestore {

    struct Plan {
        /// The class's events after the restore — the snapshot's events, with a
        /// Google event id carried over from any current event that still matches
        /// (so it's patched in place, not churned) and edit/deletion flags cleared.
        let restored: [CalendarEvent]
        /// Current calendar events that aren't in the snapshot and were pushed to
        /// Google — to delete from it.
        let deletions: [CalendarEvent]
    }

    static func plan(snapshot: [CalendarEvent], current: [CalendarEvent]) -> Plan {
        let cleaned = snapshot.map { event -> CalendarEvent in
            var e = event
            e.isEdited = false
            e.isDeletedLocally = false
            e.status = .accepted
            return e
        }

        let merged = EventReconciler.reconcile(
            parsed: cleaned,
            existing: current,
            preferParsedOverEdited: true
        ).merged

        let restoredKeys = Set(merged.map(EventReconciler.matchKey))
        let deletions = current.filter {
            $0.googleEventId != nil && !restoredKeys.contains(EventReconciler.matchKey($0))
        }

        return Plan(restored: merged, deletions: deletions)
    }

    /// Whether restoring `snapshot` would actually change anything (same set of
    /// title+date keys as the current events → nothing to do).
    static func isNoOp(snapshot: [CalendarEvent], current: [CalendarEvent]) -> Bool {
        let a = Set(snapshot.map(EventReconciler.matchKey))
        let b = Set(current.filter { !$0.isDeletedLocally }.map(EventReconciler.matchKey))
        return a == b
    }
}
