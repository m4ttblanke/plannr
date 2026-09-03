//
//  EventReconciler.swift
//  Plannr
//
//  Reconciles a freshly parsed syllabus against a class's existing events so a
//  re-upload changes only what actually changed in the user's Google Calendar,
//  instead of deleting and rebuilding the whole class calendar.
//
//  Event identity is heuristic: two events are "the same" when their
//  (case-insensitive, trimmed) title and their date string match. Gemini is
//  prompted to keep canonical titles ("HW1", "Midterm 1"), so this holds for the
//  common cases; a renamed or moved assignment reads as a delete + insert.
//

import Foundation

enum EventReconciler {

    struct Result {
        /// Events to carry into the preview and sync: unchanged + updated +
        /// newly added. Each keeps its `googleEventId` when one exists, so the
        /// backend updates in place rather than re-inserting.
        var merged: [CalendarEvent]
        /// Events that were in the class but are gone from the new syllabus and
        /// were previously pushed to Google Calendar — to be removed from it.
        var toDelete: [CalendarEvent]
    }

    static func matchKey(_ event: CalendarEvent) -> String {
        event.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "|" + event.date
    }

    /// - Parameter preferParsedOverEdited: normally a local edit wins over the
    ///   incoming copy of the same event. Restoring a past sync session passes
    ///   `true` so the snapshot's version replaces the current (possibly edited)
    ///   one — while still carrying the Google event id forward for a patch.
    static func reconcile(parsed: [CalendarEvent], existing: [CalendarEvent],
                          preferParsedOverEdited: Bool = false) -> Result {
        // Only reconcile against events the user still wants (not queued for deletion).
        let live = existing.filter { !$0.isDeletedLocally }
        guard !live.isEmpty else { return Result(merged: parsed, toDelete: []) }

        var existingByKey: [String: CalendarEvent] = [:]
        for event in live where existingByKey[matchKey(event)] == nil {
            existingByKey[matchKey(event)] = event
        }

        var merged: [CalendarEvent] = []
        var matchedKeys = Set<String>()

        for parsedEvent in parsed {
            let key = matchKey(parsedEvent)
            matchedKeys.insert(key)

            guard let old = existingByKey[key] else {
                merged.append(parsedEvent)          // genuinely new — no googleEventId
                continue
            }

            if old.isEdited && !preferParsedOverEdited {
                // The user changed this one in the app. Keep their version; it
                // already carries its googleEventId. The new syllabus's copy of
                // this event is intentionally ignored (local edit wins).
                merged.append(old)
            } else {
                // Refresh the details from the new syllabus, but keep the link to
                // the existing Google event and the user's completion state.
                var refreshed = parsedEvent
                refreshed.googleEventId = old.googleEventId
                refreshed.isTaskCompleted = old.isTaskCompleted
                merged.append(refreshed)
            }
        }

        // In the class but not in the new parse. Only those that actually made
        // it to Google Calendar need a delete call.
        let toDelete = live.filter { event in
            !matchedKeys.contains(matchKey(event)) && event.googleEventId != nil
        }

        return Result(merged: merged, toDelete: toDelete)
    }
}
